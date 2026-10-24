import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/widgets/nebula_tokens.dart';

void main() {
  test('lightness clamps and keeps hue', () {
    final source = HSLColor.fromAHSL(1, 210, .6, .5);
    final result = HSLColor.fromColor(shiftLightness(source.toColor(), .1));
    expect(result.lightness, closeTo(.6, .01));
    expect((result.hue - source.hue).abs(), lessThan(.1));
    expect(
        HSLColor.fromColor(shiftLightness(source.toColor(), 2)).lightness, 1);
    expect(
        HSLColor.fromColor(shiftLightness(source.toColor(), -2)).lightness, 0);
  });

  test('surface and accent derivation', () {
    const base = Color(0xFF362C29);
    expect(NebulaSurface(base).card, shiftLightness(base, .2));
    expect(HSLColor.fromColor(NebulaSurface(base).tabActive).lightness,
        lessThan(HSLColor.fromColor(base).lightness));
    const fallback = Color(0xFFF98E65);
    expect(NebulaTokens.accentFrom([]), fallback);
    expect(
        NebulaTokens.accentFrom(const [Color(0xFF111111), Color(0xFF777777)]),
        fallback);
    const lowSat = Color(0xFF8A817E);
    const saturated = Color(0xFFE05020);
    expect(NebulaTokens.accentFrom([lowSat, saturated]), saturated);
  });

  test('onColor selects readable foreground', () {
    expect(onColor(Colors.white), const Color(0xFF2F2418));
    expect(onColor(Colors.black), Colors.white);
  });

  testWidgets('tab bar has large tappable tabs and selected shadow',
      (tester) async {
    var selected = -1;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 360,
                    child: NebulaTabBar(
                      labels: const ['Folders', 'Top bar', 'Dock'],
                      selectedIndex: 0,
                      keys: const [
                        ValueKey('tab-0'),
                        ValueKey('tab-1'),
                        ValueKey('tab-2')
                      ],
                      onChanged: (value) => selected = value,
                      surface: NebulaSurface(const Color(0xFF362C29)),
                    ))))));
    expect(find.text('Folders'), findsOneWidget);
    final first = tester.getRect(find.byKey(const ValueKey('tab-0')));
    expect(first.height, greaterThanOrEqualTo(42));
    final decoration = tester
        .widget<AnimatedContainer>(find.byType(AnimatedContainer).first)
        .decoration as BoxDecoration;
    expect(decoration.boxShadow, isNotEmpty);
    await tester.tap(find.text('Dock'));
    expect(selected, 2);
  });

  testWidgets('mode switch positions and toggles only when enabled',
      (tester) async {
    var result = <bool>[];
    Widget app(bool light, bool enabled) => MaterialApp(
            home: Scaffold(
                body: Center(
                    child: NebulaModeSwitch(
          isLight: light,
          enabled: enabled,
          surface: NebulaSurface(const Color(0xFF362C29)),
          onChanged: result.add,
        ))));
    await tester.pumpWidget(app(false, true));
    final darkThumb = tester.getRect(find.byType(Icon));
    await tester.tap(find.descendant(
        of: find.byType(NebulaModeSwitch), matching: find.byType(InkWell)));
    expect(result, [true]);
    await tester.pumpWidget(app(true, true));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Icon)).left, greaterThan(darkThumb.left));
    await tester.pumpWidget(app(true, false));
    await tester.tap(find.descendant(
        of: find.byType(NebulaModeSwitch), matching: find.byType(InkWell)));
    expect(result, [true]);
  });
}
