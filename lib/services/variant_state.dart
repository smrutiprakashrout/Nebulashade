import 'dart:convert';
import 'dart:io';

class VariantState {
  static String activeVariantIdSync({String? configDir}) {
    try {
      final directory = _configDir(configDir);
      if (directory.isEmpty) return 'dark';
      final data = jsonDecode(
        File('$directory${Platform.pathSeparator}config.json')
            .readAsStringSync(),
      );
      if (data is Map && data['activeVariant'] == 'light') return 'light';
    } catch (_) {
      // A missing or invalid config preserves the safe dark default.
    }
    return 'dark';
  }

  static Future<void> write({
    required String activeVariant,
    required Map<String, Map<String, String>> variants,
    required String lastSwitch,
    String? configDir,
  }) async {
    final directory = _configDir(configDir);
    if (directory.isEmpty) return;
    String? tempPath;
    try {
      await Directory(directory).create(recursive: true);
      final configPath = '$directory${Platform.pathSeparator}config.json';
      tempPath =
          '$directory${Platform.pathSeparator}.config-${DateTime.now().microsecondsSinceEpoch}.tmp';
      final json = jsonEncode({
        'activeVariant': activeVariant,
        'variants': variants,
        'lastSwitch': lastSwitch,
      });
      await File(tempPath).writeAsString(json, flush: true);
      await File(tempPath).rename(configPath);
    } catch (_) {
      if (tempPath != null) {
        try {
          final temp = File(tempPath);
          if (await temp.exists()) await temp.delete();
        } catch (_) {}
      }
    }
  }

  static Future<void> recordApplied(String variantId, String hex,
      {String? configDir}) async {
    final directory = _configDir(configDir);
    if (directory.isEmpty) return;
    String? tempPath;
    try {
      final configPath = '$directory${Platform.pathSeparator}config.json';
      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(await File(configPath).readAsString());
        data = decoded is Map<String, dynamic>
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{'activeVariant': 'dark'};
      } catch (_) {
        data = <String, dynamic>{'activeVariant': 'dark'};
      }

      final existingApplied = data['appliedHex'];
      final appliedHex = existingApplied is Map
          ? Map<String, dynamic>.from(existingApplied)
          : <String, dynamic>{};
      appliedHex[variantId] = hex;
      data['appliedHex'] = appliedHex;
      data['lastAppliedHex'] = hex;

      await Directory(directory).create(recursive: true);
      tempPath =
          '$directory${Platform.pathSeparator}.applied-${DateTime.now().microsecondsSinceEpoch}.tmp';
      await File(tempPath).writeAsString(jsonEncode(data), flush: true);
      await File(tempPath).rename(configPath);
    } catch (_) {
      if (tempPath != null) {
        try {
          final temp = File(tempPath);
          if (await temp.exists()) await temp.delete();
        } catch (_) {}
      }
    }
  }

  static String snapshotDir(String id, {String? configDir}) {
    final directory = _configDir(configDir);
    if (directory.isEmpty) return '';
    return '$directory${Platform.pathSeparator}variants${Platform.pathSeparator}$id${Platform.pathSeparator}gtk-4.0';
  }

  static String backupsDir({String? configDir}) {
    final directory = _configDir(configDir);
    if (directory.isEmpty) return '';
    return '$directory${Platform.pathSeparator}backups';
  }

  static String _configDir(String? configDir) {
    if (configDir != null) return configDir;
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return '';
    return '$home${Platform.pathSeparator}.config${Platform.pathSeparator}nebulashade';
  }
}
