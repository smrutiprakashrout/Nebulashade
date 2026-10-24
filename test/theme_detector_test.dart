import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/config/theme_variants.dart';
import 'package:nebulashade/services/theme_detector.dart';

const fakeVariant = ThemeVariant(
  id: 'fake',
  label: 'Fake Theme',
  folderName: 'Fake-Theme',
);

void main() {
  test('reports missing when the theme folder is absent', () async {
    final tmp = Directory.systemTemp.createTempSync('theme-detector-');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final detector = ThemeDetector(searchDirs: [tmp.path]);

    final result = await detector.check(fakeVariant);

    expect(result.status, ThemeStatus.missing);
    expect(result.foundPath, isNull);
  });

  test('reports incomplete and lists absent files', () async {
    final tmp = Directory.systemTemp.createTempSync('theme-detector-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final themeDir = Directory('${tmp.path}/Fake-Theme')..createSync();
    File('${themeDir.path}/index.theme').createSync();

    final detector = ThemeDetector(searchDirs: [tmp.path]);

    final result = await detector.check(fakeVariant);

    expect(result.status, ThemeStatus.incomplete);
    expect(result.foundPath, themeDir.path);
    expect(
      result.missingFiles,
      ['gtk-3.0/gtk.css', 'gtk-4.0/gtk.css', 'gnome-shell/gnome-shell.css'],
    );
  });

  test('reports complete when all required files exist', () async {
    final tmp = Directory.systemTemp.createTempSync('theme-detector-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final themeDir = Directory('${tmp.path}/Fake-Theme')..createSync();
    for (final file in ThemeVariants.requiredFiles) {
      final path = '${themeDir.path}/$file';
      File(path).parent.createSync(recursive: true);
      File(path).createSync();
    }

    final detector = ThemeDetector(searchDirs: [tmp.path]);

    final result = await detector.check(fakeVariant);

    expect(result.status, ThemeStatus.complete);
    expect(result.foundPath, themeDir.path);
    expect(result.missingFiles, isEmpty);
  });

  test('canSwitch requires both variants to be complete', () async {
    final tmp = Directory.systemTemp.createTempSync('theme-detector-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final themeDir = Directory('${tmp.path}/Fake-Theme')..createSync();
    for (final file in ThemeVariants.requiredFiles) {
      final path = '${themeDir.path}/$file';
      File(path).parent.createSync(recursive: true);
      File(path).createSync();
    }

    final completeVariant = ThemeVariant(
      id: 'complete',
      label: 'Complete Theme',
      folderName: 'Fake-Theme',
    );
    final missingVariant = ThemeVariant(
      id: 'missing',
      label: 'Missing Theme',
      folderName: 'Not-Installed',
    );
    final detector = ThemeDetector(searchDirs: [tmp.path]);
    final complete = await detector.check(completeVariant);
    final missing = await detector.check(missingVariant);

    expect(detector.canSwitch({'dark': complete, 'light': missing}), isFalse);
    expect(detector.canSwitch({'dark': complete, 'light': complete}), isTrue);
  });
}
