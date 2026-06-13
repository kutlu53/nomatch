import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/game_colors.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// RADAR RINGS - Minimal Premium Design
// ═══════════════════════════════════════════════════════════════════════════════

/// Color constant for radar rings - neutral, neither purple nor lime
const Color _ringColor = Color(0xFFEDEBFF);

/// UI states for the radar/scan screen
enum ScanUiState { idle, scanning, matched }

/// Minimal radar rings with breathing opacity animation.
/// 
/// Features:
/// - 4 evenly spaced hairline circles
/// - No glow, blur, or shadows
/// - Subtle opacity breathing (1.0 → 0.6 → 1.0)
/// - 3.5s animation cycle with easeInOut
/// - Scanning mode: Sequential ring phase animation
/// - Collapse mode: Rings scale down to center and fade out
class RadarRingsWidget extends StatefulWidget {
  final bool isScanning;
  
  /// Collapse animation progress (0.0 = normal, 1.0 = fully collapsed)
  final double collapseProgress;
  
  /// Opacity override for freeze effect (null = use normal calculation)
  final double? freezeOpacity;

  /// ✅ Heading doğrulaması retry uyarısı için pulse opaklığı (0.0 - 1.0).
  /// 0 ise normal renk; >0 olduğunda halkalar kırmızıya doğru karışır.
  final double alertOpacity;

  const RadarRingsWidget({
    super.key,
    this.isScanning = false,
    this.collapseProgress = 0.0,
    this.freezeOpacity,
    this.alertOpacity = 0.0,
  });

  @override
  State<RadarRingsWidget> createState() => _RadarRingsWidgetState();
}

class _RadarRingsWidgetState extends State<RadarRingsWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600), // Phase loop duration
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant RadarRingsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Stop animation when freezeOpacity is set (matched state)
    if (widget.freezeOpacity != null && _animController.isAnimating) {
      _animController.stop();
    } else if (widget.freezeOpacity == null && !_animController.isAnimating) {
      _animController.repeat();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          return CustomPaint(
            painter: RadarRingsPainter(
              isScanning: widget.isScanning,
              animationValue: _animController.value,
              collapseProgress: widget.collapseProgress,
              freezeOpacity: widget.freezeOpacity,
              alertOpacity: widget.alertOpacity,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

/// CustomPainter for minimal radar rings.
/// 
/// Draws 4 evenly spaced concentric circles with:
/// - strokeWidth: 1.0 (hairline)
/// - Base opacity: 0.06, active ring: 0.10 when scanning
/// - No glow or effects
/// - Scanning: Sequential phase animation (inner to outer)
/// - Collapse: Rings scale down to center with stagger (outer to inner)
class RadarRingsPainter extends CustomPainter {
  final bool isScanning;
  final double animationValue; // 0.0 - 1.0 for phase animation
  final double collapseProgress; // 0.0 = normal, 1.0 = fully collapsed
  final double? freezeOpacity; // Override opacity when matched (freeze state)
  final double alertOpacity; // ✅ Heading retry uyarı pulse'ı (0.0 - 1.0)

  const RadarRingsPainter({
    this.isScanning = false,
    this.animationValue = 0.0,
    this.collapseProgress = 0.0,
    this.freezeOpacity,
    this.alertOpacity = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) * 0.42;

    const ringCount = 4;
    const baseOpacity = 0.06;
    const activeOpacity = 0.10;
    const delayPerRing = 0.25; // 250ms / 1000ms = 0.25 of animation cycle
    const collapseStaggerDelay = 0.1; // 40ms / 350ms ≈ 0.1

    for (int i = 1; i <= ringCount; i++) {
      // Calculate collapse for this ring (outer rings collapse first)
      double ringScale = 1.0;
      double ringCollapseOpacity = 1.0;
      
      if (collapseProgress > 0) {
        // Outer rings (higher i) start collapsing first
        final ringIndex = ringCount - i; // Reverse: outer = 0, inner = 3
        final ringCollapseStart = ringIndex * collapseStaggerDelay;
        final ringCollapseProgress = ((collapseProgress - ringCollapseStart) / (1.0 - ringCollapseStart)).clamp(0.0, 1.0);
        
        // Ease-in curve for scale collapse
        final easedProgress = Curves.easeIn.transform(ringCollapseProgress);
        ringScale = 1.0 - easedProgress;
        ringCollapseOpacity = 1.0 - easedProgress;
      }
      
      if (ringScale <= 0) continue; // Skip fully collapsed rings
      
      final baseRadius = maxRadius * (i / ringCount);
      final radius = baseRadius * ringScale;
      
      double ringOpacity;
      if (freezeOpacity != null) {
        // Frozen state (matched) - use override opacity
        ringOpacity = freezeOpacity! * ringCollapseOpacity;
      } else if (isScanning) {
        // Sequential phase: each ring activates with delay
        final ringPhase = (animationValue - (i - 1) * delayPerRing) % 1.0;
        // Active for ~40% of the cycle, then fade
        final activePhase = ringPhase < 0.4 
            ? (ringPhase / 0.4) // Fade in
            : ringPhase < 0.6 
                ? 1.0 // Hold
                : 1.0 - ((ringPhase - 0.6) / 0.4); // Fade out
        ringOpacity = (baseOpacity + (activeOpacity - baseOpacity) * activePhase.clamp(0.0, 1.0)) * ringCollapseOpacity;
      } else {
        // Static with very subtle breathing
        final breathe = 0.85 + 0.15 * math.sin(animationValue * math.pi * 2);
        ringOpacity = 0.08 * breathe * ringCollapseOpacity;
      }
      
      // ✅ Heading retry uyarısı: halka rengini kırmızıya doğru karıştır,
      // opaklığı ve kalınlığı artır.
      final color = alertOpacity > 0
          ? Color.lerp(_ringColor, GameColors.failurePrimary, alertOpacity)!
          : _ringColor;
      final opacity = ringOpacity + (activeOpacity * 4) * alertOpacity;
      final strokeWidth = 1.0 + alertOpacity;

      final ringPaint = Paint()
        ..color = color.withOpacity(opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth; // Hairline (alert sırasında kalınlaşır)

      canvas.drawCircle(center, radius, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant RadarRingsPainter oldDelegate) {
    return oldDelegate.isScanning != isScanning ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.collapseProgress != collapseProgress ||
        oldDelegate.freezeOpacity != freezeOpacity ||
        oldDelegate.alertOpacity != alertOpacity;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MINIMAL CENTER CROSSHAIR
// ═══════════════════════════════════════════════════════════════════════════════

/// Minimal center crosshair - very subtle
class CenterCrosshairPainter extends CustomPainter {
  final double opacity;

  const CenterCrosshairPainter({this.opacity = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.42;

    final crossPaint = Paint()
      ..color = _ringColor.withOpacity(0.06 * opacity)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    // Very short crosshair lines
    final len = radius * 0.08;
    canvas.drawLine(
      Offset(center.dx - len, center.dy),
      Offset(center.dx + len, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - len),
      Offset(center.dx, center.dy + len),
      crossPaint,
    );

    // Tiny center dot
    final dotPaint = Paint()
      ..color = _ringColor.withOpacity(0.10 * opacity);
    canvas.drawCircle(center, 1.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CenterCrosshairPainter oldDelegate) {
    return oldDelegate.opacity != opacity;
  }
}
