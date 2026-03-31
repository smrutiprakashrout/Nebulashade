import 'dart:io';
import 'package:nebulashade/components/autoadjusthue.dart';
import 'package:nebulashade/components/apply_theme.dart';
import 'package:nebulashade/constants/colours.dart';

List<String> colorCodes = [];
List<String> modifiedColorCodes = [];
List<int> selectedIndexes = [];
double hueShift = 0;
String originalCssContent = '';

Future<void> quickapplyTheme(String hexColor) async {
  final home = Platform.environment['HOME']!;

  final List<String> filePaths = [
    '$home/.themes/Everforest-Dark-Soft-Adaptive/gtk-4.0/gtk.css',
    '$home/.themes/Everforest-Dark-Soft-Adaptive/gtk-4.0/gtk-dark.css',
    '$home/.themes/Everforest-Dark-Soft-Adaptive/gtk-3.0/gtk.css',
    '$home/.themes/Everforest-Dark-Soft-Adaptive/gtk-3.0/gtk-dark.css',
    '$home/.themes/Everforest-Dark-Soft-Adaptive/gnome-shell/gnome-shell.css',
    '$home/.themes/Everforest-Dark-Soft-Adaptive/gnome-shell/pad-osd.css',
    '$home/.config/gtk-4.0/gtk.css',
    '$home/.config/gtk-4.0/gtk-dark.css',
  ];

  // Constant button colors - never shift with the hue adjustment
  const minimize = '#e69875';
  const maximize = '#a7c080';
  const close    = '#e67e80';

  // Step 1: hue shift all files first — must complete before step 2.
  // automaticColorAdjustment rewrites every color, so running concurrently
  // would clobber the button colors we apply in step 2.
  await automaticColorAdjustment(hexColor);

  // Step 2: patch button colors on top of the hue-shifted files, in parallel.
  await Future.wait(filePaths.map((path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final css = await file.readAsString();
    final patched = applyButtonColors(
        css, minimize: minimize, maximize: maximize, close: close);
    if (patched != css) await file.writeAsString(patched);
  }));

  // Reload shell theme and gtk theme — use sed to strip quotes instead of tr -d
  // to avoid single-quote escaping issues in Dart string literals.
  final shellTheme = (await Process.run('gsettings',
          ['get', 'org.gnome.shell.extensions.user-theme', 'name']))
      .stdout
      .toString()
      .trim()
      .replaceAll("'", '');

  final gtkTheme = (await Process.run(
          'gsettings', ['get', 'org.gnome.desktop.interface', 'gtk-theme']))
      .stdout
      .toString()
      .trim()
      .replaceAll("'", '');

  // Toggle shell theme: Adwaita → original (forces GNOME Shell to reload CSS)
  await Process.run('gsettings',
      ['set', 'org.gnome.shell.extensions.user-theme', 'name', 'Adwaita']);
  await Process.run('gsettings',
      ['set', 'org.gnome.shell.extensions.user-theme', 'name', shellTheme]);

  // Toggle GTK theme: Adwaita → original (forces GTK apps to reload CSS)
  await Process.run('gsettings',
      ['set', 'org.gnome.desktop.interface', 'gtk-theme', 'Adwaita']);
  await Process.run('gsettings',
      ['set', 'org.gnome.desktop.interface', 'gtk-theme', gtkTheme]);

  // Re-sync AppColors so app background matches the newly written CSS
  AppColors.init();

  await Process.run('notify-send', [
    '-i', 'dialog-information', '-a', 'NebulaShade',
    '-u', 'normal', '-t', '4000',
    'Theme Updated', 'Accent colors and GTK themes refreshed!',
  ]);
}
