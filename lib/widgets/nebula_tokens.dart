import 'package:flutter/material.dart';

class NebulaRadius {
  static const double control = 6;
  static const double card = 8;
  static const double panel = 10;
  static const double strip = 0;
  static const double chip = 4;
}

class NebulaSize {
  static const double control = 40;
  static const double tab = 42;
  static const double swatch = 44;
  static const double handle = 28;
  static const double switchW = 58;
  static const double switchH = 30;
  static const double thumb = 24;
  static const double gap = 8;
  static const double pad = 14;
}

Color shiftLightness(Color color, double delta) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
}

double luminanceOn(Color bg) => bg.computeLuminance();

Color onColor(Color bg) =>
    luminanceOn(bg) > 0.5 ? const Color(0xFF2F2418) : Colors.white;

class NebulaSurface {
  final Color base;
  NebulaSurface(this.base);

  Color get card => shiftLightness(base, 0.20);
  Color get control => shiftLightness(card, -0.07);
  Color get controlSelected => shiftLightness(card, 0.12);
  Color get track => shiftLightness(card, 0.06);
  Color get tabActive => shiftLightness(base, -0.15);
  Color get field => base;
  Color get cream => const Color(0xFFF3ECE4);
  Color get text => Colors.white;
  Color get muted => const Color(0xFFD9CDBF);
  Color get tagOkBg => const Color(0xFF8A8D63);
  Color get tagOkFg => const Color(0xFFF3F0D9);
  Color get tagNoBg => const Color(0xFF8A5A52);
  Color get tagNoFg => const Color(0xFFFBE3DE);
  Color get tagWarnBg => const Color(0xFF9A7F4A);
  Color get tagWarnFg => const Color(0xFFFFF1D6);
}

class NebulaTokens {
  static Color accentFrom(List<Color> palette) {
    Color? best;
    var saturation = -1.0;
    for (final color in palette) {
      final hsl = HSLColor.fromColor(color);
      if (hsl.lightness >= 0.45 &&
          hsl.lightness <= 0.8 &&
          hsl.saturation >= 0.4 &&
          hsl.saturation > saturation) {
        best = color;
        saturation = hsl.saturation;
      }
    }
    return best ?? const Color(0xFFF98E65);
  }
}

class NebulaTabBar extends StatelessWidget {
  const NebulaTabBar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    required this.surface,
    this.keys,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final NebulaSurface surface;
  final List<Key>? keys;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: surface.track,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == selectedIndex,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: keys != null && i < keys!.length ? keys![i] : null,
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => onChanged(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        height: NebulaSize.tab,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == selectedIndex
                              ? surface.tabActive
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: i == selectedIndex
                              ? const [
                                  BoxShadow(
                                    color: Color(0x59000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            color: i == selectedIndex
                                ? Colors.white
                                : const Color(0xFFECE3D8),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
}

class NebulaModeSwitch extends StatelessWidget {
  const NebulaModeSwitch({
    super.key,
    required this.isLight,
    required this.enabled,
    required this.onChanged,
    required this.surface,
  });

  final bool isLight;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final NebulaSurface surface;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        toggled: isLight,
        enabled: enabled,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: enabled ? () => onChanged(!isLight) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: NebulaSize.switchW,
              height: NebulaSize.switchH,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: enabled ? surface.tabActive : surface.control,
                borderRadius: BorderRadius.circular(8),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 160),
                alignment:
                    isLight ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: NebulaSize.thumb,
                  height: NebulaSize.thumb,
                  decoration: BoxDecoration(
                    color: enabled
                        ? surface.cream
                        : shiftLightness(surface.card, 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    isLight
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    size: 14,
                    color: enabled ? const Color(0xFF2F2418) : surface.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class DashedRectPainter extends CustomPainter {
  const DashedRectPainter(this.color, {this.strokeWidth = 2, this.radius = 4});
  final Color color;
  final double strokeWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2,
            size.width - strokeWidth, size.height - strokeWidth),
        Radius.circular(radius),
      ));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 6).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.radius != radius;
}
