import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/engine/engine_snapshot.dart';
import 'package:nebulashade/engine/engine_targets.dart';
import 'package:nebulashade/services/gsettings_runner.dart';

class _Gs implements GsettingsRunner {
  @override
  Future<GsResult> get(String schema, String key) async =>
      const GsResult(ok: true, value: 'test');
  @override
  Future<GsResult> set(String schema, String key, String value) async =>
      const GsResult(ok: true);
}

void main() {
  late Directory temp;
  late EngineSnapshotStore store;
  late File file;
  late List<EngineTarget> targets;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('engine-snapshot-test-');
    store = EngineSnapshotStore('${temp.path}/config', gs: _Gs());
    file = File('${temp.path}/gtk.css')..createSync(recursive: true);
    await file.writeAsString('original bytes\n');
    targets = [EngineTarget(path: file.path, fileKind: 'gtk4')];
  });
  tearDown(() async => temp.delete(recursive: true));

  test('snapshot restore is byte-identical and verifies hashes', () async {
    final id = await store
        .create('20260101000000001', targets, {'appliedHex': '#CEA14F'});
    await file.writeAsString('changed\n');
    expect(await store.restore(id, targets: targets), isTrue);
    expect(await file.readAsString(), 'original bytes\n');
  });

  test('baseline is created once and never overwritten', () async {
    await store.ensureBaseline(targets, appliedHex: '#111111');
    await file.writeAsString('later');
    await store.ensureBaseline(targets, appliedHex: '#222222');
    expect(
        await store.restore('baseline-before-beta', targets: targets), isTrue);
    expect(await file.readAsString(), 'original bytes\n');
  });

  test('prune retains ten newest timestamp snapshots and baseline', () async {
    await store.ensureBaseline(targets);
    for (var i = 1; i <= 12; i++) {
      await store.create(i.toString().padLeft(17, '0'), targets, {});
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await store.prune(keep: 10);
    expect(
        await Directory(
                '${temp.path}/config/backups/engine/baseline-before-beta')
            .exists(),
        isTrue);
    final dirs = await Directory('${temp.path}/config/backups/engine')
        .list()
        .where((e) => e is Directory)
        .length;
    expect(dirs, 11);
  });

  test('corrupt manifest is handled without throwing', () async {
    final dir =
        Directory('${temp.path}/config/backups/engine/20260101000000002')
          ..createSync(recursive: true);
    await File('${dir.path}/manifest.json').writeAsString('{broken');
    expect(await store.restore('20260101000000002', targets: targets), isFalse);
  });
}
