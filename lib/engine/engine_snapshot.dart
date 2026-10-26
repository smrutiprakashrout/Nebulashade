import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:nebulashade/engine/engine_targets.dart';
import 'package:nebulashade/services/gsettings_runner.dart';

class EngineSnapshotStore {
  EngineSnapshotStore(this.configDir, {GsettingsRunner? gs})
      : _gs = gs ?? ProcessGsettingsRunner();

  final String configDir;
  final GsettingsRunner _gs;
  String get _root => '$configDir/backups/engine';

  Future<String> ensureBaseline(List<EngineTarget> targets,
      {String? appliedHex}) async {
    final directory = Directory('$_root/baseline-before-beta');
    if (await directory.exists()) return 'baseline-before-beta';
    return create('baseline-before-beta', targets,
        {'appliedHex': appliedHex, 'baseline': true});
  }

  Future<String> create(
      String id, List<EngineTarget> targets, Map<String, Object?> extra) async {
    if (!_validId(id)) throw ArgumentError.value(id, 'id');
    final folder = Directory('$_root/$id');
    await Directory('${folder.path}/files').create(recursive: true);
    final entries = <Map<String, Object?>>[];
    for (final target in targets) {
      final source = File(target.path);
      final bytes = await source.readAsBytes();
      final flattened = _flatten(target.path);
      await File('${folder.path}/files/$flattened')
          .writeAsBytes(bytes, flush: true);
      entries.add({
        'path': target.path,
        'flattened': flattened,
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      });
    }
    final settings = <String, Object?>{};
    for (final entry in const [
      (gtkInterfaceSchema, gtkThemeKey, 'gtk-theme'),
      (userThemeSchema, userThemeNameKey, 'user-theme-name'),
      (gtkInterfaceSchema, colorSchemeKey, 'color-scheme'),
    ]) {
      final value = await _gs.get(entry.$1, entry.$2);
      settings[entry.$3] = value.ok ? value.value : null;
    }
    final manifest = <String, Object?>{
      'id': id,
      'createdAt': DateTime.now().toIso8601String(),
      'appliedHex': extra['appliedHex'],
      'files': entries,
      'settings': settings,
    };
    await _writeJson(File('${folder.path}/manifest.json'), manifest);
    return id;
  }

  Future<bool> restore(String id, {List<EngineTarget>? targets}) async {
    if (!_validId(id)) return false;
    try {
      final directory = Directory('$_root/$id');
      final decoded = jsonDecode(
          await File('${directory.path}/manifest.json').readAsString());
      if (decoded is! Map || decoded['id'] != id || decoded['files'] is! List)
        return false;
      final allowed = targets?.map((e) => e.path).toSet();
      for (final raw in decoded['files'] as List) {
        if (raw is! Map) return false;
        final targetPath = raw['path'] as String;
        final flattened = raw['flattened'] as String;
        if (allowed != null && !allowed.contains(targetPath)) continue;
        if (flattened.contains('/') || flattened.contains('..')) return false;
        final bytes =
            await File('${directory.path}/files/$flattened').readAsBytes();
        if (bytes.length != raw['size'] ||
            sha256.convert(bytes).toString() != raw['sha256']) return false;
        await _atomicWrite(File(targetPath), bytes);
        final actual = await File(targetPath).readAsBytes();
        if (sha256.convert(actual).toString() != raw['sha256']) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> prune({int keep = 10}) async {
    try {
      final root = Directory(_root);
      if (!await root.exists()) return;
      final snapshots = <({Directory directory, String id, DateTime time})>[];
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final id = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (!_validId(id) || id == 'baseline-before-beta') continue;
        var time = DateTime.fromMillisecondsSinceEpoch(0);
        try {
          final m = jsonDecode(
              await File('${entity.path}/manifest.json').readAsString());
          time = DateTime.tryParse(m['createdAt'] as String? ?? '') ?? time;
        } catch (_) {}
        snapshots.add((directory: entity, id: id, time: time));
      }
      snapshots.sort((a, b) => b.time.compareTo(a.time));
      for (final item in snapshots.skip(keep < 0 ? 0 : keep)) {
        await item.directory.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _atomicWrite(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final temp =
        File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  Future<void> _writeJson(File file, Object json) async {
    await file.parent.create(recursive: true);
    final temp =
        File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    await temp.rename(file.path);
  }

  String _flatten(String value) =>
      value.replaceAll(RegExp(r'^/+'), '').replaceAll('/', '__');

  bool _validId(String id) =>
      id == 'baseline-before-beta' || RegExp(r'^\d{17}$').hasMatch(id);
}
