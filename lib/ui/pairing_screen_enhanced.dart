import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../features/pairing/pairing_validator.dart';
import '../features/pairing/flashlight_signal.dart';
import 'widgets/flashlight_toggle.dart';

/// Enhanced pairing screen with physical validation feedback
class PairingScreenWithValidation extends StatefulWidget {
  final PairingPhase phase;
  
  const PairingScreenWithValidation({
    super.key,
    required this.phase,
  });

  @override
  State<PairingScreenWithValidation> createState() => _PairingScreenWithValidationState();
}

class _PairingScreenWithValidationState extends State<PairingScreenWithValidation> 
    with SingleTickerProviderStateMixin {
  late final AnimationController _a;
  final FlashlightSignal _flashlight = FlashlightSignal();
  bool _flashlightOn = false;

  @override
  void initState() {
    super.initState();
    _a = AnimationController(
      vsync: this,
      duration: _getDuration(widget.phase),
    )..repeat(reverse: true);
  }
  
  @override
  void didUpdateWidget(PairingScreenWithValidation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _a.duration = _getDuration(widget.phase);
    }
  }

  @override
  void dispose() {
    _a.dispose();
    _flashlight.dispose();
    super.dispose();
  }
  
  Duration _getDuration(PairingPhase phase) {
    switch (phase) {
      case PairingPhase.tooClose:
        return const Duration(milliseconds: 200); // Hızlı titreme
      case PairingPhase.wrongOrientation:
        return const Duration(milliseconds: 1200); // Orta hız
      case PairingPhase.ready:
        return const Duration(milliseconds: 400); // Hızlı pulse
      default:
        return const Duration(milliseconds: 1400); // Normal
    }
  }
  
  Future<void> _toggleFlashlight() async {
    if (_flashlightOn) {
      await _flashlight.stopBlinking();
      setState(() => _flashlightOn = false);
    } else {
      await _flashlight.startBlinking();
      setState(() => _flashlightOn = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ⚠️ INFO BANNER: Magnetometer Calibration Reminder
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                border: Border.all(color: Colors.orange, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '💡 TIP: Compass uygulamasını açıp telefonu "8" şeklinde sallamanız önerilir (kalibrasyon için)',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          
          // Ana animasyon (ok ve şekiller)
          Center(
            child: AnimatedBuilder(
              animation: _a,
              builder: (context, _) {
                final v = _a.value;
                final params = _getAnimationParams(widget.phase, v);
                
                return Transform.translate(
                  offset: params.offset,
                  child: Transform.rotate(
                    angle: params.rotation,
                    child: Transform.scale(
                      scale: params.scale,
                      child: CustomPaint(
                        painter: _AdaptivePainterNew(
                          phase: widget.phase,
                          animValue: v,
                          opacity: params.opacity,
                          color: params.color,
                        ),
                        size: const Size(160, 160),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Flaş toggle (sol üst köşe)
          Positioned(
            left: 24,
            top: 60,
            child: FlashlightToggle(
              isOn: _flashlightOn,
              onToggle: _toggleFlashlight,
            ),
          ),
        ],
      ),
    );
  }
  
  _AnimationParams _getAnimationParams(PairingPhase phase, double v) {
    switch (phase) {
      case PairingPhase.idle:
      case PairingPhase.waitingForFlat:
        // Soluk, yavaş fade - "Masaya koy"
        return _AnimationParams(
          opacity: 0.05 + 0.08 * v,
          color: Colors.white.withOpacity(0.4),
          offset: Offset(0, math.sin(v * math.pi * 2) * 8), // Yukarı-aşağı
        );
        
      case PairingPhase.searchingFlat:
        // Masada, arıyor - Normal animasyon
        return _AnimationParams(
          opacity: 0.12 + 0.15 * v,
          color: Colors.white,
          scale: 1.0 + 0.05 * v,
        );
        
      case PairingPhase.tooClose:
        // Çok yakın - Kırmızı, titrek
        return _AnimationParams(
          opacity: 0.3 + 0.4 * math.sin(v * math.pi * 8),
          color: Colors.red,
          scale: 1.0 + 0.1 * math.sin(v * math.pi * 6),
          offset: Offset(math.sin(v * math.pi * 4) * 8, 0), // Sağa-sola
        );
        
      case PairingPhase.peerFound:
        // Peer bulundu, bekleniyor
        return _AnimationParams(
          opacity: 0.2 + 0.2 * v,
          color: Colors.lightBlue,
          scale: 1.0 + 0.08 * v,
        );
        
      case PairingPhase.wrongOrientation:
        // Yön yanlış - Mavi, dönüyor
        return _AnimationParams(
          opacity: 0.3 + 0.2 * v,
          color: Colors.lightBlue,
          rotation: math.sin(v * math.pi) * 0.15, // Hafif dönme
          scale: 1.0 + 0.06 * v,
        );
        
      case PairingPhase.ready:
        // HAZIR! - Yeşil, hızlı pulse
        return _AnimationParams(
          opacity: 0.5 + 0.5 * v,
          color: const Color(0xFF48bb78), // Parlak yeşil
          scale: 1.0 + 0.2 * math.sin(v * math.pi * 4),
        );
    }
  }
}

class _AnimationParams {
  final double opacity;
  final Color color;
  final double scale;
  final double rotation;
  final Offset offset;
  
  _AnimationParams({
    required this.opacity,
    required this.color,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.offset = Offset.zero,
  });
}

class _AdaptivePainterNew extends CustomPainter {
  final PairingPhase phase;
  final double animValue;
  final double opacity;
  final Color color;
  
  const _AdaptivePainterNew({
    required this.phase,
    required this.animValue,
    required this.opacity,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.5;
    
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.fill;
    
    // Farklı phase'lerde farklı şekiller
    switch (phase) {
      case PairingPhase.wrongOrientation:
        // Çift ok (zıt yönler)
        _drawDoubleArrow(canvas, size, paint);
        break;
        
      case PairingPhase.ready:
        // Genişleyen halkalar
        _drawExpandingRings(canvas, size, paint, animValue);
        _drawArrow(canvas, size, paint); // Ortada ok
        break;
        
      default:
        // Normal tek ok
        _drawArrow(canvas, size, paint);
        
        // Çember (phase'e göre)
        if (phase == PairingPhase.searchingFlat || 
            phase == PairingPhase.peerFound) {
          _drawCircle(canvas, size, paint, animValue);
        }
    }
  }
  
  void _drawArrow(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    // Yukarı ok
    path.moveTo(w * 0.5, h * 0.12);
    path.lineTo(w * 0.88, h * 0.58);
    path.lineTo(w * 0.65, h * 0.58);
    path.lineTo(w * 0.65, h * 0.88);
    path.lineTo(w * 0.35, h * 0.88);
    path.lineTo(w * 0.35, h * 0.58);
    path.lineTo(w * 0.12, h * 0.58);
    path.close();
    canvas.drawPath(path, paint);
  }
  
  void _drawDoubleArrow(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    
    // Üst ok (yukarı)
    final path1 = Path();
    path1.moveTo(w * 0.5, h * 0.05);
    path1.lineTo(w * 0.8, h * 0.35);
    path1.lineTo(w * 0.65, h * 0.35);
    path1.lineTo(w * 0.65, h * 0.48);
    path1.lineTo(w * 0.35, h * 0.48);
    path1.lineTo(w * 0.35, h * 0.35);
    path1.lineTo(w * 0.2, h * 0.35);
    path1.close();
    
    // Alt ok (aşağı)
    final path2 = Path();
    path2.moveTo(w * 0.5, h * 0.95);
    path2.lineTo(w * 0.2, h * 0.65);
    path2.lineTo(w * 0.35, h * 0.65);
    path2.lineTo(w * 0.35, h * 0.52);
    path2.lineTo(w * 0.65, h * 0.52);
    path2.lineTo(w * 0.65, h * 0.65);
    path2.lineTo(w * 0.8, h * 0.65);
    path2.close();
    
    canvas.drawPath(path1, paint);
    canvas.drawPath(path2, paint);
  }
  
  void _drawCircle(Canvas canvas, Size size, Paint paint, double anim) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final radius = size.width * 0.6 * (1.0 + 0.1 * anim);
    
    final circlePaint = Paint()
      ..color = color.withOpacity(opacity * 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    canvas.drawCircle(Offset(cx, cy), radius, circlePaint);
  }
  
  void _drawExpandingRings(Canvas canvas, Size size, Paint paint, double anim) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    
    // 3 halka
    for (int i = 0; i < 3; i++) {
      final progress = (anim + i * 0.33) % 1.0;
      final radius = size.width * 0.4 * (1.0 + progress * 0.8);
      final opacity = (1.0 - progress) * 0.4;
      
      ringPaint.color = color.withOpacity(opacity);
      canvas.drawCircle(Offset(cx, cy), radius, ringPaint);
    }
  }

  @override
  bool shouldRepaint(_AdaptivePainterNew oldDelegate) => 
      oldDelegate.phase != phase || 
      oldDelegate.animValue != animValue || 
      oldDelegate.opacity != opacity || 
      oldDelegate.color != color;
}
