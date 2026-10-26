import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/services/folder_colorizer.dart';
import 'package:nebulashade/services/gsettings_runner.dart';

class FakeGsettingsRunner implements GsettingsRunner {
  final Map<String, String> values = {'icon-theme': 'Test-Theme'};
  String? failSetValue;
  Completer<void>? holdOnAdwaita;

  @override
  Future<GsResult> get(String schema, String key) async =>
      GsResult(ok: values.containsKey(key), value: values[key] ?? '');

  @override
  Future<GsResult> set(String schema, String key, String value) async {
    if (value == 'Adwaita' && holdOnAdwaita != null) {
      await holdOnAdwaita!.future;
    }
    if (value == failSetValue) {
      return const GsResult(ok: false, error: 'failed');
    }
    values[key] = value;
    return const GsResult(ok: true);
  }
}

void main() {
  late Directory temp;
  late Directory icons;
  late Directory config;
  late Directory home;
  late FakeGsettingsRunner gs;
  late FolderColorizer colorizer;

  Future<void> setupIcons({String theme = 'Test-Theme'}) async {
    home = Directory('${temp.path}/home');
    icons = Directory('${home.path}/.local/share/icons');
    config = Directory('${home.path}/.config/nebulashade');
    gs.values['icon-theme'] = theme;
    final dir = Directory('${icons.path}/$theme/places/scalable');
    await dir.create(recursive: true);
    await File('${dir.path}/default-folder.svg')
        .writeAsString('<svg fill:#ff0000 fill:#FF0000 fill-opacity:0.5/>');
    await File('${dir.path}/default-folder-documents.svg')
        .writeAsString('<svg fill:#ff0000/>');
    await File('${dir.path}/default-user-home.svg')
        .writeAsString('<svg fill:#FF0000/>');
    await File('${dir.path}/other.svg').writeAsString('#ff0000');
    colorizer = FolderColorizer(
        gs: gs,
        iconsRoot: icons.path,
        configDir: config.path,
        homeRoot: home.path);
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('folder-colorizer-test-');
    gs = FakeGsettingsRunner();
    await setupIcons();
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('reads first folder fill value in uppercase', () async {
    expect(await colorizer.readCurrentHex(), '#FF0000');
  });

  test('replaces listed files, backs them up and restores icon theme',
      () async {
    final result = await colorizer.apply('#00FF00');
    expect(result.ok, isTrue);
    final folder =
        File('${icons.path}/Test-Theme/places/scalable/default-folder.svg');
    final content = await folder.readAsString();
    expect(content, contains('fill:#00FF00'));
    expect(content, contains('fill-opacity:0.5'));
    expect(
        await File('${icons.path}/Test-Theme/places/scalable/other.svg')
            .readAsString(),
        '#ff0000');
    expect(gs.values['icon-theme'], 'Test-Theme');
    final backups = Directory('${config.path}/backups');
    expect(await backups.list().length, 1);
    final stored =
        await backups.list(recursive: true).where((e) => e is File).toList();
    expect(stored, isNotEmpty);
    expect(await (stored.first as File).readAsString(), contains('#ff0000'));
  });

  test('invalid hex returns false without a backup', () async {
    for (final value in ['red', '#12']) {
      expect((await colorizer.apply(value)).ok, isFalse);
    }
    expect(await Directory('${config.path}/backups').exists(), isFalse);
  });

  test('same colour is already done without backup', () async {
    final result = await colorizer.apply('#ff0000');
    expect(result.ok, isTrue);
    expect(result.message, 'Already this colour');
    expect(await Directory('${config.path}/backups').exists(), isFalse);
  });

  test('no listed regular files fails', () async {
    await Directory('${icons.path}/Test-Theme/places/scalable')
        .delete(recursive: true);
    final result = await colorizer.apply('#00FF00');
    expect(result.ok, isFalse);
  });

  test('failed Adwaita refresh does not throw and restores setting', () async {
    gs.failSetValue = 'Adwaita';
    final result = await colorizer.apply('#00FF00');
    expect(result.ok, isTrue);
    expect(gs.values['icon-theme'], 'Test-Theme');
    expect(
        result.message, contains('Restart apps to see the new folder colour'));
  });

  test('resolve falls back only inside icons root', () async {
    await Directory('${icons.path}/Test-Theme').delete(recursive: true);
    await Directory('${icons.path}/Colloid-teal-nord-dark')
        .create(recursive: true);
    gs.values['icon-theme'] = 'Missing';
    expect(await colorizer.resolveIconThemeDir(),
        '${icons.path}/Colloid-teal-nord-dark');
    await Directory('${icons.path}/Colloid-teal-nord-dark')
        .delete(recursive: true);
    expect(await colorizer.resolveIconThemeDir(), isNull);
  });

  test('follows in-theme symlinks and skips targets outside icon theme',
      () async {
    final dir = Directory('${icons.path}/Test-Theme/places/scalable');
    await File('${dir.path}/default-folder-documents.svg').delete();
    await Link('${dir.path}/default-folder-documents.svg')
        .create('${dir.path}/other.svg');
    final outside = File('${temp.path}/outside.svg');
    await outside.writeAsString('<svg fill:#ff0000/>');
    await File('${dir.path}/default-folder-games.svg').create();
    await File('${dir.path}/default-folder-games.svg').delete();
    await Link('${dir.path}/default-folder-games.svg').create(outside.path);
    final result = await colorizer.apply('#00FF00');
    expect(result.ok, isTrue);
    expect(await File('${dir.path}/other.svg').readAsString(), '#00ff00');
    expect(await outside.readAsString(), '<svg fill:#ff0000/>');
  });

  test('concurrent apply is rejected', () async {
    gs.holdOnAdwaita = Completer<void>();
    final first = colorizer.apply('#00FF00');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final second = await colorizer.apply('#0000FF');
    expect(second.ok, isFalse);
    expect(second.message, 'A folder colour change is already running');
    gs.holdOnAdwaita!.complete();
    expect((await first).ok, isTrue);
  });

  test('prunes only timestamp backup directories, keeping newest five',
      () async {
    final backups = Directory('${config.path}/backups')
      ..createSync(recursive: true);
    for (var i = 1; i <= 6; i++) {
      Directory('${backups.path}/20250101000000${i.toString().padLeft(3, '0')}')
          .createSync();
    }
    Directory('${backups.path}/keep-me').createSync();
    final result = await colorizer.apply('#00FF00');
    expect(result.ok, isTrue);
    expect(await Directory('${backups.path}/keep-me').exists(), isTrue);
    final timestampDirs = await backups
        .list()
        .where((entity) =>
            entity is Directory &&
            RegExp(r'^\d{17}$').hasMatch(entity.path
                .split(Platform.pathSeparator)
                .where((part) => part.isNotEmpty)
                .last))
        .toList();
    expect(timestampDirs.length, 5);
  });
}
