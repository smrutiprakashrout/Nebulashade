import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:nebulashade/components/apply_theme.dart';
import 'package:nebulashade/components/autoadjusthue.dart';
import 'package:nebulashade/config/theme_variants.dart';
import 'package:nebulashade/services/gsettings_runner.dart';
import 'package:nebulashade/services/theme_detector.dart';
import 'package:nebulashade/services/theme_switcher.dart';
import 'package:nebulashade/services/variant_paths.dart';
import 'package:nebulashade/services/variant_state.dart';

class ApplyResult {
  final bool ok;
  final String message;

  const ApplyResult({required this.ok, required this.message});
}

bool _applyInProgress = false;

Future<ApplyResult> applyHexToLight(
  String hex, {
  GsettingsRunner? gs,
  ThemeDetector? detector,
  String? configDir,
  String? home,
  Future<void> Function(String hex, List<String> paths)? adjust,
  Future<void> Function(String title, String body)? notify,
  ThemeVariant? lightVariant,
}) async {
  final resolvedHome = home ?? Platform.environment['HOME'] ?? '';
  final resolvedConfigDir = configDir ??
      (resolvedHome.isEmpty
          ? ''
          : path.join(resolvedHome, '.config', 'nebulashade'));
  final runner = gs ?? ProcessGsettingsRunner();
  final themeDetector = detector ?? ThemeDetector();
  final variant = lightVariant ?? ThemeVariants.light;
  final notifyFn = notify ?? _defaultNotify;

  Future<ApplyResult> failure(String message) async {
    await _notifySafely(notifyFn, 'Theme not updated', message);
    return ApplyResult(ok: false, message: message);
  }

  if (_applyInProgress) return failure('An apply is already running');
  _applyInProgress = true;

  String? backupPath;
  final backupByOriginal = <String, String>{};
  var backupComplete = false;

  try {
    if (ThemeSwitcher.busy) {
      return await failure('A theme switch is in progress');
    }
    if (resolvedHome.isEmpty) {
      return await failure('Could not locate the home directory.');
    }

    final rawHex = hex.startsWith('#') ? hex.substring(1) : hex;
    if (!RegExp(r'^(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(rawHex)) {
      return await failure('Invalid colour. Use a 6- or 8-digit hex value.');
    }
    final normalizedHex =
        '#${rawHex.length == 8 ? rawHex.substring(2) : rawHex}';

    final lightCheck = await themeDetector.check(variant);
    if (lightCheck.status != ThemeStatus.complete ||
        lightCheck.foundPath == null) {
      return await failure('The Light theme is not completely installed.');
    }
    final themePath = lightCheck.foundPath!;
    if (!VariantPaths.isUnderHome(themePath, resolvedHome)) {
      return await failure(
        'The Light theme is installed system-wide (read-only). Copy it to ~/.themes to enable colour adaptation.',
      );
    }
    final realHome = await Directory(resolvedHome).resolveSymbolicLinks();
    final realThemePath = await Directory(themePath).resolveSymbolicLinks();
    if (!VariantPaths.isUnderHome(realThemePath, realHome)) {
      return await failure(
        'The Light theme is installed system-wide (read-only). Copy it to ~/.themes to enable colour adaptation.',
      );
    }

    final liveDir = path.join(resolvedHome, '.config', 'gtk-4.0');
    if (await Directory(liveDir).exists()) {
      final realLiveDir = await Directory(liveDir).resolveSymbolicLinks();
      if (!VariantPaths.isUnderHome(realLiveDir, realHome)) {
        return await failure(
          'The live GTK 4.0 directory is outside the home directory; refusing to apply colours.',
        );
      }
    }
    for (final name in ['gtk.css', 'gtk-dark.css']) {
      final liveFile = path.join(liveDir, name);
      if (await FileSystemEntity.type(liveFile, followLinks: false) ==
          FileSystemEntityType.link) {
        return await failure(
          'The live GTK 4.0 files contain symlinks; refusing to apply colours.',
        );
      }
    }

    final paths = <String>[];
    for (final filePath in VariantPaths.forLight(resolvedHome, realThemePath)) {
      if (await FileSystemEntity.type(filePath, followLinks: false) ==
          FileSystemEntityType.file) {
        paths.add(filePath);
      }
    }

    final timestamp = DateTime.now().microsecondsSinceEpoch.toString();
    final backupsDir = path.join(resolvedConfigDir, 'backups');
    backupPath = path.join(backupsDir, timestamp, 'light-apply');
    await Directory(backupPath).create(recursive: true);
    final usedBackupNames = <String>{};
    for (var i = 0; i < paths.length; i++) {
      final original = paths[i];
      final relative = path.relative(original, from: resolvedHome);
      var flattened = relative.replaceAll(path.separator, '__');
      if (!usedBackupNames.add(flattened)) {
        flattened = '${i}__$flattened';
        usedBackupNames.add(flattened);
      }
      final backupFile = path.join(backupPath, flattened);
      await File(original).copy(backupFile);
      backupByOriginal[original] = backupFile;
    }
    backupComplete = true;
    await _pruneBackups(backupsDir);

    final adjustFn = adjust ??
        (value, selectedPaths) =>
            automaticColorAdjustment(value, overridePaths: selectedPaths);
    await adjustFn(normalizedHex, paths);

    const minimize = '#e69875';
    const maximize = '#a7c080';
    const close = '#e67e80';
    for (final filePath in paths) {
      final file = File(filePath);
      final css = await file.readAsString();
      final patched = applyButtonColors(
        css,
        minimize: minimize,
        maximize: maximize,
        close: close,
      );
      if (patched != css) await file.writeAsString(patched);
    }

    for (final filePath in paths) {
      final file = File(filePath);
      if (!await file.exists() || await file.length() == 0) {
        await _restoreFiles(backupByOriginal);
        return await failure('Colour apply failed; files restored');
      }
    }

    final previousGtkTheme = await runner.get(gtkInterfaceSchema, gtkThemeKey);
    final previousUserTheme =
        await runner.get(userThemeSchema, userThemeNameKey);
    if (!previousGtkTheme.ok || !previousUserTheme.ok) {
      await _restoreFiles(backupByOriginal);
      return await failure('Could not read current theme settings for reload.');
    }

    String? reloadOperationError;
    final restoreErrors = <String>[];
    try {
      await _setOrThrow(runner, userThemeSchema, userThemeNameKey, 'Adwaita');
      await _setOrThrow(
        runner,
        userThemeSchema,
        userThemeNameKey,
        previousUserTheme.value,
      );
      await _setOrThrow(runner, gtkInterfaceSchema, gtkThemeKey, 'Adwaita');
      await _setOrThrow(
        runner,
        gtkInterfaceSchema,
        gtkThemeKey,
        previousGtkTheme.value,
      );
    } catch (error) {
      reloadOperationError = error.toString();
    } finally {
      for (final entry in [
        (userThemeSchema, userThemeNameKey, previousUserTheme.value),
        (gtkInterfaceSchema, gtkThemeKey, previousGtkTheme.value),
      ]) {
        try {
          await runner.set(entry.$1, entry.$2, entry.$3);
        } catch (_) {
          // Verify below even when a set operation reports an error.
        }
      }

      for (final entry in [
        (userThemeSchema, userThemeNameKey, previousUserTheme.value),
        (gtkInterfaceSchema, gtkThemeKey, previousGtkTheme.value),
      ]) {
        try {
          var current = await runner.get(entry.$1, entry.$2);
          if (!current.ok || current.value != entry.$3) {
            try {
              await runner.set(entry.$1, entry.$2, entry.$3);
            } catch (_) {}
            current = await runner.get(entry.$1, entry.$2);
          }
          if (!current.ok || current.value != entry.$3) {
            if (!restoreErrors.contains(entry.$2)) {
              restoreErrors.add(entry.$2);
            }
          }
        } catch (_) {
          if (!restoreErrors.contains(entry.$2)) {
            restoreErrors.add(entry.$2);
          }
        }
      }
    }

    if (restoreErrors.isNotEmpty) {
      await _restoreFiles(backupByOriginal);
      final keys = restoreErrors.toSet().join(', ');
      return await failure('Could not restore gsettings key(s): $keys.');
    }
    if (reloadOperationError != null) {
      await _restoreFiles(backupByOriginal);
      return await failure('Theme reload failed: $reloadOperationError');
    }

    await VariantState.recordApplied('light', hex,
        configDir: resolvedConfigDir);
    await _notifySafely(
      notifyFn,
      'Theme Updated',
      'Light theme colours refreshed!',
    );
    return const ApplyResult(
        ok: true, message: 'Light theme colours refreshed!');
  } catch (error) {
    if (backupComplete) {
      await _restoreFiles(backupByOriginal);
    } else if (backupPath != null) {
      try {
        final partialBackup = Directory(backupPath);
        if (await partialBackup.exists()) {
          await partialBackup.delete(recursive: true);
        }
      } catch (_) {}
    }
    return await failure('Colour apply failed; files restored. $error');
  } finally {
    _applyInProgress = false;
  }
}

Future<void> _setOrThrow(
  GsettingsRunner runner,
  String schema,
  String key,
  String value,
) async {
  final result = await runner.set(schema, key, value);
  if (!result.ok) {
    throw _ApplyException('Could not set $key');
  }
}

Future<void> _restoreFiles(Map<String, String> backupByOriginal) async {
  for (final entry in backupByOriginal.entries) {
    try {
      final bytes = await File(entry.value).readAsBytes();
      await File(entry.key).writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }
}

Future<void> _pruneBackups(String backupsDir) async {
  final root = Directory(backupsDir);
  if (!await root.exists()) return;
  final timestampPattern = RegExp(r'^\d{16}$');
  final folders = <Directory>[];
  await for (final entity in root.list(followLinks: false)) {
    final name = path.basename(entity.path);
    if (entity is Directory && timestampPattern.hasMatch(name)) {
      folders.add(entity);
    }
  }
  folders
      .sort((a, b) => path.basename(b.path).compareTo(path.basename(a.path)));
  for (final oldFolder in folders.skip(5)) {
    await oldFolder.delete(recursive: true);
  }
}

Future<void> _notifySafely(
  Future<void> Function(String title, String body) notify,
  String title,
  String body,
) async {
  try {
    await notify(title, body);
  } catch (_) {}
}

Future<void> _defaultNotify(String title, String body) async {
  try {
    await Process.run('notify-send', [
      '-i',
      'dialog-information',
      '-a',
      'NebulaShade',
      '-u',
      'normal',
      '-t',
      '4000',
      title,
      body,
    ]);
  } catch (_) {}
}

class _ApplyException implements Exception {
  final String message;

  const _ApplyException(this.message);

  @override
  String toString() => message;
}
