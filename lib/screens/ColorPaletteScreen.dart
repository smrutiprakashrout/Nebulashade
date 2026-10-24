import 'package:flutter/material.dart';
import 'package:nebulashade/components/quick_apply.dart';
import 'package:nebulashade/components/quickpannel.dart';
import 'package:nebulashade/constants/colours.dart';
import 'package:palette_generator/palette_generator.dart';

class ColorPaletteScreen extends StatefulWidget {
  final ImageProvider imageProvider;
  final List<Color> dominantColors;

  const ColorPaletteScreen({
    required this.imageProvider,
    required this.dominantColors,
    super.key,
  });

  @override
  _ColorPaletteScreenState createState() => _ColorPaletteScreenState();
}

class _ColorPaletteScreenState extends State<ColorPaletteScreen> {
  PaletteGenerator? _palette;
  String? _selectedPaletteLabel; // Track selected color palette by label
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _generatePalette();
    _selectedPaletteLabel = "Dominant Color";
    print(getSelectedBaseColorHex(0));
    print(getSelectedBaseColorHex(1));
    print(getSelectedBaseColorHex(2));
    print(getSelectedBaseColorHex(3));
    print(getSelectedBaseColorHex(4));
    print(getSelectedBaseColorHex(5));
    print(getSelectedBaseColorHex(6));
    print(getSelectedBaseColorHex(7));
  }

  Future<void> _generatePalette() async {
    final palette = await PaletteGenerator.fromImageProvider(
      widget.imageProvider,
      size: const Size(200, 200),
      maximumColorCount: 32,
    );

    setState(() {
      _palette = palette;
    });
  }

  List<Color> generateShadesBoth(Color baseColor) {
    final hsl = HSLColor.fromColor(baseColor);

    // Slightly darker starting tone: range from 0.12 to 0.8
    return List.generate(7, (index) {
      final step = index / 6; // 0 to 1
      final lightness = 0.12 + (0.68 * step); // starts at 0.12, ends at 0.8
      return hsl.withLightness(lightness.clamp(0.0, 1.0)).toColor();
    });
  }

  Color generateShadesHSV(Color baseColor) {
    final hsv = HSVColor.fromColor(baseColor);
    return HSVColor.fromAHSV(
      hsv.alpha,
      hsv.hue, // keep original hue
      0.21, // fixed saturation
      0.25, // fixed value
    ).toColor();
  }

  List<Color> getFilteredShades(Color baseColor) {
    Color getDarksideShade(Color baseColor) {
      final hsv = HSVColor.fromColor(baseColor);

      return HSVColor.fromAHSV(
        hsv.alpha,
        hsv.hue, // keep original hue
        0.24, // fixed saturation
        0.15, // fixed value
      ).toColor();
    }

    Color getDarkBgShade(Color baseColor) {
      final hsv = HSVColor.fromColor(baseColor);

      return HSVColor.fromAHSV(
        hsv.alpha,
        hsv.hue, // keep original hue
        0.24, // fixed saturation
        0.21, // fixed value
      ).toColor();
    }

    final hsl = HSLColor.fromColor(baseColor);
    final allShades = generateShadesBoth(baseColor);
    final lighterShade = hsl.withLightness(0.92.clamp(0.0, 1.0)).toColor();
    return [
      getDarksideShade(allShades.first),
      getDarkBgShade(allShades.first),
      generateShadesHSV(allShades[2]),
      ...allShades.sublist(allShades.length - 4),
      lighterShade,
    ];
  }

  Color _getSelectedBaseColor(int shadeIndex) {
    final labels = [
      "Default Color",
      "Dominant Color",
      "Vibrant Color",
      "Dark Vibrant Color",
      "Light Vibrant Color",
      "Muted Color",
      "Dark Muted Color",
      "Light Muted Color"
    ];

    final index = labels.indexOf(_selectedPaletteLabel ?? "Dominant Color");

    if (index >= 0 && index < widget.dominantColors.length) {
      final baseColor = widget.dominantColors[index];
      final shades = getFilteredShades(baseColor);
      return (shadeIndex >= 0 && shadeIndex < shades.length)
          ? shades[shadeIndex]
          : baseColor;
    }

    return AppColors.background;
  }

  /// Returns the selected shade **as a 6‑digit HEX string** (e.g. “#A1B2C3”).
  String getSelectedBaseColorHex(int shadeIndex) {
    const labels = [
      'Default Color',
      'Dominant Color',
      'Vibrant Color',
      'Dark Vibrant Color',
      'Light Vibrant Color',
      'Muted Color',
      'Dark Muted Color',
      'Light Muted Color',
    ];

    final idx = labels.indexOf(_selectedPaletteLabel ?? 'Dominant Color');

    // Pick a base colour from the dominant list or fall back.
    Color base = (idx >= 0 && idx < widget.dominantColors.length)
        ? widget.dominantColors[idx]
        : AppColors.background;

    // Apply shade index if available.
    final shades = getFilteredShades(base);
    if (shadeIndex >= 0 && shadeIndex < shades.length) {
      base = shades[shadeIndex];
    }

    // Convert to #RRGGBB.
    final rgb = base.value & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Future<void> _applySelectedTheme() async {
    if (_isApplying) return;
    setState(() => _isApplying = true);
    try {
      await quickapplyTheme(getSelectedBaseColorHex(1));
    } catch (e) {
      debugPrint('Apply Theme failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not apply theme')),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Widget _buildColorPalette(String label, Color? baseColor) {
    final shades = getFilteredShades(baseColor ?? Colors.transparent);
    final isSelected = _selectedPaletteLabel == label;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPaletteLabel = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.white : Colors.grey.shade800,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
          color: isSelected ? Colors.white12 : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                final boxCount = shades.length;
                final availableWidth = constraints.maxWidth;
                final boxWidth = availableWidth / boxCount;

                return Row(
                  children: List.generate(boxCount, (index) {
                    return Container(
                      width: boxWidth,
                      height: 32,
                      decoration: BoxDecoration(
                        color: shades[index],
                        borderRadius: BorderRadius.only(
                          topLeft: index == 0
                              ? const Radius.circular(6)
                              : Radius.zero,
                          bottomLeft: index == 0
                              ? const Radius.circular(6)
                              : Radius.zero,
                          topRight: index == boxCount - 1
                              ? const Radius.circular(6)
                              : Radius.zero,
                          bottomRight: index == boxCount - 1
                              ? const Radius.circular(6)
                              : Radius.zero,
                        ),
                      ),
                    );
                  }),
                );
              },
            )
          ],
        ),
      ),
    );
  }

  var buttonst = 2;

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Default Color',
      'Dominant Color',
      'Vibrant Color',
      'Dark Vibrant Color',
      'Light Vibrant Color',
      'Muted Color',
      'Dark Muted Color',
      'Light Muted Color',
    ];

    final imageWidget = Image(image: widget.imageProvider, fit: BoxFit.cover);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        title: const Text(
          "Color Palette",
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      body: _palette == null
          ? const Center(child: CircularProgressIndicator())
          : Row(
              // =====================================================
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 7,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 16, top: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: imageWidget,
                                ),

                                // widdet 1=========================
                                buttonst == 1
                                    ? Center(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            color: _getSelectedBaseColor(
                                                1), // semi-transparent red
                                          ),
                                          width: 700,
                                          height: 350,
                                          child: Container(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 18,
                                                      vertical: 14),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Container(
                                                    width: 10,
                                                    height: 10,
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              50),
                                                      color: Color(
                                                          0xFFe67e80), // semi-transparent red
                                                    ),
                                                  ),
                                                  SizedBox(width: 5),
                                                  Container(
                                                    width: 10,
                                                    height: 10,
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              50),
                                                      color: Color(
                                                          0xFFe69875), // semi-transparent red
                                                    ),
                                                  ),
                                                  SizedBox(width: 5),
                                                  Container(
                                                    width: 10,
                                                    height: 10,
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              50),
                                                      color: Color(
                                                          0xFFa7c080), // semi-transparent red
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : buttonst == 2
                                        ?

                                        // widget 2
                                        Positioned(
                                            top: 20,
                                            right: 10,
                                            child: Container(
                                              width: 320,
                                              height: 300,
                                              decoration: BoxDecoration(
                                                color: _getSelectedBaseColor(1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: QuickSettingsPanel(
                                                getSelectedBaseColor:
                                                    _getSelectedBaseColor,
                                              ),
                                            ),
                                          )
                                        :
                                        // widget 3
                                        Center(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                color: _getSelectedBaseColor(
                                                    1), // semi-transparent red
                                              ),
                                              width: 700,
                                              height: 350,
                                              child: Stack(
                                                children: [
                                                  Container(
                                                    width: 200,
                                                    decoration: BoxDecoration(
                                                        color:
                                                            _getSelectedBaseColor(
                                                                0),
                                                        borderRadius:
                                                            BorderRadius.only(
                                                                topLeft: Radius
                                                                    .circular(
                                                                        6),
                                                                bottomLeft: Radius
                                                                    .circular(
                                                                        6))),
                                                    height: double.infinity,
                                                  ),
                                                  Container(
                                                    child: Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 18,
                                                          vertical: 14),
                                                      // buttons-------------------
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .start,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Container(
                                                            width: 10,
                                                            height: 10,
                                                            decoration:
                                                                BoxDecoration(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          50),
                                                              color: Color(
                                                                  0xFFe67e80), // semi-transparent red
                                                            ),
                                                          ),
                                                          SizedBox(width: 5),
                                                          Container(
                                                            width: 10,
                                                            height: 10,
                                                            decoration:
                                                                BoxDecoration(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          50),
                                                              color: Color(
                                                                  0xFFe69875), // semi-transparent red
                                                            ),
                                                          ),
                                                          SizedBox(width: 5),
                                                          Container(
                                                            width: 10,
                                                            height: 10,
                                                            decoration:
                                                                BoxDecoration(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          50),
                                                              color: Color(
                                                                  0xFFa7c080), // semi-transparent red
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              // buttons monimize,close ,maximize
                                            ),
                                          ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  buttonst = 1;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.lighten(
                                    AppColors.background,
                                    0.2), // background color
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  side: BorderSide(
                                    color: buttonst == 1
                                        ? Colors.white
                                        : Colors.transparent, // border color
                                    width:
                                        buttonst == 1 ? 1.5 : 0, // border width
                                  ), // rounded corners // rounded corners
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 10),
                                child: Text(
                                  "Background",
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                            SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  buttonst = 2;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.lighten(
                                    AppColors.background,
                                    0.2), // background color
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  side: BorderSide(
                                    color: buttonst == 2
                                        ? Colors.white
                                        : Colors.transparent, // border color
                                    width:
                                        buttonst == 2 ? 1.5 : 0, // border width
                                  ), // rounded corners
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 10),
                                child: Text(
                                  "Genome Shell",
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                            SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  buttonst = 3;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.lighten(
                                    AppColors.background,
                                    0.2), // background color
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      6), // rounded corners
                                  side: BorderSide(
                                    color: buttonst == 3
                                        ? Colors.white
                                        : Colors.transparent, // border color
                                    width:
                                        buttonst == 3 ? 1.5 : 0, // border width
                                  ), // rounded corners
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 10),
                                child: Text(
                                  "Sidebar",
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // row
                      // buttons gtk shell,backgroud,sidebar,gtk2/3
                      // Re-Apply button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 32),
                            child: ElevatedButton(
                                onPressed:
                                    _isApplying ? null : _applySelectedTheme,
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: _getSelectedBaseColor(5),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                        vertical: 20, horizontal: 28)),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.format_paint,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      _isApplying
                                          ? "Applying..."
                                          : "Apply Theme",
                                      style: TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                )),
                          ),
                        ],
                      )
                    ],
                  ),
                ),

                // =========================================================
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        for (int i = 0;
                            i < labels.length &&
                                i < widget.dominantColors.length;
                            i++)
                          _buildColorPalette(
                              labels[i], widget.dominantColors[i]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
