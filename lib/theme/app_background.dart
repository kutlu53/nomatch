import 'dart:math' as math;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// INK PLUM DESIGN SYSTEM - Color Tokens
// ═══════════════════════════════════════════════════════════════════════════════

/// Ink Plum color palette - premium dark theme
class InkPlum {
  InkPlum._();

  /// Base background color - main canvas
  static const Color base = Color(0xFF191423);

  /// Edge color - vignette outer areas
  static const Color edge = Color(0xFF120E1A);

  /// Surface color - for cards and elevated elements
  static const Color surface = Color(0xFF231B31);
}

// ═══════════════════════════════════════════════════════════════════════════════
// APP BACKGROUND WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Premium app background with Ink Plum theme.
/// 
/// Layers:
/// 1. Flat base color
/// 2. Subtle vignette (radial gradient - darker at edges)
/// 3. Very light grain/noise texture (~3% opacity)
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: InkPlum.base,
      child: Stack(
        children: [
          // Layer A: Base color (already set on Container)
          
          // Layer B: Vignette overlay
          const Positioned.fill(
            child: _VignetteLayer(),
          ),
          
          // Layer C: Grain/Noise texture
          const Positioned.fill(
            child: RepaintBoundary(
              child: _GrainLayer(),
            ),
          ),
          
          // Content
          Positioned.fill(
            child: child,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VIGNETTE LAYER
// ═══════════════════════════════════════════════════════════════════════════════

class _VignetteLayer extends StatelessWidget {
  const _VignetteLayer();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.0, -0.2), // Slightly above center
          radius: 1.1,
          colors: [
            InkPlum.base.withValues(alpha: 0.0),  // Center: transparent
            InkPlum.base.withValues(alpha: 0.0),  // Near zone: still transparent
            InkPlum.edge.withValues(alpha: 0.30), // Edges: very subtle darkening
          ],
          stops: const [0.0, 0.70, 1.0],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GRAIN/NOISE LAYER
// ═══════════════════════════════════════════════════════════════════════════════

class _GrainLayer extends StatelessWidget {
  const _GrainLayer();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _GrainPainter(),
      isComplex: true,
      willChange: false,
    );
  }
}

/// Paints a very subtle grain/noise texture - fine speckle, not texture-like
class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42); // Fixed seed for consistent pattern
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.025) // ~2.5% opacity - very subtle
      ..strokeWidth = 0.5
      ..strokeCap = StrokeCap.round;

    // Finer grain: smaller dots, sparser distribution
    final area = size.width * size.height;
    final dotCount = (area / 80).round(); // Less dense

    for (int i = 0; i < dotCount; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), 0.35, paint); // Smaller dots
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
