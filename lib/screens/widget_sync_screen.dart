import 'package:flutter/material.dart';
import 'package:nebulashade/constants/colours.dart';
import 'package:nebulashade/services/folder_colorizer.dart';
import 'package:nebulashade/services/variant_state.dart';
import 'package:nebulashade/services/widget_palette.dart';
import 'package:nebulashade/services/widget_sync_service.dart';

class WidgetSyncScreen extends StatefulWidget {
  const WidgetSyncScreen({super.key});

  @override
  State<WidgetSyncScreen> createState() => _WidgetSyncScreenState();
}

class _WidgetSyncScreenState extends State<WidgetSyncScreen> {
  final _service = WidgetSyncService();
  List<int> _colors = const [];
  Map<String, int> _current = const {};
  int _slot = 2;
  bool _busy = false;
  Map<String, SyncStepResult> _steps = const {};
  String? _notice;
  String? _resultDetails;
  bool get _light => VariantState.activeVariantIdSync() == 'light';
  WidgetPalette? get _palette => _colors.isEmpty || _slot > _colors.length
      ? null
      : WidgetPalette.fromColors(_colors, _slot);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final colors = await WidgetPalette.readColors();
      final slot = await _service.readSlot();
      final current = await _service.readCurrentColors();
      final folderHex = await FolderColorizer().readCurrentHex();
      final colorsWithFolder = Map<String, int>.from(current);
      if (folderHex != null) {
        colorsWithFolder['folder'] =
            int.parse(folderHex.replaceFirst('#', ''), radix: 16);
      }
      if (mounted) {
        setState(() {
          _colors = colors.take(7).toList();
          _slot = slot >= 1 && slot <= _colors.length
              ? slot
              : (_colors.length >= 2 ? 2 : 1);
          _current = colorsWithFolder;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _notice = 'Could not load the widget palette.');
      }
    }
  }

  Future<void> _apply() async {
    final palette = _palette;
    if (_light || palette == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await _service.apply(palette, onProgress: (steps) {
        if (mounted) setState(() => _steps = steps);
      });
      if (mounted) {
        final failed = result.steps.values
            .any((step) => step.status == SyncStepStatus.failed);
        final skipped = result.steps.values.any((step) =>
            step.status == SyncStepStatus.skipped && step.reason != 'Waiting');
        final malformedCount = result.malformed.values
            .fold<int>(0, (sum, values) => sum + values.length);
        final malformedDetails = result.malformed.entries
            .where((entry) => entry.value.isNotEmpty)
            .map((entry) =>
                '${entry.key.split('/').last}: ${entry.value.join(', ')}')
            .join('; ');
        final classTotals = result.classReplacements.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join(' · ');
        final fileTotals = result.perFileClassReplacements.entries.map((entry) {
          final classes = entry.value.entries
              .map((count) => '${count.key}=${count.value}')
              .join(' ');
          return '${entry.key.split('/').last}: $classes';
        }).join('\n');
        final repairs = result.repaired.entries
            .where((entry) => entry.value.isNotEmpty)
            .expand((entry) => entry.value
                .map((value) => '${entry.key.split('/').last}: $value'))
            .join('\n');
        final warningDetails = result.warnings.isEmpty
            ? 'Residual warnings: none'
            : 'Residual warnings:\n${result.warnings.map((warning) => '${warning.file.split('/').last}:${warning.line}: ${warning.value}').join('\n')}';
        final message = failed
            ? 'Sync finished with a failed step.'
            : skipped
                ? 'Sync applied; one or more steps were skipped.'
                : 'Sync applied successfully.';
        setState(() {
          _steps = result.steps;
          _resultDetails = 'Class totals: $classTotals\nPer file:\n$fileTotals';
          final notices = <String>[
            warningDetails,
            if (repairs.isNotEmpty) 'Repaired colours:\n$repairs',
            if (malformedCount > 0)
              'Malformed colours remaining: $malformedDetails',
          ];
          _notice = notices.join('\n');
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.lighten(AppColors.background, 0.2),
          content: Text(message, style: const TextStyle(color: Colors.white)),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: AppColors.lighten(AppColors.background, 0.2),
            content: Text(
                'Sync could not be completed. Check the theme files and try again.',
                style: const TextStyle(color: Colors.white))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_light || _busy) return;
    setState(() => _busy = true);
    try {
      await _service.reset();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: AppColors.lighten(AppColors.background, 0.2),
            content: const Text('Restored the latest sync backup',
                style: TextStyle(color: Colors.white))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: AppColors.lighten(AppColors.background, 0.2),
            content: const Text('Reset could not be completed.',
                style: TextStyle(color: Colors.white))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final available = !_light && palette != null && !_busy;
    final message = _light
        ? 'Widget sync is available only for the dark variant. Switch to the dark variant to enable Apply.'
        : _colors.isEmpty
            ? _notice ??
                'No colors found. Add colors to ~/Nebula/colors.txt and reopen this screen.'
            : null;
    final roleValues = palette == null
        ? const <String, int>{}
        : <String, int>{
            'Window': palette.window,
            'Sidebar': palette.sidebar,
            'Accent': palette.accent,
            'Folder': palette.folder,
          };
    final inSync = roleValues.isNotEmpty &&
        roleValues.entries
            .every((entry) => _current[_roleKey(entry.key)] == entry.value);
    final needsDetails = _steps.values.any((step) =>
            step.status == SyncStepStatus.failed ||
            (step.status == SyncStepStatus.skipped &&
                step.reason != 'Waiting')) ||
        (_notice?.contains('Residual warnings:') == true &&
            !_notice!.contains('Residual warnings: none'));
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        Expanded(
          child: LayoutBuilder(builder: (context, viewport) {
            final contentWidth = (viewport.maxWidth - 48).clamp(0.0, 1200.0);
            final narrow = contentWidth < 760;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Center(
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          IconButton(
                            tooltip: 'Back',
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('Sync with widgets',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w500)),
                          ),
                        ]),
                        const Padding(
                          padding: EdgeInsets.only(left: 56, top: 2),
                          child: Text(
                            'Match your GTK theme, sidebar and folders to the widget colours.',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ),
                        if (message != null) ...[
                          const SizedBox(height: 16),
                          _MessageCard(message: message),
                        ],
                        if (palette != null) ...[
                          const SizedBox(height: 20),
                          _PreviewBanner(palette: palette),
                          const SizedBox(height: 24),
                          if (narrow)
                            Column(children: [
                              _SlotStrip(
                                colors: _colors,
                                slot: _slot,
                                onSelect: (slot) =>
                                    setState(() => _slot = slot),
                                enabled: !_busy,
                                palette: palette,
                              ),
                              const SizedBox(height: 24),
                              _RoleGrid(
                                palette: palette,
                                current: _current,
                                steps: _steps,
                              ),
                            ])
                          else
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 10,
                                    child: _SlotStrip(
                                      colors: _colors,
                                      slot: _slot,
                                      onSelect: (slot) =>
                                          setState(() => _slot = slot),
                                      enabled: !_busy,
                                      palette: palette,
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  Expanded(
                                    flex: 11,
                                    child: _RoleGrid(
                                      palette: palette,
                                      current: _current,
                                      steps: _steps,
                                    ),
                                  ),
                                ]),
                          const SizedBox(height: 16),
                          _DetailsPanel(
                            steps: _steps,
                            notice: _notice,
                            resultDetails: _resultDetails,
                            initiallyExpanded: needsDetails,
                          ),
                        ],
                      ]),
                ),
              ),
            );
          }),
        ),
        _ActionBar(
          palette: palette,
          busy: _busy,
          canApply: available,
          canReset: !_light && !_busy,
          inSync: inSync,
          onApply: _apply,
          onReset: _reset,
          hasPalette: palette != null,
        ),
      ]),
    );
  }

  String _roleKey(String label) => switch (label) {
        'Window' => 'window',
        'Sidebar' => 'base',
        'Accent' => 'accent',
        _ => 'folder',
      };
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.lighten(AppColors.background, .08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE69875)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, color: Color(0xFFE69875), size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: Colors.white70, fontSize: 14))),
        ]),
      );
}

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({required this.palette});
  final WidgetPalette palette;

  Color _c(int value) => Color(0xFF000000 | value);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final height = (constraints.maxWidth * .2).clamp(190.0, 260.0);
          final sidebarWidth = (constraints.maxWidth * .22).clamp(120.0, 200.0);
          final compact = constraints.maxWidth < 640;
          return Container(
            height: height,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _c(palette.popover),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .12)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: _c(palette.window),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .10)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  SizedBox(
                    width: sidebarWidth,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(11)),
                      child: Container(
                        color: _c(palette.sidebar),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(children: [
                                _WindowDot(color: Color(0xFFE67E80)),
                                SizedBox(width: 5),
                                _WindowDot(color: Color(0xFFE69875)),
                                SizedBox(width: 5),
                                _WindowDot(color: Color(0xFFA7C080)),
                              ]),
                              const SizedBox(height: 12),
                              _NavItem('Home',
                                  selected: true, palette: palette),
                              const _NavItem('Documents'),
                              if (!compact) const _NavItem('Downloads'),
                              const _NavItem('Trash'),
                            ]),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: LayoutBuilder(builder: (context, area) {
                        final showToast = area.maxWidth >= 480;
                        return Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Projects',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      for (final label in const [
                                        'Design',
                                        'Photos',
                                        'Music',
                                        'Docs'
                                      ])
                                        Flexible(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.folder_rounded,
                                                  size: compact ? 34 : 44,
                                                  color: _c(palette.accent)),
                                              const SizedBox(height: 2),
                                              Text(label,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 12)),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Row(children: [
                                  _PreviewButton('New folder', palette),
                                  const SizedBox(width: 8),
                                  _PreviewButton('Night light', palette,
                                      pill: true),
                                ]),
                              ],
                            ),
                          ),
                          if (showToast) ...[
                            const SizedBox(width: 12),
                            SizedBox(
                              width: (area.maxWidth * .34).clamp(200.0, 240.0),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _c(palette.popover),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: .12)),
                                ),
                                child: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      _WindowDot(
                                          color: Color(0xFFA7C080), size: 9),
                                      SizedBox(width: 7),
                                      Expanded(
                                        child: Text('Build finished',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500)),
                                      ),
                                    ]),
                                    SizedBox(height: 6),
                                    Text('Matches widgets',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ]);
                      }),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      );
}

class _WindowDot extends StatelessWidget {
  const _WindowDot({required this.color, this.size = 7});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.label, {this.selected = false, this.palette});
  final String label;
  final bool selected;
  final WidgetPalette? palette;
  @override
  Widget build(BuildContext context) {
    final accent =
        palette == null ? Colors.white : Color(0xFF000000 | palette!.accent);
    final window = palette == null
        ? Colors.transparent
        : Color(0xFF000000 | palette!.window);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: selected
            ? Color.alphaBlend(accent.withValues(alpha: .18), window)
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: selected ? accent : Colors.white70,
              fontSize: selected ? 14 : 13,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400)),
    );
  }
}

class _PreviewButton extends StatelessWidget {
  const _PreviewButton(this.label, this.palette, {this.pill = false});
  final String label;
  final WidgetPalette palette;
  final bool pill;
  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Color(0xFF000000 | palette.accent),
          borderRadius: BorderRadius.circular(pill ? 18 : 10),
        ),
        child: Text(label,
            style: TextStyle(
                color: Color(0xFF000000 | palette.window),
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      );
}

class _SlotStrip extends StatelessWidget {
  const _SlotStrip({
    required this.colors,
    required this.slot,
    required this.onSelect,
    required this.enabled,
    required this.palette,
  });
  final List<int> colors;
  final int slot;
  final ValueChanged<int> onSelect;
  final bool enabled;
  final WidgetPalette palette;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Widget accent',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Row(children: [
            for (var i = 0; i < colors.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: 'Slot ${i + 1} · ${WidgetPalette.hex(colors[i])}',
                  child: Semantics(
                    button: true,
                    selected: slot == i + 1,
                    label: 'Slot ${i + 1}, ${WidgetPalette.hex(colors[i])}',
                    child: InkWell(
                      onTap: enabled ? () => onSelect(i + 1) : null,
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 64,
                        padding: EdgeInsets.all(slot == i + 1 ? 3 : 0),
                        decoration: BoxDecoration(
                          color:
                              slot == i + 1 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Color(0xFF000000 | colors[i]),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: slot == i + 1
                              ? const Center(
                                  child: Icon(Icons.check,
                                      color: Colors.white, size: 22))
                              : Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 5),
                                    child: Text('${i + 1}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500)),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: 'Slot $slot',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            TextSpan(
                text: ' · ${WidgetPalette.hex(palette.base)}',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ])),
        ],
      );
}

class _RoleGrid extends StatelessWidget {
  const _RoleGrid(
      {required this.palette, required this.current, required this.steps});
  final WidgetPalette palette;
  final Map<String, int> current;
  final Map<String, SyncStepResult> steps;

  @override
  Widget build(BuildContext context) {
    final roles = <(String, String, int)>[
      ('Window', 'window', palette.window),
      ('Sidebar', 'base', palette.sidebar),
      ('Accent', 'accent', palette.accent),
      ('Folder', 'folder', palette.folder),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('What changes',
          style: TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final role in roles)
              SizedBox(
                width: width,
                child: _RoleCard(
                  label: role.$1,
                  current: current[role.$2],
                  next: role.$3,
                  palette: palette,
                  status: _statusFor(role.$2, steps),
                ),
              ),
          ],
        );
      }),
    ]);
  }

  SyncStepResult? _statusFor(String role, Map<String, SyncStepResult> values) {
    final match = values.entries.where((entry) {
      final key = entry.key.toLowerCase();
      return switch (role) {
        'window' => key.contains('gtk') || key.contains('window'),
        'base' => key.contains('sidebar') || key.contains('shell'),
        'accent' => key.contains('accent') || key.contains('gtk'),
        _ => key.contains('folder'),
      };
    });
    return match.isEmpty ? null : match.last.value;
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.label,
    required this.current,
    required this.next,
    required this.palette,
    required this.status,
  });
  final String label;
  final int? current;
  final int next;
  final WidgetPalette palette;
  final SyncStepResult? status;
  @override
  Widget build(BuildContext context) {
    final fill = AppColors.lighten(AppColors.background, .2);
    final color = Color(0xFF000000 | next);
    final iconColor = switch (status?.status) {
      SyncStepStatus.ok => const Color(0xFFA7C080),
      SyncStepStatus.skipped => const Color(0xFFE69875),
      SyncStepStatus.failed => const Color(0xFFE67E80),
      null => null,
    };
    final statusIcon = switch (status?.status) {
      SyncStepStatus.ok => Icons.check_circle,
      SyncStepStatus.skipped => Icons.warning_amber_rounded,
      SyncStepStatus.failed => Icons.error,
      null => null,
    };
    final folder = label == 'Folder';
    final swatchColor = folder ? Color(0xFF000000 | palette.window) : color;
    return Container(
      height: 64,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: swatchColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: .15)),
          ),
          child: folder
              ? Icon(Icons.folder_rounded,
                  color: Color(0xFF000000 | palette.accent), size: 22)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              Text(WidgetPalette.hex(next),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        if (current != null && current != next)
          Text('was ${WidgetPalette.hex(current!)}',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        if (statusIcon != null) ...[
          const SizedBox(width: 6),
          Icon(statusIcon, color: iconColor, size: 16),
        ],
      ]),
    );
  }
}

class _DetailsPanel extends StatefulWidget {
  const _DetailsPanel({
    required this.steps,
    required this.notice,
    required this.resultDetails,
    required this.initiallyExpanded,
  });
  final Map<String, SyncStepResult> steps;
  final String? notice;
  final String? resultDetails;
  final bool initiallyExpanded;
  @override
  State<_DetailsPanel> createState() => _DetailsPanelState();
}

class _DetailsPanelState extends State<_DetailsPanel> {
  bool? _expanded;
  @override
  Widget build(BuildContext context) {
    final expanded = _expanded ?? widget.initiallyExpanded;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _expanded = !expanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              const Expanded(
                  child: Text('Details',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500))),
              Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white70),
            ]),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final entry in widget.steps.entries)
                _StepRow(label: entry.key, step: entry.value),
              if (widget.notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(widget.notice!,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              if (widget.resultDetails != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(widget.resultDetails!,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ),
            ]),
          ),
      ]),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.step});
  final String label;
  final SyncStepResult step;
  @override
  Widget build(BuildContext context) {
    final icon = switch (step.status) {
      SyncStepStatus.ok => Icons.check_circle,
      SyncStepStatus.skipped => Icons.warning_amber_rounded,
      SyncStepStatus.failed => Icons.cancel,
    };
    final color = switch (step.status) {
      SyncStepStatus.ok => const Color(0xFFA7C080),
      SyncStepStatus.skipped => const Color(0xFFE69875),
      SyncStepStatus.failed => const Color(0xFFE67E80),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 13))),
        if (step.reason != null)
          Flexible(
            child: Text(step.reason!,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
      ]),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.palette,
    required this.busy,
    required this.canApply,
    required this.canReset,
    required this.inSync,
    required this.onApply,
    required this.onReset,
    required this.hasPalette,
  });
  final WidgetPalette? palette;
  final bool busy;
  final bool canApply;
  final bool canReset;
  final bool inSync;
  final VoidCallback onApply;
  final VoidCallback onReset;
  final bool hasPalette;
  @override
  Widget build(BuildContext context) {
    final accent = palette == null
        ? AppColors.accent
        : Color(0xFF000000 | palette!.accent);
    final foreground =
        palette == null ? Colors.white : Color(0xFF000000 | palette!.window);
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: HSLColor.fromColor(AppColors.background)
            .withLightness(
                (HSLColor.fromColor(AppColors.background).lightness - .08)
                    .clamp(0.0, 1.0))
            .toColor(),
        border:
            Border(top: BorderSide(color: Colors.white.withValues(alpha: .10))),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Row(children: [
            Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inSync ? 'Already in sync' : '4 changes ready',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    const Text('GTK 3 and 4, Shell, sidebar, folders',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
            ),
            OutlinedButton(
              onPressed: canReset ? onReset : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(96, 44),
                side: BorderSide(color: Colors.white.withValues(alpha: .30)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                disabledForegroundColor: Colors.white38,
              ),
              child: const Text('Reset'),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: canApply ? onApply : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: foreground,
                  disabledBackgroundColor: Colors.white.withValues(alpha: .12),
                  disabledForegroundColor: Colors.white38,
                  minimumSize: const Size(168, 44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (busy)
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                  else
                    Icon(Icons.sync, size: 18, color: foreground),
                  const SizedBox(width: 8),
                  Text(busy ? 'Syncing…' : 'Sync and apply',
                      style: TextStyle(
                          color: canApply ? foreground : Colors.white38,
                          fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
