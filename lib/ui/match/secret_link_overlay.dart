import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SECRET LINK OVERLAY - Match Animation (Cinematic Transform)
// ═══════════════════════════════════════════════════════════════════════════════

/// Colors for the secret link dots
const Color _purpleDot = Color(0xFF7B5CFF);
const Color _limeDot = Color(0xFFB4F000);
const Color _linkColor = Color(0xFF7B5CFF);

/// Displays the "secret link" animation when a match occurs.
/// 
/// Features cinematic transform:
/// - Dots emerge from center and separate to diagonal positions
/// - Link stretches between dots as they move
/// - Soft-edge alpha falloff (no glow/blur)
class SecretLinkOverlay extends StatelessWidget {
  /// Dot opacity (0.0 = invisible, 1.0 = fully visible)
  final double dotOpacity;
  
  /// Dot separation progress (0.0 = both at center, 1.0 = final diagonal positions)
  final double dotSeparation;
  
  /// Link reveal progress (0.0 = no link, 1.0 = full link)
  final double linkProgress;
  
  /// Extra scale for effects
  final double scale;
  
  /// Stroke width multiplier for transition effect
  final double strokeWidthMultiplier;

  const SecretLinkOverlay({
    super.key,
    this.dotOpacity = 1.0,
    this.dotSeparation = 1.0,
    this.linkProgress = 1.0,
    this.scale = 1.0,
    this.strokeWidthMultiplier = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    if (dotOpacity <= 0) return const SizedBox.shrink();

    return RepaintBoundary(
      child: Transform.scale(
        scale: scale,
        child: CustomPaint(
          painter: _SecretLinkPainter(
            dotOpacity: dotOpacity,
            dotSeparation: dotSeparation,
            linkProgress: linkProgress,
            strokeWidthMultiplier: strokeWidthMultiplier,
          ),
          size: const Size(200, 200),
        ),
      ),
    );
  }
}

class _SecretLinkPainter extends CustomPainter {
  final double dotOpacity;
  final double dotSeparation;
  final double linkProgress;
  final double strokeWidthMultiplier;

  const _SecretLinkPainter({
    required this.dotOpacity,
    required this.dotSeparation,
    required this.linkProgress,
    this.strokeWidthMultiplier = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final center = Offset(centerX, centerY);

    // Final diagonal positions
    const purpleOffset = Offset(-18, 14);  // Lower-left
    const limeOffset = Offset(18, -14);    // Upper-right
    
    // Interpolate dot positions from center to diagonal based on separation
    final purplePos = Offset.lerp(center, center + purpleOffset, dotSeparation)!;
    final limePos = Offset.lerp(center, center + limeOffset, dotSeparation)!;

    // Draw connection line (only if linkProgress > 0)
    if (linkProgress > 0 && dotSeparation > 0.1) {
      _drawConnectionLine(canvas, purplePos, limePos, center);
    }

    // Draw dots with soft-edge alpha falloff
    _drawSoftDot(canvas, purplePos, _purpleDot, 8.0, 0.95 * dotOpacity);
    _drawSoftDot(canvas, limePos, _limeDot, 7.5, 0.90 * dotOpacity);
  }

  void _drawConnectionLine(Canvas canvas, Offset p1, Offset p2, Offset center) {
    // S-curve between the two dots
    final midX = (p1.dx + p2.dx) / 2;
    
    // Control points for S-curve (scaled by separation for natural stretch)
    final curveIntensity = dotSeparation * 15;
    final ctrl1 = Offset(midX - curveIntensity, p1.dy - curveIntensity * 0.5);
    final ctrl2 = Offset(midX + curveIntensity, p2.dy + curveIntensity * 0.5);
    
    // Create the full bezier path
    final fullPath = Path();
    fullPath.moveTo(p1.dx, p1.dy);
    fullPath.cubicTo(ctrl1.dx, ctrl1.dy, ctrl2.dx, ctrl2.dy, p2.dx, p2.dy);
    
    // Animate the reveal by drawing only a portion of the path
    // linkProgress 0 = nothing, 1 = full path
    final pathMetrics = fullPath.computeMetrics().first;
    final pathLength = pathMetrics.length;
    final drawLength = pathLength * linkProgress;
    
    if (drawLength > 0) {
      final visiblePath = pathMetrics.extractPath(0, drawLength);
      
      final linePaint = Paint()
        ..color = _linkColor.withValues(alpha: 0.22 * dotOpacity * linkProgress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * strokeWidthMultiplier
        ..strokeCap = StrokeCap.round;
      
      canvas.drawPath(visiblePath, linePaint);
    }
  }

  void _drawSoftDot(Canvas canvas, Offset center, Color color, double radius, double opacity) {
    if (opacity <= 0) return;
    
    // Soft-edge with radial alpha falloff (no blur/glow)
    final gradient = RadialGradient(
      colors: [
        color.withValues(alpha: opacity),
        color.withValues(alpha: opacity * 0.7),
        color.withValues(alpha: opacity * 0.3),
        color.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.5, 0.8, 1.0],
    );

    final rect = Rect.fromCircle(center: center, radius: radius * 1.5);
    final paint = Paint()
      ..shader = gradient.createShader(rect);

    canvas.drawCircle(center, radius * 1.5, paint);
  }

  @override
  bool shouldRepaint(covariant _SecretLinkPainter oldDelegate) {
    return oldDelegate.dotOpacity != dotOpacity ||
        oldDelegate.dotSeparation != dotSeparation ||
        oldDelegate.linkProgress != linkProgress ||
        oldDelegate.strokeWidthMultiplier != strokeWidthMultiplier;
  }
}
