import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Lightweight failure screen with alternative animation
class SoftMissView extends StatefulWidget {
  final VoidCallback onComplete;

  const SoftMissView({
    super.key,
    required this.onComplete,
  });

  @override
  State<SoftMissView> createState() => _SoftMissViewState();
}

class _SoftMissViewState extends State<SoftMissView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    print("[SOFT_MISS_VIEW] Initialized! 🎬");
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // Start animation immediately
    _controller.forward().then((_) {
      // Wait a bit before dismissing
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          widget.onComplete();
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0A0A12), // Dark background
      child: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _MissAnimationPainter(
                animation: _controller,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Failure animation painter - similar to success but with negative colors and X mark
class _MissAnimationPainter extends CustomPainter {
  final Animation<double> animation;

  _MissAnimationPainter({required this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 80.0;

    // ✅ Negative color: Dark red/crimson for failure feeling
    final primaryColor = Colors.red.shade900;
    final accentColor = Colors.orange.shade800;

    // Phase 1: Glow pulse (0.0 - 0.4) - RED glow
    if (t < 0.4) {
      final glowT = (t / 0.4).clamp(0.0, 1.0);
      final glowOpacity = lerpDouble(0.0, 1.0, glowT)!;
      final glowRadius = lerpDouble(0, radius * 1.5, glowT)!;

      final glowPaint = Paint()
        ..color = primaryColor.withOpacity(glowOpacity * 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius * 2);
      canvas.drawCircle(center, glowRadius, glowPaint);
    }

    // Phase 2: Rings converge (0.2 - 0.75) - RED rings
    if (t >= 0.2 && t < 0.75) {
      final ringT = ((t - 0.2) / 0.55).clamp(0.0, 1.0);
      final easeT = Curves.easeInOut.transform(ringT);

      final ring1Start = radius * 1.5;
      final ring2Start = radius * 1.8;
      final ring1Radius = lerpDouble(ring1Start, 0, easeT)!;
      final ring2Radius = lerpDouble(ring2Start, 0, easeT)!;

      final ringOpacity = lerpDouble(0.1, 1.0, ringT)!;

      final ringPaint = Paint()
        ..color = primaryColor.withOpacity(ringOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = lerpDouble(3.0, 16.0, ringT)!
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lerpDouble(6.0, 20.0, ringT)!);

      if (ring1Radius > 0) {
        canvas.drawCircle(center, ring1Radius, ringPaint);
      }
      if (ring2Radius > 0) {
        canvas.drawCircle(center, ring2Radius, ringPaint);
      }

      // Center glow - ORANGE for warning
      if (ringT > 0.5) {
        final mergeT = ((ringT - 0.5) / 0.5).clamp(0.0, 1.0);
        final mergeRadius = lerpDouble(0, radius * 0.5, mergeT)!;
        final mergeOpacity = lerpDouble(0.0, 0.8, mergeT)!;

        final mergePaint = Paint()
          ..color = accentColor.withOpacity(mergeOpacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, mergeRadius * 1.2);
        canvas.drawCircle(center, mergeRadius, mergePaint);
      }
    }

    // Phase 3: Failure X mark (0.75 - 1.0) - instead of checkmark
    if (t >= 0.75) {
      final fadeT = ((t - 0.75) / 0.25).clamp(0.0, 1.0);

      final fadeOpacity = lerpDouble(0.8, 0.0, fadeT)!;
      final fadeRadius = lerpDouble(radius * 0.4, radius * 0.8, fadeT)!;

      final fadePaint = Paint()
        ..color = primaryColor.withOpacity(fadeOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, fadeRadius * 0.8);
      canvas.drawCircle(center, fadeRadius, fadePaint);

      // ✅ X mark instead of checkmark
      final pulseWave = math.sin(fadeT * math.pi * 2) * 0.2;
      final xOpacity = 0.95;
      final xRadius = radius * (0.25 + fadeT * 0.2 + pulseWave);
      _drawXMark(canvas, center, xRadius, Colors.red.shade400, xOpacity);
    }
  }

  void _drawXMark(Canvas canvas, Offset center, double radius, Color color, double opacity) {
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeWidth = radius * 0.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    
    // Draw X: two diagonal lines
    // First diagonal (top-left to bottom-right)
    path.moveTo(center.dx - radius * 0.35, center.dy - radius * 0.35);
    path.lineTo(center.dx + radius * 0.35, center.dy + radius * 0.35);
    
    // Second diagonal (top-right to bottom-left)
    path.moveTo(center.dx + radius * 0.35, center.dy - radius * 0.35);
    path.lineTo(center.dx - radius * 0.35, center.dy + radius * 0.35);

    canvas.drawPath(path, paint);

    // Inner glow - RED
    final glowPaint = Paint()
      ..color = color.withOpacity(opacity * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.2);
    canvas.drawCircle(center, radius * 1.1, glowPaint);

    // Outer glow - DARK RED
    final outerGlowPaint = Paint()
      ..color = Colors.red.shade900.withOpacity(opacity * 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.06
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.15);
    canvas.drawCircle(center, radius * 1.4, outerGlowPaint);
  }

  @override
  bool shouldRepaint(covariant _MissAnimationPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}
