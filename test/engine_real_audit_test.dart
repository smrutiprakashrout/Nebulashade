import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:nebulashade/config/theme_variants.dart';
import 'package:nebulashade/engine/css_transformer.dart';
import 'package:nebulashade/engine/engine_palette.dart';
import 'package:nebulashade/engine/engine_targets.dart';
import 'package:nebulashade/engine/unified_color_engine.dart';
import 'package:nebulashade/engine/watch_gate.dart';
import 'package:nebulashade/services/gsettings_runner.dart';
import 'package:nebulashade/services/theme_detector.dart';

class _AuditGs implements GsettingsRunner {
  final values = <String, String>{
    '$gtkInterfaceSchema/$gtkThemeKey': ThemeVariants.dark.folderName,
    '$userThemeSchema/$userThemeNameKey': ThemeVariants.dark.folderName,
    '$gtkInterfaceSchema/$colorSchemeKey': 'prefer-dark',
  };
  @override
  Future<GsResult> get(String schema, String key) async =>
      GsResult(ok: true, value: values['$schema/$key'] ?? '');
  @override
  Future<GsResult> set(String schema, String key, String value) async {
    values['$schema/$key'] = value;
    return const GsResult(ok: true);
  }
}

class _AuditGate implements WatchGateHandle {
  @override
  void suspend() {}
  @override
  Future<void> resume({Future<void> Function()? reinit}) async {}
}

void main() {
  final enabled = Platform.environment['NEBULA_AUDIT'] == '1';
  test(
      'copies real target CSS to temp, then audits and applies only the copies',
      () async {
    final realHome = Platform.environment['HOME']!;
    final realTargets = await discoverTargets(home: realHome);
    expect(realTargets, isNotEmpty);
    final temp =
        await Directory.systemTemp.createTemp('nebula-engine-real-audit-');
    addTearDown(() => temp.delete(recursive: true));
    final copied = <EngineTarget>[];
    final originals = <String, List<int>>{};
    for (final target in realTargets) {
      final bytes = await File(target.path).readAsBytes();
      final relative = path.relative(target.path, from: realHome);
      final copyPath = path.join(temp.path, relative);
      await File(copyPath).parent.create(recursive: true);
      await File(copyPath).writeAsBytes(bytes);
      originals[copyPath] = bytes;
      copied.add(EngineTarget(
          path: copyPath,
          fileKind: target.fileKind,
          isWatchedGtk4Override: target.isWatchedGtk4Override));
    }
    final realTheme =
        path.join(realHome, '.themes', ThemeVariants.dark.folderName);
    final copiedTheme =
        path.join(temp.path, '.themes', ThemeVariants.dark.folderName);
    final index = File(path.join(realTheme, 'index.theme'));
    await File(path.join(copiedTheme, 'index.theme'))
        .writeAsBytes(await index.readAsBytes());
    final detector =
        ThemeDetector(searchDirs: [path.join(temp.path, '.themes')]);
    final engine = UnifiedColorEngine(
      gs: _AuditGs(),
      detector: detector,
      home: temp.path,
      configDir: path.join(temp.path, '.config', 'nebulashade'),
      gate: _AuditGate(),
    );
    const bases = [
      Color(0xffcea14f),
      Color(0xff4f7ace),
      Color(0xff5fae6b),
      Color(0xffc5503a)
    ];
    print(
        'base,file,bytesBefore/After,role/token/accent/palette,rolesAppended,residualCategoriesBefore/After,planMs,applyMs');
    for (final base in bases) {
      // Reset only the copied files before each independent target-base run.
      for (final entry in originals.entries) {
        await File(entry.key).writeAsBytes(entry.value);
      }
      final beforeResidual = <String, List<ResidualColour>>{};
      for (final target in copied) {
        beforeResidual[target.path] = auditResiduals(
          utf8.decode(await File(target.path).readAsBytes()),
          EnginePalette.fromBase(base),
        );
      }
      final planResult = await engine.plan(base);
      final watch = Stopwatch()..start();
      final applied = await engine.apply(base);
      watch.stop();
      expect(planResult.ok, isTrue, reason: planResult.problems.join('; '));
      expect(applied.ok, isTrue, reason: applied.message);
      for (final item in planResult.files) {
        final after = await File(item.path).readAsBytes();
        final afterText = utf8.decode(after);
        final afterResidual =
            auditResiduals(afterText, EnginePalette.fromBase(base));
        print(
            '${_hex(base)},${path.basename(item.path)},${item.bytesBefore}/${item.bytesAfter},${item.recoloured}/${item.tokenMapped}/${item.accentContextRecolored}/${item.paletteNamesChanged},${item.rolesAppended},before[${_categoryCounts(beforeResidual[item.path]!)}];after[${_categoryCounts(afterResidual)}],${planResult.milliseconds},${watch.elapsedMilliseconds}');
        final appendRoles = item.kind == 'gtk4';
        final once = transformCss(afterText, EnginePalette.fromBase(base),
                fileKind: item.kind, appendMissingRoles: appendRoles)
            .css;
        final twice = transformCss(once, EnginePalette.fromBase(base),
                fileKind: item.kind, appendMissingRoles: appendRoles)
            .css;
        expect(twice, once, reason: 'copy idempotence ${item.path}');
        final original = utf8.decode(originals[item.path]!);
        final a = transformCss(original, EnginePalette.fromBase(bases.first),
                fileKind: item.kind, appendMissingRoles: appendRoles)
            .css;
        final chained = transformCss(a, EnginePalette.fromBase(base),
                fileKind: item.kind, appendMissingRoles: appendRoles)
            .css;
        final direct = transformCss(original, EnginePalette.fromBase(base),
                fileKind: item.kind, appendMissingRoles: appendRoles)
            .css;
        expect(chained, direct, reason: 'copy base independence ${item.path}');
      }
      print(
          'BASE ${_hex(base)}: plan=${planResult.milliseconds}ms apply=${watch.elapsedMilliseconds}ms; idempotent=true; baseIndependent=true');
      for (final entry in _spotChecks.entries) {
        String before = '<not found>', after = '<not found>', file = '';
        for (final target in copied) {
          final original = utf8.decode(originals[target.path]!);
          final transformed =
              utf8.decode(await File(target.path).readAsBytes());
          final found = _lineFor(original, entry.value);
          if (found != '<not found>') {
            before = found;
            after = _lineFor(transformed, entry.value);
            file = path.basename(target.path);
            break;
          }
        }
        if (after == '<not found>') {
          for (final target in copied) {
            final transformed =
                utf8.decode(await File(target.path).readAsBytes());
            final found = _lineFor(transformed, entry.value);
            if (found != '<not found>') {
              after = found;
              file = path.basename(target.path);
              break;
            }
          }
        }
        print('SPOT ${_hex(base)} $file ${entry.key}: $before => $after');
      }
      final impact = <String, int>{};
      final examples = <String, String>{};
      final palette = EnginePalette.fromBase(base);
      for (final item in planResult.files) {
        final content = utf8.decode(await File(item.path).readAsBytes());
        for (final row in auditResiduals(content, palette)) {
          final key =
              '${row.selector}\t${row.property}\t${row.value}\t${row.category}';
          impact[key] = (impact[key] ?? 0) + 1;
          examples.putIfAbsent(
              key, () => '${path.basename(item.path)}:${row.line}');
        }
      }
      final ranked = impact.keys.toList()
        ..sort((a, b) => impact[b]!.compareTo(impact[a]!));
      for (final key in ranked.take(15)) {
        final fields = key.split('\t');
        print(
            'OUTLIER ${_hex(base)} ${examples[key]} ${fields[0]} ${fields[1]} ${fields[2]} [${fields[3]}] count=${impact[key]}');
      }
    }
  },
      skip: enabled
          ? false
          : 'Set NEBULA_AUDIT=1 to copy and audit real CSS; no real apply is performed.');
}

const _spotChecks = <String, String>{
  'suggested-action background': r'button\.suggested-action\s*\{',
  'suggested-action hover rgba': r'button\.suggested-action:hover',
  'levelbar low/full': r'levelbar block\.(low|full)',
  '.origin-beta': r'\.origin-beta',
  'checked sidebar button': r'sidebar.*:checked',
  'stackswitcher:checked': r'stackswitcher.*:checked',
  'colorswatch selector': r'colorswatch#ddcbaa',
  'blue_3': r'@define-color blue_3',
  'red_3': r'@define-color red_3',
  'success_color': r'@define-color success_color',
  'headerbar darker shade': r'@define-color headerbar_darker_shade_color',
  'dashtodock running dot': r'dashtodockContainer.*running',
};

String _lineFor(String text, String pattern) {
  if (pattern == r'levelbar block\.(low|full)') {
    return 'low: ${_matchingBlock(text, r'levelbar block\.low')} || full: ${_matchingBlock(text, r'levelbar block\.full')}';
  }
  return _matchingBlock(text, pattern);
}

String _matchingBlock(String text, String pattern) {
  final regex = RegExp(pattern, caseSensitive: false);
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (regex.hasMatch(lines[i])) {
      final block = <String>[lines[i].trim()];
      for (var j = i + 1; j < lines.length && j <= i + 3; j++) {
        block.add(lines[j].trim());
        if (lines[j].contains('}')) break;
      }
      final joined = block.join(' ');
      return joined.length > 500 ? joined.substring(0, 500) : joined;
    }
  }
  return '<not found>';
}

String _categoryCounts(List<ResidualColour> items) {
  final counts = <String, int>{for (final c in 'abcdefg'.split('')) c: 0};
  for (final item in items) counts[item.category] = counts[item.category]! + 1;
  return counts.entries.map((e) => '${e.key}:${e.value}').join('/');
}

String _hex(Color c) =>
    '#${c.red.toRadixString(16).padLeft(2, '0')}${c.green.toRadixString(16).padLeft(2, '0')}${c.blue.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
