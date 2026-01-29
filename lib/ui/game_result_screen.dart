import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import '../app/app_coordinator.dart';
import '../app/app_phase.dart';

/// Game result screen - shows success/failure animation
/// Success: Green/Blue theme with harmony symbol
/// Failure: Red theme with X mark (reuses failed animation)
class GameResultScreen extends StatefulWidget {
  final AppCoordinator coordinator;
  final GameResultType resultType;

  const GameResultScreen({
    super.key,
    required this.coordinator,
    required this.resultType,
  });

  @override
  State<GameResultScreen> createState() => _GameResultScreenState();
}

class _GameResultScreenState extends State<GameResultScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    print("[GAME_RESULT] ===== GAME RESULT SCREEN OPENED =====");
    print("[GAME_RESULT] Result type: ${widget.resultType}");
    print("[GAME_RESULT] Mounted: true");
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // Start animation and wait for it to complete
    print("[GAME_RESULT] Starting animation (3000ms)...");
    
    // ✅ IMMEDIATE: Call coordinator BEFORE phase change (so widget doesn't get disposed)
    // The animation will play while transitioning
    if (widget.resultType == GameResultType.success) {
      // ✅ Success: Move to share screen
      print("[GAME_RESULT] SUCCESS → proceeding to share 📱");
      // Give animation 3 seconds to display before transition
      Future.delayed(const Duration(milliseconds: 3000), () {
        widget.coordinator.proceedToShare();
      });
    } else {
      // ✅ Failure: Hard reset → splash → 2s delay → pairing
      print("[GAME_RESULT] FAILURE → hard reset with splash 🔄");
      // Give animation 3 seconds to display before transition
      Future.delayed(const Duration(milliseconds: 3000), () {
        // Hard reset: clear everything and go to splash
        widget.coordinator.resetToSplash();
        
        // After 2 seconds of splash, start pairing
        Future.delayed(const Duration(milliseconds: 2000), () {
          widget.coordinator.startPairingAfterReset();
        });
      });
    }
    
    // Start the animation controller for visual effect
    _controller.forward();
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
              painter: widget.resultType == GameResultType.success
                  ? _SuccessAnimationPainter(animation: _controller)
                  : _FailureAnimationPainter(animation: _controller),
            );
          },
        ),
      ),
    );
  }
}

/// Success animation painter - harmony theme (green/blue)
class _SuccessAnimationPainter extends CustomPainter {
  final Animation<double> animation;

  _SuccessAnimationPainter({required this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = (animation.value).clamp(0.0, 1.0);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 80.0;

    // ✅ Success colors: Green/Blue for harmony and connection
    final primaryColor = Colors.green.shade700;
    final accentColor = Colors.blue.shade600;

    // Phase 1: Glow pulse (0.0 - 0.4) - GREEN glow
    if (t < 0.4) {
      final glowT = (t / 0.4).clamp(0.0, 1.0);
      final glowOpacity = (lerpDouble(0.0, 1.0, glowT) ?? 0.0).clamp(0.0, 1.0);
      final glowRadius = (lerpDouble(0, radius * 1.5, glowT) ?? 0.0).clamp(0.0, double.infinity);

      final glowPaint = Paint()
        ..color = primaryColor.withOpacity(glowOpacity * 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius * 2);
      canvas.drawCircle(center, glowRadius, glowPaint);
    }

    // Phase 2: Rings converge (0.2 - 0.75) - GREEN rings
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

      // Center glow - BLUE for harmony
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

    // Phase 3: Harmony symbol (0.75 - 1.0) - Yin-Yang / Harmony mark
    if (t >= 0.75) {
      final fadeT = ((t - 0.75) / 0.25).clamp(0.0, 1.0);

      final fadeOpacity = lerpDouble(0.8, 0.0, fadeT)!;
      final fadeRadius = lerpDouble(radius * 0.4, radius * 0.8, fadeT)!;

      final fadePaint = Paint()
        ..color = primaryColor.withOpacity(fadeOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, fadeRadius * 0.8);
      canvas.drawCircle(center, fadeRadius, fadePaint);

      // ✅ Harmony symbol: two interlocking circles
      final pulseWave = math.sin(fadeT * math.pi * 2) * 0.2;
      final symbolOpacity = 0.95;
      final symbolRadius = radius * (0.25 + fadeT * 0.2 + pulseWave);
      _drawHarmonySymbol(canvas, center, symbolRadius, Colors.green.shade400, Colors.blue.shade400, symbolOpacity);
    }
  }

  void _drawHarmonySymbol(Canvas canvas, Offset center, double radius, Color color1, Color color2, double opacity) {
    // Draw two interlocking circles (harmony/connection)
    final paint1 = Paint()
      ..color = color1.withOpacity(opacity)
      ..strokeWidth = radius * 0.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final paint2 = Paint()
      ..color = color2.withOpacity(opacity)
      ..strokeWidth = radius * 0.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Left circle
    canvas.drawCircle(center + Offset(-radius * 0.25, 0), radius * 0.4, paint1);
    // Right circle
    canvas.drawCircle(center + Offset(radius * 0.25, 0), radius * 0.4, paint2);

    // Inner glow
    final glowPaint = Paint()
      ..color = color1.withOpacity(opacity * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.2);
    canvas.drawCircle(center, radius * 1.1, glowPaint);

    // Outer glow - GREEN
    final outerGlowPaint = Paint()
      ..color = Colors.green.shade700.withOpacity(opacity * 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.06
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.15);
    canvas.drawCircle(center, radius * 1.4, outerGlowPaint);
  }

  @override
  bool shouldRepaint(covariant _SuccessAnimationPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}

/// Failure animation painter - reuse the red X theme
class _FailureAnimationPainter extends CustomPainter {
  final Animation<double> animation;

  _FailureAnimationPainter({required this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = (animation.value).clamp(0.0, 1.0);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 80.0;

    // ✅ Negative color: Dark red/crimson for failure feeling
    final primaryColor = Colors.red.shade900;
    final accentColor = Colors.orange.shade800;

    // Phase 1: Glow pulse (0.0 - 0.4) - RED glow
    if (t < 0.4) {
      final glowT = (t / 0.4).clamp(0.0, 1.0);
      final glowOpacity = (lerpDouble(0.0, 1.0, glowT) ?? 0.0).clamp(0.0, 1.0);
      final glowRadius = (lerpDouble(0, radius * 1.5, glowT) ?? 0.0).clamp(0.0, double.infinity);

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

    // Phase 3: Failure X mark (0.75 - 1.0)
    if (t >= 0.75) {
      final fadeT = ((t - 0.75) / 0.25).clamp(0.0, 1.0);

      final fadeOpacity = lerpDouble(0.8, 0.0, fadeT)!;
      final fadeRadius = lerpDouble(radius * 0.4, radius * 0.8, fadeT)!;

      final fadePaint = Paint()
        ..color = primaryColor.withOpacity(fadeOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, fadeRadius * 0.8);
      canvas.drawCircle(center, fadeRadius, fadePaint);

      // ✅ X mark for failure
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
    path.moveTo(center.dx - radius * 0.35, center.dy - radius * 0.35);
    path.lineTo(center.dx + radius * 0.35, center.dy + radius * 0.35);
    
    path.moveTo(center.dx + radius * 0.35, center.dy - radius * 0.35);
    path.lineTo(center.dx - radius * 0.35, center.dy + radius * 0.35);

    canvas.drawPath(path, paint);

    final glowPaint = Paint()
      ..color = color.withOpacity(opacity * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.2);
    canvas.drawCircle(center, radius * 1.1, glowPaint);

    final outerGlowPaint = Paint()
      ..color = Colors.red.shade900.withOpacity(opacity * 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.06
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.15);
    canvas.drawCircle(center, radius * 1.4, outerGlowPaint);
  }

  @override
  bool shouldRepaint(covariant _FailureAnimationPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}
