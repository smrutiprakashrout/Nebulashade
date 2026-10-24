import 'dart:io';

import 'package:nebulashade/config/theme_variants.dart';
import 'package:nebulashade/services/gsettings_runner.dart';
import 'package:nebulashade/services/theme_detector.dart';
import 'package:nebulashade/services/variant_state.dart';

class SwitchResult {
  final bool ok;
  final String message;
  final bool rolledBack;

  const SwitchResult({
    required this.ok,
    required this.message,
    this.rolledBack = false,
  });
}

class ThemeSwitcher {
  static bool _inProgress = false;

  static bool get busy => _inProgress;

  final GsettingsRunner _gs;
  final ThemeDetector _detector;
  final String? _configDir;
  final String _liveGtk4Dir;
  final ThemeVariant darkVariant;
  final ThemeVariant lightVariant;

  ThemeSwitcher({
    GsettingsRunner? gs,
    ThemeDetector? detector,
    String? configDir,
    String? liveGtk4Dir,
    ThemeVariant? darkVariant,
    ThemeVariant? lightVariant,
  })  : _gs = gs ?? ProcessGsettingsRunner(),
        _detector = detector ?? ThemeDetector(),
        _configDir = configDir,
        _liveGtk4Dir = liveGtk4Dir ?? _defaultLiveGtk4Dir(),
        darkVariant = darkVariant ?? ThemeVariants.dark,
        lightVariant = lightVariant ?? ThemeVariants.light;

  static String _defaultLiveGtk4Dir() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return '';
    return '$home${Platform.pathSeparator}.config${Platform.pathSeparator}gtk-4.0';
  }

  Future<String?> currentVariantId() async {
    try {
      final result = await _gs.get(gtkInterfaceSchema, gtkThemeKey);
      if (!result.ok) return null;
      return _variantIdForTheme(result.value);
    } catch (_) {
      return null;
    }
  }

  Future<SwitchResult> switchTo(ThemeVariant target) async {
    if (_inProgress) {
      return const SwitchResult(
        ok: false,
        message: 'A switch is already in progress',
      );
    }
    _inProgress = true;

    Map<String, String?>? previousValues;
    Map<String, List<int>?>? previousFiles;
    String? backupPath;
    var backupComplete = false;

    try {
      final ThemeCheckResult? darkResult;
      final ThemeCheckResult? lightResult;
      if (_sameVariant(darkVariant, ThemeVariants.dark) &&
          _sameVariant(lightVariant, ThemeVariants.light)) {
        final checks = await _detector.checkAll();
        darkResult = checks[darkVariant.id];
        lightResult = checks[lightVariant.id];
      } else {
        darkResult = await _detector.check(darkVariant);
        lightResult = await _detector.check(lightVariant);
      }

      final gtkTheme = await _gs.get(gtkInterfaceSchema, gtkThemeKey);
      final colorScheme = await _gs.get(gtkInterfaceSchema, colorSchemeKey);
      final shellTheme = await _gs.get(userThemeSchema, userThemeNameKey);
      if (!shellTheme.ok) {
        return const SwitchResult(
          ok: false,
          message: 'GNOME User Themes extension is not available',
        );
      }
      if (!gtkTheme.ok || !colorScheme.ok) {
        return const SwitchResult(
          ok: false,
          message: 'Could not read the current GNOME theme settings',
        );
      }

      final currentId = _variantIdForTheme(gtkTheme.value);
      final targetId = _variantIdForTarget(target);
      if (targetId == null) {
        return const SwitchResult(ok: false, message: 'Unknown theme variant');
      }
      if (currentId == null) {
        return const SwitchResult(
          ok: false,
          message: 'Current theme is not an Everforest variant',
        );
      }
      if (targetId == currentId) {
        return const SwitchResult(ok: true, message: 'Already active');
      }

      final darkComplete = darkResult?.status == ThemeStatus.complete;
      final lightComplete = lightResult?.status == ThemeStatus.complete;
      final emergencyDarkRestore =
          targetId == darkVariant.id && currentId == lightVariant.id;
      if (!darkComplete || (!lightComplete && !emergencyDarkRestore)) {
        return const SwitchResult(
          ok: false,
          message: 'Both Everforest variants must be complete to switch',
        );
      }

      if (_liveGtk4Dir.isEmpty) {
        return const SwitchResult(
          ok: false,
          message: 'Could not locate ~/.config/gtk-4.0',
        );
      }
      for (final name in ['gtk.css', 'gtk-dark.css']) {
        final filePath = _join(_liveGtk4Dir, name);
        if (await FileSystemEntity.type(filePath, followLinks: false) ==
            FileSystemEntityType.link) {
          return const SwitchResult(
            ok: false,
            message: '~/.config/gtk-4.0 contains symlinks; refusing to switch',
          );
        }
      }

      final targetResult =
          targetId == darkVariant.id ? darkResult : lightResult;
      if (targetResult?.foundPath == null) {
        return const SwitchResult(
          ok: false,
          message: 'The target theme folder could not be located',
        );
      }

      previousValues = {
        gtkThemeKey: gtkTheme.value,
        colorSchemeKey: colorScheme.value,
        userThemeNameKey: shellTheme.value,
      };
      previousFiles = {};
      for (final name in ['gtk.css', 'gtk-dark.css']) {
        final file = File(_join(_liveGtk4Dir, name));
        previousFiles[name] =
            await file.exists() ? await file.readAsBytes() : null;
      }

      final timestamp = DateTime.now().microsecondsSinceEpoch.toString();
      final backupsDir = VariantState.backupsDir(configDir: _configDir);
      backupPath = _join(backupsDir, timestamp);
      final backupGtk4 = _join(backupPath, 'gtk-4.0');
      await Directory(backupGtk4).create(recursive: true);
      await _copyCapturedFiles(previousFiles, backupGtk4);
      await _pruneBackups(backupsDir);
      backupComplete = true;

      final currentSnapshot =
          VariantState.snapshotDir(currentId, configDir: _configDir);
      await Directory(currentSnapshot).create(recursive: true);
      await _copyCapturedFiles(previousFiles, currentSnapshot);

      final targetSnapshot =
          VariantState.snapshotDir(targetId, configDir: _configDir);
      final snapshotExists = await Directory(targetSnapshot).exists();
      final sourceDir = snapshotExists
          ? targetSnapshot
          : _join(targetResult!.foundPath!, 'gtk-4.0');
      await Directory(_liveGtk4Dir).create(recursive: true);
      for (final name in ['gtk.css', 'gtk-dark.css']) {
        final source = File(_join(sourceDir, name));
        final livePath = _join(_liveGtk4Dir, name);
        if (await source.exists()) {
          await _atomicWrite(livePath, await source.readAsBytes());
        } else {
          await _deleteLiveFile(livePath);
        }
      }

      final targetColorScheme =
          targetId == darkVariant.id ? 'prefer-dark' : 'prefer-light';
      await _requireSet(gtkInterfaceSchema, gtkThemeKey, target.folderName);
      await _requireSet(userThemeSchema, userThemeNameKey, target.folderName);
      await _requireSet(gtkInterfaceSchema, colorSchemeKey, targetColorScheme);

      await _verify(gtkInterfaceSchema, gtkThemeKey, target.folderName);
      await _verify(userThemeSchema, userThemeNameKey, target.folderName);
      await _verify(gtkInterfaceSchema, colorSchemeKey, targetColorScheme);

      await VariantState.write(
        activeVariant: targetId,
        variants: {
          darkVariant.id: {
            'folder': darkVariant.folderName,
            'path': darkResult!.foundPath!,
          },
          lightVariant.id: {
            'folder': lightVariant.folderName,
            'path': lightResult!.foundPath!,
          },
        },
        lastSwitch: DateTime.now().toIso8601String(),
        configDir: _configDir,
      );
      if (VariantState.activeVariantIdSync(configDir: _configDir) != targetId) {
        throw const _SwitchException('Could not save the active variant state');
      }
      return SwitchResult(ok: true, message: 'Switched to ${target.label}');
    } catch (error) {
      if (!backupComplete || previousValues == null || previousFiles == null) {
        return SwitchResult(ok: false, message: _friendlyMessage(error));
      }
      final rollbackError = await _rollback(previousValues, previousFiles);
      if (rollbackError != null) {
        return SwitchResult(
          ok: false,
          rolledBack: true,
          message:
              '${_friendlyMessage(error)} Automatic rollback was incomplete. Restore manually from $backupPath. $rollbackError',
        );
      }
      return SwitchResult(
        ok: false,
        rolledBack: true,
        message: '${_friendlyMessage(error)} The previous theme was restored.',
      );
    } finally {
      _inProgress = false;
    }
  }

  Future<void> _copyCapturedFiles(
    Map<String, List<int>?>? files,
    String destination,
  ) async {
    for (final name in ['gtk.css', 'gtk-dark.css']) {
      final bytes = files?[name];
      if (bytes != null) {
        await _atomicWrite(_join(destination, name), bytes);
      } else {
        final path = _join(destination, name);
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<void> _pruneBackups(String backupsDir) async {
    final directory = Directory(backupsDir);
    final timestampPattern = RegExp(r'^\d{16}$');
    final backups = <Directory>[];
    if (await directory.exists()) {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is Directory &&
            timestampPattern
                .hasMatch(entity.path.split(Platform.pathSeparator).last)) {
          backups.add(entity);
        }
      }
    }
    backups.sort((a, b) => b.path.compareTo(a.path));
    for (final oldBackup in backups.skip(5)) {
      await oldBackup.delete(recursive: true);
    }
  }

  Future<void> _atomicWrite(String path, List<int> bytes) async {
    final tempPath = '$path.tmp-${DateTime.now().microsecondsSinceEpoch}';
    final temp = File(tempPath);
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> _deleteLiveFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<void> _requireSet(String schema, String key, String value) async {
    final result = await _gs.set(schema, key, value);
    if (!result.ok) {
      throw _SwitchException(
        result.error?.isNotEmpty == true
            ? 'Could not set $key: ${result.error}'
            : 'Could not set $key',
      );
    }
  }

  Future<void> _verify(String schema, String key, String expected) async {
    final result = await _gs.get(schema, key);
    if (!result.ok || result.value != expected) {
      throw _SwitchException('Could not verify $key after switching');
    }
  }

  Future<String?> _rollback(
    Map<String, String?> previousValues,
    Map<String, List<int>?> previousFiles,
  ) async {
    final errors = <String>[];
    for (final entry in [
      (gtkInterfaceSchema, gtkThemeKey),
      (userThemeSchema, userThemeNameKey),
      (gtkInterfaceSchema, colorSchemeKey),
    ]) {
      final value = previousValues[entry.$2];
      if (value == null) continue;
      try {
        final result = await _gs.set(entry.$1, entry.$2, value);
        if (!result.ok) errors.add('Could not restore ${entry.$2}.');
      } catch (_) {
        errors.add('Could not restore ${entry.$2}.');
      }
    }

    for (final name in ['gtk.css', 'gtk-dark.css']) {
      try {
        final path = _join(_liveGtk4Dir, name);
        final bytes = previousFiles[name];
        if (bytes == null) {
          await _deleteLiveFile(path);
        } else {
          await _atomicWrite(path, bytes);
        }
      } catch (_) {
        errors.add('Could not restore $name.');
      }
    }
    return errors.isEmpty ? null : errors.join(' ');
  }

  String? _variantIdForTheme(String themeName) {
    if (themeName == darkVariant.folderName) return darkVariant.id;
    if (themeName == lightVariant.folderName) return lightVariant.id;
    return null;
  }

  String? _variantIdForTarget(ThemeVariant target) {
    if (target.id == darkVariant.id &&
        target.folderName == darkVariant.folderName) {
      return darkVariant.id;
    }
    if (target.id == lightVariant.id &&
        target.folderName == lightVariant.folderName) {
      return lightVariant.id;
    }
    return null;
  }

  bool _sameVariant(ThemeVariant a, ThemeVariant b) =>
      a.id == b.id && a.folderName == b.folderName;

  String _join(String parent, String child) =>
      '$parent${Platform.pathSeparator}$child';

  String _friendlyMessage(Object error) =>
      error is _SwitchException ? error.message : 'Theme switch failed: $error';
}

class _SwitchException implements Exception {
  final String message;

  const _SwitchException(this.message);

  @override
  String toString() => message;
}
