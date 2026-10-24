import 'dart:io';

import 'package:nebulashade/config/theme_variants.dart';

enum ThemeStatus { complete, incomplete, missing }

class ThemeCheckResult {
  final ThemeVariant variant;
  final ThemeStatus status;
  final String? foundPath;
  final List<String> missingFiles;
  final String? error;

  const ThemeCheckResult({
    required this.variant,
    required this.status,
    this.foundPath,
    this.missingFiles = const [],
    this.error,
  });
}

class ThemeDetector {
  final List<String> searchDirs;
  final List<String> requiredFiles;

  ThemeDetector({List<String>? searchDirs, List<String>? requiredFiles})
      : searchDirs = searchDirs ?? ThemeVariants.searchDirs(),
        requiredFiles = requiredFiles ?? ThemeVariants.requiredFiles;

  Future<ThemeCheckResult> check(ThemeVariant variant) async {
    String? bestPath;
    List<String>? bestMissingFiles;

    try {
      for (final searchDir in searchDirs) {
        final candidatePath =
            '$searchDir${Platform.pathSeparator}${variant.folderName}';
        if (!await Directory(candidatePath).exists()) continue;

        bestPath ??= candidatePath;
        bestMissingFiles ??= List<String>.from(requiredFiles);
        final missingFiles = <String>[];
        for (final requiredFile in requiredFiles) {
          final filePath =
              '$candidatePath${Platform.pathSeparator}${requiredFile.replaceAll('/', Platform.pathSeparator)}';
          if (!await File(filePath).exists()) {
            missingFiles.add(requiredFile);
          }
        }

        if (missingFiles.isEmpty) {
          return ThemeCheckResult(
            variant: variant,
            status: ThemeStatus.complete,
            foundPath: candidatePath,
          );
        }

        if (missingFiles.length < bestMissingFiles.length) {
          bestPath = candidatePath;
          bestMissingFiles = missingFiles;
        }
      }

      if (bestPath != null) {
        return ThemeCheckResult(
          variant: variant,
          status: ThemeStatus.incomplete,
          foundPath: bestPath,
          missingFiles: bestMissingFiles!,
        );
      }

      return ThemeCheckResult(
        variant: variant,
        status: ThemeStatus.missing,
      );
    } catch (error) {
      return ThemeCheckResult(
        variant: variant,
        status: bestPath == null ? ThemeStatus.missing : ThemeStatus.incomplete,
        foundPath: bestPath,
        missingFiles: bestMissingFiles ?? const [],
        error: error.toString(),
      );
    }
  }

  Future<Map<String, ThemeCheckResult>> checkAll() async {
    final dark = await check(ThemeVariants.dark);
    final light = await check(ThemeVariants.light);
    return {'dark': dark, 'light': light};
  }

  bool canSwitch(Map<String, ThemeCheckResult> results) =>
      results['dark']?.status == ThemeStatus.complete &&
      results['light']?.status == ThemeStatus.complete;
}
