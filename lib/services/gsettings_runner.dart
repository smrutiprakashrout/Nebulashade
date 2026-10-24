import 'dart:async';
import 'dart:io';

const String gtkInterfaceSchema = 'org.gnome.desktop.interface';
const String gtkThemeKey = 'gtk-theme';
const String colorSchemeKey = 'color-scheme';
const String userThemeSchema = 'org.gnome.shell.extensions.user-theme';
const String userThemeNameKey = 'name';

class GsResult {
  final bool ok;
  final String value;
  final String? error;

  const GsResult({required this.ok, this.value = '', this.error});
}

abstract class GsettingsRunner {
  Future<GsResult> get(String schema, String key);
  Future<GsResult> set(String schema, String key, String value);
}

class ProcessGsettingsRunner implements GsettingsRunner {
  static const _timeout = Duration(seconds: 5);

  @override
  Future<GsResult> get(String schema, String key) async {
    try {
      final result = await Process.run(
        'gsettings',
        ['get', schema, key],
      ).timeout(_timeout);
      final value = _cleanValue(result.stdout.toString());
      if (result.exitCode != 0) {
        return GsResult(
          ok: false,
          value: value,
          error: result.stderr.toString().trim(),
        );
      }
      return GsResult(ok: true, value: value);
    } catch (error) {
      return GsResult(ok: false, error: error.toString());
    }
  }

  @override
  Future<GsResult> set(String schema, String key, String value) async {
    try {
      final result = await Process.run(
        'gsettings',
        ['set', schema, key, _formatValue(schema, key, value)],
      ).timeout(_timeout);
      if (result.exitCode != 0) {
        return GsResult(
          ok: false,
          error: result.stderr.toString().trim(),
        );
      }
      return GsResult(ok: true, value: _cleanValue(result.stdout.toString()));
    } catch (error) {
      return GsResult(ok: false, error: error.toString());
    }
  }

  String _formatValue(String schema, String key, String value) {
    if ((schema == gtkInterfaceSchema && key == gtkThemeKey) ||
        (schema == userThemeSchema && key == userThemeNameKey)) {
      final escaped = value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
      return "'$escaped'";
    }
    return value;
  }

  String _cleanValue(String value) {
    var cleaned = value.trim();
    if (cleaned.length >= 2 &&
        cleaned.startsWith("'") &&
        cleaned.endsWith("'")) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    return cleaned.trim();
  }
}
