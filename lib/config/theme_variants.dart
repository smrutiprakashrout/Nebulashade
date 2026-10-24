import 'dart:io';

class ThemeVariant {
  final String id;
  final String label;
  final String folderName;

  const ThemeVariant({
    required this.id,
    required this.label,
    required this.folderName,
  });
}

class ThemeVariants {
  static const dark = ThemeVariant(
    id: 'dark',
    label: 'Everforest Dark',
    folderName: 'Everforest-Dark-Soft-Adaptive',
  );

  static const light = ThemeVariant(
    id: 'light',
    label: 'Everforest Light',
    folderName: 'Everforest-Light-Soft-Adaptive',
  );

  static const List<String> requiredFiles = [
    'index.theme',
    'gtk-3.0/gtk.css',
    'gtk-4.0/gtk.css',
    'gnome-shell/gnome-shell.css',
  ];

  static const String lightDownloadUrl =
      'https://github.com/OWNER/REPO/releases/download/TAG/Everforest-Light-Soft-Adaptive.zip'; // TODO: replace with the real URL
  static const String lightDownloadSha256 =
      ''; // TODO: optional lowercase hex SHA-256 of the zip; if non-empty it is enforced
  static const int maxDownloadBytes = 200 * 1024 * 1024;

  static bool get lightDownloadConfigured {
    final uri = Uri.tryParse(lightDownloadUrl);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        !lightDownloadUrl.contains('OWNER/REPO');
  }

  static List<String> searchDirs() {
    final home = Platform.environment['HOME'];
    return [
      if (home != null) '$home/.themes',
      if (home != null) '$home/.local/share/themes',
      '/usr/share/themes',
    ];
  }
}
