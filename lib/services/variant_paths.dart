import 'package:path/path.dart' as path;

class VariantPaths {
  static List<String> forDark(String home) => [
        '$home/.themes/Everforest-Dark-Soft-Adaptive/gtk-4.0/gtk.css',
        '$home/.themes/Everforest-Dark-Soft-Adaptive/gtk-4.0/gtk-dark.css',
        '$home/.themes/Everforest-Dark-Soft-Adaptive/gtk-3.0/gtk.css',
        '$home/.themes/Everforest-Dark-Soft-Adaptive/gtk-3.0/gtk-dark.css',
        '$home/.themes/Everforest-Dark-Soft-Adaptive/gnome-shell/gnome-shell.css',
        '$home/.themes/Everforest-Dark-Soft-Adaptive/gnome-shell/pad-osd.css',
        '$home/.config/gtk-4.0/gtk.css',
        '$home/.config/gtk-4.0/gtk-dark.css',
      ];

  static List<String> forLight(String home, String lightThemePath) => [
        '$lightThemePath/gtk-4.0/gtk.css',
        '$lightThemePath/gtk-4.0/gtk-dark.css',
        '$lightThemePath/gtk-3.0/gtk.css',
        '$lightThemePath/gtk-3.0/gtk-dark.css',
        '$lightThemePath/gnome-shell/gnome-shell.css',
        '$lightThemePath/gnome-shell/pad-osd.css',
        '$home/.config/gtk-4.0/gtk.css',
        '$home/.config/gtk-4.0/gtk-dark.css',
      ];

  static bool isUnderHome(String filePath, String home) {
    try {
      if (path.split(filePath).contains('..')) return false;
      final normalizedPath = path.normalize(filePath);
      final normalizedHome = path.normalize(home);
      return path.isWithin(normalizedHome, normalizedPath);
    } catch (_) {
      return false;
    }
  }
}
