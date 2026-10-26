import 'dart:convert';
import 'dart:io';

class EngineSettings {
  const EngineSettings({
    this.mode = 'beta',
    this.engineVersion = 1,
    this.appliedHex,
    this.appliedAt,
    this.lastSnapshotId,
    this.baselineSnapshotId,
  });

  final String mode;
  final int engineVersion;
  final String? appliedHex;
  final String? appliedAt;
  final String? lastSnapshotId;
  final String? baselineSnapshotId;

  static String? _configDir;
  static String? get configDir => _configDir;

  static Future<EngineSettings> read({String? configDir}) async {
    final dir = configDir ?? _defaultConfigDir();
    _configDir = dir;
    try {
      final decoded = jsonDecode(await File('$dir/engine.json').readAsString());
      if (decoded is! Map) return const EngineSettings();
      return EngineSettings(
        mode: decoded['mode'] == 'classic' ? 'classic' : 'beta',
        engineVersion: decoded['engineVersion'] is int
            ? decoded['engineVersion'] as int
            : 1,
        appliedHex: decoded['appliedHex'] as String?,
        appliedAt: decoded['appliedAt'] as String?,
        lastSnapshotId: decoded['lastSnapshotId'] as String?,
        baselineSnapshotId: decoded['baselineSnapshotId'] as String?,
      );
    } catch (_) {
      return const EngineSettings();
    }
  }

  static String modeSync() {
    try {
      final dir = _configDir ?? _defaultConfigDir();
      final decoded = jsonDecode(File('$dir/engine.json').readAsStringSync());
      return decoded is Map && decoded['mode'] == 'classic'
          ? 'classic'
          : 'beta';
    } catch (_) {
      return 'beta';
    }
  }

  Future<EngineSettings> save({
    String? mode,
    String? appliedHex,
    String? appliedAt,
    String? lastSnapshotId,
    String? baselineSnapshotId,
    String? configDir,
  }) async {
    final next = EngineSettings(
      mode: mode ?? this.mode,
      engineVersion: engineVersion,
      appliedHex: appliedHex ?? this.appliedHex,
      appliedAt: appliedAt ?? this.appliedAt,
      lastSnapshotId: lastSnapshotId ?? this.lastSnapshotId,
      baselineSnapshotId: baselineSnapshotId ?? this.baselineSnapshotId,
    );
    try {
      final dir = configDir ?? _configDir ?? _defaultConfigDir();
      _configDir = dir;
      await Directory(dir).create(recursive: true);
      final file = File('$dir/engine.json');
      final temp =
          File('$dir/.engine-${DateTime.now().microsecondsSinceEpoch}.tmp');
      await temp.writeAsString(jsonEncode(next.toJson()), flush: true);
      await temp.rename(file.path);
    } catch (_) {}
    return next;
  }

  Map<String, Object?> toJson() => {
        'mode': mode,
        'engineVersion': engineVersion,
        'appliedHex': appliedHex,
        'appliedAt': appliedAt,
        'lastSnapshotId': lastSnapshotId,
        'baselineSnapshotId': baselineSnapshotId,
      };

  static String _defaultConfigDir() {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.config/nebulashade';
  }
}
