import 'package:flutter/material.dart';
import 'dart:io';
import 'package:nebulashade/services/variant_state.dart';

class AppColors {
  static late Color background;
  static late Color textPrimary;

  // Static fallback/defaults (used if GTK parsing fails)
  static const Color fallbackBackground = Color(0xFF11161f);
  static const Color fallbackTextPrimary = Color(0xFF8ca2bf);

  static const Color cardBackground = Color(0xFF1d2735);
  static const Color primary = Color(0xFF1E2532);
  static const Color secondary = Color(0xFF2C3442);
  static const Color accent = Color(0xFF91a0b7);
  static const Color buttonBackground = Color(0xFF2a384c);
  static const Color buttonText = Colors.white70;
  static const Color subtext = Color(0xFFbdcadb);
  static const Color border = Color(0xFFbdcadb);
  static const Color switchActive = Color(0xFFbdcadb);
  static const Color switchInactive = Color(0xFF4A4F5A);
  static const Color icon = Colors.white70;
  static const Color textprimary = Colors.white70;
  static Color lighten(Color color, [double amount = 0.1]) {
    final hsl = HSLColor.fromColor(color);
    final lighter = hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
    return lighter.toColor();
  }

  static Color adjustColor(Color color,
      {int saturationDelta = 0, int valueDelta = 0}) {
    final hsv = HSVColor.fromColor(color);

    final newSaturation = (saturationDelta.clamp(0, 100)) / 100;
    final newValue = (valueDelta.clamp(0, 100)) / 100;

    final adjusted = hsv.withSaturation(newSaturation).withValue(newValue);
    return adjusted.toColor();
  }

  static late Color accentdark;
  static late Color accentbrite;

  /// Call this before using any colors (e.g., in main function)
  static void init() {
    try {
      final liveFile =
          File('${Platform.environment['HOME']}/.config/gtk-4.0/gtk.css');
      var file = liveFile;
      try {
        if (VariantState.activeVariantIdSync() == 'light') {
          final darkSnapshot =
              '${VariantState.snapshotDir('dark')}${Platform.pathSeparator}gtk.css';
          if (File(darkSnapshot).existsSync()) file = File(darkSnapshot);
        }
      } catch (_) {
        file = liveFile;
      }
      String contents;
      try {
        contents = file.readAsStringSync();
      } catch (_) {
        contents = liveFile.readAsStringSync();
      }

      final bgMatch =
          RegExp(r'background-color:\s*(#[A-Fa-f0-9]{6})').firstMatch(contents);
      final colorMatch =
          RegExp(r'color:\s*(#[A-Fa-f0-9]{6})').firstMatch(contents);

      background = bgMatch != null
          ? _parseHexColor(bgMatch.group(1)!)
          : fallbackBackground;

      textPrimary = colorMatch != null
          ? _parseHexColor(colorMatch.group(1)!)
          : fallbackTextPrimary;

      accentdark = adjustColor(background, saturationDelta: 70, valueDelta: 18);
      accentbrite =
          adjustColor(background, saturationDelta: 70, valueDelta: 68);
    } catch (e) {
      background = fallbackBackground;
      textPrimary = fallbackTextPrimary;
      print('Failed to load GTK theme: $e');
    }
  }

  static Color _parseHexColor(String hex) {
    final clean = hex.replaceAll('#', '').toUpperCase();
    return Color(int.parse('FF$clean', radix: 16));
  }
}
