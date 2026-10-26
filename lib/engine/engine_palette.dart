import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nebulashade/services/widget_palette.dart';

class SemanticTone {
  const SemanticTone({required this.fg, required this.bg, required this.onBg});

  final Color fg;
  final Color bg;
  final Color onBg;
}

class EnginePalette {
  EnginePalette._({
    required this.base,
    required this.window,
    required this.view,
    required this.sidebar,
    required this.popover,
    required this.accent,
    required this.light,
    required this.dark,
    required this.error,
    required this.warning,
    required this.success,
    required this.destructive,
  });

  factory EnginePalette.fromBase(Color base) {
    final rgb = base.value & 0xFFFFFF;
    final legacy = WidgetPalette.fromColors([rgb], 1);
    final saturation = HSVColor.fromColor(Color(0xFF000000 | rgb)).saturation;
    final semanticSaturation = (saturation * .95).clamp(.45, .72).toDouble();
    SemanticTone tone(double hue) {
      final fg = ensureContrast(
        _hsl(hue, semanticSaturation, .70),
        Color(0xFF000000 | legacy.window),
        4.5,
      );
      final bg = ensureContrast(
        _hsl(hue, semanticSaturation, .50),
        Color(0xFF000000 | legacy.window),
        3,
      );
      final onBg = ensureContrast(Colors.white, bg, 4.5);
      return SemanticTone(fg: fg, bg: bg, onBg: onBg);
    }

    final error = tone(2);
    return EnginePalette._(
      base: Color(0xFF000000 | rgb),
      window: Color(0xFF000000 | legacy.window),
      // The legacy palette exposes a window surface but no separate view role.
      // Keep the view surface on that same neutral base until a source role is
      // added to the shared palette.
      view: Color(0xFF000000 | legacy.window),
      sidebar: Color(0xFF000000 | legacy.sidebar),
      popover: Color(0xFF000000 | legacy.popover),
      accent: Color(0xFF000000 | legacy.accent),
      light: Color(0xFF000000 | legacy.light),
      dark: Color(0xFF000000 | legacy.dark),
      error: error,
      warning: tone(40),
      success: tone(112),
      destructive: error,
    );
  }

  final Color base;
  final Color window;
  final Color view;
  final Color sidebar;
  final Color popover;
  final Color accent;
  final Color light;
  final Color dark;
  final SemanticTone error;
  final SemanticTone warning;
  final SemanticTone success;
  final SemanticTone destructive;

  static Color _hsl(double hue, double saturation, double lightness) =>
      HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();
}

/// Moves only HSL lightness, in 0.01 steps, until WCAG contrast is reached.
Color ensureContrast(Color fg, Color bg, double min) {
  if (_contrast(fg, bg) >= min) return fg;
  final hsl = HSLColor.fromColor(fg);
  Color? best;
  var bestDistance = double.infinity;
  for (final direction in const [-1, 1]) {
    for (var step = 1; step <= 100; step++) {
      final l = (hsl.lightness + direction * step / 100).clamp(0.0, 1.0);
      final candidate = hsl.withLightness(l).toColor();
      if (_contrast(candidate, bg) >= min) {
        final distance = (l - hsl.lightness).abs();
        if (distance < bestDistance) {
          best = candidate;
          bestDistance = distance;
        }
        break;
      }
    }
  }
  return best ?? (_luminance(bg) > .5 ? Colors.black : Colors.white);
}

double _contrast(Color a, Color b) {
  final l1 = _luminance(a), l2 = _luminance(b);
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + .05) / (lo + .05);
}

double _luminance(Color color) {
  double channel(int value) {
    final c = value / 255;
    return c <= .04045
        ? c / 12.92
        : math.pow((c + .055) / 1.055, 2.4).toDouble();
  }

  return .2126 * channel(color.red) +
      .7152 * channel(color.green) +
      .0722 * channel(color.blue);
}
