import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nebulashade/constants/colours.dart';

List<String> colorCodes = [];
List<String> modifiedColorCodes = [];
List<int> selectedIndexes = [];
double hueShift = 0;
String originalCssContent = '';

// ---------------------------------------------------------------------------
// Pure Dart CSS patcher — zero bash/awk processes.
// Read once → patch all selectors in memory → write once per file.
// ---------------------------------------------------------------------------
String applyButtonColors(
  String css, {
  required String minimize,
  required String maximize,
  required String close,
}) {
  String replaceInBlock(String src, String selector, String newValue) {
    final re = RegExp(
      '(' + RegExp.escape(selector) + r'\s*\{[^}]*background-color:\s*)([^;]+)(;)',
      dotAll: true,
    );
    return src.replaceAllMapped(re, (m) => '${m[1]}$newValue${m[3]}');
  }

  var r = css;
  // GTK4 windowcontrols
  r = replaceInBlock(r, 'windowcontrols button.minimize:not(.suggested-action):not(.destructive-action)', minimize);
  r = replaceInBlock(r, 'windowcontrols button.minimize:hover:not(.suggested-action):not(.destructive-action)', 'shade($minimize, 0.4)');
  r = replaceInBlock(r, 'windowcontrols button.minimize:active:not(.suggested-action):not(.destructive-action)', 'shade($minimize, 0.6)');
  r = replaceInBlock(r, 'windowcontrols button.maximize:not(.suggested-action):not(.destructive-action)', maximize);
  r = replaceInBlock(r, 'windowcontrols button.maximize:hover:not(.suggested-action):not(.destructive-action)', 'shade($maximize, 0.4)');
  r = replaceInBlock(r, 'windowcontrols button.maximize:active:not(.suggested-action):not(.destructive-action)', 'shade($maximize, 0.6)');
  r = replaceInBlock(r, 'windowcontrols button.close:not(.suggested-action):not(.destructive-action)', close);
  r = replaceInBlock(r, 'windowcontrols button.close:hover:not(.suggested-action):not(.destructive-action)', 'shade($close, 0.4)');
  r = replaceInBlock(r, 'windowcontrols button.close:active:not(.suggested-action):not(.destructive-action)', 'shade($close, 0.6)');
  // GTK3 titlebuttons
  r = replaceInBlock(r, 'button.close.titlebutton:not(.suggested-action):not(.destructive-action)', close);
  r = replaceInBlock(r, 'button.close.titlebutton:hover:not(.suggested-action):not(.destructive-action)', 'shade($close, 0.4)');
  r = replaceInBlock(r, 'button.close.titlebutton:active:not(.suggested-action):not(.destructive-action)', 'shade($close, 0.6)');
  r = replaceInBlock(r, '.background.csd headerbar.titlebar.default-decoration button.close.titlebutton:hover:not(.suggested-action):not(.destructive-action)', 'shade($close, 0.4)');
  r = replaceInBlock(r, '.background.csd headerbar.titlebar.default-decoration button.close.titlebutton:active:not(.suggested-action):not(.destructive-action)', 'shade($close, 0.6)');
  r = replaceInBlock(r, 'button.minimize.titlebutton:not(.suggested-action):not(.destructive-action)', minimize);
  r = replaceInBlock(r, 'button.minimize.titlebutton:hover:not(.suggested-action):not(.destructive-action)', 'shade($minimize, 0.4)');
  r = replaceInBlock(r, 'button.minimize.titlebutton:active:not(.suggested-action):not(.destructive-action)', 'shade($minimize, 0.6)');
  r = replaceInBlock(r, '.background.csd headerbar.titlebar.default-decoration button.minimize.titlebutton:hover:not(.suggested-action):not(.destructive-action)', 'shade($minimize, 0.4)');
  r = replaceInBlock(r, '.background.csd headerbar.titlebar.default-decoration button.minimize.titlebutton:active:not(.suggested-action):not(.destructive-action)', 'shade($minimize, 0.6)');
  r = replaceInBlock(r, 'button.maximize.titlebutton:not(.suggested-action):not(.destructive-action)', maximize);
  r = replaceInBlock(r, 'button.maximize.titlebutton:hover:not(.suggested-action):not(.destructive-action)', 'shade($maximize, 0.4)');
  r = replaceInBlock(r, 'button.maximize.titlebutton:active:not(.suggested-action):not(.destructive-action)', 'shade($maximize, 0.6)');
  r = replaceInBlock(r, '.background.csd headerbar.titlebar.default-decoration button.maximize.titlebutton:hover:not(.suggested-action):not(.destructive-action)', 'shade($maximize, 0.4)');
  r = replaceInBlock(r, '.background.csd headerbar.titlebar.default-decoration button.maximize.titlebutton:active:not(.suggested-action):not(.destructive-action)', 'shade($maximize, 0.6)');
  return r;
}

// ---------------------------------------------------------------------------
// Derive button colors from AppColors so they always match the live theme.
// These are computed fresh each call so they reflect whatever AppColors
// was last init()'d with.
// ---------------------------------------------------------------------------
String _hex(Color c) =>
    '#${c.red.toRadixString(16).padLeft(2, '0')}${c.green.toRadixString(16).padLeft(2, '0')}${c.blue.toRadixString(16).padLeft(2, '0')}';

String get _minimizeColor {
  final hsv = HSVColor.fromColor(AppColors.accent);
  // Warm amber — hue ~30°, preserves saturation feel of accent
  return _hex(HSVColor.fromAHSV(
          1.0, 30, (hsv.saturation * 0.9).clamp(0.45, 0.90), (hsv.value * 1.1).clamp(0.55, 0.85))
      .toColor());
}

String get _maximizeColor {
  final hsv = HSVColor.fromColor(AppColors.accent);
  // Soft green — hue ~120°
  return _hex(HSVColor.fromAHSV(
          1.0, 120, (hsv.saturation * 0.7).clamp(0.35, 0.80), 0.63)
      .toColor());
}

String get _closeColor {
  final hsv = HSVColor.fromColor(AppColors.accent);
  // Coral red — hue 0°
  return _hex(HSVColor.fromAHSV(
          1.0, 0, (hsv.saturation * 0.85).clamp(0.50, 0.90), 0.68)
      .toColor());
}

// ---------------------------------------------------------------------------
// Public apply entry point
// ---------------------------------------------------------------------------
Future<void> applyTheme(
  BuildContext context,
  List<String> filePaths,
  Future<void> Function() updateCssFileCallback,
) async {
  if (!context.mounted) return;
  Navigator.pop(context);
  await updateCssFileCallback();

  final minimize = _minimizeColor;
  final maximize = _maximizeColor;
  final close = _closeColor;

  // All files in parallel — zero awk spawns
  await Future.wait(filePaths.map((path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final css = await file.readAsString();
    final patched = applyButtonColors(css, minimize: minimize, maximize: maximize, close: close);
    if (patched != css) await file.writeAsString(patched);
  }));

  // Both theme reloads in a single bash process
  await Process.run('bash', ['-c',
    "t=\$(gsettings get org.gnome.shell.extensions.user-theme name | tr -d \"'\"); "
    "gsettings set org.gnome.shell.extensions.user-theme name 'Adwaita'; "
    "gsettings set org.gnome.shell.extensions.user-theme name \"\$t\"; "
    "t2=\$(gsettings get org.gnome.desktop.interface gtk-theme | tr -d \"'\"); "
    "gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'; "
    "gsettings set org.gnome.desktop.interface gtk-theme \"\$t2\""
  ]);

  // Re-read gtk.css so AppColors.background matches the newly written theme —
  // this is what was causing the app bg vs shell bg mismatch.
  AppColors.init();

  await Process.run('notify-send', [
    '-i', 'dialog-information', '-a', 'NebulaShade',
    '-u', 'normal', '-t', '4000',
    'Theme Updated', 'Accent colors and GTK themes refreshed!',
  ]);
}
