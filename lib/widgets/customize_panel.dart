import 'package:flutter/material.dart';
import 'package:nebulashade/widgets/nebula_tokens.dart';

enum CustomizeTarget { folders, topBar, dock }

class CustomizePanel extends StatefulWidget {
  final Color baseColor;
  final List<Color> wallpaperPalette;
  final Color? initialFolderColor;
  final bool folderApplyEnabled;
  final String? folderApplyDisabledReason;
  final bool applying;
  final Future<void> Function(String hex)? onApplyFolder;
  final Future<void> Function(String hex)? onApplyTopBar;
  final Future<void> Function(String hex)? onApplyDock;
  final bool fillHeight;

  const CustomizePanel({
    super.key,
    required this.baseColor,
    required this.wallpaperPalette,
    required this.initialFolderColor,
    required this.folderApplyEnabled,
    required this.folderApplyDisabledReason,
    required this.applying,
    required this.onApplyFolder,
    required this.onApplyTopBar,
    required this.onApplyDock,
    this.fillHeight = true,
  });

  @override
  State<CustomizePanel> createState() => _CustomizePanelState();
}

class _CustomizePanelState extends State<CustomizePanel> {
  static const _cream = Color(0xFFF3ECE4);
  static const _muted = Color(0xFFD9CDBF);
  static const _fallbackAccent = Color(0xFFF98E65);
  static const _folderFallback = _fallbackAccent;
  static const _topDefault = Color(0xFF403632);
  static const _dockDefault = Color(0xFF362C29);
  static const _fallbackSwatches = [
    Color(0xFF26201D),
    Color(0xFF362C29),
    Color(0xFF403632),
    Color(0xFFE14509),
    Color(0xFFF98E65),
    Color(0xFFFBB79D),
    Color(0xFFFDE2D8),
  ];

  late Color _folderColor;
  Color _topBarColor = _topDefault;
  Color _dockColor = _dockDefault;
  CustomizeTarget _target = CustomizeTarget.folders;

  @override
  void initState() {
    super.initState();
    _folderColor = widget.initialFolderColor ?? _folderFallback;
  }

  @override
  void didUpdateWidget(covariant CustomizePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFolderColor != widget.initialFolderColor &&
        widget.initialFolderColor != null) {
      _folderColor = widget.initialFolderColor!;
    }
  }

  Color get _workingColor => switch (_target) {
        CustomizeTarget.folders => _folderColor,
        CustomizeTarget.topBar => _topBarColor,
        CustomizeTarget.dock => _dockColor,
      };

  List<Color> get _swatches => widget.wallpaperPalette.isEmpty
      ? _fallbackSwatches
      : widget.wallpaperPalette.take(7).toList();

  NebulaSurface get _surface => NebulaSurface(widget.baseColor);
  Color get _accent => NebulaTokens.accentFrom(widget.wallpaperPalette);

  String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  void _setWorkingColor(Color color) {
    setState(() {
      switch (_target) {
        case CustomizeTarget.folders:
          _folderColor = color;
        case CustomizeTarget.topBar:
          _topBarColor = color;
        case CustomizeTarget.dock:
          _dockColor = color;
      }
    });
  }

  void _suggestFromWallpaper() {
    final palette = widget.wallpaperPalette;
    if (palette.isEmpty) return;
    setState(() {
      _folderColor = palette[palette.length > 5 ? 5 : palette.length - 1];
      _topBarColor = palette[palette.length > 2 ? 2 : palette.length - 1];
      _dockColor = palette[palette.length > 1 ? 1 : palette.length - 1];
    });
  }

  Color _resetColor() => switch (_target) {
        CustomizeTarget.folders => widget.initialFolderColor ?? _folderFallback,
        CustomizeTarget.topBar => _topDefault,
        CustomizeTarget.dock => _dockDefault,
      };

  Future<void> _showCustomColorDialog() async {
    var input = '';
    String? error;
    Color preview = _workingColor;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NebulaRadius.card)),
          title: const Text('Use a custom colour'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: '',
                      decoration: InputDecoration(
                        labelText: 'Hex colour',
                        errorText: error,
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(NebulaRadius.control)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(NebulaRadius.control)),
                      ),
                      onChanged: (value) {
                        input = value;
                        final valid =
                            RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(value);
                        setDialogState(() {
                          error = value.isEmpty || valid
                              ? null
                              : 'Enter a valid #RRGGBB colour';
                          if (valid) {
                            final hex = value.replaceFirst('#', '');
                            preview = Color(int.parse('FF$hex', radix: 16));
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: preview,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white54),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            SizedBox(
                height: NebulaSize.control,
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                )),
            SizedBox(
                height: NebulaSize.control,
                child: TextButton(
                  onPressed: () {
                    final value = input;
                    if (!RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(value)) {
                      setDialogState(
                          () => error = 'Enter a valid #RRGGBB colour');
                      return;
                    }
                    _setWorkingColor(preview);
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Use colour'),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _apply() async {
    final hex = _hex(_workingColor);
    switch (_target) {
      case CustomizeTarget.folders:
        if (widget.folderApplyEnabled && widget.onApplyFolder != null) {
          await widget.onApplyFolder!(hex);
        }
      case CustomizeTarget.topBar:
        await widget.onApplyTopBar?.call(hex);
      case CustomizeTarget.dock:
        await widget.onApplyDock?.call(hex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = _surface;
    // ThemeScreen measures this panel under IntrinsicHeight, so use the window
    // width to choose the compact layout.
    final narrow = MediaQuery.sizeOf(context).width < 784;
    final compactHeight = MediaQuery.sizeOf(context).height < 400;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: surface.card,
          borderRadius: BorderRadius.circular(NebulaRadius.panel)),
      child: Column(
        mainAxisSize: widget.fillHeight ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(narrow),
          SizedBox(height: compactHeight ? 0 : 8),
          _buildTargetTabs(surface),
          SizedBox(height: compactHeight ? 0 : 8),
          if (widget.fillHeight)
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 150,
                  maxHeight: 320,
                ),
                child: _buildPreview(narrow),
              ),
            )
          else
            SizedBox(
              height: 150,
              child: _buildPreview(narrow),
            ),
          SizedBox(height: compactHeight ? 0 : 10),
          _buildSwatches(narrow),
          SizedBox(height: compactHeight ? 0 : 10),
          _buildBottomRow(narrow),
        ],
      ),
    );
  }

  Widget _buildHeader(bool narrow) {
    const title = Text('Folder, top bar & dock',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500));
    final wallpaperChip = SizedBox(
      height: 36,
      child: Material(
          color: _surface.control,
          borderRadius: BorderRadius.circular(NebulaRadius.control),
          child: InkWell(
            key: const ValueKey('from-wallpaper'),
            borderRadius: BorderRadius.circular(NebulaRadius.control),
            onTap: _suggestFromWallpaper,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.auto_fix_high, size: 15, color: _muted),
                const SizedBox(width: 4),
                Text('From wallpaper',
                    style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ]),
            ),
          )),
    );
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          Align(alignment: Alignment.centerRight, child: wallpaperChip)
        ],
      );
    }
    return Row(
      children: [
        const Expanded(child: title),
        const SizedBox(width: 8),
        wallpaperChip
      ],
    );
  }

  Widget _buildPreview(bool narrow) {
    final scale = narrow ? 0.78 : 1.0;
    return ClipRRect(
      key: const ValueKey('customize-preview'),
      borderRadius: BorderRadius.circular(NebulaRadius.control),
      child: GestureDetector(
        onTap: () => setState(() => _target = CustomizeTarget.topBar),
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF1C1613))),
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 18,
                width: double.infinity,
                child: GestureDetector(
                  key: const ValueKey('preview-topbar'),
                  onTap: () => setState(() => _target = CustomizeTarget.topBar),
                  child: _previewTarget(
                    CustomizeTarget.topBar,
                    color: _topBarColor,
                    child: Row(
                      children: [
                        const SizedBox(width: 10),
                        _bar(_cream, 34),
                        const Spacer(),
                        _bar(_muted, 26),
                        const Spacer(),
                        _bar(_muted, 10),
                        const SizedBox(width: 5),
                        _bar(_muted, 10),
                        const SizedBox(width: 10),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0, -0.15),
              child: FractionallySizedBox(
                heightFactor: 0.26,
                widthFactor: 0.6,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: GestureDetector(
                    key: const ValueKey('preview-folders'),
                    onTap: () =>
                        setState(() => _target = CustomizeTarget.folders),
                    child: _previewTarget(
                      CustomizeTarget.folders,
                      color: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            3,
                            (i) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 7),
                              child: _FolderShape(
                                  color: _folderColor, scale: scale),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FractionallySizedBox(
                  heightFactor: 0.23,
                  widthFactor: 0.5,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: GestureDetector(
                      key: const ValueKey('preview-dock'),
                      onTap: () =>
                          setState(() => _target = CustomizeTarget.dock),
                      child: _previewTarget(
                        CustomizeTarget.dock,
                        color: _dockColor,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 11 * scale, vertical: 7 * scale),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            for (int i = 0; i < 4; i++) ...[
                              if (i > 0) SizedBox(width: 6 * scale),
                              Container(
                                width: 20 * scale,
                                height: 20 * scale,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8A7A68),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewTarget(CustomizeTarget target,
      {required Color color, required Widget child}) {
    final selected = _target == target;
    return CustomPaint(
      foregroundPainter:
          selected ? const DashedRectPainter(_cream, radius: 4) : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(target == CustomizeTarget.topBar
              ? 0
              : target == CustomizeTarget.dock
                  ? 8
                  : 3),
        ),
        child: child,
      ),
    );
  }

  Widget _bar(Color color, double width) => Container(
        width: width,
        height: 3,
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      );

  Widget _buildTargetTabs(NebulaSurface surface) => NebulaTabBar(
        labels: const ['Folders', 'Top bar', 'Dock'],
        selectedIndex: _target.index,
        surface: surface,
        keys: const [
          ValueKey('tab-folders'),
          ValueKey('tab-topbar'),
          ValueKey('tab-dock')
        ],
        onChanged: (index) =>
            setState(() => _target = CustomizeTarget.values[index]),
      );

  Widget _buildSwatches(bool narrow) {
    final cells = <Widget>[
      for (var i = 0; i < _swatches.length; i++) _swatchCell(_swatches[i], i),
      _customSwatchCell(),
    ];
    final rows =
        narrow ? [cells.take(4).toList(), cells.skip(4).toList()] : [cells];
    return Column(children: [
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
        if (rowIndex > 0) const SizedBox(height: 2),
        Row(children: [
          for (final cell in rows[rowIndex]) Expanded(child: cell)
        ]),
      ],
    ]);
  }

  Widget _swatchCell(Color color, int index) {
    final selected = color.toARGB32() == _workingColor.toARGB32();
    return GestureDetector(
      key: ValueKey('swatch-${_hex(color)}'),
      onTap: () => _setWorkingColor(color),
      child: Container(
        height: NebulaSize.swatch,
        decoration: BoxDecoration(
            color: color,
            border: selected ? Border.all(color: _cream, width: 2) : null),
        child: selected
            ? Center(child: Icon(Icons.check, size: 18, color: onColor(color)))
            : null,
      ),
    );
  }

  Widget _customSwatchCell() => GestureDetector(
        key: const ValueKey('custom-color'),
        onTap: _showCustomColorDialog,
        child: Container(
          height: NebulaSize.swatch,
          color: _surface.control,
          child: const Center(child: Icon(Icons.add, color: _muted)),
        ),
      );

  Widget _buildBottomRow(bool narrow) {
    final callback = switch (_target) {
      CustomizeTarget.folders =>
        widget.folderApplyEnabled ? widget.onApplyFolder : null,
      CustomizeTarget.topBar => widget.onApplyTopBar,
      CustomizeTarget.dock => widget.onApplyDock,
    };
    final disabledReason = switch (_target) {
      CustomizeTarget.folders =>
        widget.folderApplyDisabledReason ?? 'Folder icon theme not found',
      CustomizeTarget.topBar ||
      CustomizeTarget.dock =>
        'Top bar and dock apply is coming in the next update',
    };
    final enabled = !widget.applying && callback != null;
    final hexChip = InkWell(
      key: const ValueKey('selected-hex'),
      onTap: _showCustomColorDialog,
      borderRadius: BorderRadius.circular(NebulaRadius.control),
      child: Container(
        height: NebulaSize.control,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
            color: _surface.field,
            borderRadius: BorderRadius.circular(NebulaRadius.control)),
        child: Row(children: [
          Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                  color: _workingColor,
                  borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_hex(_workingColor),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _cream, fontSize: 12, fontFamily: 'monospace'))),
        ]),
      ),
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
            height: NebulaSize.control,
            child: TextButton(
              key: const ValueKey('reset'),
              onPressed: widget.applying
                  ? null
                  : () => _setWorkingColor(_resetColor()),
              style: TextButton.styleFrom(
                  foregroundColor: _muted,
                  backgroundColor: _surface.control,
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(NebulaRadius.control))),
              child: const Text('Reset', style: TextStyle(fontSize: 12)),
            )),
        const SizedBox(width: 4),
        Tooltip(
          message: enabled ? '' : disabledReason,
          child: ElevatedButton.icon(
            key: const ValueKey('customize-apply'),
            onPressed: enabled ? _apply : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: onColor(_accent),
              disabledBackgroundColor: _accent.withValues(alpha: 0.5),
              disabledForegroundColor: onColor(_accent).withValues(alpha: 0.7),
              minimumSize: const Size(86, NebulaSize.control),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(NebulaRadius.control)),
            ),
            icon: const Icon(Icons.check, size: 15),
            label: SizedBox(
              width: 60,
              child: Text(widget.applying ? 'Applying...' : 'Apply',
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ],
    );
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: hexChip),
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerRight, child: controls),
        ],
      );
    }
    return Row(
      children: [Expanded(child: hexChip), const Spacer(), controls],
    );
  }
}

class _FolderShape extends StatelessWidget {
  const _FolderShape({required this.color, required this.scale});
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 36 * scale,
        height: 28 * scale,
        child: Stack(
          children: [
            Positioned(
              left: 1 * scale,
              top: 0,
              child: Container(
                width: 14 * scale,
                height: 6 * scale,
                decoration: BoxDecoration(
                  color: HSLColor.fromColor(color)
                      .withLightness(
                          (HSLColor.fromColor(color).lightness - 0.12)
                              .clamp(0, 1))
                      .toColor(),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                width: 34 * scale,
                height: 22 * scale,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ],
        ),
      );
}
