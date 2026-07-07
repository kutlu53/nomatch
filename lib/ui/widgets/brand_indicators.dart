import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../theme/game_colors.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// BRAND INDICATORS — Material spinner/progress yerine markaya uygun göstergeler
// ═══════════════════════════════════════════════════════════════════════════════
//
// Yazısız/geometrik estetiği bozan stock CircularProgressIndicator yerine kullanılır.

/// Belirsiz (indeterminate) yükleme göstergesi.
/// İç içe iki halkanın nabız gibi genişleyip solduğu, marka renklerinde bir efekt.
class PulseLoader extends StatefulWidget {
  final double size;
  final Color color;

  const PulseLoader({
    super.key,
    this.size = 56,
    this.color = GameColors.purple,
  });

  @override
  State<PulseLoader> createState() => _PulseLoaderState();
}

class _PulseLoaderState extends State<PulseLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _PulsePainter(progress: _c.value, color: widget.color),
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;

  const _PulsePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) / 2;

    // İki halka, yarım faz kaydırmalı — sürekli akan bir nabız.
    for (int i = 0; i < 2; i++) {
      final t = (progress + i * 0.5) % 1.0;
      final r = maxR * (0.35 + 0.6 * t);
      final opacity = (1.0 - t) * 0.6;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, r, paint);
    }

    // Sabit çekirdek nokta.
    final core = Paint()..color = color.withValues(alpha: 0.9);
    canvas.drawCircle(center, maxR * 0.14, core);
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) =>
      old.progress != progress || old.color != color;
}

/// Belirli (determinate) ilerleme halkası — uzun-basış progress'i için.
/// Material CircularProgressIndicator(value:) yerine kullanılır.
class ProgressRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final Color color;
  final double strokeWidth;

  const ProgressRing({
    super.key,
    required this.value,
    this.size = 80,
    this.color = GameColors.purple,
    this.strokeWidth = 5,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ProgressRingPainter(
          value: value.clamp(0.0, 1.0),
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double value;
  final Color color;
  final double strokeWidth;

  const _ProgressRingPainter({
    required this.value,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = (math.min(size.width, size.height) - strokeWidth) / 2;

    final track = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, r, track);

    final arc = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2, // tepeden başla
      2 * math.pi * value,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter old) =>
      old.value != value || old.color != color || old.strokeWidth != strokeWidth;
}
