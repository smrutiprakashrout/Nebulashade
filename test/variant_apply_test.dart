import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/components/autoadjusthue.dart';
import 'package:nebulashade/config/theme_variants.dart';
import 'package:nebulashade/services/gsettings_runner.dart';
import 'package:nebulashade/services/theme_detector.dart';
import 'package:nebulashade/services/variant_apply.dart';
import 'package:nebulashade/services/variant_paths.dart';
import 'package:nebulashade/services/variant_state.dart';

const testLight =
    ThemeVariant(id: 'light', label: 'Test Light', folderName: 'T-Light');

class FakeGsettingsRunner implements GsettingsRunner {
  final Map<String, String> values;
  final List<(String, String, String)> setCalls = [];
  String? failKey;
  String? failValue;

  FakeGsettingsRunner(this.values);

  String _id(String schema, String key) => '$schema/$key';

  @override
  Future<GsResult> get(String schema, String key) async => GsResult(
        ok: values.containsKey(_id(schema, key)),
        value: values[_id(schema, key)] ?? '',
      );

  @override
  Future<GsResult> set(String schema, String key, String value) async {
    setCalls.add((schema, key, value));
    if (key == failKey && value == failValue) {
      return const GsResult(ok: false, error: 'injected set failure');
    }
    values[_id(schema, key)] = value;
    return const GsResult(ok: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dark path list remains exactly the original eight paths', () {
    expect(VariantPaths.forDark('/h'), [
      '/h/.themes/Everforest-Dark-Soft-Adaptive/gtk-4.0/gtk.css',
      '/h/.themes/Everforest-Dark-Soft-Adaptive/gtk-4.0/gtk-dark.css',
      '/h/.themes/Everforest-Dark-Soft-Adaptive/gtk-3.0/gtk.css',
      '/h/.themes/Everforest-Dark-Soft-Adaptive/gtk-3.0/gtk-dark.css',
      '/h/.themes/Everforest-Dark-Soft-Adaptive/gnome-shell/gnome-shell.css',
      '/h/.themes/Everforest-Dark-Soft-Adaptive/gnome-shell/pad-osd.css',
      '/h/.config/gtk-4.0/gtk.css',
      '/h/.config/gtk-4.0/gtk-dark.css',
    ]);
  });

  test('Light paths and home containment are correct', () {
    expect(VariantPaths.forLight('/home/u', '/home/u/.themes/X'), [
      '/home/u/.themes/X/gtk-4.0/gtk.css',
      '/home/u/.themes/X/gtk-4.0/gtk-dark.css',
      '/home/u/.themes/X/gtk-3.0/gtk.css',
      '/home/u/.themes/X/gtk-3.0/gtk-dark.css',
      '/home/u/.themes/X/gnome-shell/gnome-shell.css',
      '/home/u/.themes/X/gnome-shell/pad-osd.css',
      '/home/u/.config/gtk-4.0/gtk.css',
      '/home/u/.config/gtk-4.0/gtk-dark.css',
    ]);
    expect(VariantPaths.isUnderHome('/home/u/.themes/X', '/home/u'), isTrue);
    expect(VariantPaths.isUnderHome('/usr/share/themes/X', '/home/u'), isFalse);
    expect(
      VariantPaths.isUnderHome('/home/u/a/../.themes/X', '/home/u'),
      isFalse,
    );
    expect(VariantPaths.isUnderHome('/home/u/../etc/themes/X', '/home/u'),
        isFalse);
  });

  test('hue override changes only the listed temporary file', () async {
    final temp = await Directory.systemTemp.createTemp('variant_hue_test_');
    try {
      final included = File('${temp.path}/included.css');
      final untouched = File('${temp.path}/untouched.css');
      await included.writeAsString('a { color: #4a6a8a; }');
      await untouched.writeAsString('b { color: #4a6a8a; }');

      await automaticColorAdjustment('#a64a8a', overridePaths: [included.path]);

      final result = await included.readAsString();
      final color = RegExp(r'#[0-9a-fA-F]{6}').firstMatch(result)!.group(0)!;
      final actualHue = HSVColor.fromColor(_colorFromHex(color)).hue;
      final targetHue = HSVColor.fromColor(_colorFromHex('#a64a8a')).hue;
      final distance = ((actualHue - targetHue + 540) % 360) - 180;
      expect(distance.abs(), lessThanOrEqualTo(3));
      expect(await untouched.readAsString(), 'b { color: #4a6a8a; }');
    } finally {
      await temp.delete(recursive: true);
    }
  });

  group('applyHexToLight', () {
    late Directory temp;
    late Directory home;
    late Directory themeRoot;
    late Directory config;
    late FakeGsettingsRunner gs;
    late Map<String, List<int>> originalBytes;
    late List<String> lightFiles;

    Future<void> setup({bool complete = true}) async {
      temp = await Directory.systemTemp.createTemp('variant_apply_test_');
      home = Directory('${temp.path}/home')..createSync();
      themeRoot = Directory('${home.path}/.themes/T-Light')
        ..createSync(recursive: true);
      config = Directory('${home.path}/.config/nebulashade');
      final liveDir = Directory('${home.path}/.config/gtk-4.0')
        ..createSync(recursive: true);
      lightFiles = [
        '${themeRoot.path}/gtk-4.0/gtk.css',
        '${themeRoot.path}/gtk-4.0/gtk-dark.css',
        '${themeRoot.path}/gtk-3.0/gtk.css',
        '${themeRoot.path}/gtk-3.0/gtk-dark.css',
        '${themeRoot.path}/gnome-shell/gnome-shell.css',
        '${themeRoot.path}/gnome-shell/pad-osd.css',
        '${liveDir.path}/gtk.css',
        '${liveDir.path}/gtk-dark.css',
      ];
      final relativeThemeFiles = [
        'index.theme',
        'gtk-3.0/gtk.css',
        'gtk-4.0/gtk.css',
        'gnome-shell/gnome-shell.css',
        'gtk-4.0/gtk-dark.css',
        'gtk-3.0/gtk-dark.css',
        'gnome-shell/pad-osd.css',
      ];
      for (final relative in relativeThemeFiles) {
        if (!complete && relative == 'gtk-3.0/gtk.css') continue;
        final file = File('${themeRoot.path}/$relative');
        await file.parent.create(recursive: true);
        await file.writeAsString('a { background-color: #4a6a8a; }');
      }
      for (final filePath in lightFiles.skip(6)) {
        final file = File(filePath);
        await file.parent.create(recursive: true);
        await file.writeAsString('a { background-color: #4a6a8a; }');
      }
      originalBytes = {
        for (final filePath in lightFiles)
          if (File(filePath).existsSync())
            filePath: await File(filePath).readAsBytes(),
      };
      gs = FakeGsettingsRunner({
        '$gtkInterfaceSchema/$gtkThemeKey': 'T-Light',
        '$userThemeSchema/$userThemeNameKey': 'T-Light',
      });
    }

    ThemeDetector detector() => ThemeDetector(
          searchDirs: ['${home.path}/.themes'],
        );

    Future<ApplyResult> apply({
      String hex = '#b05a76',
      ThemeDetector? themeDetector,
      Future<void> Function(String, List<String>)? adjust,
      Future<void> Function(String, String)? notify,
    }) =>
        applyHexToLight(
          hex,
          gs: gs,
          detector: themeDetector ?? detector(),
          configDir: config.path,
          home: home.path,
          lightVariant: testLight,
          adjust: adjust,
          notify: notify,
        );

    tearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    test('applies Light colours, backs up files, and records success',
        () async {
      await setup();
      final notifications = <(String, String)>[];
      final result = await apply(
        notify: (title, body) async => notifications.add((title, body)),
      );

      expect(result.ok, isTrue);
      expect(
        await File(lightFiles.first).readAsBytes(),
        isNot(equals(originalBytes[lightFiles.first])),
      );
      expect(
        gs.values['$gtkInterfaceSchema/$gtkThemeKey'],
        'T-Light',
      );
      expect(gs.values['$userThemeSchema/$userThemeNameKey'], 'T-Light');
      final backupRoot = Directory('${config.path}/backups');
      final backupFolders = await backupRoot.list().toList();
      expect(backupFolders, hasLength(1));
      final flattened = File(
        '${backupFolders.single.path}/light-apply/.themes__T-Light__gtk-4.0__gtk.css',
      );
      expect(await flattened.exists(), isTrue);
      final state =
          jsonDecode(await File('${config.path}/config.json').readAsString());
      expect(state['appliedHex']['light'], '#b05a76');
      expect(state['lastAppliedHex'], '#b05a76');
      expect(
          notifications, [('Theme Updated', 'Light theme colours refreshed!')]);
    });

    test('sanity failure restores every file and leaves gsettings untouched',
        () async {
      await setup();
      final originalSettings = Map<String, String>.from(gs.values);
      final result = await apply(
        adjust: (hex, paths) async => File(paths.first).writeAsString(''),
        notify: (title, body) async {},
      );
      expect(result.ok, isFalse);
      expect(result.message, 'Colour apply failed; files restored');
      expect(gs.values, originalSettings);
      expect(gs.setCalls, isEmpty);
      for (final filePath in lightFiles) {
        expect(await File(filePath).readAsBytes(), originalBytes[filePath]);
      }
    });

    test('failed temporary GTK Adwaita set still restores both settings',
        () async {
      await setup();
      gs.failKey = gtkThemeKey;
      gs.failValue = 'Adwaita';
      final result = await apply(notify: (title, body) async {});
      expect(result.ok, isFalse);
      expect(gs.values['$gtkInterfaceSchema/$gtkThemeKey'], 'T-Light');
      expect(gs.values['$userThemeSchema/$userThemeNameKey'], 'T-Light');
      expect(
        gs.setCalls
            .any((call) => call.$2 == userThemeNameKey && call.$3 == 'T-Light'),
        isTrue,
      );
      expect(
        gs.setCalls
            .any((call) => call.$2 == gtkThemeKey && call.$3 == 'T-Light'),
        isTrue,
      );
    });

    test('system-wide Light theme is read-only and creates no backup',
        () async {
      await setup();
      final systemThemes = Directory('${temp.path}/usr/share/themes')
        ..createSync(recursive: true);
      final outsideRoot = Directory('${systemThemes.path}/T-Light');
      for (final required in ThemeVariants.requiredFiles) {
        final file = File('${outsideRoot.path}/$required');
        await file.parent.create(recursive: true);
        await file.writeAsString('a { color: #4a6a8a; }');
      }
      final result = await apply(
        themeDetector: ThemeDetector(searchDirs: [systemThemes.path]),
        notify: (title, body) async {},
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('installed system-wide (read-only)'));
      expect(await Directory('${config.path}/backups').exists(), isFalse);
      for (final entry in originalBytes.entries) {
        expect(await File(entry.key).readAsBytes(), entry.value);
      }
    });

    test('invalid hex does not modify files or settings', () async {
      await setup();
      final result = await apply(hex: 'red', notify: (title, body) async {});
      expect(result.ok, isFalse);
      expect(gs.setCalls, isEmpty);
      for (final entry in originalBytes.entries) {
        expect(await File(entry.key).readAsBytes(), entry.value);
      }
      expect(await Directory('${config.path}/backups').exists(), isFalse);
    });

    test('missing or incomplete Light theme fails without changes', () async {
      await setup(complete: false);
      final result = await apply(notify: (title, body) async {});
      expect(result.ok, isFalse);
      expect(gs.setCalls, isEmpty);
      expect(await Directory('${config.path}/backups').exists(), isFalse);
    });
  });

  test('recordApplied preserves config and tolerates corrupt config', () async {
    final temp = await Directory.systemTemp.createTemp('variant_state_apply_');
    try {
      final configFile = File('${temp.path}/config.json');
      await configFile.writeAsString(jsonEncode({
        'activeVariant': 'light',
        'variants': {
          'light': {'folder': 'T-Light'}
        },
        'appliedHex': {'dark': '#123456'},
        'other': 'preserve-me',
      }));
      await VariantState.recordApplied('light', '#abcdef',
          configDir: temp.path);
      var data = jsonDecode(await configFile.readAsString());
      expect(data['activeVariant'], 'light');
      expect(data['variants']['light']['folder'], 'T-Light');
      expect(data['other'], 'preserve-me');
      expect(data['appliedHex'], {'dark': '#123456', 'light': '#abcdef'});
      expect(data['lastAppliedHex'], '#abcdef');

      await configFile.writeAsString('{corrupt');
      await VariantState.recordApplied('dark', '#123456', configDir: temp.path);
      data = jsonDecode(await configFile.readAsString());
      expect(data['activeVariant'], 'dark');
      expect(data['appliedHex']['dark'], '#123456');
      expect(data['lastAppliedHex'], '#123456');
    } finally {
      await temp.delete(recursive: true);
    }
  });
}

Color _colorFromHex(String hex) =>
    Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
