import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/config/theme_variants.dart';
import 'package:nebulashade/services/gsettings_runner.dart';
import 'package:nebulashade/services/theme_detector.dart';
import 'package:nebulashade/services/theme_switcher.dart';
import 'package:nebulashade/services/variant_state.dart';

const dark = ThemeVariant(id: 'dark', label: 'T Dark', folderName: 'T-Dark');
const light =
    ThemeVariant(id: 'light', label: 'T Light', folderName: 'T-Light');

class FakeGsettingsRunner implements GsettingsRunner {
  final Map<String, String> values;
  String? failSetKey;

  FakeGsettingsRunner(this.values);

  String _id(String schema, String key) => '$schema/$key';

  @override
  Future<GsResult> get(String schema, String key) async => GsResult(
      ok: values.containsKey(_id(schema, key)),
      value: values[_id(schema, key)] ?? '');

  @override
  Future<GsResult> set(String schema, String key, String value) async {
    if (key == failSetKey) {
      failSetKey = null;
      return GsResult(ok: false, error: 'injected failure');
    }
    values[_id(schema, key)] = value;
    return const GsResult(ok: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeSwitcher', () {
    late Directory temp;
    late Directory themes;
    late Directory config;
    late Directory live;
    late FakeGsettingsRunner gs;
    late ThemeSwitcher switcher;

    Future<void> createTheme(ThemeVariant variant, {String? lightSeed}) async {
      final root = Directory('${themes.path}/${variant.folderName}');
      for (final required in ThemeVariants.requiredFiles) {
        final file = File(
            '${root.path}/${required.replaceAll('/', Platform.pathSeparator)}');
        await file.parent.create(recursive: true);
        await file.writeAsString(
          required == 'gtk-4.0/gtk.css' && lightSeed != null
              ? lightSeed
              : 'seed-${variant.id}-$required',
        );
      }
    }

    Future<void> setup({bool includeLight = true}) async {
      temp = await Directory.systemTemp.createTemp('theme_switcher_test_');
      themes = Directory('${temp.path}/themes')..createSync();
      config = Directory('${temp.path}/config');
      live = Directory('${temp.path}/live')..createSync();
      await createTheme(dark);
      if (includeLight) await createTheme(light, lightSeed: 'LIGHT-SEED');
      await File('${live.path}/gtk.css').writeAsString('DARK-LIVE');
      await File('${live.path}/gtk-dark.css').writeAsString('DARK-LIVE-2');
      gs = FakeGsettingsRunner({
        '$gtkInterfaceSchema/$gtkThemeKey': dark.folderName,
        '$gtkInterfaceSchema/$colorSchemeKey': 'prefer-dark',
        '$userThemeSchema/$userThemeNameKey': dark.folderName,
      });
      switcher = ThemeSwitcher(
        gs: gs,
        detector: ThemeDetector(searchDirs: [themes.path]),
        configDir: config.path,
        liveGtk4Dir: live.path,
        darkVariant: dark,
        lightVariant: light,
      );
    }

    tearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    test('switches dark to light with backup and dark snapshot', () async {
      await setup();
      final result = await switcher.switchTo(light);
      expect(result.ok, isTrue);
      expect(gs.values['$gtkInterfaceSchema/$gtkThemeKey'], light.folderName);
      expect(gs.values['$gtkInterfaceSchema/$colorSchemeKey'], 'prefer-light');
      expect(gs.values['$userThemeSchema/$userThemeNameKey'], light.folderName);
      expect(await File('${live.path}/gtk.css').readAsString(), 'LIGHT-SEED');
      expect(
        await File(
                '${VariantState.snapshotDir('dark', configDir: config.path)}/gtk.css')
            .readAsString(),
        'DARK-LIVE',
      );
      final state =
          jsonDecode(await File('${config.path}/config.json').readAsString());
      expect(state['activeVariant'], 'light');
      final backups =
          Directory(VariantState.backupsDir(configDir: config.path));
      expect(await backups.list().isEmpty, isFalse);
    });

    test('round trip restores the exact dark live files', () async {
      await setup();
      expect((await switcher.switchTo(light)).ok, isTrue);
      expect((await switcher.switchTo(dark)).ok, isTrue);
      expect(await File('${live.path}/gtk.css').readAsString(), 'DARK-LIVE');
      expect(await File('${live.path}/gtk-dark.css').readAsString(),
          'DARK-LIVE-2');
    });

    test('failed user theme set rolls back settings and live files', () async {
      await setup();
      gs.failSetKey = userThemeNameKey;
      final initialValues = Map<String, String>.from(gs.values);
      final result = await switcher.switchTo(light);
      expect(result.ok, isFalse);
      expect(result.rolledBack, isTrue);
      expect(gs.values, initialValues);
      expect(await File('${live.path}/gtk.css').readAsString(), 'DARK-LIVE');
      expect(await File('${live.path}/gtk-dark.css').readAsString(),
          'DARK-LIVE-2');
    });

    test('missing light theme fails preflight without state or backup',
        () async {
      await setup(includeLight: false);
      final result = await switcher.switchTo(light);
      expect(result.ok, isFalse);
      expect(
          await Directory(VariantState.backupsDir(configDir: config.path))
              .exists(),
          isFalse);
      expect(await Directory('${config.path}/variants').exists(), isFalse);
      expect(await File('${config.path}/config.json').exists(), isFalse);
      expect(await File('${live.path}/gtk.css').readAsString(), 'DARK-LIVE');
    });

    test('refuses a symlinked live file without changing state', () async {
      await setup();
      await File('${live.path}/gtk.css').delete();
      await Link('${live.path}/gtk.css').create('${live.path}/gtk-dark.css');
      final result = await switcher.switchTo(light);
      expect(result.ok, isFalse);
      expect(result.message, contains('contains symlinks'));
      expect(
          await Directory(VariantState.backupsDir(configDir: config.path))
              .exists(),
          isFalse);
      expect(await File('${config.path}/config.json').exists(), isFalse);
    });

    test('already active returns without creating backups', () async {
      await setup();
      final result = await switcher.switchTo(dark);
      expect(result.ok, isTrue);
      expect(result.message, 'Already active');
      expect(
          await Directory(VariantState.backupsDir(configDir: config.path))
              .exists(),
          isFalse);
    });

    test('missing and corrupt variant state default to dark', () async {
      final missing =
          Directory.systemTemp.createTempSync('variant_state_missing_');
      expect(VariantState.activeVariantIdSync(configDir: missing.path), 'dark');
      await File('${missing.path}/config.json').writeAsString('{bad json');
      expect(VariantState.activeVariantIdSync(configDir: missing.path), 'dark');
      await missing.delete(recursive: true);
    });
  });
}
