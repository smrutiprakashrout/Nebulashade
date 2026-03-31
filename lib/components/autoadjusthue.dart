import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';

Future<void> automaticColorAdjustment(String targetHexCode) async {
  // Define file paths
  final List<String> filePaths = [
    '${Platform.environment['HOME']}/.themes/Everforest-Dark-Soft-Adaptive/gtk-4.0/gtk.css',
    '${Platform.environment['HOME']}/.themes/Everforest-Dark-Soft-Adaptive/gtk-4.0/gtk-dark.css',
    '${Platform.environment['HOME']}/.themes/Everforest-Dark-Soft-Adaptive/gtk-3.0/gtk.css',
    '${Platform.environment['HOME']}/.themes/Everforest-Dark-Soft-Adaptive/gtk-3.0/gtk-dark.css',
    '${Platform.environment['HOME']}/.themes/Everforest-Dark-Soft-Adaptive/gnome-shell/gnome-shell.css',
    '${Platform.environment['HOME']}/.themes/Everforest-Dark-Soft-Adaptive/gnome-shell/pad-osd.css',
    '${Platform.environment['HOME']}/.config/gtk-4.0/gtk.css',
    '${Platform.environment['HOME']}/.config/gtk-4.0/gtk-dark.css',
  ];

  // Parse target color
  final targetColor = _parseColor(targetHexCode);
  if (targetColor == null) {
    // print("Invalid hex color provided: $targetHexCode");
    return;
  }

  // Extract target hue
  final targetHue = HSVColor.fromColor(targetColor).hue;
  // print("Target hue: $targetHue");

  try {
    // All files processed in parallel — no sequential awaits
    await Future.wait(filePaths.map((path) async {
      final file = File(path);
      if (!await file.exists()) return;
      String fileContent = await file.readAsString();
      final colorCodes = _extractColorsFromContent(fileContent);
      if (colorCodes.isEmpty) return;
      final double averageHue = _calculateAverageHue(colorCodes);
      final double hueShift = _calculateHueShift(targetHue, averageHue);
      for (String colorCode in colorCodes) {
        final shiftedColor = _shiftHuePreservingFormat(colorCode, hueShift);
        if (colorCode != shiftedColor) {
          fileContent = fileContent.replaceAll(colorCode, shiftedColor);
        }
      }
      await file.writeAsString(fileContent);
    }));
    
    // print("Color adjustment completed successfully!");
  } catch (e) {
    // print("Error during color adjustment: ${e.toString()}");
  }
}

// Extract colors from a single CSS content string
List<String> _extractColorsFromContent(String content) {
  final regex = RegExp(
    r'#(?:[0-9a-fA-F]{3}){1,2}' // hex
    r'|rgba?\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*(?:,\s*(?:\d*\.\d+|\d+))?\s*\)', // rgb/rgba
    caseSensitive: false,
  );

  final matches = <String>{};
  matches.addAll(regex.allMatches(content).map((m) => m.group(0)!));
  return matches.toList();
}

// Extract colors from CSS files
// Future<List<String>> _extractColorsFromCss(List<String> filePaths) async {
//   final fileContents = await Future.wait(filePaths.map((path) async {
//     final file = File(path);
//     if (await file.exists()) {
//       return await file.readAsString();
//     }
//     return '';
//   }));

//   final allMatches = <String>{};
//   for (var content in fileContents) {
//     allMatches.addAll(_extractColorsFromContent(content));
//   }

//   return allMatches.toList();
// }

// Parse color string to Color object with improved error handling
Color? _parseColor(String code) {
  try {
    if (code.startsWith('#')) {
      final hex = code.substring(1);
      if (hex.length == 3) {
        // Convert 3-digit hex to 6-digit
        final r = int.parse('${hex[0]}${hex[0]}', radix: 16);
        final g = int.parse('${hex[1]}${hex[1]}', radix: 16);
        final b = int.parse('${hex[2]}${hex[2]}', radix: 16);
        return Color.fromARGB(255, r, g, b);
      } else if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    } else if (code.startsWith('rgba')) {
      final values = code
          .replaceAll(RegExp(r'[rgba() ]'), '')
          .split(',')
          .map((s) => s.trim())
          .toList();

      if (values.length < 3) return null;

      final r = int.parse(values[0]);
      final g = int.parse(values[1]);
      final b = int.parse(values[2]);
      final a = values.length == 4 
          ? (double.parse(values[3]) * 255).round() 
          : 255;

      return Color.fromARGB(a, r, g, b);
    } else if (code.startsWith('rgb')) {
      final values = code
          .replaceAll(RegExp(r'[rgb() ]'), '')
          .split(',')
          .map((s) => s.trim())
          .toList();

      if (values.length < 3) return null;

      final r = int.parse(values[0]);
      final g = int.parse(values[1]);
      final b = int.parse(values[2]);

      return Color.fromRGBO(r, g, b, 1.0);
    }
  } catch (e) {
    // print("Error parsing color '$code': ${e.toString()}");
  }
  return null;
}

// Calculate the proper average hue from a list of color codes
double _calculateAverageHue(List<String> colorCodes) {
  // Vector averaging for circular hue values
  double sumSin = 0;
  double sumCos = 0;
  int validCount = 0;

  for (String colorCode in colorCodes) {
    final color = _parseColor(colorCode);
    if (color != null) {
      // Convert hue to radians and perform vector addition
      final hueRadians = HSVColor.fromColor(color).hue * pi / 180;
      sumSin += sin(hueRadians);
      sumCos += cos(hueRadians);
      validCount++;
    }
  }

  if (validCount == 0) return 0;

  // Calculate the average angle and convert back to degrees
  final avgHueRadians = atan2(sumSin / validCount, sumCos / validCount);
  // Convert back to degrees (0-360 range)
  double avgHue = (avgHueRadians * 180 / pi) % 360;
  if (avgHue < 0) avgHue += 360;
  
  return avgHue;
}

// Calculate the shortest distance between two hues
double _calculateHueShift(double targetHue, double currentHue) {
  // Calculate both clockwise and counterclockwise distance
  double clockwise = (targetHue - currentHue) % 360;
  double counterClockwise = (currentHue - targetHue) % 360;
  
  // Use the shorter distance
  return clockwise <= counterClockwise ? clockwise : -counterClockwise;
}

// Shift hue of a color while preserving its original format
String _shiftHuePreservingFormat(String colorCode, double hueShift) {
  final color = _parseColor(colorCode);
  if (color == null) return colorCode;

  final hsv = HSVColor.fromColor(color);
  // Ensure hue stays within 0-360 range
  final newHue = (hsv.hue + hueShift) % 360;
  final newColor = hsv.withHue(newHue).toColor();

  if (colorCode.startsWith('#')) {
    final originalHex = colorCode.substring(1);
    // Preserve original format (3 or 6 digits)
    if (originalHex.length == 3) {
      // For 3-digit hex, round to closest single digit
      final r = (newColor.red / 17).round().toRadixString(16);
      final g = (newColor.green / 17).round().toRadixString(16);
      final b = (newColor.blue / 17).round().toRadixString(16);
      return '#$r$g$b';
    } else {
      // For 6-digit hex
      return '#${newColor.red.toRadixString(16).padLeft(2, '0')}${newColor.green.toRadixString(16).padLeft(2, '0')}${newColor.blue.toRadixString(16).padLeft(2, '0')}';
    }
  } else if (colorCode.startsWith('rgba')) {
    // Extract original alpha value format
    final alphaMatch = RegExp(r',\s*([\d.]+)\s*\)').firstMatch(colorCode);
    final originalAlpha = alphaMatch?.group(1) ?? newColor.opacity.toStringAsFixed(2);
    
    return 'rgba(${newColor.red}, ${newColor.green}, ${newColor.blue}, $originalAlpha)';
  } else if (colorCode.startsWith('rgb')) {
    return 'rgb(${newColor.red}, ${newColor.green}, ${newColor.blue})';
  }

  return colorCode;
}