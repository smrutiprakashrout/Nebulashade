import 'dart:io';
import 'dart:ui'; // Required for ImageFilter
import 'package:flutter/material.dart';
import 'package:nebulashade/constants/colours.dart';
import 'package:nebulashade/screens/ColorPaletteScreen.dart';
import 'package:nebulashade/screens/color_edit_screen.dart';
import 'package:nebulashade/screens/dynamic/getthemes_screen.dart';
import 'package:nebulashade/screens/dynamic/newwallpaper_screen.dart';
import 'package:palette_generator/palette_generator.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:nebulashade/components/quick_apply.dart';
import 'package:shimmer/shimmer.dart';
// import 'package:file_picker/file_picker.dart';

class ThemeScreen extends StatefulWidget {
  const ThemeScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _ThemeScreenState createState() => _ThemeScreenState();
}

class _ThemeScreenState extends State<ThemeScreen> {
  bool isDarkMode = true;
  String? wallpaperPath;
  List<Color> dominantColors = [];
  // Theme variables
  String globalTheme = "Loading...";
  String gtk3Theme = "Loading...";
  String gtk4Theme = "Loading...";
  String shellTheme = "Loading...";
  List<Color> selectedShades = []; // To store the result
  // PaletteGenerator? _palette;
  String? _selectedPaletteLabel;
  List<String> shades = [];
  bool ispalletegen = false;
  bool isThemeChange = false;
  List<String> getCurrentShades() {
    return shades; // Returns the current shades list from the parent's state
  }

  @override
  void initState() {
    super.initState();
    _getCurrentWallpaper();
    // _generatePalette();
    Timer.periodic(Duration(seconds: 3), (_) {
      _getCurrentWallpaper(); // Periodically check for updates
    });
    _getCurrentThemes();
    shades.isNotEmpty
        ? print("shades generated -> $shades")
        : print("shades generation in progress");
  }

// ============================================================================================

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

  // Color _getSelectedBaseColor(int shadeIndex) {
  //   final labels = [
  //     "Default Color",
  //     "Dominant Color",
  //     "Vibrant Color",
  //     "Dark Vibrant Color",
  //     "Light Vibrant Color",
  //     "Muted Color",
  //     "Dark Muted Color",
  //     "Light Muted Color"
  //   ];

  //   final index = labels.indexOf(_selectedPaletteLabel ?? "Dominant Color");

  //   if (index >= 0 && index < dominantColors.length) {
  //     final baseColor = dominantColors[index];
  //     final shades = getFilteredShades(baseColor);
  //     return (shadeIndex >= 0 && shadeIndex < shades.length)
  //         ? shades[shadeIndex]
  //         : baseColor;
  //   }

  //   return AppColors.background;
  // }

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
    Color base = (idx >= 0 && idx < dominantColors.length)
        ? dominantColors[idx]
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

// ============================================================================================

  Future<void> _extractColorsFromWallpaper(String imagePath) async {
    try {
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) return;

      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        FileImage(imageFile),
        maximumColorCount: 9, // Get 7 dominant colors
      );

      setState(() {
        dominantColors = paletteGenerator.colors.toList();
      });

      // Build a list of the 8 hex strings
      final nshades = List.generate(8, getSelectedBaseColorHex);

      // Pretty‑print the whole list
      // print('🌈 Received shades themes screen → $shades');

      // Convert each color to hex string
      final colorHexList = dominantColors
          .map((color) => '#${color.value.toRadixString(16).padLeft(8, '0')}')
          .toList();
      // Prepare file path
      final homeDir = Platform.environment['HOME']!;
      final dirPath = path.join(homeDir, 'Nebula');
      final filePath = path.join(dirPath, 'colors.txt');

      // Create directory if it doesn't exist
      final directory = Directory(dirPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Write to file
      final colorFile = File(filePath);
      await colorFile.writeAsString(colorHexList.join('\n'));

      print('Colors written to $filePath');
      setState(() {
        ispalletegen = true;
        shades = nshades;
        print(shades);
      });
    } catch (e) {
      print('Error extracting colors: $e');
    }
  }

  Future<void> _getCurrentWallpaper() async {
    try {
      final result = await Process.run(
        'gsettings',
        ['get', 'org.gnome.desktop.background', 'picture-uri'],
      );

      if (result.exitCode == 0) {
        String output = result.stdout.toString().trim();

        if (output.startsWith("'file://") && output.endsWith("'")) {
          String path = output.substring(8, output.length - 1);

          if (wallpaperPath != path) {
            setState(() {
              wallpaperPath = path;
            });
            print('Wallpaper path updated: $wallpaperPath');

            // Add this line to trigger color extraction
            await _extractColorsFromWallpaper(path);
          }
        }
      }
    } catch (e) {
      print("Error fetching wallpaper: $e");
      setState(() {
        wallpaperPath = null;
        dominantColors = []; // Clear colors on error
      });
    }
  }

  Future<void> _getCurrentThemes() async {
    try {
      final gtkResult = await Process.run(
          'gsettings', ['get', 'org.gnome.desktop.interface', 'gtk-theme']);
      final shellResult = await Process.run('gsettings',
          ['get', 'org.gnome.shell.extensions.user-theme', 'name']);

      setState(() {
        globalTheme = _cleanGSettingsValue(gtkResult.stdout.toString());
        gtk3Theme = globalTheme;
        gtk4Theme = globalTheme;
        shellTheme = _cleanGSettingsValue(shellResult.stdout.toString());
      });
    } catch (e) {
      print("Error fetching theme: $e");
      setState(() {
        globalTheme = "Error"; // Optional: Update UI to show error
      });
    }
  }

  String _cleanGSettingsValue(String value) {
    value = value.trim();
    if (value.startsWith("'") && value.endsWith("'")) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

// Folder picker functionality (Linux-specific via GTK integration)
  Future<void> _openFolderPicker() async {
    try {
      final result =
          await Process.run('zenity', ['--file-selection', '--directory']);

      if (result.exitCode == 0) {
        String path = result.stdout.toString().trim();
        setState(() {
          wallpaperPath = path;
        });
      } else {
        print("No folder selected");
      }
    } catch (e) {
      print("Error picking folder: $e");
    }
  }

  Future<List<String>> _getAvailableThemes() async {
    final homeDir = Platform.environment['HOME'];
    final themesDir = Directory('$homeDir/.themes');

    if (await themesDir.exists()) {
      final dirs = themesDir
          .listSync()
          .whereType<Directory>()
          .map((dir) => dir.path.split('/').last)
          .toList();

      return dirs;
    }
    return [];
  }

// Add this in your build method where you want to show the colors
  Widget _buildColorPalette() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(height: 40),
        Container(
          height: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.lighten(AppColors.background, 0.2),
                      padding: EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () {},
                    child: Text("Open CSS file",
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  SizedBox(width: 10),
                  Container(
                    margin: EdgeInsets.only(bottom: 0),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => GetThemes(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.lighten(AppColors.background, 0.2),
                        foregroundColor: AppColors.buttonText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        elevation: 0,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                        child: Icon(
                          Icons.shopping_cart,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Container(
                    margin: const EdgeInsets.only(bottom: 0),
                    child: ElevatedButton(
                      onPressed: _openFolderPicker,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.lighten(AppColors.background, 0.2),
                        foregroundColor: AppColors.buttonText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        elevation: 0,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                        child: Icon(
                          Icons.inventory,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(width: 20),
              Expanded(
                flex: 5,
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: ispalletegen == false
                      ? Container(
                          width: 590,
                          height: double.infinity,
                          color: AppColors.lighten(AppColors.background, 0.2),
                          child: Center(
                            child: Text(
                              "Loading color palette ...",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w400),
                            ),
                          ),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: dominantColors.length,
                          itemBuilder: (context, index) {
                            return GestureDetector(
                              onTap: () {
                                print('Color selected: ${dominantColors[index]}');
                              },
                              child: Container(
                                width: 64.8,
                                decoration: BoxDecoration(
                                  color: dominantColors[index],
                                  borderRadius: BorderRadius.circular(0),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: screenHeight),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Container(
                        width: 250,
                        height: 265,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Container(
                                    width: 10,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: Colors.white70,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.only(
                                  bottomLeft: Radius.circular(10),
                                  bottomRight: Radius.circular(10),
                                ),
                                child: wallpaperPath != null
                                    ? Image.file(
                                        File(wallpaperPath!),
                                        key: ValueKey(
                                            wallpaperPath), // This triggers a re-render
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                      )
                                    : Center(
                                        child: CircularProgressIndicator(),
                                      ),
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 11, vertical: 10),
                            height: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color:
                                  AppColors.lighten(AppColors.background, 0.2),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text("Album",
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 14)),
                                    // SizedBox(width: 10),
                                    // _HoverIcon(icon: Icons.edit, size: 18),
                                    SizedBox(width: 10),
                                    _HoverIcon(
                                        icon: Icons.tab_unselected, size: 18),
                                    SizedBox(width: 10),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                NewWallpaper(shades),
                                          ),
                                        ).then((_) {
                                          _getCurrentWallpaper(); // Refresh wallpaper after returning
                                        });
                                      },
                                      child: _HoverIcon(
                                        icon: Icons.install_desktop,
                                        size: 18,
                                      ),
                                    ),
                                    Spacer(),
                                    Icon(Icons.photo,
                                        color: Colors.white, size: 24),
                                  ],
                                ),
                                Container(
                                  height: 150,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      ImageRowScroller(
                                        // shades: shades,
                                        ispalletegen: ispalletegen,
                                        onPaletteStateChanged: (newValue) {
                                          setState(() {
                                            ispalletegen = newValue;
                                          });
                                        },
                                        onThemechange: (newt) {
                                          setState(() {
                                            isThemeChange = newt;
                                          });
                                        },
                                        getCurrentShades: () => shades,
                                        onWallpaperChanged:
                                            (String newPath) async {
                                          // Force an immediate refresh instead of waiting for timer
                                          setState(() {
                                            wallpaperPath = newPath;
                                          });
                                          await _extractColorsFromWallpaper(
                                              newPath);
                                          // Now call this after colors are updated
                                        },
                                      )
                                    ],
                                  ),
                                )
                              ],
                            ),
                          ),
                          SizedBox(height: 16),
                          GestureDetector(
                            onTap: () {
                              if (wallpaperPath != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ColorPaletteScreen(
                                      imageProvider:
                                          FileImage(File(wallpaperPath!)),
                                      dominantColors: dominantColors,
                                    ),
                                  ),
                                );
                              }
                            },
                            child: isThemeChange
                                ? Stack(
                                    children: [
                                      Shimmer.fromColors(
                                        baseColor: AppColors.lighten(
                                            AppColors.background, 0.3),
                                        highlightColor: Colors.deepPurpleAccent,
                                        period: Duration(seconds: 1),
                                        child: Container(
                                          padding: EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: AppColors.lighten(
                                                AppColors.background, 0.2),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Align(
                                            alignment: Alignment.center,
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text("Starting Quick Adapt ...",
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 14)),
                                                SizedBox(width: 12),
                                                Icon(Icons.bolt,
                                                    color: Colors.white),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        alignment: Alignment.center,
                                        height: 50,
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text("Starting Quick Adapt ...",
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14)),
                                            SizedBox(width: 12),
                                            Icon(Icons.bolt,
                                                color: Colors.white),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                : Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.lighten(
                                          AppColors.background, 0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text("Quick Adapt Colours",
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14)),
                                        SizedBox(width: 12),
                                        Icon(Icons.bolt, color: Colors.white),
                                      ],
                                    ),
                                  ),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
                _buildColorPalette(),
                SizedBox(height: 20),

                _buildThemeOption("Global Theme", globalTheme, Icons.add),
                _buildThemeOption("GTK 3.0 Theme", gtk3Theme, Icons.edit),
                _buildThemeOption("GTK 4.0 Theme", gtk4Theme, Icons.edit),
                _buildThemeOption("Gnome Shell", shellTheme, Icons.edit),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Toggle Dark Mode",
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    Transform.scale(
                      scale: 0.9,
                      child: Switch(
                        value: isDarkMode,
                        onChanged: (bool value) {
                          setState(() {
                            isDarkMode = value;
                          });
                        },
                        activeColor: AppColors.adjustColor(AppColors.background,
                            saturationDelta: 24, valueDelta: 49),
                        activeTrackColor: AppColors.adjustColor(
                            AppColors.background,
                            saturationDelta: 70,
                            valueDelta: 18),
                        inactiveThumbColor: AppColors.adjustColor(
                            AppColors.background,
                            saturationDelta: 70,
                            valueDelta: 18),
                        inactiveTrackColor: AppColors.adjustColor(
                            AppColors.background,
                            saturationDelta: 24,
                            valueDelta: 49),
                      ),
                    )
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Fix Flatpak GTK Theme",
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    Transform.scale(
                      scale: 0.9,
                      child: Switch(
                        value: isDarkMode,
                        onChanged: (bool value) {
                          setState(() {
                            isDarkMode = value;
                          });
                        },
                        activeColor: AppColors.adjustColor(AppColors.background,
                            saturationDelta: 24, valueDelta: 49),
                        activeTrackColor: AppColors.adjustColor(
                            AppColors.background,
                            saturationDelta: 70,
                            valueDelta: 18),
                        inactiveThumbColor: AppColors.adjustColor(
                            AppColors.background,
                            saturationDelta: 70,
                            valueDelta: 18),
                        inactiveTrackColor: AppColors.adjustColor(
                            AppColors.background,
                            saturationDelta: 24,
                            valueDelta: 49),
                      ),
                    )
                  ],
                ),
                SizedBox(height: 16),
                // ---------------------------------------------------
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeOption(String title, String themeName, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Text(title, style: TextStyle(color: Colors.white, fontSize: 14)),
          if (title == "Global Theme") ...[
            SizedBox(width: 8),
            Icon(Icons.info, color: Colors.white, size: 24),
          ],
          Spacer(),
          GestureDetector(
            onTap: () async {
              List<String> availableThemes = await _getAvailableThemes();
              showDialog(
                context: context,
                barrierColor: Colors.transparent,
                builder: (context) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Dialog(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      child: GestureDetector(
                        onTap: () {}, // Prevent tap from bubbling up
                        child: Padding(
                          padding: EdgeInsets.only(
                              left: MediaQuery.of(context).size.width * 0.52),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: BackdropFilter(
                              filter:
                                  ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                              child: Container(
                                width: 420,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      width: 1,
                                      color: Colors.white.withAlpha(51)),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppColors.cardBackground.withAlpha(205),
                                      AppColors.cardBackground.withAlpha(127),
                                      AppColors.accent.withAlpha(51),
                                    ],
                                    stops: [0.0, 0.6, 1.0],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: availableThemes.expand((theme) {
                                      return [
                                        ListTile(
                                          title: Text(
                                            theme,
                                            style:
                                                TextStyle(color: Colors.white),
                                          ),
                                          onTap: () {
                                            setState(() {
                                              themeName = theme;
                                            });
                                            Navigator.of(context).pop();
                                          },
                                        ),
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color:
                                              AppColors.subtext.withAlpha(20),
                                        ),
                                      ];
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
            child: Container(
              width: 450,
              padding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.lighten(AppColors.background, 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                themeName,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          SizedBox(width: 8),
          Container(
            padding: EdgeInsets.symmetric(vertical: 4.5, horizontal: 2),
            decoration: BoxDecoration(
              color: AppColors.lighten(AppColors.background, 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(icon, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CssColorListScreen(
                      extractedColors: dominantColors, // your extracted palette
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HoverIcon extends StatefulWidget {
  final IconData icon;
  final double size;

  const _HoverIcon({required this.icon, this.size = 18});

  @override
  State<_HoverIcon> createState() => _HoverIconState();
}

class _HoverIconState extends State<_HoverIcon> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _isHovered ? Colors.white12 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          widget.icon,
          size: widget.size,
          color: Colors.white,
        ),
      ),
    );
  }
}

class ImageRowScroller extends StatefulWidget {
  // final List<String> shades;
  final bool ispalletegen;
  final Function(bool) onPaletteStateChanged;
  final Function(bool) onThemechange;
  final Function(String) onWallpaperChanged;
  final Function() getCurrentShades;

  const ImageRowScroller({
    // required this.shades,
    required this.ispalletegen,
    required this.onPaletteStateChanged,
    required this.onThemechange,
    required this.onWallpaperChanged,
    required this.getCurrentShades,
    super.key,
  });

  @override
  State<ImageRowScroller> createState() => _ImageRowScrollerState();
}

class _ImageRowScrollerState extends State<ImageRowScroller> {
  List<File> imageFiles = [];

  @override
  void initState() {
    super.initState();
    loadImages();

    // print("hello -> ${widget.shades}");
  }

  Future<void> loadImages() async {
    final homeDir = Platform.environment['HOME'] ??
        (await getApplicationDocumentsDirectory()).path;
    final targetDir = Directory('$homeDir/nexwallpapers');

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final files = targetDir
        .listSync()
        .whereType<File>()
        .where(
            (file) => file.path.endsWith('.jpg') || file.path.endsWith('.png'))
        .toList();

    setState(() {
      imageFiles = files;
    });
  }

// =================================================
  Future<void> setAsWallpaper(String path) async {
    final uri = 'file://${Uri.encodeFull(path)}'; // Ensure proper URI format

    try {
      widget.onPaletteStateChanged(false);
      widget.onThemechange(true);
      final result1 = await Process.run('gsettings', [
        'set',
        'org.gnome.desktop.background',
        'picture-uri',
        uri,
      ]);

      final result2 = await Process.run('gsettings', [
        'set',
        'org.gnome.desktop.background',
        'picture-uri-dark',
        uri,
      ]);

      if (result1.exitCode == 0 && result2.exitCode == 0) {
        await Process.run('notify-send', [
          '-i',
          'dialog-information',
          '-a',
          'NebulaShade',
          '-u',
          'normal',
          '-t',
          '7000',
          'Background Updated',
          'Wallpaper set successfully!'
        ]);

        // Step 1: update wallpaper display + extract fresh palette from new wallpaper.
        // Must complete first so currentShades has the NEW colors.
        await widget.onWallpaperChanged(path);

        // Step 2: apply theme using the freshly extracted shades.
        final List<String> freshShades = widget.getCurrentShades();
        if (freshShades.isNotEmpty) {
          await quickapplyTheme(freshShades[1]);
        }
        widget.onThemechange(false);
      } else {
        throw Exception("gsettings failed");
      }
    } catch (e) {
      await Process.run('notify-send', [
        '-i',
        'dialog-information',
        '-a',
        'NebulaShade',
        '-u',
        'normal',
        '-t',
        '7000',
        'Background Failed to Update',
        'Wallpaper is not set!'
      ]);
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(content: Text('Failed to set wallpaper: $e')),
      // );
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = imageFiles;

    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.isNotEmpty ? images.length : 5,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final hasImages = images.isNotEmpty;

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: hasImages
                ? GestureDetector(
                    key: ValueKey(images[index].path), // Ensure key is unique
                    onTap: () async {
                      await setAsWallpaper(images[index].path);
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.file(
                          File(images[index].path),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  )
                : Shimmer.fromColors(
                    key: ValueKey(
                        'shimmer_$index'), // Different key for placeholder
                    baseColor: AppColors.lighten(AppColors.background, 0.1),
                    highlightColor:
                        AppColors.lighten(AppColors.background, 0.9),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
                          color: Colors.grey[300],
                          child: const Center(
                            child: Icon(Icons.image, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class CustomShimmer extends StatefulWidget {
  final Widget child;

  const CustomShimmer({Key? key, required this.child}) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _CustomShimmerState createState() => _CustomShimmerState();
}

class _CustomShimmerState extends State<CustomShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 1),
    );

    _animation = Tween<double>(begin: -2, end: 2)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut))
      ..addListener(() {
        setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _controller.reverse();
        } else if (status == AnimationStatus.dismissed) {
          _controller.forward();
        }
      });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) {
        return LinearGradient(
          colors: [
            AppColors.lighten(AppColors.background, 0.3),
            Colors.deepPurpleAccent,
            AppColors.lighten(AppColors.background, 0.3),
          ],
          stops: [
            0.0,
            0.5 + _animation.value * 0.25,
            1.0,
          ],
        ).createShader(bounds);
      },
      child: widget.child,
    );
  }
}
