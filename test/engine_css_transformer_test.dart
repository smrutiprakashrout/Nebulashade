import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/engine/css_transformer.dart';
import 'package:nebulashade/engine/engine_palette.dart';

void main() {
  final fixtures = <String, String>{
    'gtk3': '''/* keep #df0065 */
@import "palette.css";
@define-color theme_bg_color #30241f;
@define-color warning_color #df0065;
.window { color: #30241f; background: #30241f; }
.base { color: #29201c; }
.popover { color: rgba(35, 25, 21, 0.5); }
.accent { color: #cc662eaa; }
.hsl { color: hsl(23deg, 58%, 40%); }
.nested.suggested-action { color: mix(shade(alpha(#ab4936, 0.7), 0.8), #ddcbaa, 0.3); }
.sidebar button:checked { background-color: #ab4936; }
colorswatch#ddcbaa-color-button, #abc, #fff { color: #ddcbaa; }
.warning { color: #df0065; }
.warning .unmapped { color: #11aa33; }
windowcontrols button.minimize:not(.suggested-action):not(.destructive-action) { background-color: #010203; }
button.maximize.titlebutton:not(.suggested-action):not(.destructive-action) { background-color: #010203; }
button.close.titlebutton:not(.suggested-action):not(.destructive-action) { background-color: #010203; }
.uri { background: url(data:image/svg+xml,%23df0065); }
.bad { color: #123456789; }
''',
    'gtk4':
        '@define-color error_bg_color #f852ca;\n.item { background:#30241f; color:#cc662e; }\n',
    'shell':
        '@define-color success_standalone_color #a1014b;\n.button { color: rgba(163, 79, 46, .7); }\n',
    'osd': '.panel { background:#30241f; }\n',
  };
  const bases = [
    Color(0xffcea14f),
    Color(0xff4f7ace),
    Color(0xff5fae6b),
    Color(0xff824fc1),
    Color(0xff08090a)
  ];

  test('all format, preservation, semantic and structural guarantees', () {
    for (final entry in fixtures.entries) {
      for (final base in bases) {
        final p = EnginePalette.fromBase(base);
        final result = transformCss(entry.value, p, fileKind: entry.key);
        final second = transformCss(result.css, p, fileKind: entry.key);
        expect(second.css, result.css, reason: '${entry.key} idempotence');
        expect(count(result.css, '{'), count(result.css, '}'));
        expect(count(result.css, '('), count(result.css, ')'));
        expect(count(result.css, '\n'), count(entry.value, '\n'));
        expect(count(result.css, '@define-color'),
            count(entry.value, '@define-color'));
        expect(RegExp(r'NaN|null|Infinity').hasMatch(result.css), isFalse);
        final a = transformCss(entry.value, EnginePalette.fromBase(bases.first),
                fileKind: entry.key)
            .css;
        final chained =
            transformCss(a, EnginePalette.fromBase(base), fileKind: entry.key)
                .css;
        final direct = transformCss(entry.value, p, fileKind: entry.key).css;
        expect(chained, direct, reason: '${entry.key} base independence');
      }
    }
  });

  test('preserves comments, URL, semantic selector and window controls', () {
    final css = fixtures['gtk3']!;
    final result = transformCss(css, EnginePalette.fromBase(bases.first),
        fileKind: 'gtk3');
    expect(result.css, contains('/* keep #df0065 */'));
    expect(result.css, contains('url(data:image/svg+xml,%23df0065)'));
    expect(result.css, contains('colorswatch#ddcbaa-color-button, #abc, #fff'));
    expect(result.css, contains('.nested.suggested-action'));
    expect(result.css, contains('.sidebar button:checked'));
    expect(
        result.css,
        contains(
            '.warning { color: ${hex(EnginePalette.fromBase(bases.first).warning.fg).toLowerCase()}; }'));
    expect(
        result.notes,
        contains(predicate<String>((s) => s.contains(
            'semantic-context literal left unchanged: .warning .unmapped #11aa33'))));
    expect(
        result.css,
        contains(
            'windowcontrols button.minimize:not(.suggested-action):not(.destructive-action) { background-color: #e69875; }'));
    expect(
        result.css,
        contains(
            'button.maximize.titlebutton:not(.suggested-action):not(.destructive-action) { background-color: #a7c080; }'));
    expect(
        result.css,
        contains(
            'button.close.titlebutton:not(.suggested-action):not(.destructive-action) { background-color: #e67e80; }'));
    expect(result.css, contains('#123456'));
  });

  test('semantic definitions use same palette values for all kinds', () {
    final p = EnginePalette.fromBase(bases.first);
    final outputs = fixtures.entries
        .map((e) => transformCss(e.value, p, fileKind: e.key).css)
        .toList();
    final warning =
        '#${p.warning.fg.red.toRadixString(16).padLeft(2, '0')}${p.warning.fg.green.toRadixString(16).padLeft(2, '0')}${p.warning.fg.blue.toRadixString(16).padLeft(2, '0')}'
            .toUpperCase();
    expect(outputs[0], contains('@define-color warning_color $warning;'));
    expect(outputs[1],
        contains('@define-color error_bg_color ${hex(p.error.bg)};'));
    expect(
        outputs[2],
        contains(
            '@define-color success_standalone_color ${hex(p.success.fg)};'));
    expect(
        transformCss('@define-color warning_color #df0065;', p,
                fileKind: 'gtk3')
            .css,
        transformCss('@define-color warning_color #df0065;', p,
                fileKind: 'shell')
            .css);
  });

  test('selector, prelude, string, comment and URL hashes stay untouched', () {
    const css = '''
colorswatch#ddcbaa-color-button, #abc { color: #ddcbaa; content: "#fff"; background: url(data:image/svg+xml,%23abc); }
@keyframes #ddcbaa { 0% { color: #ddcbaa; } 100% { color: #abc; } }
/* #ddcbaa */
''';
    final output =
        transformCss(css, EnginePalette.fromBase(bases[1]), fileKind: 'gtk3')
            .css;
    expect(output, contains('colorswatch#ddcbaa-color-button, #abc'));
    expect(output, contains('@keyframes #ddcbaa'));
    expect(output, contains('content: "#fff"'));
    expect(output, contains('url(data:image/svg+xml,%23abc)'));
    expect(output, contains('/* #ddcbaa */'));
    expect(output, isNot(contains('color: #ddcbaa')));
  });

  test('accent contexts preserve value and palette names use canonical values',
      () {
    const css = '''
@define-color blue_3 #ff0000;
@define-color green_2 #ff0000;
.suggested-action { background-color: #ab4936; }
''';
    final p = EnginePalette.fromBase(bases[0]);
    final output = transformCss(css, p, fileKind: 'gtk3').css;
    final accent = HSVColor.fromColor(p.accent);
    final shifted = RegExp(r'background-color:\s*(#[0-9a-fA-F]{6})')
        .firstMatch(output)!
        .group(1)!;
    final hsv = HSVColor.fromColor(
        Color(int.parse('ff${shifted.substring(1)}', radix: 16)));
    expect((hsv.hue - accent.hue).abs(), lessThan(2));
    expect(hsv.saturation,
        closeTo(HSVColor.fromColor(const Color(0xffab4936)).saturation, .02));
    expect(output, contains('@define-color green_2 #57E389;'));
    expect(output, contains('@define-color blue_3'));
  });

  test('missing GTK4 roles use one replaceable managed block', () {
    final p = EnginePalette.fromBase(bases.first);
    final first = transformCss('@define-color window_fg_color #ffeeee;\n', p,
        fileKind: 'gtk4', appendMissingRoles: true);
    final second =
        transformCss(first.css, p, fileKind: 'gtk4', appendMissingRoles: true);
    expect(first.rolesAppended, 10);
    expect(second.css, first.css);
    expect(
        RegExp('NEBULA-ENGINE-ROLES BEGIN').allMatches(second.css).length, 1);
    expect(
        second.css,
        contains(
            '@define-color headerbar_darker_shade_color rgba(0, 0, 0, 0.90);'));
  });
}

int count(String s, String token) => token == '\n'
    ? '\n'.allMatches(s).length
    : token == '@define-color'
        ? RegExp(r'@define-color').allMatches(s).length
        : token.allMatches(s).length;

String hex(Color c) =>
    '#${c.red.toRadixString(16).padLeft(2, '0')}${c.green.toRadixString(16).padLeft(2, '0')}${c.blue.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
