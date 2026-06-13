import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

class RadarPairingView extends StatefulWidget {
  final String? focusCandidatePeerId;
  final bool focusCandidateLocked;
  final bool pairHandshakeComplete;
  final bool isConnectingTransition;
  final bool isScanning; // ✅ Radar rings phase animation

  // ✅ NEW: Match animation parameters
  final double collapseProgress; // 0.0 = normal, 1.0 = fully collapsed
  final double? freezeOpacity; // Override opacity when matched

  /// ✅ Heading doğrulaması retry uyarısı için pulse opaklığı (0.0 - 1.0)
  final double alertOpacity;

  const RadarPairingView({
    super.key,
    required this.focusCandidatePeerId,
    required this.focusCandidateLocked,
    required this.pairHandshakeComplete,
    this.isConnectingTransition = false,
    this.isScanning = false,
    this.collapseProgress = 0.0, // ✅ NEW
    this.freezeOpacity, // ✅ NEW
    this.alertOpacity = 0.0,
  });

  @override
  State<RadarPairingView> createState() => _RadarPairingViewState();
}

class _RadarPairingViewState extends State<RadarPairingView> with TickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  // Connection transition animation
  AnimationController? _transitionController;
  Animation<double>? _transitionAnimation;

  @override
  void initState() {
    super.initState();
    if (widget.isConnectingTransition) {
      _startTransitionAnimation();
    }
  }

  @override
  void didUpdateWidget(covariant RadarPairingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusCandidatePeerId == null) {
      _ticker.stop();
    } else if (!_ticker.isAnimating) {
      _ticker.repeat();
    }

    // Handle transition animation
    if (widget.isConnectingTransition != oldWidget.isConnectingTransition) {
      if (widget.isConnectingTransition) {
        _startTransitionAnimation();
      } else {
        _stopTransitionAnimation();
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _transitionController?.dispose();
    super.dispose();
  }

  void _startTransitionAnimation() {
    _transitionController?.dispose();
    _transitionController = AnimationController(
      vsync: this,
      // ✅ ENHANCED: Longer animation (3 seconds) for dramatic effect
      duration: const Duration(milliseconds: 3000),
    );
    _transitionAnimation = CurvedAnimation(
      parent: _transitionController!,
      // ✅ ENHANCED: Dramatic easing for epic feel
      curve: Curves.easeInOutQuart,
    );
    _transitionController!.forward();
  }

  void _stopTransitionAnimation() {
    _transitionController?.dispose();
    _transitionController = null;
    _transitionAnimation = null;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.expand(
        child: Stack(
          children: [
            // Bağlantı durumuna göre merkez spinner
            SizedBox.expand(
              child: CustomPaint(
                painter: _RadarPainter(
                  repaint: _ticker,
                  focusCandidatePeerId: widget.focusCandidatePeerId,
                  focusCandidateLocked: widget.focusCandidateLocked,
                  pairHandshakeComplete: widget.pairHandshakeComplete,
                  isConnectingTransition: widget.isConnectingTransition,
                ),
              ),
            ),
            // Connection transition overlay
            if (widget.isConnectingTransition && _transitionAnimation != null)
              SizedBox.expand(
                child: CustomPaint(
                  painter: _ConnectionTransitionPainter(
                    animation: _transitionAnimation!,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final Animation<double> repaint;
  final String? focusCandidatePeerId;
  final bool focusCandidateLocked;
  final bool pairHandshakeComplete;
  final bool isConnectingTransition;

  _RadarPainter({
    required this.repaint,
    required this.focusCandidatePeerId,
    required this.focusCandidateLocked,
    required this.pairHandshakeComplete,
    this.isConnectingTransition = false,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.42;

    // Center spinner for connecting/handshake
    if ((focusCandidateLocked || pairHandshakeComplete) && focusCandidatePeerId != null) {
      _drawCenterSpinner(canvas, center, radius, isConnectingTransition);
    }
  }

  void _drawCenterSpinner(Canvas canvas, Offset center, double radius, bool isConnectingTransition) {
    // ✨ Hafif center spinner
    final spinnerRadius = radius * 0.1;
    final spinnerSpeed = 1.2;
    final spinnerAngle = repaint.value * math.pi * 2 * spinnerSpeed;

    // ✨ Daha az segment, daha hafif
    final segmentCount = 6;
    final segmentAngle = (math.pi * 2) / segmentCount;

    for (int i = 0; i < segmentCount; i++) {
      final segmentStart = spinnerAngle + (i * segmentAngle);
      final segmentOpacity = (i / segmentCount) * 0.4 + 0.1;  // Daha hafif

      final spinnerPaint = Paint()
        ..color = Colors.cyan.withOpacity(segmentOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8  // Daha ince
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: spinnerRadius),
        segmentStart,
        segmentAngle * 0.6,
        false,
        spinnerPaint,
      );
    }

    // ✨ Çok hafif outer ring
    final outerSpinnerPaint = Paint()
      ..color = Colors.cyan.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, spinnerRadius * 1.2, outerSpinnerPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.focusCandidatePeerId != focusCandidatePeerId ||
        oldDelegate.focusCandidateLocked != focusCandidateLocked ||
        oldDelegate.pairHandshakeComplete != pairHandshakeComplete ||
        oldDelegate.isConnectingTransition != isConnectingTransition;
  }
}

/// Painter for connection transition overlay animation
class _ConnectionTransitionPainter extends CustomPainter {
  final Animation<double> animation;

  _ConnectionTransitionPainter({
    required this.animation,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final t = animation.value;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.42;

    final targetPosition = center;
    const targetColor = Colors.cyan;

    // Animation phases:
    // 0.0 - 0.3: Target peer brightens
    // 0.2 - 0.7: Two rings move toward center and merge
    // 0.7 - 1.0: Fade out

    // Phase 1: Target peer brightness (0.0 - 0.4) - ENHANCED
    if (t < 0.4) {
      final brightT = (t / 0.4).clamp(0.0, 1.0);
      final brightOpacity = lerpDouble(0.0, 1.0, brightT)!;
      final brightRadius = radius * 0.16; // ✅ LARGER

      // ✅ ENHANCED: Stronger outer glow
      final glowPaint = Paint()
        ..color = targetColor.withOpacity(brightOpacity * 0.7)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, brightRadius * 3.0);
      canvas.drawCircle(targetPosition, brightRadius * 3.5, glowPaint);

      // ✅ ENHANCED: Brighter core
      final corePaint = Paint()
        ..color = targetColor.withOpacity(brightOpacity * 1.2);
      canvas.drawCircle(targetPosition, brightRadius, corePaint);
    }

    // Phase 2: Two rings move toward center and merge (0.2 - 0.75) - ENHANCED
    if (t >= 0.2 && t < 0.75) {
      final ringT = ((t - 0.2) / 0.55).clamp(0.0, 1.0);
      final easeT = Curves.easeInOut.transform(ringT);

      // ✅ ENHANCED: Rings start further out for more dramatic effect
      final ring1Start = radius * 1.5;
      final ring2Start = radius * 1.8;
      final ring1Radius = lerpDouble(ring1Start, 0, easeT)!;
      final ring2Radius = lerpDouble(ring2Start, 0, easeT)!;

      // ✅ ENHANCED: Opacity increases more dramatically
      final ringOpacity = lerpDouble(0.1, 1.0, ringT)!;

      // ✅ ENHANCED: Thicker and more glowing
      final ringPaint = Paint()
        ..color = targetColor.withOpacity(ringOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = lerpDouble(3.0, 16.0, ringT)! // Much thicker
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lerpDouble(6.0, 20.0, ringT)!); // More glow

      if (ring1Radius > 0) {
        canvas.drawCircle(center, ring1Radius, ringPaint);
      }
      if (ring2Radius > 0) {
        canvas.drawCircle(center, ring2Radius, ringPaint);
      }

      // ✅ ENHANCED: Stronger center glow
      if (ringT > 0.5) {
        final mergeT = ((ringT - 0.5) / 0.5).clamp(0.0, 1.0);
        final mergeRadius = lerpDouble(0, radius * 0.5, mergeT)!;
        final mergeOpacity = lerpDouble(0.0, 0.8, mergeT)!;

        final mergePaint = Paint()
          ..color = targetColor.withOpacity(mergeOpacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, mergeRadius * 1.2);
        canvas.drawCircle(center, mergeRadius, mergePaint);
      }
    }

    // Phase 3: Fade out & Success checkmark (0.75 - 1.0) - ENHANCED
    if (t >= 0.75) {
      final fadeT = ((t - 0.75) / 0.25).clamp(0.0, 1.0);

      // ✅ ENHANCED: Background circle fades out more gradually
      final fadeOpacity = lerpDouble(0.8, 0.0, fadeT)!;
      final fadeRadius = lerpDouble(radius * 0.4, radius * 0.8, fadeT)!;

      final fadePaint = Paint()
        ..color = targetColor.withOpacity(fadeOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, fadeRadius * 0.8);
      canvas.drawCircle(center, fadeRadius, fadePaint);

      // ✅ ENHANCED: Green checkmark - much more prominent
      final pulseWave = math.sin(fadeT * math.pi * 2) * 0.2; // Double pulse frequency
      final checkOpacity = 0.95; // Much brighter
      final checkRadius = radius * (0.25 + fadeT * 0.2 + pulseWave);
      _drawCheckmark(canvas, center, checkRadius, Colors.green.shade400, checkOpacity);
    }
  }

  /// ✅ ENHANCED: Draw success checkmark - much more prominent
  void _drawCheckmark(Canvas canvas, Offset center, double radius, Color color, double opacity) {
    // ✅ ENHANCED: Thicker, more visible checkmark
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeWidth = radius * 0.2 // Much thicker
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Draw checkmark: ✓ (larger proportions)
    final path = Path();

    // Left part of check (diagonal down-right)
    path.moveTo(center.dx - radius * 0.3, center.dy + radius * 0.05);
    path.lineTo(center.dx - radius * 0.05, center.dy + radius * 0.3);

    // Right part of check (diagonal up-right)
    path.lineTo(center.dx + radius * 0.4, center.dy - radius * 0.25);

    canvas.drawPath(path, paint);

    // ✅ ENHANCED: Glowing circle around checkmark
    final glowPaint = Paint()
      ..color = color.withOpacity(opacity * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12 // Thicker circle
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.2); // More glow
    canvas.drawCircle(center, radius * 1.1, glowPaint);

    // ✅ ENHANCED: Outer ring glow
    final outerGlowPaint = Paint()
      ..color = color.withOpacity(opacity * 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.06
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.15);
    canvas.drawCircle(center, radius * 1.4, outerGlowPaint);
  }

  @override
  bool shouldRepaint(covariant _ConnectionTransitionPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}
