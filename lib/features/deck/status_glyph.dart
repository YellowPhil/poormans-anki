import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'card_status.dart';

class StatusGlyph extends StatelessWidget {
  const StatusGlyph(this.phase, {super.key, this.size = 16});

  final CardPhase phase;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _GlyphPainter(phase)),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.phase);

  final CardPhase phase;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 1;
    final paint = Paint()
      ..color = AppColors.textMuted
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    switch (phase) {
      case CardPhase.fresh:
        const segments = 8;
        for (var i = 0; i < segments; i++) {
          final start = i * 2 * math.pi / segments;
          canvas.drawArc(
            Rect.fromCircle(center: c, radius: r),
            start,
            math.pi / segments,
            false,
            paint,
          );
        }
      case CardPhase.learning:
        canvas.drawCircle(c, r, paint);
        canvas.drawCircle(c, r * 0.3, paint..style = PaintingStyle.fill);
      case CardPhase.review:
        canvas.drawCircle(c, r, paint);
        canvas.drawCircle(c, r * 0.6, paint);
        canvas.drawCircle(c, r * 0.2, paint..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.phase != phase;
}
