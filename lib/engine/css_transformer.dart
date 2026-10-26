import 'package:flutter/material.dart';
import 'package:nebulashade/components/apply_theme.dart' show applyButtonColors;
import 'package:nebulashade/engine/engine_palette.dart';
import 'package:nebulashade/services/widget_palette.dart';

class CssTransformResult {
  const CssTransformResult({
    required this.css,
    required this.recoloured,
    required this.semanticTokensChanged,
    required this.notes,
    this.roleRewritten = 0,
    this.tokenMapped = 0,
    this.accentContextRecolored = 0,
    this.paletteNamesChanged = 0,
    this.rolesAppended = 0,
  });

  final String css;
  final int recoloured;
  final int semanticTokensChanged;
  final List<String> notes;
  final int roleRewritten;
  final int tokenMapped;
  final int accentContextRecolored;
  final int paletteNamesChanged;
  final int rolesAppended;
}

const List<String> kAccentContextPatterns = [
  r'\.suggested-action',
  r'\.selection-mode',
  r'(^|[\s>,])selection\b',
  r':selected',
  r':checked',
  r'progressbar\s+progress',
  r'scale\s+(highlight|trough\s+highlight)',
  r'switch:checked',
  r'check:checked',
  r'radio:checked',
];

// Colour literals are scanned only inside declaration value spans. The CSS
// structural pass skips comments, strings and URL payloads and retains selector
// text verbatim. Classification is ported from widget_palette.dart:71-104.
final RegExp _define = RegExp(r'^\s*@define-color\s+([\w-]+)\s+(.+?)\s*$');
final RegExp _semanticName = RegExp(
  r'^(warning|error|success|destructive)(_bg|_fg|_standalone)?(_color)?$',
);
final RegExp _hex = RegExp(r'^#([0-9a-fA-F]+)$');
final RegExp _rgb = RegExp(
  r'^(rgba?)\((\s*)(\d+)(\s*,\s*)(\d+)(\s*,\s*)(\d+)((?:\s*,\s*[\d.]+)?)(\s*)\)$',
  caseSensitive: false,
);
final RegExp _hsl = RegExp(
  r'^(hsla?)\((\s*)(-?[\d.]+)((?:deg)?)(\s*[, ]\s*)([\d.]+)%([\s]*[, ]\s*)([\d.]+)%((?:\s*[,/]\s*[\d.]+%?)?)(\s*)\)$',
  caseSensitive: false,
);

CssTransformResult transformCss(String css, EnginePalette p,
    {required String fileKind, bool appendMissingRoles = false}) {
  if (!const {'gtk3', 'gtk4', 'shell', 'osd'}.contains(fileKind)) {
    throw ArgumentError.value(fileKind, 'fileKind');
  }
  final notes = <String>[];
  final spans = _declarationSpans(css);
  final claims = <String, _SemanticBinding>{};
  final conflicts = <String>{};
  for (final span in spans.where((s) => s.defineName != null)) {
    final name = span.defineName!;
    final named = _semanticName.firstMatch(name);
    if (named == null) continue;
    final token =
        _parseLiteral(css.substring(span.valueStart, span.valueEnd).trim());
    if (token == null) continue;
    final binding = _binding(named.group(1)!, named.group(2));
    final key = _rgbKey(token.color);
    final old = claims[key];
    if (old != null && (old.role != binding.role || old.tone != binding.tone)) {
      conflicts.add(key);
    } else {
      claims[key] = binding;
    }
  }
  for (final key in conflicts) {
    claims.remove(key);
    notes.add('ambiguous semantic RGB left unchanged: $key');
  }

  final replacements = <_Replacement>[];
  var recoloured = 0, semanticChanged = 0, tokenMapped = 0;
  var roleChanged = 0;
  var accentChanged = 0, paletteChanged = 0;
  for (final span in spans) {
    final define = span.defineName;
    if (define != null) {
      final semantic = _semanticName.firstMatch(define);
      final paletteName = _paletteName.firstMatch(define);
      if (semantic != null) {
        final tone = _binding(semantic.group(1)!, semantic.group(2));
        final replacement = _hexColor(_toneFor(p, tone));
        if (css
                .substring(span.valueStart, span.valueEnd)
                .trim()
                .toLowerCase() !=
            replacement.toLowerCase()) {
          replacements
              .add(_Replacement(span.valueStart, span.valueEnd, replacement));
          semanticChanged++;
        }
        continue;
      }
      if (paletteName != null && _canonicalPalette.containsKey(define)) {
        final color = define.startsWith('blue_')
            ? _accentRamp(_canonicalPalette[define]!, p.accent)
            : _canonicalPalette[define]!;
        final replacement = _hexColor(color);
        if (css
                .substring(span.valueStart, span.valueEnd)
                .trim()
                .toLowerCase() !=
            replacement.toLowerCase()) {
          replacements
              .add(_Replacement(span.valueStart, span.valueEnd, replacement));
          paletteChanged++;
        }
        continue;
      }
    }
    for (final tokenSpan
        in _literalSpans(css, span.valueStart, span.valueEnd)) {
      final literal = css.substring(tokenSpan.start, tokenSpan.end);
      final repaired = _repairMalformedHex(literal);
      final parsed = _parseLiteral(repaired);
      if (parsed == null) {
        if (repaired != literal)
          replacements
              .add(_Replacement(tokenSpan.start, tokenSpan.end, repaired));
        continue;
      }
      final rgb = parsed.color.value & 0xffffff;
      if ({0xe69875, 0xa7c080, 0xe67e80}.contains(rgb)) continue;
      final key = _rgbKey(parsed.color);
      final binding = claims[key];
      if (binding != null) {
        final mapped = _toneFor(p, binding);
        final value = parsed.format(mapped);
        if (value != literal) {
          replacements.add(_Replacement(tokenSpan.start, tokenSpan.end, value));
          recoloured++;
          tokenMapped++;
        }
        continue;
      }
      final semanticContext = _isSemanticSelector(span.selector);
      if (semanticContext) {
        notes.add(
            'semantic-context literal left unchanged: ${span.selector} $literal');
        continue;
      }
      if (_accentContext(span.selector) && parsed.color.alpha != 0) {
        final hsv = HSVColor.fromColor(parsed.color);
        if (hsv.saturation >= .03 && !_isWindowControl(span.selector)) {
          final shifted = HSVColor.fromAHSV(hsv.alpha,
                  HSVColor.fromColor(p.accent).hue, hsv.saturation, hsv.value)
              .toColor();
          final value = parsed.format(shifted);
          if (value != literal) {
            replacements
                .add(_Replacement(tokenSpan.start, tokenSpan.end, value));
            recoloured++;
            accentChanged++;
          }
          continue;
        }
      }
      final roleMapped = _rewriteLiteral(literal, p, notes, '');
      final mapped =
          roleMapped == literal && repaired != literal ? repaired : roleMapped;
      if (mapped != literal) {
        replacements.add(_Replacement(tokenSpan.start, tokenSpan.end, mapped));
        recoloured++;
        roleChanged++;
      }
    }
  }
  var rewritten = _applyReplacements(css, replacements);
  var rolesAppended = 0;
  if (appendMissingRoles && fileKind == 'gtk4') {
    final managed = _managedRoles(rewritten, p);
    rewritten = managed.css;
    rolesAppended = managed.count;
  }
  // Public selector patcher only: never invoke its process-spawning apply flow.
  final withButtons = applyButtonColors(
    rewritten,
    minimize: '#e69875',
    maximize: '#a7c080',
    close: '#e67e80',
  );
  return CssTransformResult(
    css: withButtons,
    recoloured: recoloured,
    semanticTokensChanged: semanticChanged,
    notes: List.unmodifiable(notes),
    roleRewritten: roleChanged,
    tokenMapped: tokenMapped,
    accentContextRecolored: accentChanged,
    paletteNamesChanged: paletteChanged,
    rolesAppended: rolesAppended,
  );
}

class CssColorOccurrence {
  const CssColorOccurrence(
      {required this.value,
      required this.selector,
      required this.property,
      required this.line});
  final String value, selector, property;
  final int line;
}

List<CssColorOccurrence> scanCssColorOccurrences(String css) {
  final result = <CssColorOccurrence>[];
  var line = 1, lineCursor = 0;
  for (final span in _declarationSpans(css)) {
    for (final token in _literalSpans(css, span.valueStart, span.valueEnd)) {
      while (lineCursor < token.start) {
        if (css.codeUnitAt(lineCursor) == 10) line++;
        lineCursor++;
      }
      result.add(CssColorOccurrence(
          value: css.substring(token.start, token.end),
          selector: span.defineName ?? span.selector,
          property: span.property,
          line: line));
    }
  }
  return result;
}

class _Span {
  const _Span(this.valueStart, this.valueEnd, this.selector, this.property,
      {this.defineName});
  final int valueStart, valueEnd;
  final String selector, property;
  final String? defineName;
  String get value => '';
}

class _Range {
  const _Range(this.start, this.end);
  final int start, end;
}

class _Replacement {
  const _Replacement(this.start, this.end, this.value);
  final int start, end;
  final String value;
}

class _SemanticBinding {
  const _SemanticBinding(this.role, this.tone);
  final String role, tone;
}

List<_Span> _declarationSpans(String css) {
  final spans = <_Span>[];
  final selectors = <String>[];
  var i = 0, segmentStart = 0, parens = 0, quote = 0, comment = false;
  var property = '';
  var selector = '';
  void capture(int end) {
    var start = segmentStart;
    while (start < end && css[start].trim().isEmpty) start++;
    var colon = -1;
    for (var j = start; j < end; j++) {
      if (css[j] == ':') {
        colon = j;
        break;
      }
    }
    final segment = css.substring(start, end);
    final define = _define.firstMatch(segment);
    if (define != null) {
      final name = define.group(1)!;
      final valueAt = start + segment.indexOf(define.group(2)!);
      spans.add(_Span(
          valueAt, valueAt + define.group(2)!.length, '', '@define-color',
          defineName: name));
    } else if (colon >= 0 &&
        selectors.isNotEmpty &&
        !selector.trimLeft().startsWith('@')) {
      property = css.substring(start, colon).trim();
      final valueStart = colon + 1;
      spans.add(_Span(valueStart, end, selector, property));
    }
  }

  while (i < css.length) {
    final c = css.codeUnitAt(i);
    if (comment) {
      if (c == 42 && i + 1 < css.length && css.codeUnitAt(i + 1) == 47) {
        comment = false;
        i += 2;
        continue;
      }
      i++;
      continue;
    }
    if (quote != 0) {
      if (c == 92) {
        i += 2;
        continue;
      }
      if (c == quote) quote = 0;
      i++;
      continue;
    }
    if (c == 47 && i + 1 < css.length && css.codeUnitAt(i + 1) == 42) {
      comment = true;
      i += 2;
      continue;
    }
    if (c == 34 || c == 39) {
      quote = c;
      i++;
      continue;
    }
    if (c == 40) {
      parens++;
      i++;
      continue;
    }
    if (c == 41) {
      if (parens > 0) parens--;
      i++;
      continue;
    }
    if (parens == 0 && (c == 59 || c == 123 || c == 125)) {
      capture(i);
      if (c == 123) {
        final prelude = css.substring(segmentStart, i).trim();
        selectors.add(prelude.startsWith('@') ? '' : prelude);
        selector = selectors.where((s) => s.isNotEmpty).join(' ');
      } else if (c == 125 && selectors.isNotEmpty) {
        selectors.removeLast();
        selector = selectors.where((s) => s.isNotEmpty).join(' ');
      }
      segmentStart = i + 1;
    }
    i++;
  }
  capture(css.length);
  return spans;
}

List<_Range> _literalSpans(String css, int start, int end) {
  final out = <_Range>[];
  var i = start;
  while (i < end) {
    final c = css.codeUnitAt(i);
    if (c == 47 && i + 1 < end && css.codeUnitAt(i + 1) == 42) {
      final close = css.indexOf('*/', i + 2);
      i = close < 0 || close >= end ? end : close + 2;
      continue;
    }
    if (c == 34 || c == 39) {
      final q = c;
      i++;
      while (i < end) {
        if (css.codeUnitAt(i) == 92) {
          i += 2;
          continue;
        }
        if (css.codeUnitAt(i++) == q) break;
      }
      continue;
    }
    if (_startsIgnoreCase(css, i, 'url(')) {
      var d = 1;
      i += 4;
      while (i < end && d > 0) {
        if (css.codeUnitAt(i) == 40) d++;
        if (css.codeUnitAt(i) == 41) d--;
        i++;
      }
      continue;
    }
    if (c == 35) {
      var j = i + 1;
      while (j < end && _isHex(css.codeUnitAt(j))) j++;
      if (j - i >= 4) {
        out.add(_Range(i, j));
        i = j;
        continue;
      }
    }
    if (_isFunctionStart(css, i, end)) {
      var open = i;
      while (open < end && css.codeUnitAt(open) != 40) open++;
      var depth = 0, j = open;
      for (; j < end; j++) {
        final unit = css.codeUnitAt(j);
        if (unit == 40) depth++;
        if (unit == 41) {
          depth--;
          if (depth == 0) {
            j++;
            break;
          }
        }
      }
      if (depth == 0) {
        out.add(_Range(i, j));
        i = j;
        continue;
      }
    }
    i++;
  }
  return out;
}

bool _isHex(int c) =>
    (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
bool _startsIgnoreCase(String s, int at, String token) {
  if (at + token.length > s.length) return false;
  for (var i = 0; i < token.length; i++) {
    var c = s.codeUnitAt(at + i);
    if (c >= 65 && c <= 90) c += 32;
    if (c != token.codeUnitAt(i)) return false;
  }
  return true;
}

bool _isFunctionStart(String s, int at, int end) =>
    _startsIgnoreCase(s, at, 'rgba(') ||
    _startsIgnoreCase(s, at, 'rgb(') ||
    _startsIgnoreCase(s, at, 'hsla(') ||
    _startsIgnoreCase(s, at, 'hsl(');
final RegExp _paletteName =
    RegExp(r'^(blue|green|yellow|orange|red|purple|brown|light|dark)_[1-5]$');
const _canonicalPalette = <String, Color>{
  'blue_1': Color(0xff99c1f1),
  'blue_2': Color(0xff62a0ea),
  'blue_3': Color(0xff3584e4),
  'blue_4': Color(0xff1c71d8),
  'blue_5': Color(0xff1a5fb4),
  'green_1': Color(0xff8ff0a4),
  'green_2': Color(0xff57e389),
  'green_3': Color(0xff33d17a),
  'green_4': Color(0xff2ec27e),
  'green_5': Color(0xff26a269),
  'yellow_1': Color(0xfff9f06b),
  'yellow_2': Color(0xfff8e45c),
  'yellow_3': Color(0xfff6d32d),
  'yellow_4': Color(0xfff5c211),
  'yellow_5': Color(0xffe5a50a),
  'orange_1': Color(0xffffbe6f),
  'orange_2': Color(0xffffa348),
  'orange_3': Color(0xffff7800),
  'orange_4': Color(0xffe66100),
  'orange_5': Color(0xffc64600),
  'red_1': Color(0xfff66151),
  'red_2': Color(0xffed333b),
  'red_3': Color(0xffe01b24),
  'red_4': Color(0xffc01c28),
  'red_5': Color(0xffa51d2d),
  'purple_1': Color(0xffdc8add),
  'purple_2': Color(0xffc061cb),
  'purple_3': Color(0xff9141ac),
  'purple_4': Color(0xff813d9c),
  'purple_5': Color(0xff613583),
  'brown_1': Color(0xffcdab8f),
  'brown_2': Color(0xffb5835a),
  'brown_3': Color(0xff986a44),
  'brown_4': Color(0xff865e3c),
  'brown_5': Color(0xff63452c),
  'light_1': Color(0xffffffff),
  'light_2': Color(0xfff6f5f4),
  'light_3': Color(0xffdeddda),
  'light_4': Color(0xffc0bfbc),
  'light_5': Color(0xff9a9996),
  'dark_1': Color(0xff77767b),
  'dark_2': Color(0xff5e5c64),
  'dark_3': Color(0xff3d3846),
  'dark_4': Color(0xff241f31),
  'dark_5': Color(0xff000000),
};

bool isCanonicalPaletteValue(String name, String value, EnginePalette palette) {
  final canonical = _canonicalPalette[name];
  final parsed = _parseLiteral(value.trim());
  if (canonical == null || parsed == null) return false;
  final expected = name.startsWith('blue_')
      ? _accentRamp(canonical, palette.accent)
      : canonical;
  return (parsed.color.value & 0xffffff) == (expected.value & 0xffffff);
}

Color _accentRamp(Color canonical, Color accent) {
  final c = HSVColor.fromColor(canonical), a = HSVColor.fromColor(accent);
  return HSVColor.fromAHSV(1, a.hue, c.saturation, c.value).toColor();
}

String _rgbKey(Color c) => _hexColor(c).toLowerCase();
_SemanticBinding _binding(String role, String? suffix) => _SemanticBinding(
    role,
    suffix == '_bg'
        ? 'bg'
        : suffix == '_fg'
            ? 'onBg'
            : 'fg');
Color _toneFor(EnginePalette p, _SemanticBinding b) {
  final tone = _tone(p, b.role);
  return switch (b.tone) { 'bg' => tone.bg, 'onBg' => tone.onBg, _ => tone.fg };
}

bool _isSemanticSelector(String selector) =>
    RegExp(r'\.error|\.warning|\.success|\.destructive-action|\.destructive')
        .hasMatch(selector);
bool _isWindowControl(String selector) =>
    RegExp(r'windowcontrols|titlebutton').hasMatch(selector);
bool _accentContext(String selector) => selector.split(',').any((part) =>
    kAccentContextPatterns.any((pattern) => RegExp(pattern).hasMatch(part)));
String _applyReplacements(String source, List<_Replacement> replacements) {
  if (replacements.isEmpty) return source;
  replacements.sort((a, b) => a.start.compareTo(b.start));
  final out = StringBuffer();
  var cursor = 0;
  for (final r in replacements) {
    if (r.start < cursor) continue;
    out.write(source.substring(cursor, r.start));
    out.write(r.value);
    cursor = r.end;
  }
  out.write(source.substring(cursor));
  return out.toString();
}

class _ManagedResult {
  const _ManagedResult(this.css, this.count);
  final String css;
  final int count;
}

_ManagedResult _managedRoles(String css, EnginePalette p) {
  const begin = '/* NEBULA-ENGINE-ROLES BEGIN */';
  const end = '/* NEBULA-ENGINE-ROLES END */';
  final blockStart = css.indexOf(begin), blockEnd = css.indexOf(end);
  final hadManagedBlock = blockStart >= 0 && blockEnd >= blockStart;
  var base = css;
  if (hadManagedBlock) {
    var removeEnd = blockEnd + end.length;
    if (removeEnd < css.length && css.codeUnitAt(removeEnd) == 10) removeEnd++;
    base = css.replaceRange(blockStart, removeEnd, '');
  }
  final defined = <String>{
    for (final m in RegExp(r'@define-color\s+([\w-]+)').allMatches(base))
      m.group(1)!
  };
  final windowFg = RegExp(r'@define-color\s+window_fg_color\s+([^;]+);')
          .firstMatch(base)
          ?.group(1)
          ?.trim() ??
      '#ffeff3';
  final specs = <String, String>{
    'headerbar_darker_shade_color': 'rgba(0, 0, 0, 0.90)',
    'popover_shade_color': 'rgba(0, 0, 0, 0.25)',
    'sidebar_bg_color': _hexColor(p.sidebar),
    'sidebar_backdrop_color': _hexColor(p.sidebar),
    'sidebar_fg_color': windowFg,
    'sidebar_shade_color': 'rgba(0, 0, 0, 0.25)',
    'secondary_sidebar_bg_color': _hexColor(_lighten(p.window, .02)),
    'secondary_sidebar_fg_color': windowFg,
    'thumbnail_bg_color': _hexColor(_lighten(p.view, .06)),
    'thumbnail_fg_color': windowFg,
  };
  final missing = specs.keys.where((name) => !defined.contains(name)).toList();
  final managedContent = [
    for (final name in missing) '@define-color $name ${specs[name]};'
  ].join('\n');
  if (missing.isEmpty) return _ManagedResult(base, 0);
  final block = '$begin\n$managedContent\n$end';
  final prefix = base.endsWith('\n') ? base : '$base\n';
  return _ManagedResult(
      '$prefix$block\n', hadManagedBlock ? 0 : missing.length);
}

Color _lighten(Color color, double amount) {
  final h = HSLColor.fromColor(color);
  return h.withLightness((h.lightness + amount).clamp(0.0, 1.0)).toColor();
}

SemanticTone _tone(EnginePalette p, String name) => switch (name) {
      'warning' => p.warning,
      'success' => p.success,
      'destructive' => p.destructive,
      _ => p.error,
    };

String _rewriteLiteral(String literal, EnginePalette palette,
    List<String> notes, String selector) {
  if (RegExp(r'\.error|\.warning|\.success|\.destructive-action')
      .hasMatch(selector)) {
    notes.add('semantic-context literal left unchanged: $selector $literal');
    return literal;
  }
  final repaired = _repairMalformedHex(literal);
  final parsed = _parseLiteral(repaired);
  if (parsed == null) return repaired;
  final rgb = parsed.color.value & 0xFFFFFF;
  if ({0xe69875, 0xa7c080, 0xe67e80}.contains(rgb)) return literal;
  final classes = WidgetPalette.classifyRgb(rgb);
  if (classes.length != 1) return literal;
  final klass = classes.single;
  final mapped = WidgetPalette.mapClassifiedRgb(rgb, klass, _legacy(palette));
  if (mapped == rgb) return literal;
  return parsed.format(Color(0xFF000000 | mapped));
}

WidgetPalette _legacy(EnginePalette p) => WidgetPalette.fromColors(
      [p.base.value & 0xFFFFFF],
      1,
    );

class _Parsed {
  const _Parsed(this.color, this.format);
  final Color color;
  final String Function(Color) format;
}

_Parsed? _parseLiteral(String token) {
  final hm = _hex.firstMatch(token);
  if (hm != null) {
    final body = hm.group(1)!;
    if (body.length != 3 &&
        body.length != 4 &&
        body.length != 6 &&
        body.length != 8) return null;
    final rgbBody = body.length <= 4
        ? body.substring(0, 3).split('').map((c) => '$c$c').join()
        : body.substring(0, 6);
    final color = Color(0xFF000000 | int.parse(rgbBody, radix: 16));
    return _Parsed(color, (mapped) {
      final mappedHex =
          mapped.value.toRadixString(16).padLeft(8, '0').substring(2);
      if (body.length == 3) {
        final digits = [mapped.red, mapped.green, mapped.blue]
            .map((c) => (c / 17).round().toRadixString(16))
            .join();
        return '#${body == body.toUpperCase() ? digits.toUpperCase() : digits}';
      }
      final rgb = body.length == 4
          ? mappedHex.substring(0, 6) + body.substring(3)
          : mappedHex.substring(0, 6);
      final value =
          body.length == 8 ? rgb.substring(0, 6) + body.substring(6) : rgb;
      return '#${body == body.toUpperCase() ? value.toUpperCase() : value}';
    });
  }
  final rm = _rgb.firstMatch(token);
  if (rm != null) {
    final c = Color.fromARGB(255, int.parse(rm.group(3)!),
        int.parse(rm.group(5)!), int.parse(rm.group(7)!));
    return _Parsed(
        c,
        (mapped) =>
            '${rm.group(1)}(${rm.group(2)}${mapped.red}${rm.group(4)}${mapped.green}${rm.group(6)}${mapped.blue}${rm.group(8)}${rm.group(9)})');
  }
  final sm = _hsl.firstMatch(token);
  if (sm != null) {
    final h = double.parse(sm.group(3)!);
    final s = double.parse(sm.group(6)!) / 100;
    final l = double.parse(sm.group(8)!) / 100;
    final color = HSLColor.fromAHSL(1, h, s, l).toColor();
    return _Parsed(color, (mapped) {
      final hsl = HSLColor.fromColor(mapped);
      return '${sm.group(1)}(${sm.group(2)}${hsl.hue.toStringAsFixed(1)}${sm.group(4)}${sm.group(5)}${(hsl.saturation * 100).toStringAsFixed(1)}%${sm.group(7)}${(hsl.lightness * 100).toStringAsFixed(1)}%${sm.group(9)}${sm.group(10)})';
    });
  }
  return null;
}

String _repairMalformedHex(String token) {
  final match = _hex.firstMatch(token);
  if (match == null || match.group(1)!.length <= 8) return token;
  final body = match.group(1)!;
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(body)) return token;
  return '#${body.substring(0, 6)}';
}

String _hexColor(Color c) =>
    '#${c.red.toRadixString(16).padLeft(2, '0')}${c.green.toRadixString(16).padLeft(2, '0')}${c.blue.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
