class VisualColor {
  const VisualColor(this.hue, this.saturation, this.lightness);
  final double hue, saturation, lightness;
  factory VisualColor.parse(Object? value) {
    final match = RegExp(
      r'^hsl\((\d+(?:\.\d+)?) (\d+(?:\.\d+)?)% (\d+(?:\.\d+)?)%\)$',
    ).firstMatch(value is String ? value : '');
    if (match == null) throw const FormatException('시각화 색상 형식 오류');
    final h = double.parse(match[1]!),
        s = double.parse(match[2]!),
        l = double.parse(match[3]!);
    if (h > 360 || s > 100 || l > 100) {
      throw const FormatException('시각화 색상 범위 오류');
    }
    return VisualColor(h, s / 100, l / 100);
  }
}

class VisualGlyph {
  const VisualGlyph(this.text, this.color, this.opacity, this.offsetY);
  final String text;
  final VisualColor color;
  final double opacity, offsetY;
}

class CueVisual {
  const CueVisual(
    this.size,
    this.offsetY,
    this.weight,
    this.family,
    this.spacingEm,
    this.hasPitch,
    this.glyphs,
  );
  final double size, offsetY, spacingEm;
  final int weight;
  final String family;
  final bool hasPitch;
  final List<VisualGlyph> glyphs;

  factory CueVisual.fromJson(dynamic data, String text) {
    double number(dynamic value, double lo, double hi) {
      if (value is! num || !value.isFinite || value < lo || value > hi) {
        throw const FormatException('시각화 속성 범위 오류');
      }
      return value.toDouble();
    }

    if (data is! Map ||
        data['characters'] is! List ||
        data['font_weight'] is! int ||
        data['font_family'] is! String ||
        data['has_pitch'] is! bool) {
      throw const FormatException('시각화 속성 형식 오류');
    }
    final glyphs = <VisualGlyph>[];
    for (final item in data['characters']) {
      if (item is! Map || item['text'] is! String) {
        throw const FormatException('시각화 글자 형식 오류');
      }
      glyphs.add(
        VisualGlyph(
          item['text'],
          VisualColor.parse(item['color']),
          number(item['opacity'], 0, 1),
          number(item['offset_y'], -20, 20),
        ),
      );
    }
    if (glyphs.map((g) => g.text).join() != text) {
      throw const FormatException('시각화와 전사 텍스트가 다릅니다.');
    }
    final weight = number(data['font_weight'], 100, 900).toInt();
    return CueVisual(
      number(data['font_size'], 8, 120),
      number(data['offset_y'], -115, 115),
      weight,
      data['font_family'],
      number(data['letter_spacing_em'], -1, 1),
      data['has_pitch'],
      List.unmodifiable(glyphs),
    );
  }

  factory CueVisual.neutral(String text) => CueVisual(
    22.1,
    0,
    400,
    '',
    0,
    false,
    text.runes
        .map(
          (r) => VisualGlyph(
            String.fromCharCode(r),
            const VisualColor(0, 0, .35),
            1,
            0,
          ),
        )
        .toList(),
  );
}
