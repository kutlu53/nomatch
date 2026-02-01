import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import '../app/pairing_manager.dart';

/// Eşleşme başarısızlık ekranı - tragic animasyon
class PairingFailedScreen extends StatefulWidget {
  final PairingManager pairingManager;

  const PairingFailedScreen({
    super.key,
    required this.pairingManager,
  });

  @override
  State<PairingFailedScreen> createState() => _PairingFailedScreenState();
}

class _PairingFailedScreenState extends State<PairingFailedScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutQuart,
    );

    _controller.forward();

    // Pairing ekranına geri dön 4 saniye sonra
    Future.delayed(const Duration(milliseconds: 4000), () {
      if (mounted) {
        // TODO: Restart pairing
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 🖤 Dark romantic background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1A1A2E), // Very dark blue
                  Color(0xFF16213E), // Dark navy
                  Color(0xFF0F3460), // Dark red-blue
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // Broken hearts animation (center'da)
          Center(
            child: CustomPaint(
              painter: _BrokenHeartsPainter(_animation),
              size: const Size(400, 400),
            ),
          ),
          // Sad particles (overlay - kalpları sarar ama transparent)
          CustomPaint(
            painter: _SadParticlesPainter(_animation),
            size: Size.infinite,
          ),
        ],
      ),
    );
  }
}

/// Falling particles animation
class _SadParticlesPainter extends CustomPainter {
  final Animation<double> animation;

  _SadParticlesPainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final paint = Paint()..style = PaintingStyle.fill;

    // ✅ Partiküller sadece Phase 3'te (0.75 - 1.0) gösterilir
    if (t >= 0.75) {
      final particleT = ((t - 0.75) / 0.25).clamp(0.0, 1.0);
      
      // Düşen partiküller (kalplar parçalandıktan sonra)
      for (int i = 0; i < 8; i++) {
        final angle = (i * (2 * math.pi / 8));
        final fallDistance = particleT * size.height * 0.5;
        final x = size.width / 2 + math.cos(angle) * (50 + particleT * 100);
        final y = (size.height / 2) + fallDistance;
        final opacity = math.max(0, 1.0 - (particleT * 2));
        final radius = 2 + (particleT * 3);

        paint.color = Colors.red.withOpacity(opacity * 0.6);
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SadParticlesPainter oldDelegate) => true;
}

/// Broken hearts animation
class _BrokenHeartsPainter extends CustomPainter {
  final Animation<double> animation;

  _BrokenHeartsPainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final center = Offset(size.width / 2, size.height / 2);
    final heartSize = 60.0;

    // Phase 1: Hearts appear and glow (0.0 - 0.3)
    if (t < 0.3) {
      final appearT = (t / 0.3).clamp(0.0, 1.0);
      final scaleT = Curves.elasticOut.transform(appearT);
      final scale = lerpDouble(0.0, 1.0, scaleT)!;
      final opacity = appearT;

      // Left heart (red)
      _drawHeart(canvas, 
        Offset(center.dx - 80, center.dy - 40),
        heartSize * scale,
        Colors.red.withOpacity(opacity),
      );

      // Right heart (red)
      _drawHeart(canvas,
        Offset(center.dx + 80, center.dy - 40),
        heartSize * scale,
        Colors.red.withOpacity(opacity),
      );
    }

    // Phase 2: Hearts move toward each other, struggle (0.2 - 0.8)
    if (t >= 0.2 && t < 0.8) {
      final moveT = ((t - 0.2) / 0.6).clamp(0.0, 1.0);
      
      // Easing function: ease in out, but with struggle effect
      final easeT = Curves.easeInOutCubic.transform(moveT);
      
      // Struggle effect: oscillate around the movement path
      final struggle = math.sin(moveT * math.pi * 6) * (1.0 - moveT) * 15;
      
      // Left heart moves right
      final leftX = center.dx - 80 + (easeT * 70) + struggle;
      final leftY = center.dy - 40 - (moveT * 20);
      
      // Right heart moves left
      final rightX = center.dx + 80 - (easeT * 70) - struggle;
      final rightY = center.dy - 40 - (moveT * 20);

      // Rotation based on struggle
      final leftRotation = struggle * 0.02;
      final rightRotation = -struggle * 0.02;

      final opacity = 1.0 - (moveT * 0.3);

      // Draw with rotation
      canvas.save();
      canvas.translate(leftX, leftY);
      canvas.rotate(leftRotation);
      _drawHeart(canvas, 
        Offset.zero,
        heartSize,
        Colors.red.withOpacity(opacity),
      );
      canvas.restore();

      canvas.save();
      canvas.translate(rightX, rightY);
      canvas.rotate(rightRotation);
      _drawHeart(canvas,
        Offset.zero,
        heartSize,
        Colors.red.withOpacity(opacity),
      );
      canvas.restore();

      // Glow effect when struggling
      if (moveT > 0.3) {
        final glowIntensity = math.sin(moveT * math.pi * 4) * 0.5 + 0.5;
        final glowPaint = Paint()
          ..color = Colors.red.withOpacity(0.3 * glowIntensity * (1.0 - moveT))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 20 * glowIntensity);

        canvas.drawCircle(Offset(leftX, leftY), heartSize * 1.5, glowPaint);
        canvas.drawCircle(Offset(rightX, rightY), heartSize * 1.5, glowPaint);
      }
    }

    // Phase 3: Hearts break apart (0.75 - 1.0)
    if (t >= 0.75) {
      final breakT = ((t - 0.75) / 0.25).clamp(0.0, 1.0);
      
      // Scattered fragments
      final leftX = center.dx - 120 - (breakT * 100);
      final rightX = center.dx + 120 + (breakT * 100);
      final fallY = center.dy - 40 + (breakT * 150);

      final scatterOpacity = math.max(0, 1.0 - breakT);

      // Draw scattered heart fragments
      _drawBrokenHeart(canvas,
        Offset(leftX, fallY),
        heartSize * (1.0 - breakT * 0.5),
        Colors.red.withOpacity(scatterOpacity * 0.7),
      );

      _drawBrokenHeart(canvas,
        Offset(rightX, fallY),
        heartSize * (1.0 - breakT * 0.5),
        Colors.red.withOpacity(scatterOpacity * 0.7),
      );

      // Small floating particles from broken hearts
      for (int i = 0; i < 5; i++) {
        final angle = (breakT * math.pi * 2) + (i * (2 * math.pi / 5));
        final distance = 30 + (breakT * 80);
        final px = center.dx - 120 + math.cos(angle) * distance;
        final py = center.dy - 40 + math.sin(angle) * distance + (breakT * 80);
        final particleOpacity = math.max(0, 1.0 - (breakT * 2));

        final particlePaint = Paint()
          ..color = Colors.red.withOpacity(particleOpacity * 0.5);
        canvas.drawCircle(Offset(px, py), 2 + (breakT * 2), particlePaint);

        // Right side particles
        final px2 = center.dx + 120 + math.cos(angle + math.pi) * distance;
        final py2 = center.dy - 40 + math.sin(angle + math.pi) * distance + (breakT * 80);
        canvas.drawCircle(Offset(px2, py2), 2 + (breakT * 2), particlePaint);
      }
    }
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    
    // Heart shape
    final x = center.dx;
    final y = center.dy;
    final s = size;

    // Top left curve
    path.moveTo(x, y + s * 0.3);
    path.cubicTo(
      x - s * 0.5, y - s * 0.2,
      x - s * 0.5, y - s * 0.5,
      x - s * 0.2, y - s * 0.4,
    );

    // Top right curve
    path.cubicTo(
      x, y - s * 0.6,
      x + s * 0.2, y - s * 0.4,
      x + s * 0.5, y - s * 0.5,
    );

    path.cubicTo(
      x + s * 0.5, y - s * 0.2,
      x, y + s * 0.3,
      x, y + s * 0.3,
    );

    // Bottom point
    path.lineTo(x, y + s * 0.6);
    path.close();

    canvas.drawPath(path, paint);

    // Add glow
    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.3);
    canvas.drawPath(path, glowPaint);
  }

  void _drawBrokenHeart(Canvas canvas, Offset center, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final x = center.dx;
    final y = center.dy;
    final s = size;

    // Left fragment
    final leftPath = Path();
    leftPath.moveTo(x - s * 0.1, y - s * 0.2);
    leftPath.cubicTo(x - s * 0.3, y - s * 0.4, x - s * 0.3, y - s * 0.1, x - s * 0.1, y);
    leftPath.lineTo(x, y + s * 0.3);
    leftPath.close();

    canvas.drawPath(leftPath, paint);

    // Right fragment
    final rightPath = Path();
    rightPath.moveTo(x + s * 0.1, y - s * 0.2);
    rightPath.cubicTo(x + s * 0.3, y - s * 0.4, x + s * 0.3, y - s * 0.1, x + s * 0.1, y);
    rightPath.lineTo(x, y + s * 0.3);
    rightPath.close();

    canvas.drawPath(rightPath, paint);
  }

  @override
  bool shouldRepaint(covariant _BrokenHeartsPainter oldDelegate) => true;
}
