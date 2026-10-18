import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:first_flutter/services/mucap_client.dart';
import 'package:first_flutter/models/mucap_visual_style.dart';
import 'package:first_flutter/widgets/mucap_visualization.dart';

void main() {
  testWidgets('renders original low and high pitch colors on the timeline', (
    tester,
  ) async {
    CueVisual style(String text, String color, double offset) =>
        CueVisual.fromJson({
          'font_size': 26,
          'offset_y': offset,
          'font_weight': 400,
          'font_family': '',
          'letter_spacing_em': 0,
          'has_pitch': true,
          'characters': [
            {'text': text, 'color': color, 'opacity': .8, 'offset_y': 0},
          ],
        }, text);
    final result = MucapResult(3, 'fixture', [
      CaptionCue(
        .5,
        1.5,
        '둥',
        0,
        26,
        visual: style('둥', 'hsl(260 82% 28%)', 115),
      ),
      CaptionCue(
        1.5,
        3,
        '딩',
        1,
        26,
        visual: style('딩', 'hsl(355 82% 65%)', -115),
      ),
    ], []);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MucapVisualization(result: result, position: 1)),
      ),
    );
    final low = tester.widget<Text>(find.text('둥'));
    final high = tester.widget<Text>(find.text('딩'));
    expect(low.style!.color, HSLColor.fromAHSL(1, 260, .82, .28).toColor());
    expect(high.style!.color, HSLColor.fromAHSL(1, 355, .82, .65).toColor());
    expect(
      tester.getCenter(find.text('둥')).dy,
      greaterThan(tester.getCenter(find.text('딩')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  test('missing pitch uses neutral color and invalid HSL is rejected', () {
    expect(CueVisual.neutral('둥').glyphs.single.color.saturation, 0);
    expect(() => VisualColor.parse('hsl(355 82% 165%)'), throwsFormatException);
  });
}
