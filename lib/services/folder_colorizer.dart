import 'dart:io';

import 'package:nebulashade/services/gsettings_runner.dart';

class FolderColorResult {
  final bool ok;
  final String message;

  const FolderColorResult({required this.ok, required this.message});
}

class FolderColorizer {
  FolderColorizer({GsettingsRunner? gs, String? iconsRoot, String? configDir})
      : _gs = gs ?? ProcessGsettingsRunner(),
        _iconsRoot = iconsRoot ??
            '${Platform.environment['HOME'] ?? ''}/.local/share/icons',
        _configDir = configDir ??
            '${Platform.environment['HOME'] ?? ''}/.config/nebulashade';

  final GsettingsRunner _gs;
  final String _iconsRoot;
  final String _configDir;

  static bool _applying = false;
  static final RegExp _timestampPattern = RegExp(r'^\d{17}$');

  static const List<String> fileNames = [
    'folder-bookmark.svg',
    'folder-code.svg',
    'folder-documents.svg',
    'folder-download.svg',
    'folder-dropbox.svg',
    'folder-games.svg',
    'folder-github.svg',
    'folder-music.svg',
    'folder-open.svg',
    'folder-pictures.svg',
    'folder-projects.svg',
    'folder-publicshare.svg',
    'folder-root.svg',
    'folder-steam.svg',
    'folder.svg',
    'folder-templates.svg',
    'folder-temp.svg',
    'folder-torrent.svg',
    'folder-vbox.svg',
    'folder-video.svg',
    'folder-wine.svg',
    'user-desktop.svg',
    'user-home.svg',
    'folder-music.svg',
  ];

  Future<String?> resolveIconThemeDir() async {
    try {
      final result = await _gs.get(gtkInterfaceSchema, 'icon-theme');
      if (result.ok && result.value.isNotEmpty) {
        final selected = Directory('$_iconsRoot/${result.value}');
        if (await selected.exists()) return selected.path;
      }
      final fallback = Directory('$_iconsRoot/Colloid-teal-nord-dark');
      return await fallback.exists() ? fallback.path : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> readCurrentHex() async {
    try {
      final dir = await resolveIconThemeDir();
      if (dir == null) return null;
      final file = File('$dir/places/scalable/default-folder.svg');
      if (!await file.exists()) return null;
      final contents = await file.readAsString();
      return RegExp(r'fill:(#[A-Fa-f0-9]{6})')
          .firstMatch(contents)
          ?.group(1)
          ?.toUpperCase();
    } catch (_) {
      return null;
    }
  }

  Future<FolderColorResult> apply(String newHex) async {
    if (_applying) {
      return const FolderColorResult(
          ok: false, message: 'A folder colour change is already running');
    }
    _applying = true;
    try {
      if (!RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(newHex)) {
        return const FolderColorResult(ok: false, message: 'Invalid colour');
      }
      final normalized = '#${newHex.replaceFirst('#', '').toUpperCase()}';
      final dir = await resolveIconThemeDir();
      if (dir == null) {
        return const FolderColorResult(
            ok: false,
            message: 'Folder icon theme not found in ~/.local/share/icons');
      }
      final oldHex = await readCurrentHex();
      if (oldHex == null) {
        return const FolderColorResult(
            ok: false, message: 'Could not read the current folder colour');
      }
      if (oldHex.toUpperCase() == normalized) {
        return const FolderColorResult(
            ok: true, message: 'Already this colour');
      }

      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) {
        return const FolderColorResult(
            ok: false, message: 'Home directory is unavailable');
      }
      final homeRoot = Directory(home).resolveSymbolicLinksSync();
      final filesByPath = <String, File>{};
      for (final name in fileNames) {
        final path = '$dir/places/scalable/default-$name';
        try {
          final entityType =
              await FileSystemEntity.type(path, followLinks: true);
          if (entityType != FileSystemEntityType.file) continue;
          final realPath = await File(path).resolveSymbolicLinks();
          final normalized = File(realPath).absolute.path;
          if (!normalized.startsWith('$homeRoot${Platform.pathSeparator}')) {
            continue;
          }
          filesByPath.putIfAbsent(normalized, () => File(normalized));
        } on FileSystemException {
          // Ignore missing or dangling icon links.
        }
      }
      final files = filesByPath.values.toList();
      if (files.isEmpty) {
        return const FolderColorResult(
            ok: false, message: 'No folder icon files were found');
      }

      final originals = <String, List<int>>{};
      final timestamp = _timestampNow();
      final backupRoot = Directory('$_configDir/backups/$timestamp');
      await backupRoot.create(recursive: true);
      for (final file in files) {
        final bytes = await file.readAsBytes();
        originals[file.path] = bytes;
        final name = file.path.split(Platform.pathSeparator).last;
        final backup = File('${backupRoot.path}/folder-icons/$name');
        await backup.parent.create(recursive: true);
        await backup.writeAsBytes(bytes, flush: true);
      }
      await _pruneBackups();

      try {
        for (final file in files) {
          var content = String.fromCharCodes(originals[file.path]!);
          content = content.replaceAll(oldHex.toUpperCase(), normalized);
          content = content.replaceAll(
              oldHex.toLowerCase(), normalized.toLowerCase());
          content = content.replaceAll(oldHex, normalized);
          await _writeAtomically(file, content);
        }
        for (final file in files) {
          if (!await file.exists() || await file.length() == 0) {
            await _restore(originals);
            return const FolderColorResult(
                ok: false,
                message: 'Folder colour update failed; files restored');
          }
        }
      } catch (_) {
        await _restore(originals);
        return const FolderColorResult(
            ok: false, message: 'Folder colour update failed; files restored');
      }

      var refreshSkipped = false;
      final previous = await _gs.get(gtkInterfaceSchema, 'icon-theme');
      if (!previous.ok || previous.value.isEmpty) {
        refreshSkipped = true;
      } else {
        try {
          await _gs.set(gtkInterfaceSchema, 'icon-theme', 'Adwaita');
          await _gs.set(gtkInterfaceSchema, 'icon-theme', previous.value);
        } catch (_) {
          refreshSkipped = true;
        } finally {
          try {
            await _gs.set(gtkInterfaceSchema, 'icon-theme', previous.value);
            var current = await _gs.get(gtkInterfaceSchema, 'icon-theme');
            if (!current.ok || current.value != previous.value) {
              await _gs.set(gtkInterfaceSchema, 'icon-theme', previous.value);
              current = await _gs.get(gtkInterfaceSchema, 'icon-theme');
            }
            if (!current.ok || current.value != previous.value) {
              refreshSkipped = true;
            }
          } catch (_) {
            refreshSkipped = true;
          }
        }
      }
      return FolderColorResult(
        ok: true,
        message: refreshSkipped
            ? 'Folder colour updated. Restart apps to see the new folder colour'
            : 'Folder colour updated',
      );
    } catch (_) {
      return const FolderColorResult(
          ok: false, message: 'Could not update folder colour');
    } finally {
      _applying = false;
    }
  }

  Future<void> _writeAtomically(File file, String content) async {
    final temp = File(
        '${file.path}.nebulashade-tmp-${DateTime.now().microsecondsSinceEpoch}');
    try {
      await temp.writeAsString(content, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> _restore(Map<String, List<int>> originals) async {
    for (final entry in originals.entries) {
      try {
        await _writeBytesAtomically(File(entry.key), entry.value);
      } catch (_) {}
    }
  }

  Future<void> _writeBytesAtomically(File file, List<int> bytes) async {
    final temp = File(
        '${file.path}.nebulashade-restore-${DateTime.now().microsecondsSinceEpoch}');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> _pruneBackups() async {
    final backups = Directory('$_configDir/backups');
    if (!await backups.exists()) return;
    final dirs = <Directory>[];
    await for (final entity in backups.list(followLinks: false)) {
      if (entity is Directory &&
          _timestampPattern.hasMatch(_directoryName(entity.path))) {
        dirs.add(entity);
      }
    }
    dirs.sort(
        (a, b) => _directoryName(b.path).compareTo(_directoryName(a.path)));
    for (final directory in dirs.skip(5)) {
      await directory.delete(recursive: true);
    }
  }

  String _directoryName(String path) => path
      .split(Platform.pathSeparator)
      .where((segment) => segment.isNotEmpty)
      .last;

  String _timestampNow() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return '${now.year}${two(now.month)}${two(now.day)}${two(now.hour)}${two(now.minute)}${two(now.second)}${three(now.millisecond)}';
  }
}
