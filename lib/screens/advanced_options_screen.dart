import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nebulashade/constants/colours.dart';
import 'package:nebulashade/screens/ColorPaletteScreen.dart';
import 'package:nebulashade/screens/color_edit_screen.dart';
import 'package:nebulashade/screens/widget_sync_screen.dart';

class AdvancedOptionsScreen extends StatelessWidget {
  final String? wallpaperPath;
  final List<Color> dominantColors;

  const AdvancedOptionsScreen({
    super.key,
    required this.wallpaperPath,
    required this.dominantColors,
  });

  @override
  Widget build(BuildContext context) {
    final hasWallpaper = wallpaperPath != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Advanced Options'),
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildOptionTile(
              enabled: hasWallpaper,
              icon: Icons.palette,
              title: 'Color Palette',
              subtitle: hasWallpaper
                  ? 'View colors extracted from your wallpaper'
                  : 'Select a wallpaper on the Theme screen first',
              onTap: hasWallpaper
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ColorPaletteScreen(
                            imageProvider: FileImage(File(wallpaperPath!)),
                            dominantColors: dominantColors,
                          ),
                        ),
                      );
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            _buildOptionTile(
              enabled: true,
              icon: Icons.widgets_outlined,
              title: 'Sync with Widgets',
              subtitle: 'Match GTK, Shell, folders, and widget colours',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WidgetSyncScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _buildOptionTile(
              enabled: true,
              icon: Icons.code,
              title: 'CSS Color Editor',
              subtitle: 'View and edit colors from your CSS files',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CssColorListScreen(extractedColors: dominantColors),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required bool enabled,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: AppColors.lighten(AppColors.background, 0.2),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
