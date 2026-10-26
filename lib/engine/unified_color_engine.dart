import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:nebulashade/constants/colours.dart';
import 'package:nebulashade/engine/css_transformer.dart';
import 'package:nebulashade/engine/engine_palette.dart';
import 'package:nebulashade/engine/engine_settings.dart';
import 'package:nebulashade/engine/engine_snapshot.dart';
import 'package:nebulashade/engine/engine_targets.dart';
import 'package:nebulashade/engine/watch_gate.dart';
import 'package:nebulashade/services/gsettings_runner.dart';
import 'package:nebulashade/services/theme_detector.dart';
import 'package:nebulashade/services/theme_switcher.dart';

class EngineFilePlan {
  const EngineFilePlan({
    required this.path,
    required this.kind,
    required this.bytesBefore,
    required this.bytesAfter,
    required this.recoloured,
    required this.semanticTokensChanged,
    required this.residualOutliers,
    required this.residualSelectors,
    required this.notes,
    required this.output,
    this.roleRewritten = 0,
    this.tokenMapped = 0,
    this.accentContextRecolored = 0,
    this.paletteNamesChanged = 0,
    this.rolesAppended = 0,
  });

  final String path;
  final String kind;
  final int bytesBefore;
  final int bytesAfter;
  final int recoloured;
  final int semanticTokensChanged;
  final int residualOutliers;
  final List<String> residualSelectors;
  final List<String> notes;
  final List<int> output;
  final int roleRewritten,
      tokenMapped,
      accentContextRecolored,
      paletteNamesChanged,
      rolesAppended;
}

class EnginePlan {
  const EnginePlan({
    required this.ok,
    required this.problems,
    required this.files,
    required this.milliseconds,
  });

  final bool ok;
  final List<String> problems;
  final List<EngineFilePlan> files;
  final int milliseconds;
}

class EngineResult {
  const EngineResult({
    required this.ok,
    required this.message,
    this.snapshotId,
    this.plan,
    this.rolledBack = false,
  });

  final bool ok;
  final String message;
  final String? snapshotId;
  final EnginePlan? plan;
  final bool rolledBack;
}

class UnifiedColorEngine {
  UnifiedColorEngine({
    GsettingsRunner? gs,
    ThemeDetector? detector,
    String? configDir,
    String? home,
    WatchGateHandle? gate,
    bool Function()? themeSwitchBusyCheck,
    Future<void> Function(String path, int index)? beforeWrite,
    bool Function(String path)? forceVerifyMismatch,
  })  : _gs = gs ?? ProcessGsettingsRunner(),
        _detector = detector,
        _home = home ?? Platform.environment['HOME'] ?? '',
        _configDir = configDir ??
            '${home ?? Platform.environment['HOME'] ?? ''}${Platform.pathSeparator}.config${Platform.pathSeparator}nebulashade',
        _gate = gate ?? WatchGate(),
        _themeSwitchBusy = themeSwitchBusyCheck ?? (() => ThemeSwitcher.busy),
        _beforeWrite = beforeWrite,
        _forceVerifyMismatch = forceVerifyMismatch;

  final GsettingsRunner _gs;
  final ThemeDetector? _detector;
  final String _home;
  final String _configDir;
  final WatchGateHandle _gate;
  final bool Function() _themeSwitchBusy;
  final Future<void> Function(String path, int index)? _beforeWrite;
  final bool Function(String path)? _forceVerifyMismatch;
  static bool _busy = false;
  static bool get busy => _busy;

  ThemeDetector get _resolvedDetector => _detector ?? ThemeDetector();
  EngineSnapshotStore get _snapshots =>
      EngineSnapshotStore(_configDir, gs: _gs);

  Future<EnginePlan> plan(Color base) async {
    final stopwatch = Stopwatch()..start();
    final problems = <String>[];
    final plans = <EngineFilePlan>[];
    try {
      final targets =
          await discoverTargets(detector: _resolvedDetector, home: _home);
      if (targets.isEmpty)
        problems.addAll(EngineTarget.skipped.isEmpty
            ? ['No regular theme targets found under home.']
            : EngineTarget.skipped);
      final palette = EnginePalette.fromBase(base);
      for (final target in targets) {
        try {
          final bytes = await File(target.path).readAsBytes();
          final source = utf8.decode(bytes);
          final appendMissingRoles = target.fileKind == 'gtk4';
          final transformed = bytes.length > 64 * 1024
              ? await Isolate.run(() => transformCss(source, palette,
                  fileKind: target.fileKind,
                  appendMissingRoles: appendMissingRoles))
              : transformCss(source, palette,
                  fileKind: target.fileKind,
                  appendMissingRoles: appendMissingRoles);
          final output = utf8.encode(transformed.css);
          final residual = auditResiduals(transformed.css, palette);
          final issues = _validate(
              source, transformed.css, bytes.length, output.length,
              rolesAppended: transformed.rolesAppended);
          for (final issue in issues) problems.add('${target.path}: $issue');
          plans.add(EngineFilePlan(
            path: target.path,
            kind: target.fileKind,
            bytesBefore: bytes.length,
            bytesAfter: output.length,
            recoloured: transformed.recoloured,
            semanticTokensChanged: transformed.semanticTokensChanged,
            residualOutliers: residual.length,
            residualSelectors:
                List.unmodifiable(residual.take(5).map((e) => e.selector)),
            notes: transformed.notes,
            output: List.unmodifiable(output),
            roleRewritten: transformed.roleRewritten,
            tokenMapped: transformed.tokenMapped,
            accentContextRecolored: transformed.accentContextRecolored,
            paletteNamesChanged: transformed.paletteNamesChanged,
            rolesAppended: transformed.rolesAppended,
          ));
        } catch (error) {
          problems.add('${target.path}: transform failed: $error');
        }
      }
    } catch (error) {
      problems.add('Plan failed: $error');
    }
    stopwatch.stop();
    return EnginePlan(
      ok: problems.isEmpty && plans.isNotEmpty,
      problems: List.unmodifiable(problems),
      files: List.unmodifiable(plans),
      milliseconds: stopwatch.elapsedMilliseconds,
    );
  }

  Future<EngineResult> apply(Color base) async {
    if (_busy)
      return const EngineResult(
          ok: false, message: 'An Adaptive v2 apply is already running.');
    _busy = true;
    var gateHeld = false;
    String? snapshotId;
    List<EngineTarget> targets = const [];
    EnginePlan? planned;
    var writeStarted = false;
    try {
      if (_themeSwitchBusy())
        return const EngineResult(
            ok: false, message: 'A theme switch is in progress.');
      final currentVariant =
          await ThemeSwitcher(gs: _gs, detector: _resolvedDetector)
              .currentVariantId();
      if (currentVariant != 'dark') {
        return const EngineResult(
            ok: false,
            message:
                'Adaptive v2 supports the Dark variant only for now; use Classic.');
      }
      targets = await discoverTargets(detector: _resolvedDetector, home: _home);
      if (EngineTarget.skipped.any((s) => s.startsWith('Symlink:'))) {
        return EngineResult(
            ok: false,
            message:
                'Symlink target refused: ${EngineTarget.skipped.join('; ')}');
      }
      if (targets.isEmpty)
        return EngineResult(
            ok: false,
            message:
                'No regular theme targets found: ${EngineTarget.skipped.join('; ')}');
      for (final target in targets) {
        final type =
            await FileSystemEntity.type(target.path, followLinks: false);
        if (type != FileSystemEntityType.file) {
          return EngineResult(
              ok: false,
              message:
                  'Target is missing or is not a regular file: ${target.path}');
        }
        final handle = await File(target.path).open(mode: FileMode.append);
        await handle.close();
      }
      planned = await plan(base);
      if (!planned.ok)
        return EngineResult(
            ok: false,
            message:
                'Validation failed; no files were written: ${planned.problems.join(' | ')}',
            plan: planned);

      final normalizedHex = _hex(base);
      await _snapshots.ensureBaseline(targets, appliedHex: normalizedHex);
      snapshotId = _timestampId();
      await _snapshots
          .create(snapshotId, targets, {'appliedHex': normalizedHex});
      await _snapshots.prune(keep: 10);

      _gate.suspend();
      gateHeld = true;
      writeStarted = true;
      for (var i = 0; i < planned.files.length; i++) {
        final item = planned.files[i];
        await _beforeWrite?.call(item.path, i + 1);
        await _atomicWrite(File(item.path), item.output);
        final file = File(item.path);
        if (!await file.exists() || await file.length() == 0) {
          throw FileSystemException('Write verification failed', item.path);
        }
      }

      final reloadError = await _reload();
      if (reloadError != null)
        throw StateError('Theme reload failed: $reloadError');
      for (final item in planned.files) {
        final bytes = await File(item.path).readAsBytes();
        if (_forceVerifyMismatch?.call(item.path) == true ||
            sha256.convert(bytes).toString() !=
                sha256.convert(item.output).toString()) {
          throw StateError('Post-write verification mismatch: ${item.path}');
        }
        final residual =
            auditResiduals(utf8.decode(bytes), EnginePalette.fromBase(base));
        if (residual.length != item.residualOutliers) {
          throw StateError('Residual verification mismatch: ${item.path}');
        }
      }
      final now = DateTime.now().toIso8601String();
      final settings = await EngineSettings.read(configDir: _configDir);
      await settings.save(
        appliedHex: normalizedHex,
        appliedAt: now,
        lastSnapshotId: snapshotId,
        baselineSnapshotId: 'baseline-before-beta',
        configDir: _configDir,
      );
      await _gate.resume(reinit: () async {
        AppColors.init();
      });
      gateHeld = false;
      return EngineResult(
          ok: true,
          message: 'Adaptive v2 Beta applied.',
          snapshotId: snapshotId,
          plan: planned);
    } catch (error) {
      var rolledBack = false;
      var message = 'Adaptive v2 apply failed: $error';
      if (writeStarted && snapshotId != null) {
        rolledBack = await _snapshots.restore(snapshotId, targets: targets);
        final reloadError = await _reload();
        if (reloadError != null)
          message = '$message; rollback reload failed: $reloadError';
        if (!rolledBack)
          message =
              '$message; rollback failed; snapshot: $_configDir/backups/engine/$snapshotId';
      }
      if (gateHeld) {
        await _gate.resume(reinit: () async {
          AppColors.init();
        });
        gateHeld = false;
      }
      return EngineResult(
          ok: false,
          message: message,
          snapshotId: snapshotId,
          plan: planned,
          rolledBack: rolledBack);
    } finally {
      if (gateHeld)
        await _gate.resume(reinit: () async {
          AppColors.init();
        });
      _busy = false;
    }
  }

  Future<EngineResult> revertLast() async {
    final settings = await EngineSettings.read(configDir: _configDir);
    final id = settings.lastSnapshotId;
    if (id == null)
      return const EngineResult(
          ok: false, message: 'No Adaptive v2 snapshot is recorded.');
    return _revert(id);
  }

  Future<EngineResult> revertToBaseline() async =>
      _revert('baseline-before-beta');

  Future<EngineResult> _revert(String id) async {
    if (_busy)
      return const EngineResult(
          ok: false, message: 'An Adaptive v2 operation is already running.');
    _busy = true;
    var held = false;
    try {
      final targets =
          await discoverTargets(detector: _resolvedDetector, home: _home);
      _gate.suspend();
      held = true;
      final ok = await _snapshots.restore(id, targets: targets);
      if (!ok)
        return EngineResult(ok: false, message: 'Snapshot restore failed: $id');
      final reloadError = await _reload();
      if (reloadError != null)
        return EngineResult(
            ok: false,
            message: 'Snapshot restored; reload failed: $reloadError',
            snapshotId: id);
      final settings = await EngineSettings.read(configDir: _configDir);
      await settings.save(
          lastSnapshotId: id == 'baseline-before-beta' ? null : id,
          configDir: _configDir);
      return EngineResult(
          ok: true, message: 'Restored snapshot $id.', snapshotId: id);
    } catch (error) {
      return EngineResult(
          ok: false, message: 'Revert failed: $error', snapshotId: id);
    } finally {
      if (held)
        await _gate.resume(reinit: () async {
          AppColors.init();
        });
      _busy = false;
    }
  }

  Future<String?> _reload() async {
    final gtk = await _gs.get(gtkInterfaceSchema, gtkThemeKey);
    final shell = await _gs.get(userThemeSchema, userThemeNameKey);
    if (!gtk.ok || !shell.ok) return 'could not read original theme settings';
    String? failure;
    try {
      for (final pair in [
        (userThemeSchema, userThemeNameKey, shell.value),
        (gtkInterfaceSchema, gtkThemeKey, gtk.value),
      ]) {
        final first = await _gs.set(pair.$1, pair.$2, 'Adwaita');
        if (!first.ok)
          throw StateError(first.error ?? 'Adwaita toggle rejected');
        final second = await _gs.set(pair.$1, pair.$2, pair.$3);
        if (!second.ok)
          throw StateError(second.error ?? 'theme restore rejected');
      }
    } catch (error) {
      failure = error.toString();
    } finally {
      for (final pair in [
        (userThemeSchema, userThemeNameKey, shell.value),
        (gtkInterfaceSchema, gtkThemeKey, gtk.value),
      ]) {
        await _restoreSetting(pair.$1, pair.$2, pair.$3);
      }
    }
    return failure;
  }

  Future<void> _restoreSetting(
      String schema, String key, String expected) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final current = await _gs.get(schema, key);
      if (current.ok && current.value == expected) return;
      await _gs.set(schema, key, expected);
    }
  }

  Future<void> _atomicWrite(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final temp =
        File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }
}

class ResidualColour {
  const ResidualColour(this.value, this.selector,
      {this.category = 'g', this.property = '', this.line = 0});
  final String value;
  final String selector;
  final String category, property;
  final int line;
}

List<ResidualColour> auditResiduals(String css, EnginePalette palette) {
  final residuals = <ResidualColour>[];
  final targetHue = HSVColor.fromColor(palette.accent).hue;
  for (final occurrence in scanCssColorOccurrences(css)) {
    final value = occurrence.value;
    if (occurrence.property == '@define-color' &&
        isCanonicalPaletteValue(occurrence.selector, value, palette)) continue;
    final color = _asColor(value);
    if (color == null ||
        {0xe69875, 0xa7c080, 0xe67e80}.contains(color.toARGB32() & 0xffffff))
      continue;
    final hsl = HSLColor.fromColor(color);
    if (hsl.saturation < .12 ||
        hsl.lightness <= .06 ||
        hsl.lightness >= .94 ||
        _hueDistance(hsl.hue, targetHue) <= 35) continue;
    final category = _residualCategory(occurrence);
    residuals.add(ResidualColour(value, occurrence.selector,
        category: category,
        property: occurrence.property,
        line: occurrence.line));
  }
  return List.unmodifiable(residuals);
}

String _residualCategory(CssColorOccurrence o) {
  if (o.property == '@define-color' &&
      RegExp(r'^(blue|green|yellow|orange|red|purple|brown|light|dark)_[1-5]$')
          .hasMatch(o.selector)) return 'a';
  if (RegExp(r'warning|error|success|destructive').hasMatch(o.selector) ||
      RegExp(r'\.error|\.warning|\.success|\.destructive').hasMatch(o.selector))
    return 'b';
  if (RegExp(r'windowcontrols|titlebutton').hasMatch(o.selector)) return 'c';
  if (o.value.toLowerCase().startsWith('rgba(') &&
      RegExp(r',\s*0(?:\.\d+)?\s*\)$').hasMatch(o.value)) return 'd';
  if (RegExp(r'box-shadow|border|outline').hasMatch(o.property)) return 'd';
  if (RegExp(
          r'^(#panel|\.popup-|\.dash|\.overview|\.notification|\.osd|\.login|\.lock|\.quick-settings|\.calendar)')
      .hasMatch(o.selector)) return 'e';
  if (RegExp(r'category|app-|origin-|pano|forge|tiling|folder|nebulashade',
          caseSensitive: false)
      .hasMatch(o.selector)) return 'f';
  return 'g';
}

Color? _asColor(String value) {
  final hex =
      RegExp(r'^#([0-9a-fA-F]{6})(?:[0-9a-fA-F]{2})?$').firstMatch(value);
  if (hex != null)
    return Color(0xFF000000 | int.parse(hex.group(1)!, radix: 16));
  final rgb =
      RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(value);
  if (rgb != null)
    return Color.fromARGB(255, int.parse(rgb.group(1)!),
        int.parse(rgb.group(2)!), int.parse(rgb.group(3)!));
  final hsl = RegExp(
          r'hsla?\(\s*(-?[\d.]+)(?:deg)?\s*[, ]\s*([\d.]+)%\s*[, ]\s*([\d.]+)%',
          caseSensitive: false)
      .firstMatch(value);
  if (hsl != null)
    return HSLColor.fromAHSL(
            1,
            double.parse(hsl.group(1)!),
            double.parse(hsl.group(2)!) / 100,
            double.parse(hsl.group(3)!) / 100)
        .toColor();
  return null;
}

double _hueDistance(double a, double b) {
  final d = (a - b).abs() % 360;
  return math.min(d, 360 - d);
}

List<String> _validate(
    String before, String after, int bytesBefore, int bytesAfter,
    {int rolesAppended = 0}) {
  final issues = <String>[];
  if (before.isEmpty) issues.add('empty input');
  bool balanced(String s, String open, String close) {
    var depth = 0;
    for (final c in s.split('')) {
      if (c == open) depth++;
      if (c == close && --depth < 0) return false;
    }
    return depth == 0;
  }

  if (after.isEmpty) issues.add('empty output');
  if (rolesAppended == 0 &&
      bytesBefore > 0 &&
      (bytesAfter - bytesBefore).abs() > bytesBefore * .25)
    issues.add('size change exceeds 25%');
  if (!balanced(after, '{', '}')) issues.add('brace balance changed/invalid');
  if (!balanced(after, '(', ')'))
    issues.add('parenthesis balance changed/invalid');
  if (_count(before, r'@define-color\b') + rolesAppended !=
      _count(after, r'@define-color\b'))
    issues.add('@define-color count changed');
  // CSS class names may legitimately contain the substring "null" (for
  // example .prompt-dialog-null-label); reject invalid value tokens only.
  if (RegExp(r'(?:^|[:(,]\s*)(?:NaN|null|Infinity)(?:$|[),;\s])',
          caseSensitive: false)
      .hasMatch(after)) issues.add('invalid numeric/null text');
  final roleNewlines = rolesAppended == 0
      ? 0
      : rolesAppended + 2 + (before.endsWith('\n') ? 0 : 1);
  if (_count(before, r'\n') + roleNewlines != _count(after, r'\n'))
    issues.add('line count changed');
  return issues;
}

int _count(String text, String pattern) =>
    RegExp(pattern).allMatches(text).length;
String _hex(Color c) =>
    '#${c.red.toRadixString(16).padLeft(2, '0')}${c.green.toRadixString(16).padLeft(2, '0')}${c.blue.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
String _timestampId() => DateTime.now()
    .toIso8601String()
    .replaceAll(RegExp(r'[^0-9]'), '')
    .substring(0, 17);
