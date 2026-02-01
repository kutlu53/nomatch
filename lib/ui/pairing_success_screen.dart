import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import '../app/pairing_manager.dart';

/// Eşleşme başarı ekranı - dramatik animasyon ekranı
class PairingSuccessScreen extends StatefulWidget {
  final PairingManager pairingManager;

  const PairingSuccessScreen({
    super.key,
    required this.pairingManager,
  });

  @override
  State<PairingSuccessScreen> createState() => _PairingSuccessScreenState();
}

class _PairingSuccessScreenState extends State<PairingSuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutQuart,
    );

    _controller.forward();

    // ✅ OPTIMIZATION: Start game preparation IMMEDIATELY (parallel with animation)
    // This way user doesn't wait after animation completes
    print('[UI] 🎬 Animation started - preparing game in background...');
    widget.pairingManager.prepareGame(); // Non-blocking, runs in parallel
    
    // ✅ When animation completes, show game immediately (preparation already done)
    Future.delayed(const Duration(milliseconds: 3000), () async {
      if (mounted) {
        print('[UI] 🎬 Animation complete - showing game...');
        await widget.pairingManager.showGame();
        print('[UI] ✅ Game visible');
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
          // ✨ Modern gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F172A), // Deep navy
                  Color(0xFF1E293B), // Slate
                  Color(0xFF0F172A), // Deep navy
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // Animated particles background
          CustomPaint(
            painter: _ParticlesPainter(_animation),
            size: Size.infinite,
          ),
          // Center animation
          Center(
            child: CustomPaint(
              painter: _ConnectionSuccessPainter(_animation),
              size: const Size(300, 300),
            ),
          ),
        ],
      ),
    );
  }
}

/// Particle background animation
class _ParticlesPainter extends CustomPainter {
  final Animation<double> animation;

  _ParticlesPainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final paint = Paint()..style = PaintingStyle.fill;

    // Çeşitli renkli partiküller
    final colors = [
      Colors.cyan.withOpacity(0.3),
      Colors.blue.withOpacity(0.2),
      Colors.purple.withOpacity(0.2),
    ];

    for (int i = 0; i < 5; i++) {
      final angle = (t * math.pi * 2) + (i * (2 * math.pi / 5));
      final distance = 100 + (t * 50);
      final x = size.width / 2 + math.cos(angle) * distance;
      final y = size.height / 2 + math.sin(angle) * distance;
      final radius = 2 + (t * 3);

      paint.color = colors[i % colors.length];
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) => true;
}

/// Connection success animation painter
class _ConnectionSuccessPainter extends CustomPainter {
  final Animation<double> animation;

  _ConnectionSuccessPainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 80.0;

    // Phase 1: Glow pulse (0.0 - 0.4)
    if (t < 0.4) {
      final glowT = (t / 0.4).clamp(0.0, 1.0);
      final glowOpacity = lerpDouble(0.0, 1.0, glowT)!;
      final glowRadius = lerpDouble(0, radius * 1.5, glowT)!;

      final glowPaint = Paint()
        ..color = Colors.cyan.withOpacity(glowOpacity * 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius * 2);
      canvas.drawCircle(center, glowRadius, glowPaint);
    }

    // Phase 2: Rings converge (0.2 - 0.75)
    if (t >= 0.2 && t < 0.75) {
      final ringT = ((t - 0.2) / 0.55).clamp(0.0, 1.0);
      final easeT = Curves.easeInOut.transform(ringT);

      final ring1Start = radius * 1.5;
      final ring2Start = radius * 1.8;
      final ring1Radius = lerpDouble(ring1Start, 0, easeT)!;
      final ring2Radius = lerpDouble(ring2Start, 0, easeT)!;

      final ringOpacity = lerpDouble(0.1, 1.0, ringT)!;

      final ringPaint = Paint()
        ..color = Colors.cyan.withOpacity(ringOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = lerpDouble(3.0, 16.0, ringT)!
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lerpDouble(6.0, 20.0, ringT)!);

      if (ring1Radius > 0) {
        canvas.drawCircle(center, ring1Radius, ringPaint);
      }
      if (ring2Radius > 0) {
        canvas.drawCircle(center, ring2Radius, ringPaint);
      }

      // Center glow
      if (ringT > 0.5) {
        final mergeT = ((ringT - 0.5) / 0.5).clamp(0.0, 1.0);
        final mergeRadius = lerpDouble(0, radius * 0.5, mergeT)!;
        final mergeOpacity = lerpDouble(0.0, 0.8, mergeT)!;

        final mergePaint = Paint()
          ..color = Colors.cyan.withOpacity(mergeOpacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, mergeRadius * 1.2);
        canvas.drawCircle(center, mergeRadius, mergePaint);
      }
    }

    // Phase 3: Success checkmark (0.75 - 1.0)
    if (t >= 0.75) {
      final fadeT = ((t - 0.75) / 0.25).clamp(0.0, 1.0);

      final fadeOpacity = lerpDouble(0.8, 0.0, fadeT)!;
      final fadeRadius = lerpDouble(radius * 0.4, radius * 0.8, fadeT)!;

      final fadePaint = Paint()
        ..color = Colors.cyan.withOpacity(fadeOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, fadeRadius * 0.8);
      canvas.drawCircle(center, fadeRadius, fadePaint);

      // Checkmark
      final pulseWave = math.sin(fadeT * math.pi * 2) * 0.2;
      final checkOpacity = 0.95;
      final checkRadius = radius * (0.25 + fadeT * 0.2 + pulseWave);
      _drawCheckmark(canvas, center, checkRadius, Colors.green.shade400, checkOpacity);
    }
  }

  void _drawCheckmark(Canvas canvas, Offset center, double radius, Color color, double opacity) {
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeWidth = radius * 0.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(center.dx - radius * 0.3, center.dy + radius * 0.05);
    path.lineTo(center.dx - radius * 0.05, center.dy + radius * 0.3);
    path.lineTo(center.dx + radius * 0.4, center.dy - radius * 0.25);

    canvas.drawPath(path, paint);

    final glowPaint = Paint()
      ..color = color.withOpacity(opacity * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.2);
    canvas.drawCircle(center, radius * 1.1, glowPaint);

    final outerGlowPaint = Paint()
      ..color = color.withOpacity(opacity * 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.06
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.15);
    canvas.drawCircle(center, radius * 1.4, outerGlowPaint);
  }

  @override
  bool shouldRepaint(covariant _ConnectionSuccessPainter oldDelegate) => true;
}
