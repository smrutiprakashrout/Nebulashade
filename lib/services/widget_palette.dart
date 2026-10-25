import 'dart:io';
import 'dart:math' as math;

enum WidgetColorClass { window, base, popover, accent, accentTone }

/// Palette math shared with the Conky Ulauncher widget.
class WidgetPalette {
  const WidgetPalette({
    required this.slot,
    required this.base,
    required this.widgetBg,
    required this.light,
    required this.accent,
    required this.dark,
    required this.sidebar,
    required this.popover,
  });

  final int slot;
  final int base;
  final int widgetBg;
  final int light;
  final int accent;
  final int dark;
  final int sidebar;
  final int popover;

  int get window => widgetBg;
  int get folder => accent;

  static Future<List<int>> readColors({String? path}) async {
    final home = Platform.environment['HOME'] ?? '';
    final file = File(path ?? '$home/Nebula/colors.txt');
    if (!await file.exists()) return const [];
    final result = <int>[];
    for (final line in await file.readAsLines()) {
      final match =
          RegExp(r'^\s*#?(?:ff)?([0-9a-fA-F]{6})\s*$').firstMatch(line);
      if (match != null) result.add(int.parse(match.group(1)!, radix: 16));
    }
    return result;
  }

  static WidgetPalette fromColors(List<int> colors, int slot) {
    if (slot < 1 || slot > colors.length) {
      throw RangeError.range(slot, 1, colors.length, 'slot');
    }
    final base = colors[slot - 1];
    final h = _hsv(base).$1;
    int adjust(int saturation, int value) =>
        _fromHsv(h, saturation / 100, value / 100);
    final bg = adjust(30, 20);
    final v = _hsv(bg).$3;
    return WidgetPalette(
      slot: slot,
      base: base,
      widgetBg: bg,
      light: adjust(16, 100),
      accent: adjust(58, 80),
      dark: adjust(66, 73),
      sidebar: _fromHsv(h, .30, v * .806),
      popover: _fromHsv(h, .30, v * .686),
    );
  }

  static String hex(int rgb) =>
      '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Returns the closest S/V class. Multiple entries mean an exact tie and
  /// must be left unchanged by the caller.
  static List<WidgetColorClass> classifyRgb(int rgb) {
    final (_, saturation, value) = _hsv(rgb);
    if (saturation < .20 || value < .12 || saturation >= .65) {
      return const [];
    }
    if (rgb == 0xe69875 || rgb == 0xa7c080 || rgb == 0xe67e80) {
      return const [];
    }

    const ranges = <WidgetColorClass, ((double, double), (double, double))>{
      WidgetColorClass.window: ((.25, .34), (.18, .22)),
      WidgetColorClass.base: ((.25, .34), (.15, .175)),
      WidgetColorClass.popover: ((.27, .35), (.125, .15)),
      WidgetColorClass.accent: ((.53, .63), (.76, .84)),
      WidgetColorClass.accentTone: ((.20, .50), (.66, .92)),
    };

    final matches = <(WidgetColorClass, double)>[];
    for (final entry in ranges.entries) {
      final saturationRange = entry.value.$1;
      final valueRange = entry.value.$2;
      final saturationCenter = (saturationRange.$1 + saturationRange.$2) / 2;
      final valueCenter = (valueRange.$1 + valueRange.$2) / 2;
      final ds = saturation - saturationCenter;
      final dv = value - valueCenter;
      matches.add((entry.key, ds * ds + dv * dv));
    }
    if (matches.isEmpty) return const [];
    matches.sort((a, b) => a.$2.compareTo(b.$2));
    final best = matches.first.$2;
    return List.unmodifiable(matches
        .where((match) => (match.$2 - best).abs() < 1e-12)
        .map((m) => m.$1));
  }

  /// Converts an S/V-classified color to the selected widget palette.
  /// Accent tones retain their own saturation and value while taking the new
  /// accent hue.
  static int mapClassifiedRgb(
      int rgb, WidgetColorClass colorClass, WidgetPalette palette) {
    switch (colorClass) {
      case WidgetColorClass.window:
        return palette.window;
      case WidgetColorClass.base:
        return palette.sidebar;
      case WidgetColorClass.popover:
        return palette.popover;
      case WidgetColorClass.accent:
        return palette.accent;
      case WidgetColorClass.accentTone:
        final (_, saturation, value) = _hsv(rgb);
        final (accentHue, _, _) = _hsv(palette.accent);
        return _fromHsv(accentHue, saturation, value);
    }
  }

  static bool isMappedRgb(
      int rgb, WidgetColorClass colorClass, WidgetPalette palette) {
    if (colorClass != WidgetColorClass.accentTone) {
      return rgb == mapClassifiedRgb(rgb, colorClass, palette);
    }
    final (hue, saturation, value) = _hsv(rgb);
    final (targetHue, _, _) = _hsv(palette.accent);
    final delta = ((hue - targetHue + 540) % 360) - 180;
    final mapped = mapClassifiedRgb(rgb, colorClass, palette);
    final (_, mappedSaturation, mappedValue) = _hsv(mapped);
    return delta.abs() <= 2 &&
        (saturation - mappedSaturation).abs() <= .02 &&
        (value - mappedValue).abs() <= .02;
  }

  static (double, double, double) _hsv(int rgb) {
    final r = ((rgb >> 16) & 255) / 255;
    final g = ((rgb >> 8) & 255) / 255;
    final b = (rgb & 255) / 255;
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final d = max - min;
    var h = 0.0;
    if (d != 0) {
      if (max == r) {
        h = ((g - b) / d) % 6;
      } else if (max == g) {
        h = (b - r) / d + 2;
      } else {
        h = (r - g) / d + 4;
      }
      h *= 60;
      if (h < 0) h += 360;
    }
    return (h, max == 0 ? 0 : d / max, max);
  }

  static int _fromHsv(double h, double s, double v) {
    final c = v * s;
    final x = c * (1 - (((h / 60) % 2) - 1).abs());
    final m = v - c;
    late double r, g, b;
    if (h < 60) {
      r = c;
      g = x;
      b = 0;
    } else if (h < 120) {
      r = x;
      g = c;
      b = 0;
    } else if (h < 180) {
      r = 0;
      g = c;
      b = x;
    } else if (h < 240) {
      r = 0;
      g = x;
      b = c;
    } else if (h < 300) {
      r = x;
      g = 0;
      b = c;
    } else {
      r = c;
      g = 0;
      b = x;
    }
    int channel(double n) => ((n + m) * 255).round().clamp(0, 255);
    return (channel(r) << 16) | (channel(g) << 8) | channel(b);
  }
}
