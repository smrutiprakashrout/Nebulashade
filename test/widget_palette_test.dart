import 'package:flutter_test/flutter_test.dart';
import 'package:nebulashade/services/widget_palette.dart';

void main() {
  test('matches the widget palette values for slots 2 and 4', () {
    const colors = [
      0xf4e5b1,
      0x310f02,
      0x6b1403,
      0xcea14f,
      0xb3350a,
      0xe0bb71,
      0x852c08,
    ];
    final slot2 = WidgetPalette.fromColors(colors, 2);
    expect(WidgetPalette.hex(slot2.widgetBg), '#332824');
    expect(WidgetPalette.hex(slot2.light), '#FFE1D6');
    expect(WidgetPalette.hex(slot2.accent), '#CC7656');
    expect(WidgetPalette.hex(slot2.dark), '#BA613F');

    final slot4 = WidgetPalette.fromColors(colors, 4);
    expect(WidgetPalette.hex(slot4.window), '#332E24');
    expect(WidgetPalette.hex(slot4.sidebar), '#29251D');
    expect(WidgetPalette.hex(slot4.popover), '#231F18');
    expect(WidgetPalette.hex(slot4.accent), '#CCA256');
  });
}
