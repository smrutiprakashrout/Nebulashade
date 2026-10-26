import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/engine/engine_palette.dart';
import 'package:nebulashade/services/widget_palette.dart';

void main() {
  test('deterministic palette matches WidgetPalette legacy roles', () {
    for (final color in [const Color(0xffcea14f), const Color(0xff4f7ace)]) {
      final a = EnginePalette.fromBase(color);
      final b = EnginePalette.fromBase(color);
      final old = WidgetPalette.fromColors([color.value & 0xffffff], 1);
      expect(a.window, Color(0xff000000 | old.window));
      expect(a.sidebar, Color(0xff000000 | old.sidebar));
      expect(a.popover, Color(0xff000000 | old.popover));
      expect(a.accent, Color(0xff000000 | old.accent));
      expect(a.light, Color(0xff000000 | old.light));
      expect(a.dark, Color(0xff000000 | old.dark));
      expect(a.error.bg, b.error.bg);
    }
  });

  test('semantic tones meet contrast and hue requirements for varied bases',
      () {
    const bases = [
      Color(0xffcea14f),
      Color(0xff4f7ace),
      Color(0xff5fae6b),
      Color(0xff824fc1),
      Color(0xff08090a),
      Color(0xfff4f4f4),
      Color(0xff808080),
      Color(0xffc83e29),
      Color(0xff27a6a2),
      Color(0xffe2cfaa),
      Color(0xff381f53),
      Color(0xffb6d9c0),
    ];
    for (final base in bases) {
      final p = EnginePalette.fromBase(base);
      for (final role in [p.error, p.warning, p.success, p.destructive]) {
        expect(contrast(role.fg, p.window), greaterThanOrEqualTo(4.5));
        expect(contrast(role.bg, p.window), greaterThanOrEqualTo(3));
        expect(contrast(role.onBg, role.bg), greaterThanOrEqualTo(4.5));
      }
      expect(hue(p.error.bg), closeTo(2, 5));
      expect(hue(p.warning.bg), closeTo(40, 5));
      expect(hue(p.success.bg), closeTo(112, 5));
    }
  });
}

double contrast(Color a, Color b) {
  double lum(Color c) {
    double f(int x) {
      final v = x / 255;
      return v <= .04045
          ? v / 12.92
          : math.pow((v + .055) / 1.055, 2.4).toDouble();
    }

    return .2126 * f(c.red) + .7152 * f(c.green) + .0722 * f(c.blue);
  }

  final x = lum(a), y = lum(b);
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

double hue(Color c) => HSVColor.fromColor(c).hue;
