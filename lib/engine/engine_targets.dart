import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:nebulashade/config/theme_variants.dart';
import 'package:nebulashade/services/theme_detector.dart';

class EngineTarget {
  const EngineTarget({
    required this.path,
    required this.fileKind,
    this.isWatchedGtk4Override = false,
  });

  final String path;
  final String fileKind;
  final bool isWatchedGtk4Override;

  static List<String> skipped = <String>[];
}

Future<List<EngineTarget>> discoverTargets({
  ThemeDetector? detector,
  String? home,
}) async {
  EngineTarget.skipped = <String>[];
  final resolvedHome =
      path.normalize(path.absolute(home ?? Platform.environment['HOME'] ?? ''));
  if (resolvedHome == '.') return const [];
  final theme = await (detector ?? ThemeDetector()).check(ThemeVariants.dark);
  if (theme.status != ThemeStatus.complete || theme.foundPath == null)
    return const [];
  final themePath = path.normalize(path.absolute(theme.foundPath!));
  if (!_under(themePath, resolvedHome)) {
    EngineTarget.skipped = <String>['Refused theme outside home: $themePath'];
    return const [];
  }
  try {
    final realHome =
        path.normalize(await Directory(resolvedHome).resolveSymbolicLinks());
    final realTheme =
        path.normalize(await Directory(themePath).resolveSymbolicLinks());
    if (!_under(realTheme, realHome)) {
      EngineTarget.skipped = <String>[
        'Refused theme resolving outside home: $realTheme'
      ];
      return const [];
    }
  } catch (_) {
    EngineTarget.skipped = <String>['Could not resolve theme path: $themePath'];
    return const [];
  }

  final candidates = <EngineTarget>[
    EngineTarget(
        path: path.join(themePath, 'gtk-4.0', 'gtk.css'), fileKind: 'gtk4'),
    EngineTarget(
        path: path.join(themePath, 'gtk-4.0', 'gtk-dark.css'),
        fileKind: 'gtk4'),
    EngineTarget(
        path: path.join(themePath, 'gtk-3.0', 'gtk.css'), fileKind: 'gtk3'),
    EngineTarget(
        path: path.join(themePath, 'gtk-3.0', 'gtk-dark.css'),
        fileKind: 'gtk3'),
    EngineTarget(
        path: path.join(themePath, 'gnome-shell', 'gnome-shell.css'),
        fileKind: 'shell'),
    EngineTarget(
        path: path.join(themePath, 'gnome-shell', 'pad-osd.css'),
        fileKind: 'osd'),
  ];
  final gtk3 = path.join(resolvedHome, '.config', 'gtk-3.0');
  for (final name in ['gtk.css', 'gtk-dark.css']) {
    final filePath = path.join(gtk3, name);
    if (await File(filePath).exists()) {
      candidates.add(EngineTarget(path: filePath, fileKind: 'gtk3'));
    }
  }
  final gtk4 = path.join(resolvedHome, '.config', 'gtk-4.0');
  candidates.addAll([
    EngineTarget(
        path: path.join(gtk4, 'gtk.css'),
        fileKind: 'gtk4',
        isWatchedGtk4Override: true),
    EngineTarget(
        path: path.join(gtk4, 'gtk-dark.css'),
        fileKind: 'gtk4',
        isWatchedGtk4Override: true),
  ]);

  final targets = <EngineTarget>[];
  for (final target in candidates) {
    if (!_under(path.normalize(path.absolute(target.path)), resolvedHome)) {
      EngineTarget.skipped.add('Outside home: ${target.path}');
      continue;
    }
    final type = await FileSystemEntity.type(target.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      EngineTarget.skipped.add('Symlink: ${target.path}');
    } else if (type == FileSystemEntityType.file) {
      try {
        final realPath =
            path.normalize(await File(target.path).resolveSymbolicLinks());
        final realHome = path
            .normalize(await Directory(resolvedHome).resolveSymbolicLinks());
        if (!_under(realPath, realHome)) {
          EngineTarget.skipped
              .add('Target resolves outside home: ${target.path}');
        } else {
          targets.add(target);
        }
      } catch (_) {
        EngineTarget.skipped.add('Could not resolve target: ${target.path}');
      }
    }
  }
  // GTK4 overrides are deliberately last because the app watcher observes gtk.css.
  return List.unmodifiable(targets);
}

bool _under(String candidate, String root) =>
    candidate == root || path.isWithin(root, candidate);
