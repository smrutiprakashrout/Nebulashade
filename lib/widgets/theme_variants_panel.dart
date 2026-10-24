import 'package:flutter/material.dart';
import 'package:nebulashade/services/theme_detector.dart';
import 'package:nebulashade/services/theme_downloader.dart';
import 'package:nebulashade/widgets/nebula_tokens.dart';

class ThemeVariantsPanel extends StatelessWidget {
  final ThemeCheckResult? dark;
  final ThemeCheckResult? light;
  final bool checking;
  final String? activeVariantId;
  final bool switching;
  final bool canSwitch;
  final bool downloadConfigured;
  final DownloadPhase downloadPhase;
  final double? downloadProgress;
  final List<Color> darkPalette;
  final Color baseColor;
  final VoidCallback onRefresh;
  final void Function(String variantId) onSelectVariant;
  final VoidCallback onDownloadLight;
  final VoidCallback? onRestoreDark;
  final Widget footer;

  const ThemeVariantsPanel({
    super.key,
    required this.dark,
    required this.light,
    required this.checking,
    required this.activeVariantId,
    required this.switching,
    required this.canSwitch,
    required this.downloadConfigured,
    required this.downloadPhase,
    required this.downloadProgress,
    required this.darkPalette,
    required this.baseColor,
    required this.onRefresh,
    required this.onSelectVariant,
    required this.onDownloadLight,
    required this.onRestoreDark,
    required this.footer,
  });

  static const _fallbackDark = [
    Color(0xFF26201D),
    Color(0xFF362C29),
    Color(0xFFE14509),
    Color(0xFFF98E65),
    Color(0xFFFDE2D8),
  ];
  static const _lightPalette = [
    Color(0xFFFDF6E3),
    Color(0xFFE6E2CC),
    Color(0xFFA7C080),
    Color(0xFFDBBC7F),
    Color(0xFFE69875),
  ];

  List<Color> get _darkSwatches =>
      darkPalette.length >= 5 ? darkPalette.take(5).toList() : _fallbackDark;

  @override
  Widget build(BuildContext context) {
    final surface = NebulaSurface(baseColor);
    final viewport = MediaQuery.sizeOf(context);
    // ThemeScreen places this panel inside IntrinsicHeight; a descendant
    // LayoutBuilder cannot provide intrinsic dimensions there.
    final previewHeight = (viewport.height * 0.18).clamp(96.0, 128.0);
    final panelWidth = (viewport.width - 48) / 2;
    final content = _buildContent(surface, previewHeight, panelWidth);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: surface.card,
          borderRadius: BorderRadius.circular(NebulaRadius.panel)),
      child: viewport.height < 560
          ? SingleChildScrollView(child: content)
          : content,
    );
  }

  Widget _buildContent(
      NebulaSurface surface, double previewHeight, double width) {
    final canInteract = canSwitch && !switching && activeVariantId != null;
    final disabledReason = switching
        ? 'Switching in progress'
        : !canSwitch
            ? 'Install both Everforest variants first'
            : activeVariantId == null
                ? 'Current theme is not an Everforest variant'
                : '';
    final stackCards = width < 360;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 14, height: 14),
            Expanded(
              child: Center(
                child: _buildSwitcher(surface, canInteract, disabledReason),
              ),
            ),
            SizedBox(
              width: 14,
              height: 14,
              child: switching
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildPreview(previewHeight, surface, canInteract, disabledReason),
        const SizedBox(height: 10),
        if (stackCards) ...[
          _buildVariantCard(isLight: false, surface: surface),
          const SizedBox(height: 8),
          _buildVariantCard(isLight: true, surface: surface),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _buildVariantCard(isLight: false, surface: surface)),
              const SizedBox(width: 10),
              Expanded(
                  child: _buildVariantCard(isLight: true, surface: surface)),
            ],
          ),
        if (activeVariantId == 'light' &&
            light?.status != ThemeStatus.complete &&
            onRestoreDark != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: NebulaSize.control,
              child: TextButton.icon(
                onPressed:
                    dark?.status == ThemeStatus.complete ? onRestoreDark : null,
                style: TextButton.styleFrom(
                  foregroundColor: onColor(surface.cream),
                  backgroundColor: surface.control,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(NebulaRadius.control),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('Restore Dark'),
              ),
            ),
          ),
        ],
        if (!canSwitch) ...[
          const SizedBox(height: 8),
          Text(
            'Install both variants to switch modes.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62), fontSize: 12),
          ),
        ],
        const SizedBox(height: 14),
        footer,
      ],
    );
  }

  Widget _buildHeader() => Row(
        children: [
          const Expanded(
            child: Text(
              'Theme variants',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
          ),
          SizedBox(
            width: 40,
            height: 40,
            child: checking
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    key: const ValueKey('refresh'),
                    tooltip: 'Refresh theme status',
                    onPressed: onRefresh,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.refresh,
                        color: Colors.white, size: 18),
                  ),
          ),
        ],
      );

  Widget _buildSwitcher(
      NebulaSurface surface, bool enabled, String disabledReason) {
    final isLight = activeVariantId == 'light';
    final row = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.dark_mode_outlined,
          size: 16, color: isLight ? surface.muted : Colors.white),
      const SizedBox(width: 4),
      Text('Dark',
          style: TextStyle(
              color: isLight ? surface.muted : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500)),
      const SizedBox(width: 8),
      NebulaModeSwitch(
          key: const ValueKey('mode-switch'),
          isLight: isLight,
          enabled: enabled,
          surface: surface,
          onChanged: (value) => onSelectVariant(value ? 'light' : 'dark')),
      const SizedBox(width: 8),
      Text('Light',
          style: TextStyle(
              color: !enabled
                  ? const Color(0xFFC4B8A9)
                  : isLight
                      ? Colors.white
                      : surface.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500)),
      const SizedBox(width: 4),
      Icon(
          light?.status == ThemeStatus.complete
              ? Icons.light_mode_outlined
              : Icons.lock_outline,
          size: 16,
          color: !enabled
              ? const Color(0xFFC4B8A9)
              : isLight
                  ? Colors.white
                  : surface.muted),
    ]);
    return enabled ? row : Tooltip(message: disabledReason, child: row);
  }

  Widget _buildPreview(double height, NebulaSurface surface, bool enabled,
      String disabledReason) {
    final darkSwatches = _darkSwatches;
    final lightReady = light?.status == ThemeStatus.complete;
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NebulaRadius.control),
        child: Stack(
          children: [
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                      message: enabled ? '' : disabledReason,
                      child: GestureDetector(
                          key: const ValueKey('preview-dark'),
                          onTap: enabled ? () => onSelectVariant('dark') : null,
                          child: _MiniWindow(
                            background: const Color(0xFF26201D),
                            bars: [
                              darkSwatches[2],
                              darkSwatches[3],
                              darkSwatches[4]
                            ],
                            dotColors: const [
                              Color(0xFFE67E80),
                              Color(0xFFDBBC7F),
                              Color(0xFFA7C080)
                            ],
                          ))),
                ),
                Expanded(
                  child: Tooltip(
                      message: enabled ? '' : disabledReason,
                      child: GestureDetector(
                          key: const ValueKey('preview-light'),
                          onTap:
                              enabled ? () => onSelectVariant('light') : null,
                          child: _MiniWindow(
                            background: lightReady
                                ? const Color(0xFFFDF6E3)
                                : const Color(0xFFE6DDCF),
                            bars: lightReady
                                ? const [
                                    Color(0xFFA7C080),
                                    Color(0xFFDBBC7F),
                                    Color(0xFFE69875)
                                  ]
                                : const [
                                    Color(0xFFCFC4B2),
                                    Color(0xFFD8CDBB),
                                    Color(0xFFCFC4B2)
                                  ],
                            dotColors: lightReady
                                ? const [
                                    Color(0xFFE67E80),
                                    Color(0xFFDBBC7F),
                                    Color(0xFFA7C080)
                                  ]
                                : const [
                                    Color(0xFFCFC4B2),
                                    Color(0xFFD8CDBB),
                                    Color(0xFFCFC4B2)
                                  ],
                          ))),
                ),
              ],
            ),
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    color: surface.cream,
                    borderRadius: BorderRadius.circular(6)),
                child: Icon(Icons.swap_horiz,
                    size: 18, color: onColor(surface.cream)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(child: Container(width: 2, color: surface.cream)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantCard(
      {required bool isLight, required NebulaSurface surface}) {
    final result = isLight ? light : dark;
    final status = result?.status;
    final isSelected =
        isLight ? activeVariantId == 'light' : activeVariantId != 'light';
    final missing = isLight &&
        (status == ThemeStatus.missing || status == ThemeStatus.incomplete);
    final palette = isLight ? _lightPalette : _darkSwatches;
    final background = surface.control;
    final content = Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            result?.variant.label ??
                (isLight ? 'Everforest Light' : 'Everforest Dark'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          _buildStatusPill(
              surface: surface,
              isLight: isLight,
              status: status,
              missingFiles: result?.missingFiles ?? const []),
          const SizedBox(height: 7),
          _buildPaletteStrip(palette),
          if (isLight && missing) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              key: const ValueKey('download-light'),
              height: NebulaSize.control,
              child: Tooltip(
                message: !downloadConfigured
                    ? 'Download source not configured yet'
                    : '',
                child: ElevatedButton.icon(
                  onPressed: !downloadConfigured ||
                          checking ||
                          downloadPhase != DownloadPhase.idle
                      ? null
                      : onDownloadLight,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: surface.cream,
                    foregroundColor: onColor(surface.cream),
                    disabledBackgroundColor:
                        surface.cream.withValues(alpha: 0.55),
                    disabledForegroundColor:
                        onColor(surface.cream).withValues(alpha: 0.55),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(NebulaRadius.control)),
                  ),
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: Text(_downloadLabel,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(NebulaRadius.card),
        border: Border.all(
          color: isSelected ? surface.cream : Colors.transparent,
          width: 2,
        ),
      ),
      child: CustomPaint(
        foregroundPainter: missing
            ? const DashedRectPainter(Color(0xFFA89A8A), radius: 8)
            : null,
        child: content,
      ),
    );
  }

  String get _downloadLabel => switch (downloadPhase) {
        DownloadPhase.downloading => downloadProgress == null
            ? 'Downloading...'
            : 'Downloading ${(downloadProgress! * 100).round().clamp(0, 100)}%',
        DownloadPhase.verifying => 'Verifying...',
        DownloadPhase.extracting => 'Extracting...',
        DownloadPhase.installing || DownloadPhase.done => 'Installing...',
        DownloadPhase.failed || DownloadPhase.idle => 'Download',
      };

  Widget _buildStatusPill({
    required NebulaSurface surface,
    required bool isLight,
    required ThemeStatus? status,
    required List<String> missingFiles,
  }) {
    final active =
        isLight ? activeVariantId == 'light' : activeVariantId != 'light';
    if (status == null && checking) {
      return _pill('Checking...', surface.control, surface.muted);
    }
    switch (status ?? ThemeStatus.missing) {
      case ThemeStatus.complete:
        if (active) {
          return _pill(
            'Active',
            surface.tagOkBg,
            surface.tagOkFg,
            icon: Icons.check_circle_outline,
          );
        }
        return _pill(
          'Installed',
          surface.control,
          surface.muted,
          icon: Icons.check_circle_outline,
          iconColor: surface.tagOkFg,
        );
      case ThemeStatus.missing:
        return _pill('Not installed', surface.tagNoBg, surface.tagNoFg,
            icon: Icons.close);
      case ThemeStatus.incomplete:
        return Tooltip(
          message: 'Missing: ${missingFiles.join(', ')}',
          child: _pill(
            'Incomplete',
            surface.tagWarnBg,
            surface.tagWarnFg,
            icon: Icons.warning_amber_rounded,
          ),
        );
    }
  }

  Widget _pill(
    String label,
    Color background,
    Color foreground, {
    IconData? icon,
    Color? iconColor,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(NebulaRadius.chip)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: iconColor ?? foreground),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: foreground, fontSize: 12)),
            ),
          ],
        ),
      );

  Widget _buildPaletteStrip(List<Color> colors) => Row(
        children: [
          for (var i = 0; i < 5; i++) ...[
            Expanded(
              child: Container(
                height: 22,
                decoration: BoxDecoration(color: colors[i]),
              ),
            ),
          ],
        ],
      );
}

class _MiniWindow extends StatelessWidget {
  final Color background;
  final List<Color> bars;
  final List<Color> dotColors;

  const _MiniWindow({
    required this.background,
    required this.bars,
    required this.dotColors,
  });

  @override
  Widget build(BuildContext context) => Container(
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final color in dotColors) ...[
                  Container(
                      width: 7,
                      height: 7,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                ],
              ],
            ),
            const Spacer(),
            for (var i = 0; i < bars.length; i++) ...[
              FractionallySizedBox(
                widthFactor: i == 0
                    ? 0.82
                    : i == 1
                        ? 0.62
                        : 0.72,
                child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                        color: bars[i],
                        borderRadius: BorderRadius.circular(2))),
              ),
              if (i < bars.length - 1) const SizedBox(height: 5),
            ],
          ],
        ),
      );
}
