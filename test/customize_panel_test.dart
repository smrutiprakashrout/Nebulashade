import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/config/theme_variants.dart';
import 'package:nebulashade/services/theme_detector.dart';
import 'package:nebulashade/services/theme_downloader.dart';
import 'package:nebulashade/widgets/customize_panel.dart';
import 'package:nebulashade/widgets/theme_variants_panel.dart';

Widget panelApp({
  List<Color> palette = const [
    Color(0xFF111111),
    Color(0xFF222222),
    Color(0xFF333333),
    Color(0xFF444444),
  ],
  bool folderApplyEnabled = true,
  String? reason,
  bool applying = false,
  Future<void> Function(String)? onFolder,
  Future<void> Function(String)? onTopBar,
  Future<void> Function(String)? onDock,
  double width = 480,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: CustomizePanel(
              baseColor: const Color(0xFF362C29),
              wallpaperPalette: palette,
              initialFolderColor: const Color(0xFFF98E65),
              folderApplyEnabled: folderApplyEnabled,
              folderApplyDisabledReason: reason,
              applying: applying,
              onApplyFolder: onFolder,
              onApplyTopBar: onTopBar,
              onApplyDock: onDock,
            ),
          ),
        ),
      ),
    );

const _darkVariant = ThemeVariant(
  id: 'dark',
  label: 'Everforest Dark',
  folderName: 'T-Dark',
);
const _lightVariant = ThemeVariant(
  id: 'light',
  label: 'Everforest Light',
  folderName: 'T-Light',
);

ThemeCheckResult _themeResult(ThemeVariant variant, ThemeStatus status) =>
    ThemeCheckResult(
      variant: variant,
      status: status,
      foundPath:
          status == ThemeStatus.complete ? '/tmp/${variant.folderName}' : null,
    );

Widget _themePanelParent({required Size size, required bool lightMissing}) {
  final dark = _themeResult(_darkVariant, ThemeStatus.complete);
  final light = _themeResult(
    _lightVariant,
    lightMissing ? ThemeStatus.missing : ThemeStatus.complete,
  );
  return MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: size.height),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 1,
                          child: ThemeVariantsPanel(
                            dark: dark,
                            light: light,
                            checking: false,
                            activeVariantId: lightMissing ? 'dark' : 'light',
                            switching: false,
                            canSwitch: !lightMissing,
                            downloadConfigured: false,
                            downloadPhase: DownloadPhase.idle,
                            downloadProgress: null,
                            darkPalette: const [],
                            baseColor: const Color(0xFF362C29),
                            onRefresh: () {},
                            onSelectVariant: (_) {},
                            onDownloadLight: () {},
                            onRestoreDark: null,
                            footer: const SizedBox(height: 36),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 1,
                          child: CustomizePanel(
                            baseColor: const Color(0xFF362C29),
                            wallpaperPalette: const [],
                            initialFolderColor: const Color(0xFFF98E65),
                            folderApplyEnabled: false,
                            folderApplyDisabledReason: null,
                            applying: false,
                            onApplyFolder: null,
                            onApplyTopBar: null,
                            onApplyDock: null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Rect _panelRect(WidgetTester tester, Type panelType) {
  final panel = find.byType(panelType);
  return tester.getRect(
    find.descendant(of: panel, matching: find.byType(Container)).first,
  );
}

void main() {
  testWidgets('ThemeScreen parent chain renders with Light missing',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final size in [
      const Size(1280, 800),
      const Size(1000, 700),
      const Size(900, 650)
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester
          .pumpWidget(_themePanelParent(size: size, lightMissing: true));
      expect(tester.takeException(), isNull);
      final left = _panelRect(tester, ThemeVariantsPanel);
      final right = _panelRect(tester, CustomizePanel);
      expect((right.top - left.top).abs(), lessThanOrEqualTo(0.5));
      expect((right.height - left.height).abs(), lessThanOrEqualTo(0.5));
      expect((right.width - left.width).abs(), lessThanOrEqualTo(0.5));
      expect(
          tester
              .getRect(find.byKey(const ValueKey('customize-preview')))
              .height,
          greaterThanOrEqualTo(150));
      expect(
        tester.getRect(find.byKey(const ValueKey('customize-preview'))).height,
        greaterThan(150),
      );
      final preview =
          tester.getRect(find.byKey(const ValueKey('customize-preview')));
      final topBar =
          tester.getRect(find.byKey(const ValueKey('preview-topbar')));
      final folders =
          tester.getRect(find.byKey(const ValueKey('preview-folders')));
      final dock = tester.getRect(find.byKey(const ValueKey('preview-dock')));
      expect(preview.contains(topBar.topLeft), isTrue);
      expect(preview.contains(folders.topLeft), isTrue);
      expect(preview.contains(dock.topLeft), isTrue);
      expect(folders.overlaps(topBar), isFalse);
      expect(folders.overlaps(dock), isFalse);
      final apply =
          tester.getRect(find.byKey(const ValueKey('customize-apply')));
      expect(right.bottom - apply.bottom, lessThanOrEqualTo(20));
    }
  });

  testWidgets('ThemeScreen parent chain renders with both variants installed',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final size in [
      const Size(1280, 800),
      const Size(1000, 700),
      const Size(900, 650)
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester
          .pumpWidget(_themePanelParent(size: size, lightMissing: false));
      expect(tester.takeException(), isNull);
      final left = _panelRect(tester, ThemeVariantsPanel);
      final right = _panelRect(tester, CustomizePanel);
      expect((right.top - left.top).abs(), lessThanOrEqualTo(0.5));
      expect((right.height - left.height).abs(), lessThanOrEqualTo(0.5));
      expect((right.width - left.width).abs(), lessThanOrEqualTo(0.5));
      expect(find.text('Download'), findsNothing);
      expect(find.text('Install both variants to switch modes.'), findsNothing);
      expect(
          tester
              .getRect(find.byKey(const ValueKey('customize-preview')))
              .height,
          greaterThanOrEqualTo(150));
      final apply =
          tester.getRect(find.byKey(const ValueKey('customize-apply')));
      expect(right.bottom - apply.bottom, lessThanOrEqualTo(20));
    }
  });

  testWidgets('tight heights fill panel without overflow', (tester) async {
    for (final height in [360.0, 480.0, 700.0]) {
      tester.view.physicalSize = Size(800, height);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 480,
              height: height,
              child: const CustomizePanel(
                baseColor: Color(0xFF362C29),
                wallpaperPalette: [],
                initialFolderColor: Color(0xFFF98E65),
                folderApplyEnabled: false,
                folderApplyDisabledReason: null,
                applying: false,
                onApplyFolder: null,
                onApplyTopBar: null,
                onApplyDock: null,
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull, reason: 'height=$height');
      expect(
          tester
              .getRect(find.byKey(const ValueKey('customize-preview')))
              .height,
          greaterThanOrEqualTo(150));
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('loose scroll parent uses natural panel height', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CustomizePanel(
                baseColor: Color(0xFF362C29),
                wallpaperPalette: [],
                initialFolderColor: Color(0xFFF98E65),
                folderApplyEnabled: false,
                folderApplyDisabledReason: null,
                applying: false,
                onApplyFolder: null,
                onApplyTopBar: null,
                onApplyDock: null,
                fillHeight: false,
              ),
            ],
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(
        tester.getRect(find.byKey(const ValueKey('customize-preview'))).height,
        150);
  });

  testWidgets('shows header, targets, suggestion, reset and apply',
      (tester) async {
    await tester.pumpWidget(panelApp(onFolder: (_) async {}));
    expect(find.text('Folder, top bar & dock'), findsOneWidget);
    expect(find.text('Folders'), findsOneWidget);
    expect(find.text('Top bar'), findsOneWidget);
    expect(find.text('Dock'), findsOneWidget);
    expect(find.text('From wallpaper'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
  });

  testWidgets(
      'new controls have full-size hit targets and tab precedes preview',
      (tester) async {
    tester.view.physicalSize = const Size(480, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(panelApp(width: 480, onFolder: (_) async {}));
    for (final key in ['tab-folders', 'tab-topbar', 'tab-dock']) {
      expect(tester.getSize(find.byKey(ValueKey(key))).height,
          greaterThanOrEqualTo(42));
      expect(tester.getSize(find.byKey(ValueKey(key))).width,
          greaterThanOrEqualTo(40));
    }
    for (final key in ['selected-hex', 'reset', 'customize-apply']) {
      expect(tester.getSize(find.byKey(ValueKey(key))).height,
          greaterThanOrEqualTo(40));
    }
    for (final finder in [
      find.byKey(const ValueKey('tab-dock')),
      find.byKey(const ValueKey('customize-preview'))
    ]) {
      expect(finder, findsOneWidget);
    }
    expect(
        tester.getRect(find.byKey(const ValueKey('tab-folders'))).bottom,
        lessThanOrEqualTo(tester
            .getRect(find.byKey(const ValueKey('customize-preview')))
            .top));
    expect(find.byIcon(Icons.folder_outlined), findsNothing);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('swatches are square, flush and at least 40px at width 480',
      (tester) async {
    tester.view.physicalSize = const Size(480, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(panelApp(
      width: 480,
      palette: const [
        Color(0xFF111111),
        Color(0xFF222222),
        Color(0xFF333333),
        Color(0xFF444444),
        Color(0xFF555555),
        Color(0xFF666666),
        Color(0xFF777777),
      ],
    ));
    final keys = [
      'swatch-#111111',
      'swatch-#222222',
      'swatch-#333333',
      'swatch-#444444',
      'swatch-#555555',
      'swatch-#666666',
      'swatch-#777777',
      'custom-color'
    ];
    for (final key in keys) {
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(rect.height, 44);
      expect(rect.width, greaterThanOrEqualTo(40));
    }
    for (var index = 0; index < keys.length - 1; index++) {
      final first = tester.getRect(find.byKey(ValueKey(keys[index])));
      final next = tester.getRect(find.byKey(ValueKey(keys[index + 1])));
      if ((first.top - next.top).abs() < .5) {
        expect((first.right - next.left).abs(), lessThanOrEqualTo(.5));
      }
    }
    final decorations = tester.widgetList<DecoratedBox>(find.descendant(
        of: find.byType(CustomizePanel), matching: find.byType(DecoratedBox)));
    expect(
        decorations.any((widget) =>
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle),
        isFalse);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('narrow swatches use two rows with large cells', (tester) async {
    tester.view.physicalSize = const Size(300, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(panelApp(width: 300));
    final first = tester.getRect(find.byKey(const ValueKey('swatch-#111111')));
    final fourth = tester.getRect(find.byKey(const ValueKey('swatch-#444444')));
    final fifth = tester.getRect(find.byKey(const ValueKey('custom-color')));
    expect((first.top - fourth.top).abs(), lessThan(.5));
    expect(fifth.top, greaterThan(first.top));
    expect(fifth.width, greaterThanOrEqualTo(40));
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  test('customize panel and shared tokens have no LayoutBuilder', () {
    expect(File('lib/widgets/customize_panel.dart').readAsStringSync(),
        isNot(contains('LayoutBuilder')));
    expect(File('lib/widgets/nebula_tokens.dart').readAsStringSync(),
        isNot(contains('LayoutBuilder')));
  });

  testWidgets('swatch updates only selected target working colour',
      (tester) async {
    await tester.pumpWidget(panelApp(onFolder: (_) async {}));
    final foldersBefore = find
        .descendant(
            of: find.byKey(const ValueKey('selected-hex')),
            matching: find.byType(Text))
        .evaluate()
        .single
        .widget as Text;
    final original = foldersBefore.data;
    await tester.tap(find.text('Top bar'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('swatch-#111111')));
    await tester.pump();
    expect(find.text('#111111'), findsOneWidget);
    await tester.tap(find.text('Folders'));
    await tester.pump();
    expect(find.text(original!), findsOneWidget);
  });

  testWidgets('folder apply calls callback with working hex', (tester) async {
    String? applied;
    await tester.pumpWidget(panelApp(onFolder: (hex) async => applied = hex));
    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(applied, matches(RegExp(r'^#[0-9A-F]{6}$')));
  });

  testWidgets('top bar and dock apply are disabled with explanation',
      (tester) async {
    await tester.pumpWidget(panelApp());
    for (final target in ['Top bar', 'Dock']) {
      await tester.tap(find.text(target));
      await tester.pump();
      expect(
        find.byTooltip('Top bar and dock apply is coming in the next update'),
        findsOneWidget,
      );
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    }
  });

  testWidgets('disabled folder apply shows reason', (tester) async {
    await tester.pumpWidget(
        panelApp(folderApplyEnabled: false, reason: 'No folder theme'));
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    expect(find.byTooltip('No folder theme'), findsOneWidget);
  });

  testWidgets('applying disables Apply and retains its label slot',
      (tester) async {
    await tester.pumpWidget(panelApp(applying: true, onFolder: (_) async {}));
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    expect(find.text('Applying...'), findsOneWidget);
  });

  testWidgets('custom colour dialog validates and applies a valid colour',
      (tester) async {
    await tester.pumpWidget(panelApp(onFolder: (_) async {}));
    await tester.tap(find.byKey(const ValueKey('custom-color')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('Enter a valid #RRGGBB colour'), findsOneWidget);
    expect(find.text('Use colour'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '#112233');
    await tester.pump();
    await tester.tap(find.text('Use colour'));
    await tester.pumpAndSettle();
    expect(find.text('#112233'), findsOneWidget);
  });

  testWidgets('empty wallpaper palette suggestion is a no-op', (tester) async {
    await tester.pumpWidget(panelApp(palette: [], onFolder: (_) async {}));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('From wallpaper'));
    await tester.pump();
    expect(find.text('#F98E65'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow across narrow widths and heights',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final width in [520.0, 400.0, 340.0, 300.0]) {
      for (final height in [700.0, 420.0]) {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(panelApp(width: width, onFolder: (_) async {}));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'width=$width height=$height');
      }
    }
  });
}
