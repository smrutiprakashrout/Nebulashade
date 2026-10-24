import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:nebulashade/config/theme_variants.dart';

enum DownloadPhase {
  idle,
  downloading,
  verifying,
  extracting,
  installing,
  done,
  failed,
}

class InstallResult {
  final bool ok;
  final String? message;
  final String? installedPath;

  const InstallResult({
    required this.ok,
    this.message,
    this.installedPath,
  });
}

class ThemeDownloader {
  static const _connectTimeout = Duration(seconds: 15);
  static const _totalTimeout = Duration(minutes: 5);

  Future<InstallResult> downloadAndInstall(
    ThemeVariant variant, {
    required String url,
    String sha256 = '',
    void Function(DownloadPhase, double? progress)? onProgress,
    String? themesDir,
  }) async {
    final client = http.Client();
    Directory? downloadDir;
    try {
      if (!_isAllowedVariant(variant, themesDir)) {
        throw const _InstallException(
            'Only the Everforest Light theme can be installed.');
      }

      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const _InstallException('The download URL must use HTTPS.');
      }

      _report(onProgress, DownloadPhase.downloading, 0);
      downloadDir = await Directory.systemTemp.createTemp('nebulashade_dl_');
      final zipFile =
          File('${downloadDir.path}${Platform.pathSeparator}theme.zip');
      final request = http.Request('GET', uri);
      final response = await client.send(request).timeout(_connectTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw _InstallException(
          'Download failed with HTTP ${response.statusCode}.',
        );
      }
      if (response.request?.url.scheme != 'https') {
        throw const _InstallException(
            'The download redirected to a non-HTTPS URL.');
      }

      final contentLength = int.tryParse(
        response.headers[HttpHeaders.contentLengthHeader] ?? '',
      );
      if (contentLength != null &&
          contentLength > ThemeVariants.maxDownloadBytes) {
        throw const _InstallException('The download exceeds the 200 MB limit.');
      }

      final transfer = _writeResponse(
        response,
        zipFile,
        contentLength,
        onProgress,
      );
      await transfer.timeout(
        _totalTimeout,
        onTimeout: () async {
          client.close();
          try {
            await transfer;
          } catch (_) {
            // Closing the client aborts the pending response stream.
          }
          throw const _InstallException('The download timed out.');
        },
      );

      if (sha256.isNotEmpty) {
        _report(onProgress, DownloadPhase.verifying, null);
        final digest = await sha256Hash(zipFile);
        if (digest.toLowerCase() != sha256.toLowerCase()) {
          throw const _InstallException(
              'The downloaded file failed SHA-256 verification.');
        }
      }

      final result = await installFromZip(
        zipFile.path,
        variant,
        themesDir: themesDir,
        onProgress: onProgress,
      );
      if (!result.ok) _report(onProgress, DownloadPhase.failed, null);
      return result;
    } catch (error) {
      _report(onProgress, DownloadPhase.failed, null);
      return InstallResult(ok: false, message: _friendlyMessage(error));
    } finally {
      client.close();
    }
  }

  Future<void> _writeResponse(
    http.StreamedResponse response,
    File zipFile,
    int? contentLength,
    void Function(DownloadPhase, double?)? onProgress,
  ) async {
    var received = 0;
    final sink = zipFile.openWrite();
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > ThemeVariants.maxDownloadBytes) {
          throw const _InstallException(
              'The download exceeds the 200 MB limit.');
        }
        sink.add(chunk);
        _report(
          onProgress,
          DownloadPhase.downloading,
          contentLength != null && contentLength > 0
              ? received / contentLength
              : null,
        );
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<InstallResult> installFromZip(
    String zipPath,
    ThemeVariant variant, {
    String? themesDir,
    void Function(DownloadPhase, double?)? onProgress,
  }) async {
    Directory? staging;
    String? targetPath;
    String? backupPath;
    var backupMoved = false;
    var stagingCreated = false;

    try {
      if (!_isAllowedVariant(variant, themesDir)) {
        throw const _InstallException(
            'Only the Everforest Light theme can be installed.');
      }
      final resolvedThemesDir = await _resolveThemesDir(themesDir);
      await Directory(resolvedThemesDir).create(recursive: true);

      final stamp = DateTime.now().microsecondsSinceEpoch;
      var stagingSuffix = 0;
      do {
        final suffix = stagingSuffix == 0 ? '' : '-$stagingSuffix';
        staging = Directory(
          '$resolvedThemesDir${Platform.pathSeparator}.nebulashade-staging-$stamp$suffix',
        );
        stagingSuffix++;
      } while (await staging.exists());
      await staging.create();
      stagingCreated = true;

      _report(onProgress, DownloadPhase.extracting, null);
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        throw const _InstallException(
            'The downloaded archive could not be found.');
      }
      final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
      await _extractArchive(archive, staging);

      final themeRoot = await _locateThemeRoot(staging, variant);
      if (themeRoot == null) {
        throw const _InstallException(
          'Archive does not contain the expected theme folder',
        );
      }

      final missingFiles = await _missingFiles(themeRoot);
      if (missingFiles.isNotEmpty) {
        throw _InstallException(
          'Theme is incomplete. Missing: ${missingFiles.join(', ')}',
        );
      }

      _report(onProgress, DownloadPhase.installing, null);
      targetPath =
          '$resolvedThemesDir${Platform.pathSeparator}${variant.folderName}';
      if (await _isCompleteTheme(Directory(targetPath))) {
        _report(onProgress, DownloadPhase.done, 1);
        return InstallResult(
          ok: true,
          message: 'Already installed',
          installedPath: targetPath,
        );
      }

      if (await _entityExists(targetPath)) {
        final backupStamp = DateTime.now().microsecondsSinceEpoch;
        var backupSuffix = 0;
        do {
          final suffix = backupSuffix == 0 ? '' : '-$backupSuffix';
          backupPath = '$targetPath.bak-$backupStamp$suffix';
          backupSuffix++;
        } while (await _entityExists(backupPath));
        await _renameEntity(targetPath, backupPath);
        backupMoved = true;
      }

      try {
        await themeRoot.rename(targetPath);
      } catch (_) {
        if (backupMoved &&
            backupPath != null &&
            !await _entityExists(targetPath)) {
          await _renameEntity(backupPath, targetPath);
          backupMoved = false;
        }
        rethrow;
      }

      _report(onProgress, DownloadPhase.done, 1);
      return InstallResult(
        ok: true,
        message: 'Everforest Light installed',
        installedPath: targetPath,
      );
    } catch (error) {
      if (backupMoved && backupPath != null && targetPath != null) {
        try {
          if (!await _entityExists(targetPath)) {
            await _renameEntity(backupPath, targetPath);
          }
        } catch (_) {
          // Keep the backup intact if restoration is not possible.
        }
      }
      _report(onProgress, DownloadPhase.failed, null);
      return InstallResult(ok: false, message: _friendlyMessage(error));
    } finally {
      final stage = staging;
      if (stage != null && stagingCreated) {
        try {
          if (await stage.exists()) await stage.delete(recursive: true);
        } catch (_) {
          // Staging was created by this call; cleanup failures do not escape.
        }
      }
    }
  }

  Future<String> sha256Hash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<void> _extractArchive(Archive archive, Directory staging) async {
    final stagingPath = staging.absolute.path;
    for (final entry in archive) {
      final normalizedName = _normalizeEntryName(entry.name);
      if (normalizedName == null || _isIgnoredEntry(normalizedName)) continue;
      if (entry.isSymbolicLink) continue;

      final relativePath =
          normalizedName.replaceAll('/', Platform.pathSeparator);
      final outputPath = '$stagingPath${Platform.pathSeparator}$relativePath';
      final outputAbsolute = FileSystemEntity.isDirectorySync(stagingPath)
          ? Directory(outputPath).absolute.path
          : File(outputPath).absolute.path;
      if (!outputAbsolute.startsWith('$stagingPath${Platform.pathSeparator}')) {
        throw const _InstallException('Archive contains an unsafe file path.');
      }

      if (entry.isDirectory) {
        await Directory(outputPath).create(recursive: true);
      } else {
        final file = File(outputPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.content, flush: true);
      }
    }
  }

  String? _normalizeEntryName(String name) {
    final slashName = name.replaceAll('\\', '/');
    if (slashName.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(slashName)) {
      throw const _InstallException('Archive contains an absolute file path.');
    }
    final segments = slashName.split('/');
    if (segments.contains('..')) {
      throw const _InstallException('Archive contains an unsafe file path.');
    }
    final normalized = segments
        .where((segment) => segment.isNotEmpty && segment != '.')
        .join('/');
    return normalized.isEmpty ? null : normalized;
  }

  bool _isIgnoredEntry(String name) {
    final segments = name.split('/');
    return segments.first == '__MACOSX' || segments.last == '.DS_Store';
  }

  Future<Directory?> _locateThemeRoot(
    Directory staging,
    ThemeVariant variant,
  ) async {
    final nested = Directory(
      '${staging.path}${Platform.pathSeparator}${variant.folderName}',
    );
    if (await nested.exists()) return nested;

    if (await File('${staging.path}${Platform.pathSeparator}index.theme')
        .exists()) {
      return staging;
    }
    return null;
  }

  Future<List<String>> _missingFiles(Directory root) async {
    final missing = <String>[];
    for (final requiredFile in ThemeVariants.requiredFiles) {
      final filePath =
          '${root.path}${Platform.pathSeparator}${requiredFile.replaceAll('/', Platform.pathSeparator)}';
      if (!await File(filePath).exists()) missing.add(requiredFile);
    }
    return missing;
  }

  Future<bool> _isCompleteTheme(Directory target) async =>
      await target.exists() && (await _missingFiles(target)).isEmpty;

  Future<bool> _entityExists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  Future<void> _renameEntity(String from, String to) async {
    final type = await FileSystemEntity.type(from, followLinks: false);
    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(from).rename(to);
      case FileSystemEntityType.file:
        await File(from).rename(to);
      case FileSystemEntityType.link:
        await Link(from).rename(to);
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw const _InstallException(
            'The existing theme path is not a regular file or directory.');
      case FileSystemEntityType.notFound:
        throw const _InstallException('The existing theme folder disappeared.');
    }
  }

  bool _isAllowedVariant(ThemeVariant variant, String? themesDir) =>
      variant.id == ThemeVariants.light.id &&
      variant.folderName != ThemeVariants.dark.folderName &&
      variant.folderName.isNotEmpty &&
      variant.folderName != '.' &&
      variant.folderName != '..' &&
      !variant.folderName.contains('/') &&
      !variant.folderName.contains('\\') &&
      (themesDir != null ||
          variant.folderName == ThemeVariants.light.folderName);

  Future<String> _resolveThemesDir(String? themesDir) async {
    if (themesDir != null) {
      final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final provided = await Directory(themesDir).resolveSymbolicLinks();
      if (!provided.startsWith('$tempRoot${Platform.pathSeparator}')) {
        throw const _InstallException(
          'A custom themes directory must be inside the system temp directory.',
        );
      }
      return provided;
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw const _InstallException('Could not locate your home directory.');
    }
    final themesPath = '$home${Platform.pathSeparator}.themes';
    if (await FileSystemEntity.type(themesPath, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const _InstallException(
        'The .themes directory is a symbolic link; refusing to install outside it.',
      );
    }
    return themesPath;
  }

  void _report(
    void Function(DownloadPhase, double?)? callback,
    DownloadPhase phase,
    double? progress,
  ) {
    try {
      callback?.call(phase, progress);
    } catch (_) {
      // A UI progress callback must not interrupt installation or cleanup.
    }
  }

  String _friendlyMessage(Object error) => error is _InstallException
      ? error.message
      : 'Could not install the theme: $error';
}

class _InstallException implements Exception {
  final String message;

  const _InstallException(this.message);

  @override
  String toString() => message;
}
