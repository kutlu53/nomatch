import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';

import '../../theme/game_colors.dart';

/// Kayıp / eşleşememe animasyonu — soyut geometrik "ayrılma".
///
/// Kazanç animasyonundaki (birleşen halkalar) dilin karşılığı: bağlı iki
/// yörünge gerilir ve bağ kopar. BLE/ekran mantığından bağımsız, tek başına
/// kullanılabilir (önizleme galerisi de bunu doğrudan kullanır).
class DivergeAnimation extends StatefulWidget {
  final Duration duration;
  const DivergeAnimation({
    super.key,
    this.duration = const Duration(milliseconds: 3500),
  });

  @override
  State<DivergeAnimation> createState() => _DivergeAnimationState();
}

class _DivergeAnimationState extends State<DivergeAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOutQuart);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: CustomPaint(
            painter: _DivergeOrbsPainter(_animation),
            size: const Size(400, 400),
          ),
        ),
        CustomPaint(
          painter: _DivergeParticlesPainter(_animation),
          size: Size.infinite,
        ),
      ],
    );
  }
}

/// Ayrışma sonrası dışa savrulan parçacıklar.
class _DivergeParticlesPainter extends CustomPainter {
  final Animation<double> animation;
  _DivergeParticlesPainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final paint = Paint()..style = PaintingStyle.fill;
    final center = Offset(size.width / 2, size.height / 2);

    if (t >= 0.70) {
      final pt = ((t - 0.70) / 0.30).clamp(0.0, 1.0);
      for (int side = -1; side <= 1; side += 2) {
        final originX = center.dx + side * 60.0;
        for (int i = 0; i < 5; i++) {
          final angle = (i * (2 * math.pi / 5)) + pt * math.pi;
          final dist = 20 + pt * 130;
          final x = originX + side * math.cos(angle) * dist;
          final y = center.dy + math.sin(angle) * dist + pt * 60;
          final opacity = math.max(0.0, 1.0 - pt * 2) * 0.55;
          paint.color = GameColors.failureGlow.withValues(alpha: opacity);
          canvas.drawCircle(Offset(x, y), 2 + pt * 2, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DivergeParticlesPainter oldDelegate) => true;
}

/// İki yörüngenin bağının gerilip kopması.
class _DivergeOrbsPainter extends CustomPainter {
  final Animation<double> animation;
  _DivergeOrbsPainter(this.animation) : super(repaint: animation);

  static const _orbColor = GameColors.failurePrimary;
  static const _linkColor = GameColors.failureAccent;
  static const _glowColor = GameColors.failureGlow;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final center = Offset(size.width / 2, size.height / 2);
    const orbR = 30.0;

    final appear = (t / 0.30).clamp(0.0, 1.0);
    final scale = Curves.easeOutBack.transform(appear);
    final sep = lerpDouble(44, 190, Curves.easeInCubic.transform(t))!;
    final tension = (t > 0.30 && t < 0.70)
        ? math.sin((t - 0.30) * math.pi * 9) * (0.70 - t) * 26
        : 0.0;
    final orbOpacity = t < 0.70 ? 1.0 : (1.0 - (t - 0.70) / 0.30).clamp(0.0, 1.0);
    final r = orbR * (t < 0.30 ? scale : 1.0) * (0.6 + 0.4 * orbOpacity);

    final leftC = Offset(center.dx - sep + tension, center.dy);
    final rightC = Offset(center.dx + sep - tension, center.dy);

    final linkOpacity = t < 0.70 ? (1.0 - t / 0.70) * 0.6 : 0.0;
    if (linkOpacity > 0) {
      final linkPaint = Paint()
        ..color = _linkColor.withValues(alpha: linkOpacity)
        ..strokeWidth = 3.0 * (1.0 - t)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(leftC, rightC, linkPaint);
    }

    _drawOrb(canvas, leftC, r, orbOpacity);
    _drawOrb(canvas, rightC, r, orbOpacity);
  }

  void _drawOrb(Canvas canvas, Offset c, double r, double opacity) {
    final glow = Paint()
      ..color = _glowColor.withValues(alpha: 0.25 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(c, r * 1.5, glow);

    final core = Paint()..color = _orbColor.withValues(alpha: opacity);
    canvas.drawCircle(c, r, core);

    final hi = Paint()..color = Colors.white.withValues(alpha: 0.18 * opacity);
    canvas.drawCircle(c.translate(-r * 0.28, -r * 0.28), r * 0.30, hi);
  }

  @override
  bool shouldRepaint(covariant _DivergeOrbsPainter oldDelegate) => true;
}
