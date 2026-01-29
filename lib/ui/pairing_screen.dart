import 'package:flutter/material.dart';
import 'dart:math' as math;

class PairingScreenSimple extends StatefulWidget {
  const PairingScreenSimple({super.key});

  @override
  State<PairingScreenSimple> createState() => _PairingScreenSimpleState();
}

class _PairingScreenSimpleState extends State<PairingScreenSimple> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: AnimatedBuilder(
          animation: _a,
          builder: (context, _) {
            final v = _a.value;
            return CustomPaint(
              painter: _ArrowPainter(opacity: 0.08 + 0.10 * v, color: scheme.onSurface),
              size: const Size(160, 160),
            );
          },
        ),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final double opacity;
  final Color color;
  const _ArrowPainter({required this.opacity, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withOpacity(opacity);
    final w = size.width;
    final h = size.height;
    final path = Path();
    // simple up-pointing arrow
    path.moveTo(w * 0.5, h * 0.12);
    path.lineTo(w * 0.88, h * 0.58);
    path.lineTo(w * 0.65, h * 0.58);
    path.lineTo(w * 0.65, h * 0.88);
    path.lineTo(w * 0.35, h * 0.88);
    path.lineTo(w * 0.35, h * 0.58);
    path.lineTo(w * 0.12, h * 0.58);
    path.close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) => oldDelegate.opacity != opacity || oldDelegate.color != color;
}

