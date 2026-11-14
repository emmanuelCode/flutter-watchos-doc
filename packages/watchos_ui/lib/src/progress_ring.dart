import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Activity-style circular progress ring drawn directly on Canvas (no Material/Cupertino).
class WatchOSProgressRing extends StatelessWidget {
  const WatchOSProgressRing({
    super.key,
    required this.progress,
    this.size = 56.0,
    this.strokeWidth = 7.0,
    this.color,
    this.trackColor,
    this.child,
  });

  final double progress;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? trackColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = WatchOSTheme.of(context);
    final clamped = progress.clamp(0.0, 1.0).toDouble();
    final activeColor = color ?? theme.accentColor;
    final bgColor = trackColor ?? activeColor.withValues(alpha: 0.22);

    return Semantics(
      value: '${(clamped * 100).round()}%',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            progress: clamped,
            strokeWidth: strokeWidth,
            color: activeColor,
            trackColor: bgColor,
          ),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.max(0.0, (math.min(size.width, size.height) - strokeWidth) / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    if (progress <= 0) return;

    final activePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}
