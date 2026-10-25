import 'dart:convert';
import 'dart:io';

import 'package:nebulashade/constants/colours.dart';
import 'package:nebulashade/services/folder_colorizer.dart';
import 'package:nebulashade/services/widget_palette.dart';

enum SyncStepStatus { ok, skipped, failed }

class SyncStepResult {
  const SyncStepResult(this.status, [this.reason]);
  final SyncStepStatus status;
  final String? reason;
}

class SyncResult {
  const SyncResult(
      {required this.steps,
      required this.replacements,
      required this.classReplacements,
      required this.perFileClassReplacements,
      required this.malformed,
      required this.repaired,
      required this.warnings});
  final Map<String, SyncStepResult> steps;
  final Map<String, int> replacements;
  final Map<String, int> classReplacements;
  final Map<String, Map<String, int>> perFileClassReplacements;
  final Map<String, List<String>> malformed;
  final Map<String, List<String>> repaired;
  final List<SyncWarning> warnings;
}

class SyncWarning {
  const SyncWarning(this.file, this.line, this.value);
  final String file;
  final int line;
  final String value;

  Map<String, Object> toJson() => {
        'file': file,
        'line': line,
        'value': value,
      };
}

class CssRewriteResult {
  const CssRewriteResult({
    required this.content,
    required this.counts,
    required this.repaired,
  });
  final String content;
  final Map<String, int> counts;
  final List<String> repaired;
}

class WidgetSyncService {
  WidgetSyncService({String? home})
      : _home = home ?? Platform.environment['HOME'] ?? '';
  final String _home;

  List<String> get filePaths => [
        '$_home/.themes/Everforest-Dark-Soft-Adaptive/gtk-4.0/gtk.css',
        '$_home/.themes/Everforest-Dark-Soft-Adaptive/gtk-4.0/gtk-dark.css',
        '$_home/.themes/Everforest-Dark-Soft-Adaptive/gtk-3.0/gtk.css',
        '$_home/.themes/Everforest-Dark-Soft-Adaptive/gtk-3.0/gtk-dark.css',
        '$_home/.themes/Everforest-Dark-Soft-Adaptive/gnome-shell/gnome-shell.css',
        '$_home/.themes/Everforest-Dark-Soft-Adaptive/gnome-shell/pad-osd.css',
        '$_home/.config/gtk-4.0/gtk.css',
        '$_home/.config/gtk-4.0/gtk-dark.css',
      ];

  Future<int> readSlot() async {
    final f = File('$_home/Nebula/slot.txt');
    if (!await f.exists()) return 2;
    return int.tryParse((await f.readAsString()).trim()) ?? 2;
  }

  Future<Map<String, int>> readCurrentColors() async {
    try {
      return await _readAnchors();
    } catch (_) {
      return const {};
    }
  }

  Future<SyncResult> apply(WidgetPalette palette,
      {void Function(Map<String, SyncStepResult>)? onProgress}) async {
    final stamp = _timestamp();
    final backupDir =
        Directory('$_home/.config/nebulashade/backups/$stamp/sync');
    final originals = <String, List<int>>{};
    final steps = <String, SyncStepResult>{
      'GTK3 theme': const SyncStepResult(SyncStepStatus.skipped, 'Waiting'),
      'GTK4 theme': const SyncStepResult(SyncStepStatus.skipped, 'Waiting'),
      'Shell': const SyncStepResult(SyncStepStatus.skipped, 'Waiting'),
      'Sidebar block': const SyncStepResult(SyncStepStatus.skipped, 'Waiting'),
      'Folder': const SyncStepResult(SyncStepStatus.skipped, 'Waiting'),
      'Widgets': const SyncStepResult(SyncStepStatus.skipped, 'Waiting'),
    };
    void report(String key, SyncStepResult result) {
      steps[key] = result;
      onProgress?.call(Map.unmodifiable(steps));
    }

    final counts = <String, int>{};
    final perFileClasses = <String, Map<String, int>>{};
    final classTotals = <String, int>{
      for (final role in WidgetColorClass.values) role.name: 0,
    };
    final malformed = <String, List<String>>{};
    final repaired = <String, List<String>>{};
    var warnings = <SyncWarning>[];
    final seenGroups = <String>{};
    await backupDir.create(recursive: true);
    var sidebarCount = 0;
    try {
      for (final path in filePaths) {
        final file = File(path);
        if (!await file.exists()) {
          counts[path] = 0;
          perFileClasses[path] = _emptyClassCounts();
          continue;
        }
        final bytes = await file.readAsBytes();
        originals[path] = bytes;
        final backup = File(
            '${backupDir.path}/${filePaths.indexOf(path)}-${file.uri.pathSegments.last}');
        await backup.writeAsBytes(bytes, flush: true);
        var content = utf8.decode(bytes);
        final rewritten = rewriteCss(content, palette);
        content = rewritten.content;
        final fileClasses = _emptyClassCounts();
        for (final entry in rewritten.counts.entries) {
          fileClasses[entry.key] = entry.value;
          classTotals[entry.key] = (classTotals[entry.key] ?? 0) + entry.value;
        }
        perFileClasses[path] = fileClasses;
        counts[path] = rewritten.counts.values.fold<int>(0, (a, b) => a + b);
        repaired[path] = rewritten.repaired;
        if (path == '$_home/.config/gtk-4.0/gtk.css' ||
            path ==
                '$_home/.themes/Everforest-Dark-Soft-Adaptive/gtk-4.0/gtk.css' ||
            path ==
                '$_home/.themes/Everforest-Dark-Soft-Adaptive/gtk-4.0/gtk-dark.css') {
          content = _withSidebarBlock(content, palette.sidebar);
          sidebarCount++;
        }
        malformed[path] = _malformedColors(content);
        await _atomicWrite(file, content);
        if (path.contains('/gtk-3.0/')) {
          seenGroups.add('GTK3 theme');
          report('GTK3 theme', const SyncStepResult(SyncStepStatus.ok));
        }
        if (path.contains('/gtk-4.0/')) {
          seenGroups.add('GTK4 theme');
          report('GTK4 theme', const SyncStepResult(SyncStepStatus.ok));
        }
        if (path.contains('/gnome-shell/')) {
          seenGroups.add('Shell');
          report('Shell', const SyncStepResult(SyncStepStatus.ok));
        }
      }
      if (originals.isEmpty) {
        throw const FileSystemException('No theme files found');
      }
      for (final path in originals.keys) {
        final f = File(path);
        if (!await f.exists() || await f.length() == 0) {
          throw FileSystemException('File write verification failed', path);
        }
      }
      warnings = _findResiduals(palette);
      if (sidebarCount > 0) {
        report('Sidebar block', const SyncStepResult(SyncStepStatus.ok));
      } else {
        report(
            'Sidebar block',
            const SyncStepResult(
                SyncStepStatus.skipped, 'No sidebar CSS targets were found'));
      }
      for (final key in ['GTK3 theme', 'GTK4 theme', 'Shell']) {
        if (!seenGroups.contains(key)) {
          report(
              key,
              const SyncStepResult(
                  SyncStepStatus.skipped, 'No matching files were found'));
        }
      }
      await _reload();
      await Directory('$_home/.config/nebulashade').create(recursive: true);
      await _atomicWrite(
          File('$_home/.config/nebulashade/sync.json'),
          jsonEncode({
            'slot': palette.slot,
            'hexes': {
              'window': WidgetPalette.hex(palette.window),
              'base': WidgetPalette.hex(palette.sidebar),
              'popover': WidgetPalette.hex(palette.popover),
              'accent': WidgetPalette.hex(palette.accent),
              'light': WidgetPalette.hex(palette.light),
              'dark': WidgetPalette.hex(palette.dark),
            },
            'timestamp': stamp,
          }));
      await _atomicWrite(
          File('$_home/.config/nebulashade/sync-last.json'),
          jsonEncode({
            'slot': palette.slot,
            'timestamp': stamp,
            'files': {
              for (final path in filePaths)
                path: {
                  'replacements': counts[path] ?? 0,
                  'classes': perFileClasses[path] ?? _emptyClassCounts(),
                },
            },
            'classes': classTotals,
            'repaired': repaired,
            'warnings': warnings.map((warning) => warning.toJson()).toList(),
          }));
      await _writeSlot(palette.slot);
      final conky = await Process.run('pkill', ['-USR1', 'conky']);
      final widget = await Process.run(
          'python3', ['$_home/testc/conky/scripts/ulauncher_sync.py']);
      if (conky.exitCode != 0 || widget.exitCode != 0) {
        report(
            'Widgets',
            const SyncStepResult(SyncStepStatus.skipped,
                'Conky or Ulauncher widget refresh did not complete'));
      } else {
        report('Widgets', const SyncStepResult(SyncStepStatus.ok));
      }
      await _pruneBackups();
      try {
        final folder =
            await FolderColorizer().apply(WidgetPalette.hex(palette.folder));
        report(
            'Folder',
            folder.ok
                ? const SyncStepResult(SyncStepStatus.ok)
                : SyncStepResult(
                    SyncStepStatus.skipped, _safeFolderReason(folder.message)));
      } catch (_) {
        report(
            'Folder',
            const SyncStepResult(
                SyncStepStatus.skipped, 'Folder colour could not be updated'));
      }
      await Process.run('notify-send', [
        '-a',
        'NebulaShade',
        'Widgets Synced',
        'GTK and widget colours refreshed'
      ]);
      return SyncResult(
          steps: Map.unmodifiable(steps),
          replacements: Map.unmodifiable(counts),
          classReplacements: Map.unmodifiable(classTotals),
          perFileClassReplacements: Map.unmodifiable(<String, Map<String, int>>{
            for (final entry in perFileClasses.entries)
              entry.key: Map<String, int>.unmodifiable(entry.value),
          }),
          malformed: Map.unmodifiable(malformed),
          repaired: Map.unmodifiable(repaired),
          warnings: List.unmodifiable(warnings));
    } catch (_) {
      await _restore(originals);
      for (final key in [
        'GTK3 theme',
        'GTK4 theme',
        'Shell',
        'Sidebar block'
      ]) {
        report(
            key,
            const SyncStepResult(SyncStepStatus.failed,
                'Theme files could not be safely updated; originals were restored'));
      }
      report(
          'Folder',
          const SyncStepResult(
              SyncStepStatus.skipped, 'Theme update did not complete'));
      report(
          'Widgets',
          const SyncStepResult(
              SyncStepStatus.skipped, 'Theme update did not complete'));
      return SyncResult(
          steps: Map.unmodifiable(steps),
          replacements: Map.unmodifiable(counts),
          classReplacements: Map.unmodifiable(classTotals),
          perFileClassReplacements: Map.unmodifiable(<String, Map<String, int>>{
            for (final entry in perFileClasses.entries)
              entry.key: Map<String, int>.unmodifiable(entry.value),
          }),
          malformed: Map.unmodifiable(malformed),
          repaired: Map.unmodifiable(repaired),
          warnings: List.unmodifiable(warnings));
    }
  }

  String _safeFolderReason(String message) {
    if (message.toLowerCase().contains('icon theme')) {
      return 'Active icon theme is not available in ~/.local/share/icons';
    }
    if (message.toLowerCase().contains('folder icon files')) {
      return 'No editable folder SVG targets were found in the active icon theme';
    }
    if (message.toLowerCase().contains('current folder colour')) {
      return 'Could not read the current folder SVG colour';
    }
    return 'Folder colour could not be updated';
  }

  Future<void> reset() async {
    final root = Directory('$_home/.config/nebulashade/backups');
    final dirs = await root
        .list(followLinks: false)
        .where((e) => e is Directory)
        .cast<Directory>()
        .toList();
    dirs.sort((a, b) => b.path.compareTo(a.path));
    Directory? backup;
    for (final directory in dirs) {
      final candidate = Directory('${directory.path}/sync');
      if (await candidate.exists()) {
        backup = candidate;
        break;
      }
    }
    if (backup == null) {
      throw const FileSystemException('No sync backup found');
    }
    final entries = await backup.list().toList();
    for (final entity in entries.whereType<File>()) {
      final name = entity.uri.pathSegments.last;
      final match = RegExp(r'^(\d+)-(.+)$').firstMatch(name);
      if (match == null) continue;
      final index = int.parse(match.group(1)!);
      if (index >= 0 && index < filePaths.length) {
        await _atomicWrite(File(filePaths[index]), await entity.readAsString());
      }
    }
    for (final path in [
      '$_home/.config/gtk-4.0/gtk.css',
      '$_home/.themes/Everforest-Dark-Soft-Adaptive/gtk-4.0/gtk.css',
      '$_home/.themes/Everforest-Dark-Soft-Adaptive/gtk-4.0/gtk-dark.css',
    ]) {
      final file = File(path);
      if (await file.exists()) {
        final content = (await file.readAsString()).replaceAll(
            RegExp(
                r'\n?/\* NEBULA-SYNC BEGIN \*/[\s\S]*?/\* NEBULA-SYNC END \*/\s*$'),
            '');
        await _atomicWrite(file, content);
      }
    }
    await _reload();
    await Process.run('notify-send', [
      '-a',
      'NebulaShade',
      'Widget Sync Reset',
      'Restored the previous theme files'
    ]);
  }

  Future<Map<String, int>> _readAnchors() async {
    final files = [
      File('$_home/.config/gtk-4.0/gtk.css'),
      File('$_home/.themes/Everforest-Dark-Soft-Adaptive/gtk-3.0/gtk.css'),
    ];
    final found = <String, int>{};
    final aliases = {
      'window': ['theme_bg_color'],
      'base': ['theme_base_color'],
      'popover': ['popover_bg_color'],
      'accent': ['accent_bg_color', 'theme_selected_bg_color'],
    };
    for (final file in files) {
      if (!await file.exists()) continue;
      final css = await file.readAsString();
      for (final role in aliases.keys) {
        if (found.containsKey(role)) continue;
        for (final name in aliases[role]!) {
          final re = RegExp('@define-color\\s+$name\\s+#([0-9a-fA-F]{6})');
          final match = re.firstMatch(css);
          if (match != null) {
            found[role] = int.parse(match.group(1)!, radix: 16);
            break;
          }
        }
      }
    }
    for (final role in ['window', 'base', 'popover', 'accent']) {
      if (!found.containsKey(role)) {
        throw FileSystemException('Could not read GTK $role anchor');
      }
    }
    return found;
  }

  static CssRewriteResult rewriteCss(String css, WidgetPalette palette) {
    final counts = _emptyClassCounts();
    final repaired = <String>[];
    var result = css.replaceAllMapped(RegExp(r'#([0-9a-fA-F]+)\b'), (match) {
      final body = match.group(1)!;
      if (body.length < 6) return match.group(0)!;
      final isValidAlphaHex = body.length == 8;
      final isMalformed = body.length != 6 && !isValidAlphaHex;
      final normalizedBody = isMalformed ? body.substring(0, 6) : body;
      final original = match.group(0)!;
      final normalized = '#$normalizedBody';
      if (isMalformed) {
        repaired.add(
            'line ${css.substring(0, match.start).split('\n').length}: $original -> $normalized');
      }
      final rgb = int.parse(normalizedBody.substring(0, 6), radix: 16);
      final classes = WidgetPalette.classifyRgb(rgb);
      if (classes.length != 1) return normalized;
      final colorClass = classes.single;
      counts[colorClass.name] = counts[colorClass.name]! + 1;
      final mapped = WidgetPalette.mapClassifiedRgb(rgb, colorClass, palette);
      final mappedHex = mapped.toRadixString(16).padLeft(6, '0');
      final useUpper = body == body.toUpperCase();
      final formatted = useUpper ? mappedHex.toUpperCase() : mappedHex;
      final alpha = isValidAlphaHex ? body.substring(6) : '';
      return '#$formatted$alpha';
    });

    final rgbPattern = RegExp(
        r'(rgba?)\((\s*)(\d+)(\s*,\s*)(\d+)(\s*,\s*)(\d+)((?:\s*,\s*[\d.]+)?)(\s*)\)',
        caseSensitive: false);
    result = result.replaceAllMapped(rgbPattern, (match) {
      final rgb = (int.parse(match.group(3)!) << 16) |
          (int.parse(match.group(5)!) << 8) |
          int.parse(match.group(7)!);
      final classes = WidgetPalette.classifyRgb(rgb);
      if (classes.length != 1) return match.group(0)!;
      final colorClass = classes.single;
      counts[colorClass.name] = counts[colorClass.name]! + 1;
      final mapped = WidgetPalette.mapClassifiedRgb(rgb, colorClass, palette);
      return '${match.group(1)}(${match.group(2)}${(mapped >> 16) & 255}'
          '${match.group(4)}${(mapped >> 8) & 255}'
          '${match.group(6)}${mapped & 255}'
          '${match.group(8)}${match.group(9)})';
    });
    return CssRewriteResult(
        content: result,
        counts: Map.unmodifiable(counts),
        repaired: List.unmodifiable(repaired));
  }

  List<SyncWarning> _findResiduals(WidgetPalette palette) {
    final warnings = <SyncWarning>[];
    final hex = RegExp(r'#([0-9a-fA-F]+)\b');
    final rgb = RegExp(
        r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*[\d.]+)?\s*\)',
        caseSensitive: false);
    for (final path in filePaths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final css = file.readAsStringSync();
      for (final match in hex.allMatches(css)) {
        final body = match.group(1)!;
        if (body.length != 6 && body.length != 8) continue;
        final token = match.group(0)!;
        final value = int.parse(body.substring(0, 6), radix: 16);
        _addResidualWarning(
            warnings, path, css, match.start, token, value, palette);
      }
      for (final match in rgb.allMatches(css)) {
        final value = (int.parse(match.group(1)!) << 16) |
            (int.parse(match.group(2)!) << 8) |
            int.parse(match.group(3)!);
        _addResidualWarning(
            warnings, path, css, match.start, match.group(0)!, value, palette);
      }
    }
    return List.unmodifiable(warnings);
  }

  void _addResidualWarning(List<SyncWarning> warnings, String path, String css,
      int offset, String token, int rgb, WidgetPalette palette) {
    final classes = WidgetPalette.classifyRgb(rgb);
    if (classes.isEmpty) return;
    final line = css.substring(0, offset).split('\n').length;
    if (classes.length > 1 ||
        !WidgetPalette.isMappedRgb(rgb, classes.single, palette)) {
      warnings.add(SyncWarning(path, line, token));
    }
  }

  static Map<String, int> _emptyClassCounts() => {
        for (final role in WidgetColorClass.values) role.name: 0,
      };

  List<String> _malformedColors(String css) {
    final issues = <String>[];
    final seen = <String>{};
    final hexToken = RegExp(r'#([A-Za-z0-9]+)');
    for (final match in hexToken.allMatches(css)) {
      final token = match.group(1)!;
      final allHex = RegExp(r'^[0-9a-fA-F]+$').hasMatch(token);
      if (allHex && !const {3, 4, 6, 8}.contains(token.length)) {
        final line = css.substring(0, match.start).split('\n').length;
        final issue = 'line $line: #$token';
        if (seen.add(issue)) issues.add(issue);
      } else if (RegExp(r'^[0-9][0-9a-zA-Z]*$').hasMatch(token) && !allHex) {
        final line = css.substring(0, match.start).split('\n').length;
        final issue = 'line $line: #$token';
        if (seen.add(issue)) issues.add(issue);
      }
    }
    final function = RegExp(r'rgba?\(([^)]*)\)', caseSensitive: false);
    for (final match in function.allMatches(css)) {
      final raw = match.group(1)!;
      final parts = raw.split(',').map((part) => part.trim()).toList();
      final expected = match.group(0)!.toLowerCase().startsWith('rgba') ? 4 : 3;
      final values = parts.map((part) => double.tryParse(part)).toList();
      if (parts.length != expected ||
          values.any((value) => value == null) ||
          values.take(3).any((value) => value! < 0 || value > 255) ||
          (expected == 4 &&
              (values[3] == null || values[3]! < 0 || values[3]! > 1))) {
        final line = css.substring(0, match.start).split('\n').length;
        final issue = 'line $line: ${match.group(0)}';
        if (seen.add(issue)) issues.add(issue);
      }
    }
    return issues;
  }

  String _withSidebarBlock(String css, int sidebar) {
    final clean = css
        .replaceAll(
            RegExp(
                r'\n?/\* NEBULA-SYNC BEGIN \*/[\s\S]*?/\* NEBULA-SYNC END \*/\s*$'),
            '')
        .trimRight();
    final color = WidgetPalette.hex(sidebar);
    return '$clean\n\n/* NEBULA-SYNC BEGIN */\n'
        '@define-color sidebar_bg_color $color;\n'
        '@define-color sidebar_backdrop_color $color;\n'
        '@define-color sidebar_fg_color #f2efea;\n'
        '@define-color sidebar_shade_color shade($color, 0.9);\n'
        '.nautilus-window placessidebar > scrolledwindow { background-color: $color; }\n'
        '.sidebar-pane placessidebar > scrolledwindow, .sidebar-pane placessidebar > scrolledwindow viewport, .sidebar-pane placessidebar list { background-color: $color; }\n'
        'placessidebar list.navigation-sidebar > row button.sidebar-button, placessidebar list.navigation-sidebar > row button.sidebar-button:checked { background-color: $color; }\n'
        '/* NEBULA-SYNC END */\n';
  }

  Future<void> _writeSlot(int slot) async {
    final dir = Directory('$_home/Nebula');
    await dir.create(recursive: true);
    await _atomicWrite(File('${dir.path}/slot.txt'), '$slot\n');
  }

  Future<void> _reload() async {
    final shell = (await Process.run('gsettings',
            ['get', 'org.gnome.shell.extensions.user-theme', 'name']))
        .stdout
        .toString()
        .trim()
        .replaceAll("'", '');
    final gtk = (await Process.run(
            'gsettings', ['get', 'org.gnome.desktop.interface', 'gtk-theme']))
        .stdout
        .toString()
        .trim()
        .replaceAll("'", '');
    for (final args in [
      ['set', 'org.gnome.shell.extensions.user-theme', 'name', 'Adwaita'],
      ['set', 'org.gnome.shell.extensions.user-theme', 'name', shell],
      ['set', 'org.gnome.desktop.interface', 'gtk-theme', 'Adwaita'],
      ['set', 'org.gnome.desktop.interface', 'gtk-theme', gtk],
    ]) {
      final result = await Process.run('gsettings', args);
      if (result.exitCode != 0) {
        throw const FileSystemException('GTK theme reload failed');
      }
    }
    AppColors.init();
  }

  Future<void> _atomicWrite(File file, String content) async {
    await file.parent.create(recursive: true);
    final temp =
        File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await temp.writeAsString(content, flush: true);
    await temp.rename(file.path);
  }

  Future<void> _restore(Map<String, List<int>> originals) async {
    for (final entry in originals.entries) {
      await File(entry.key).writeAsBytes(entry.value, flush: true);
    }
  }

  Future<void> _pruneBackups() async {
    final root = Directory('$_home/.config/nebulashade/backups');
    final dirs = await root
        .list(followLinks: false)
        .where((e) => e is Directory)
        .cast<Directory>()
        .toList();
    dirs.sort((a, b) => b.path.compareTo(a.path));
    for (final dir in dirs.skip(5)) {
      await dir.delete(recursive: true);
    }
  }

  String _timestamp() => DateTime.now()
      .toIso8601String()
      .replaceAll(RegExp(r'[^0-9]'), '')
      .substring(0, 17);
}
