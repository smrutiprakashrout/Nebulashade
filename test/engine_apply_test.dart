import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/config/theme_variants.dart';
import 'package:nebulashade/engine/engine_settings.dart';
import 'package:nebulashade/engine/unified_color_engine.dart';
import 'package:nebulashade/engine/watch_gate.dart';
import 'package:nebulashade/services/gsettings_runner.dart';
import 'package:nebulashade/services/theme_detector.dart';

class _FakeGs implements GsettingsRunner {
  final values = <String, String>{
    '$gtkInterfaceSchema/$gtkThemeKey': ThemeVariants.dark.folderName,
    '$userThemeSchema/$userThemeNameKey': ThemeVariants.dark.folderName,
    '$gtkInterfaceSchema/$colorSchemeKey': 'prefer-dark',
  };
  bool failAdwaitaOnce = false;
  @override
  Future<GsResult> get(String schema, String key) async => GsResult(
      ok: values.containsKey('$schema/$key'),
      value: values['$schema/$key'] ?? '');
  @override
  Future<GsResult> set(String schema, String key, String value) async {
    if (failAdwaitaOnce && value == 'Adwaita') {
      failAdwaitaOnce = false;
      return const GsResult(ok: false, error: 'simulated reload failure');
    }
    values['$schema/$key'] = value;
    return const GsResult(ok: true);
  }
}

class _Gate implements WatchGateHandle {
  bool held = false;
  int resumeCalls = 0;
  int reinitCalls = 0;
  @override
  void suspend() => held = true;
  @override
  Future<void> resume({Future<void> Function()? reinit}) async {
    if (!held) return;
    held = false;
    resumeCalls++;
    if (reinit != null) reinitCalls++;
  }
}

class _Harness {
  _Harness(this.dir, this.gs, this.gate)
      : home = '${dir.path}/home',
        config = '${dir.path}/config';
  final Directory dir;
  final _FakeGs gs;
  final _Gate gate;
  final String home;
  final String config;
  late final String theme = '$home/.themes/${ThemeVariants.dark.folderName}';

  Future<void> createTargets({bool symlinkGtkOverride = false}) async {
    final bodies = <String, String>{
      'gtk-4.0/gtk.css':
          '@define-color warning_color #df0065;\n.a { background: #30241f; }\n',
      'gtk-4.0/gtk-dark.css':
          '@define-color error_bg_color #f852ca;\n.b { color: #30241f; }\n',
      'gtk-3.0/gtk.css':
          '@define-color success_color #a1014b;\n.c { background: #30241f; }\n',
      'gtk-3.0/gtk-dark.css': '.d { background: #30241f; }\n',
      'gnome-shell/gnome-shell.css': '.shell { background: #30241f; }\n',
      'gnome-shell/pad-osd.css': '.osd { background: #30241f; }\n',
    };
    for (final entry in bodies.entries) {
      final f = File('$theme/${entry.key}')..createSync(recursive: true);
      await f.writeAsString(entry.value);
    }
    await File('$theme/index.theme').writeAsString('[Theme]\nName=Fake\n');
    final config = Directory('$home/.config/gtk-4.0')
      ..createSync(recursive: true);
    final source = File('${config.path}/gtk.css');
    if (symlinkGtkOverride) {
      final outside = File('${dir.path}/outside.css')
        ..writeAsStringSync('.x{}');
      await Link(source.path).create(outside.path);
    } else {
      await source.writeAsString('.live { background: #30241f; }\n');
    }
    await File('${config.path}/gtk-dark.css')
        .writeAsString('.live-dark { background: #30241f; }\n');
  }

  UnifiedColorEngine engine({
    bool Function()? busy,
    Future<void> Function(String, int)? beforeWrite,
    bool Function(String)? mismatch,
  }) =>
      UnifiedColorEngine(
        gs: gs,
        detector: ThemeDetector(searchDirs: ['$home/.themes']),
        home: home,
        configDir: config,
        gate: gate,
        themeSwitchBusyCheck: busy,
        beforeWrite: beforeWrite,
        forceVerifyMismatch: mismatch,
      );

  List<File> files() => [
        File('$theme/gtk-4.0/gtk.css'),
        File('$theme/gtk-4.0/gtk-dark.css'),
        File('$theme/gtk-3.0/gtk.css'),
        File('$theme/gtk-3.0/gtk-dark.css'),
        File('$theme/gnome-shell/gnome-shell.css'),
        File('$theme/gnome-shell/pad-osd.css'),
        File('$home/.config/gtk-4.0/gtk.css'),
        File('$home/.config/gtk-4.0/gtk-dark.css'),
      ];
}

void main() {
  late Directory temp;
  late _Harness h;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('engine-apply-test-');
    final gs = _FakeGs();
    final gate = _Gate();
    h = _Harness(temp, gs, gate);
    await h.createTargets();
  });
  tearDown(() async => temp.delete(recursive: true));

  test(
      'success writes all temp targets, snapshots, restores settings and resumes gate once',
      () async {
    final before = h.files().map((f) => f.readAsStringSync()).toList();
    final result = await h.engine().apply(const Color(0xffcea14f));
    expect(result.ok, isTrue, reason: result.message);
    expect(result.snapshotId, isNotNull);
    expect(h.files().map((f) => f.readAsStringSync()).toList(), isNot(before));
    expect(
        Directory('${h.config}/backups/engine/${result.snapshotId}')
            .existsSync(),
        isTrue);
    expect(h.gs.values['$gtkInterfaceSchema/$gtkThemeKey'],
        ThemeVariants.dark.folderName);
    expect(h.gs.values['$userThemeSchema/$userThemeNameKey'],
        ThemeVariants.dark.folderName);
    final settings = await EngineSettings.read(configDir: h.config);
    expect(settings.appliedHex, '#CEA14F');
    expect(settings.lastSnapshotId, result.snapshotId);
    expect(h.gate.held, isFalse);
    expect(h.gate.resumeCalls, 1);
    expect(h.gate.reinitCalls, 1);
  });

  test('validation failure writes nothing', () async {
    await h.files().first.writeAsString('');
    final before = h.files().map((f) => f.readAsBytesSync()).toList();
    final result = await h.engine().apply(const Color(0xffcea14f));
    expect(result.ok, isFalse);
    expect(result.message, contains('Validation failed'));
    expect(h.files().map((f) => f.readAsBytesSync()).toList(), before);
    expect(h.gate.resumeCalls, 0);
  });

  test('write failure on fourth target rolls all targets back and resumes gate',
      () async {
    final before = h.files().map((f) => f.readAsBytesSync()).toList();
    final result = await h.engine(beforeWrite: (path, index) async {
      if (index == 4) throw StateError('injected fourth-write error');
    }).apply(const Color(0xffcea14f));
    expect(result.ok, isFalse);
    expect(result.rolledBack, isTrue);
    expect(h.files().map((f) => f.readAsBytesSync()).toList(), before);
    expect(h.gate.resumeCalls, 1);
  });

  test('reload error restores settings and rolls back files', () async {
    final before = h.files().map((f) => f.readAsBytesSync()).toList();
    h.gs.failAdwaitaOnce = true;
    final result = await h.engine().apply(const Color(0xffcea14f));
    expect(result.ok, isFalse);
    expect(result.rolledBack, isTrue);
    expect(h.files().map((f) => f.readAsBytesSync()).toList(), before);
    expect(h.gs.values['$gtkInterfaceSchema/$gtkThemeKey'],
        ThemeVariants.dark.folderName);
    expect(h.gs.values['$userThemeSchema/$userThemeNameKey'],
        ThemeVariants.dark.folderName);
  });

  test('verification mismatch rolls back', () async {
    final before = h.files().map((f) => f.readAsBytesSync()).toList();
    final first = h.files().first.path;
    final result = await h
        .engine(mismatch: (p) => p == first)
        .apply(const Color(0xffcea14f));
    expect(result.ok, isFalse);
    expect(result.rolledBack, isTrue);
    expect(h.files().map((f) => f.readAsBytesSync()).toList(), before);
  });

  test('revertLast and baseline restore originals', () async {
    final before = h.files().map((f) => f.readAsBytesSync()).toList();
    final engine = h.engine();
    await engine.apply(const Color(0xffcea14f));
    expect((await engine.revertLast()).ok, isTrue);
    expect(h.files().map((f) => f.readAsBytesSync()).toList(), before);
    await engine.apply(const Color(0xff4f7ace));
    expect((await engine.revertToBaseline()).ok, isTrue);
    expect(h.files().map((f) => f.readAsBytesSync()).toList(), before);
  });

  test('light variant, busy switch and symlink targets are refused', () async {
    h.gs.values['$gtkInterfaceSchema/$gtkThemeKey'] =
        ThemeVariants.light.folderName;
    expect((await h.engine().apply(const Color(0xffcea14f))).message,
        contains('Dark variant only'));
    h.gs.values['$gtkInterfaceSchema/$gtkThemeKey'] =
        ThemeVariants.dark.folderName;
    expect(
        (await h.engine(busy: () => true).apply(const Color(0xffcea14f)))
            .message,
        contains('theme switch'));
    await temp.delete(recursive: true);
    temp = await Directory.systemTemp.createTemp('engine-symlink-test-');
    h = _Harness(temp, _FakeGs(), _Gate());
    await h.createTargets(symlinkGtkOverride: true);
    expect((await h.engine().apply(const Color(0xffcea14f))).message,
        contains('Symlink target refused'));
  });

  test('concurrent second apply is refused and gate resumes after first',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final engine = h.engine(beforeWrite: (path, index) async {
      if (index == 1) {
        entered.complete();
        await release.future;
      }
    });
    final first = engine.apply(const Color(0xffcea14f));
    await entered.future;
    final second = await engine.apply(const Color(0xff4f7ace));
    expect(second.ok, isFalse);
    expect(second.message, contains('already running'));
    release.complete();
    expect((await first).ok, isTrue);
    expect(h.gate.held, isFalse);
  });

  test('same base twice is byte-stable and creates a second snapshot',
      () async {
    final engine = h.engine();
    final a = await engine.apply(const Color(0xffcea14f));
    final once = h.files().map((f) => f.readAsBytesSync()).toList();
    final b = await engine.apply(const Color(0xffcea14f));
    expect(b.ok, isTrue, reason: b.message);
    expect(h.files().map((f) => f.readAsBytesSync()).toList(), once);
    expect(a.snapshotId, isNot(b.snapshotId));
  });
}
