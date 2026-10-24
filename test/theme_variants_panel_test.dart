import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/config/theme_variants.dart';
import 'package:nebulashade/services/theme_detector.dart';
import 'package:nebulashade/services/theme_downloader.dart';
import 'package:nebulashade/widgets/theme_variants_panel.dart';

const darkVariant = ThemeVariant(
  id: 'dark',
  label: 'Everforest Dark',
  folderName: 'Everforest-Dark-Soft-Adaptive',
);
const lightVariant = ThemeVariant(
  id: 'light',
  label: 'Everforest Light',
  folderName: 'Everforest-Light-Soft-Adaptive',
);

ThemeCheckResult result(ThemeVariant variant, ThemeStatus status,
        {List<String> missingFiles = const []}) =>
    ThemeCheckResult(
      variant: variant,
      status: status,
      foundPath:
          status == ThemeStatus.complete ? '/tmp/${variant.folderName}' : null,
      missingFiles: missingFiles,
    );

Widget panelApp({
  ThemeCheckResult? dark,
  ThemeCheckResult? light,
  bool checking = false,
  String? activeVariantId = 'dark',
  bool switching = false,
  bool? canSwitch,
  bool downloadConfigured = true,
  DownloadPhase downloadPhase = DownloadPhase.idle,
  double? downloadProgress,
  VoidCallback? onRefresh,
  void Function(String)? onSelectVariant,
  VoidCallback? onDownloadLight,
  VoidCallback? onRestoreDark,
  double width = 480,
  bool intrinsicHeight = false,
}) {
  final resolvedDark = dark ?? result(darkVariant, ThemeStatus.complete);
  final resolvedLight = light ?? result(lightVariant, ThemeStatus.missing);
  final panel = ThemeVariantsPanel(
    dark: resolvedDark,
    light: resolvedLight,
    checking: checking,
    activeVariantId: activeVariantId,
    switching: switching,
    canSwitch: canSwitch ??
        (resolvedDark.status == ThemeStatus.complete &&
            resolvedLight.status == ThemeStatus.complete),
    downloadConfigured: downloadConfigured,
    downloadPhase: downloadPhase,
    downloadProgress: downloadProgress,
    darkPalette: const [],
    baseColor: const Color(0xFF362C29),
    onRefresh: onRefresh ?? () {},
    onSelectVariant: onSelectVariant ?? (_) {},
    onDownloadLight: onDownloadLight ?? () {},
    onRestoreDark: onRestoreDark,
    footer: Row(
      children: [
        const Expanded(
            child: Text('Fix Flatpak GTK Theme',
                style: TextStyle(color: Colors.white, fontSize: 12))),
        Switch(value: true, onChanged: null),
      ],
    ),
  );
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: intrinsicHeight ? IntrinsicHeight(child: panel) : panel,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Light missing shows lock, hint, and one Download button',
      (tester) async {
    await tester.pumpWidget(panelApp());
    expect(find.text('Everforest Dark'), findsOneWidget);
    expect(find.text('Everforest Light'), findsOneWidget);
    expect(find.text('Not installed'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Install both variants to switch modes.'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_outlined), findsNothing);
    expect(find.byKey(const ValueKey('mode-switch')), findsOneWidget);
  });

  testWidgets('Download callback respects configuration', (tester) async {
    var downloads = 0;
    await tester.pumpWidget(panelApp(
      onDownloadLight: () => downloads++,
    ));
    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(downloads, 1);

    await tester.pumpWidget(panelApp(
      downloadConfigured: false,
      onDownloadLight: () => downloads++,
    ));
    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(downloads, 1);
  });

  testWidgets('complete variants show sun and only switch to unselected',
      (tester) async {
    var selected = <String>[];
    await tester.pumpWidget(panelApp(
      dark: result(darkVariant, ThemeStatus.complete),
      light: result(lightVariant, ThemeStatus.complete),
      activeVariantId: 'light',
      onSelectVariant: selected.add,
    ));
    expect(find.text('Download'), findsNothing);
    expect(find.byIcon(Icons.light_mode_outlined), findsWidgets);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(find.text('Install both variants to switch modes.'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mode-switch')));
    await tester.pump();
    expect(selected, ['dark']);
  });

  testWidgets('canSwitch false disables segments', (tester) async {
    var calls = 0;
    await tester.pumpWidget(panelApp(
      dark: result(darkVariant, ThemeStatus.complete),
      light: result(lightVariant, ThemeStatus.complete),
      canSwitch: false,
      onSelectVariant: (_) => calls++,
    ));
    await tester.tap(find.byKey(const ValueKey('mode-switch')));
    await tester.pump();
    expect(calls, 0);
  });

  testWidgets('switching disables segments', (tester) async {
    var calls = 0;
    await tester.pumpWidget(panelApp(
      dark: result(darkVariant, ThemeStatus.complete),
      light: result(lightVariant, ThemeStatus.complete),
      switching: true,
      onSelectVariant: (_) => calls++,
    ));
    await tester.tap(find.byKey(const ValueKey('mode-switch')));
    await tester.pump();
    expect(calls, 0);
  });

  testWidgets('incomplete Light shows amber status and Download',
      (tester) async {
    await tester.pumpWidget(panelApp(
      light: result(lightVariant, ThemeStatus.incomplete,
          missingFiles: const ['gtk-4.0/gtk.css']),
    ));
    expect(find.text('Incomplete'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('Restore Dark callback is available for active incomplete Light',
      (tester) async {
    var restored = 0;
    await tester.pumpWidget(panelApp(
      light: result(lightVariant, ThemeStatus.missing),
      activeVariantId: 'light',
      onRestoreDark: () => restored++,
    ));
    expect(find.text('Restore Dark'), findsOneWidget);
    await tester.tap(find.text('Restore Dark'));
    await tester.pump();
    expect(restored, 1);
  });

  testWidgets('supports ThemeScreen intrinsic-height parent', (tester) async {
    await tester.pumpWidget(panelApp(intrinsicHeight: true));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode switch and preview halves select only while enabled',
      (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(panelApp(
      dark: result(darkVariant, ThemeStatus.complete),
      light: result(lightVariant, ThemeStatus.complete),
      activeVariantId: 'dark',
      onSelectVariant: selected.add,
    ));
    expect(
        tester.getSize(find.byKey(const ValueKey('mode-switch'))).height, 30);
    expect(tester.getRect(find.byKey(const ValueKey('preview-dark'))).width,
        greaterThan(0));
    expect(tester.getRect(find.byKey(const ValueKey('preview-light'))).width,
        greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('preview-light')));
    await tester.pump();
    expect(selected, ['light']);
    await tester.pumpWidget(panelApp(
      dark: result(darkVariant, ThemeStatus.complete),
      light: result(lightVariant, ThemeStatus.complete),
      activeVariantId: 'dark',
      switching: true,
      onSelectVariant: selected.add,
    ));
    await tester.tap(find.byKey(const ValueKey('preview-light')));
    await tester.pump();
    expect(selected, ['light']);
  });

  testWidgets('left panel controls retain requested target sizes',
      (tester) async {
    await tester.pumpWidget(panelApp());
    expect(tester.getSize(find.byKey(const ValueKey('mode-switch'))).width, 58);
    expect(tester.getSize(find.byKey(const ValueKey('download-light'))).height,
        40);
    expect(tester.getSize(find.byKey(const ValueKey('refresh'))).height, 40);
  });

  testWidgets('missing and complete states do not overflow at small sizes',
      (tester) async {
    final sizes = <Size>[
      const Size(480, 700),
      const Size(480, 420),
      const Size(360, 700),
      const Size(360, 420),
      const Size(300, 700),
      const Size(300, 420),
    ];
    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      for (final complete in [false, true]) {
        await tester.pumpWidget(panelApp(
          width: size.width,
          dark: result(darkVariant, ThemeStatus.complete),
          light: result(
            lightVariant,
            complete ? ThemeStatus.complete : ThemeStatus.missing,
          ),
          activeVariantId: complete ? 'light' : 'dark',
        ));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'size=$size complete=$complete');
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
