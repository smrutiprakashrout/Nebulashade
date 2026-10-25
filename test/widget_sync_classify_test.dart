import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/services/widget_palette.dart';
import 'package:nebulashade/services/widget_sync_service.dart';

WidgetPalette _slotFourPalette() => const WidgetPalette(
      slot: 4,
      base: 0xffc55651,
      widgetBg: 0x332424,
      light: 0xffd8d6,
      accent: 0xcc5b56,
      dark: 0xba453f,
      sidebar: 0x291d1d,
      popover: 0x231918,
    );

void main() {
  test('classifies the observed GTK and Shell colors by saturation/value', () {
    const expected = <String, WidgetColorClass>{
      '#8756cc': WidgetColorClass.accent,
      '#a356cc': WidgetColorClass.accent,
      '#291d20': WidgetColorClass.base,
      '#281d29': WidgetColorClass.base,
      '#23181c': WidgetColorClass.popover,
      '#221823': WidgetColorClass.popover,
      '#1f1823': WidgetColorClass.popover,
      '#cc96ad': WidgetColorClass.accentTone,
      '#be81a9': WidgetColorClass.accentTone,
      '#ddaabc': WidgetColorClass.accentTone,
      '#b86f96': WidgetColorClass.accentTone,
      '#af5e87': WidgetColorClass.accentTone,
      '#cf9fb8': WidgetColorClass.accentTone,
      '#291d21': WidgetColorClass.base,
      '#23181b': WidgetColorClass.popover,
    };
    for (final entry in expected.entries) {
      final rgb = int.parse(entry.key.substring(1), radix: 16);
      expect(WidgetPalette.classifyRgb(rgb), [entry.value], reason: entry.key);
    }

    for (final value in [
      '#e2c4d4',
      '#e69875',
      '#a7c080',
      '#e67e80',
      '#000000',
    ]) {
      expect(
          WidgetPalette.classifyRgb(int.parse(value.substring(1), radix: 16)),
          isEmpty,
          reason: value);
    }
  });

  test('rewrites fixture colors, repairs malformed hex, and preserves alpha',
      () {
    const fixture =
        '.quick-toggle:checked{background-color:rgba(163,86,204,0.95) !important;}\n'
        '.notification-banner{background-color:#221823;}\n'
        '.quick-toggle:checked:hover{background-color:#ddaabc1d8 !important;}';
    final palette = _slotFourPalette();
    final result = WidgetSyncService.rewriteCss(fixture, palette);
    final tone = WidgetPalette.mapClassifiedRgb(
        0xddaabc, WidgetColorClass.accentTone, palette);

    expect(result.content, contains('rgba(204,91,86,0.95)'));
    expect(result.content, contains('#231918'));
    expect(result.content,
        contains('#${tone.toRadixString(16).padLeft(6, '0')} !important;'));
    expect(result.content, isNot(contains('#ddaabc1d8')));
    expect(result.repaired, hasLength(1));
    expect(result.repaired.single, contains('#ddaabc1d8 -> #ddaabc'));
    expect(result.counts[WidgetColorClass.accent.name], 1);
    expect(result.counts[WidgetColorClass.popover.name], 1);
    expect(result.counts[WidgetColorClass.accentTone.name], 1);

    final alphaResult =
        WidgetSyncService.rewriteCss('.x { color: #a356cc80; }', palette);
    expect(alphaResult.content, contains('#cc5b5680'));
    expect(alphaResult.repaired, isEmpty);
  });

  if (Platform.environment['NEBULASHADE_LIVE_SYNC'] == '1') {
    test('applies slot 4 to the live theme files', () async {
      final colors = await WidgetPalette.readColors();
      final palette = WidgetPalette.fromColors(colors, 4);
      expect(WidgetPalette.hex(palette.accent), '#CC5B56');
      final service = WidgetSyncService();
      final result = await service.apply(palette);
      stdout.writeln(jsonEncode({
        'files': result.replacements,
        'perFileClasses': result.perFileClassReplacements,
        'classes': result.classReplacements,
        'repaired': result.repaired,
        'warnings': result.warnings.map((warning) => warning.toJson()).toList(),
      }));
      expect(
          result.steps.values
              .any((step) => step.status == SyncStepStatus.failed),
          isFalse);

      const oldHexes = [
        '#a356cc',
        '#8756cc',
        '#221823',
        '#281d29',
        '#1f1823',
        '#291d21',
        '#23181b',
      ];
      final remaining = <String, List<String>>{};
      for (final path in service.filePaths) {
        final file = File(path);
        if (!await file.exists()) continue;
        final css = await file.readAsString();
        final hits = oldHexes
            .where((hex) =>
                RegExp(RegExp.escape(hex), caseSensitive: false).hasMatch(css))
            .toList();
        if (hits.isNotEmpty) remaining[path] = hits;
      }
      stdout.writeln('remainingOldHexes=${jsonEncode(remaining)}');
      expect(remaining, isEmpty);
    });
  }
}
