import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/mucap_client.dart';
import '../models/mucap_visual_style.dart';

/// Mirrors audio_text_viz.py's HTML stage using its exported per-glyph styles.
/// Layout scales to the available width; font rasterization remains native.
class MucapVisualization extends StatelessWidget {
  const MucapVisualization({
    super.key,
    required this.result,
    required this.position,
  });
  final MucapResult result;
  final double position;

  @override
  Widget build(BuildContext context) {
    final duration = result.duration;
    final current = position.clamp(0.0, duration);
    final visible = math.min(7.0, duration);
    final start = (current - visible / 2).clamp(0.0, duration - visible);
    final end = start + visible;
    return Column(
      children: [
        SizedBox(
          height: 420,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              double x(double time) =>
                  ((time - start) / visible).clamp(0.0, 1.0) * width;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xff111111)),
                ),
                child: ClipRect(
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      const Positioned.fill(
                        child: CustomPaint(painter: _TimelineGrid()),
                      ),
                      for (final cue in result.captions)
                        if (cue.time >= start - .001 && cue.time <= end + .001)
                          Positioned(
                            left: x(cue.time),
                            top: 210 + (cue.visual?.offsetY ?? 0),
                            child: FractionalTranslation(
                              translation: const Offset(-.5, -.5),
                              child: _CaptionToken(
                                cue: cue,
                                popping:
                                    current - cue.time >= 0 &&
                                    current - cue.time <= .32,
                              ),
                            ),
                          ),
                      Positioned(
                        left: x(current) - 1.5,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 3, color: Colors.red),
                      ),
                      for (var second = 0; second <= duration.ceil(); second++)
                        if (second >= start - .001 && second <= end + .001)
                          Positioned(
                            left: x(second.toDouble()),
                            bottom: 8,
                            child: FractionalTranslation(
                              translation: const Offset(-.5, 0),
                              child: Text(
                                '${second}s',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text('${current.toStringAsFixed(1)} / ${duration.toStringAsFixed(1)}초'),
        if (result.captions.every((cue) => cue.visual?.hasPitch != true))
          const Text('뚜렷한 음높이를 찾지 못해 중립 색상으로 표시합니다.'),
      ],
    );
  }
}

class _CaptionToken extends StatelessWidget {
  const _CaptionToken({required this.cue, required this.popping});
  final CaptionCue cue;
  final bool popping;
  @override
  Widget build(BuildContext context) {
    final style = cue.visual ?? CueVisual.neutral(cue.text);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: popping ? 1 : 0),
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      builder: (context, amount, child) => Transform.translate(
        offset: Offset(0, -18 * amount),
        child: Transform.scale(
          scale: 1 + .12 * amount,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final glyph in style.glyphs)
            Transform.translate(
              offset: Offset(0, glyph.offsetY),
              child: Opacity(
                opacity: glyph.opacity,
                child: Text(
                  glyph.text,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: style.size,
                    fontFamily: style.family.startsWith('Georgia')
                        ? 'Georgia'
                        : 'Helvetica',
                    fontWeight: FontWeight
                        .values[(style.weight ~/ 100 - 1).clamp(0, 8)],
                    letterSpacing: style.spacingEm * style.size,
                    color: HSLColor.fromAHSL(
                      1,
                      glyph.color.hue,
                      glyph.color.saturation,
                      glyph.color.lightness,
                    ).toColor(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineGrid extends CustomPainter {
  const _TimelineGrid();
  @override
  void paint(Canvas canvas, Size size) {
    final vertical = Paint()
      ..color = const Color(0x2e000000)
      ..strokeWidth = 1;
    for (var i = 0; i < 8; i++) {
      canvas.drawLine(
        Offset(size.width * i / 8, 0),
        Offset(size.width * i / 8, size.height),
        vertical,
      );
    }
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()..color = const Color(0x14000000),
    );
    canvas.drawLine(
      Offset(0, size.height - 34),
      Offset(size.width, size.height - 34),
      Paint()..color = const Color(0x73000000),
    );
  }

  @override
  bool shouldRepaint(_TimelineGrid oldDelegate) => false;
}
