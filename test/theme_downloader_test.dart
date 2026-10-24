import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/config/theme_variants.dart';
import 'package:nebulashade/services/theme_downloader.dart';

const testVariant = ThemeVariant(
  id: 'light',
  label: 'T',
  folderName: 'Test-Light',
);

void main() {
  late Directory tempDir;
  late Directory themesDir;
  late ThemeDownloader downloader;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('theme-downloader-');
    themesDir = Directory('${tempDir.path}/themes')..createSync();
    downloader = ThemeDownloader();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('installs a complete zip containing the expected folder', () async {
    final zip = await _writeZip(
      tempDir,
      _validEntries(prefix: 'Test-Light/'),
    );

    final result = await downloader.installFromZip(
      zip.path,
      testVariant,
      themesDir: themesDir.path,
    );

    expect(result.ok, isTrue);
    expect(Directory('${themesDir.path}/Test-Light').existsSync(), isTrue);
    expect(await _missingInstalledFiles(themesDir), isEmpty);
    expect(_stagingDirs(themesDir), isEmpty);
  });

  test('installs a zip whose root contains index.theme', () async {
    final zip = await _writeZip(tempDir, _validEntries());

    final result = await downloader.installFromZip(
      zip.path,
      testVariant,
      themesDir: themesDir.path,
    );

    expect(result.ok, isTrue);
    expect(Directory('${themesDir.path}/Test-Light').existsSync(), isTrue);
    expect(_stagingDirs(themesDir), isEmpty);
  });

  test('rejects a zip missing gtk-4.0/gtk.css and cleans staging', () async {
    final entries = _validEntries(prefix: 'Test-Light/')
      ..removeWhere(
          (entry) => entry.startsWith('Test-Light/gtk-4.0/gtk.css\n'));
    final zip = await _writeZip(tempDir, entries);

    final result = await downloader.installFromZip(
      zip.path,
      testVariant,
      themesDir: themesDir.path,
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('gtk-4.0/gtk.css'));
    expect(Directory('${themesDir.path}/Test-Light').existsSync(), isFalse);
    expect(_stagingDirs(themesDir), isEmpty);
  });

  test('rejects zip-slip paths without writing outside the temp directory',
      () async {
    final zip = await _writeZip(tempDir, [
      ..._validEntries(prefix: 'Test-Light/'),
      '../evil.txt',
    ]);

    final result = await downloader.installFromZip(
      zip.path,
      testVariant,
      themesDir: themesDir.path,
    );

    expect(result.ok, isFalse);
    expect(File('${tempDir.path}/evil.txt').existsSync(), isFalse);
    expect(Directory('${themesDir.path}/Test-Light').existsSync(), isFalse);
    expect(_stagingDirs(themesDir), isEmpty);
  });

  test('does not overwrite an already complete target', () async {
    final target = Directory('${themesDir.path}/Test-Light')..createSync();
    _writeCompleteTheme(target, content: 'existing');
    final zip = await _writeZip(
      tempDir,
      _validEntries(prefix: 'Test-Light/', content: 'new'),
    );

    final result = await downloader.installFromZip(
      zip.path,
      testVariant,
      themesDir: themesDir.path,
    );

    expect(result.ok, isTrue);
    expect(result.message, 'Already installed');
    expect(File('${target.path}/index.theme').readAsStringSync(), 'existing');
    expect(_stagingDirs(themesDir), isEmpty);
  });

  test('backs up an incomplete target before installing the new theme',
      () async {
    final target = Directory('${themesDir.path}/Test-Light')..createSync();
    File('${target.path}/old.marker').writeAsStringSync('preserve me');
    final zip = await _writeZip(
      tempDir,
      _validEntries(prefix: 'Test-Light/', content: 'new'),
    );

    final result = await downloader.installFromZip(
      zip.path,
      testVariant,
      themesDir: themesDir.path,
    );

    final backups = themesDir
        .listSync()
        .whereType<Directory>()
        .where((directory) => directory.path.contains('Test-Light.bak-'))
        .toList();
    expect(result.ok, isTrue);
    expect(await _missingInstalledFiles(themesDir), isEmpty);
    expect(backups, hasLength(1));
    expect(File('${backups.single.path}/old.marker').readAsStringSync(),
        'preserve me');
    expect(_stagingDirs(themesDir), isEmpty);
  });

  test('placeholder Light URL is not configured', () {
    expect(ThemeVariants.lightDownloadConfigured, isFalse);
  });
}

List<String> _validEntries({String prefix = '', String content = 'theme'}) => [
      '${prefix}index.theme',
      '${prefix}gtk-3.0/gtk.css',
      '${prefix}gtk-4.0/gtk.css',
      '${prefix}gnome-shell/gnome-shell.css',
    ].map((path) => '$path\n$content').toList();

Future<File> _writeZip(Directory directory, List<String> entries) async {
  final archive = Archive();
  for (final entry in entries) {
    final separator = entry.indexOf('\n');
    final name = separator < 0 ? entry : entry.substring(0, separator);
    final content = separator < 0 ? 'payload' : entry.substring(separator + 1);
    archive.addFile(ArchiveFile.string(name, content));
  }
  final bytes = ZipEncoder().encodeBytes(archive);
  final file = File(
      '${directory.path}/fixture-${DateTime.now().microsecondsSinceEpoch}.zip');
  await file.writeAsBytes(bytes);
  return file;
}

void _writeCompleteTheme(Directory directory, {String content = 'old'}) {
  for (final requiredFile in ThemeVariants.requiredFiles) {
    final path = '${directory.path}/$requiredFile';
    File(path).parent.createSync(recursive: true);
    File(path).writeAsStringSync(content);
  }
}

Future<List<String>> _missingInstalledFiles(Directory themesDir) async {
  final installed = Directory('${themesDir.path}/Test-Light');
  final missing = <String>[];
  for (final file in ThemeVariants.requiredFiles) {
    if (!await File('${installed.path}/$file').exists()) missing.add(file);
  }
  return missing;
}

List<FileSystemEntity> _stagingDirs(Directory themesDir) => themesDir
    .listSync()
    .where(
        (entity) => entity.path.split(Platform.pathSeparator).last.startsWith(
              '.nebulashade-staging-',
            ))
    .toList();
