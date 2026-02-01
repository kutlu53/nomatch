import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../app/pairing_manager.dart' show PeerInfo;

class RadarPairingView extends StatefulWidget {
  final List<PeerInfo> peers;
  final String? focusCandidatePeerId;
  final bool readySoon;
  final bool focusCandidateLocked;
  final bool pairHandshakeComplete;
  final bool isConnectingTransition;
  final double? localHeadingDeg; // Local device heading for radar rotation
  final bool validationFailed; // ✅ NEW: Visual feedback
  
  const RadarPairingView({
    super.key,
    required this.peers,
    required this.focusCandidatePeerId,
    required this.readySoon,
    required this.focusCandidateLocked,
    required this.pairHandshakeComplete,
    this.isConnectingTransition = false,
    this.localHeadingDeg,
    this.validationFailed = false, // ✅ NEW
  });

  @override
  State<RadarPairingView> createState() => _RadarPairingViewState();
}

class _RadarPairingViewState extends State<RadarPairingView> with TickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  final Map<String, _PeerTrack> _tracks = {};
  
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
    
    _syncPeers();
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

  void _syncPeers() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final peer in widget.peers) {
      final track = _tracks.putIfAbsent(peer.id, () => _PeerTrack(id: peer.id));
      track.update(peer: peer, nowMs: now);
    }
    _tracks.removeWhere((_, track) => track.fadeFor(now) <= 0.0);
  }

  @override
  Widget build(BuildContext context) {
    _syncPeers();
    return RepaintBoundary(
      child: SizedBox.expand(
        child: Stack(
          children: [
            // Main radar view (TRANSPARENT background)
            SizedBox.expand(
              child: CustomPaint(
                painter: _RadarPainter(
                  tracks: _tracks,
                  repaint: _ticker,
                  focusCandidatePeerId: widget.focusCandidatePeerId,
                  readySoon: widget.readySoon,
                  focusCandidateLocked: widget.focusCandidateLocked,
                  pairHandshakeComplete: widget.pairHandshakeComplete,
                  localHeadingDeg: widget.localHeadingDeg,
                  validationFailed: widget.validationFailed,
                  isConnectingTransition: widget.isConnectingTransition,
                  drawBackground: false, // ✅ IMPORTANT: Don't draw background
                ),
              ),
            ),
            // Connection transition overlay
            if (widget.isConnectingTransition && _transitionAnimation != null)
              SizedBox.expand(
                child: CustomPaint(
                  painter: _ConnectionTransitionPainter(
                    animation: _transitionAnimation!,
                    focusCandidatePeerId: widget.focusCandidatePeerId,
                    tracks: _tracks,
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
  final Map<String, _PeerTrack> tracks;
  final Animation<double> repaint;
  final String? focusCandidatePeerId;
  final bool readySoon;
  final bool focusCandidateLocked;
  final bool pairHandshakeComplete;
  final double? localHeadingDeg; // Local device heading for radar rotation
  final bool validationFailed; // ✅ NEW: Visual feedback for validation fail
  final bool isConnectingTransition; // ✅ NEW: Fade heading arrow during transition
  final bool drawBackground; // ✅ NEW: Control background drawing

  _RadarPainter({
    required this.tracks,
    required this.repaint,
    required this.focusCandidatePeerId,
    required this.readySoon,
    required this.focusCandidateLocked,
    required this.pairHandshakeComplete,
    this.localHeadingDeg,
    this.validationFailed = false, // ✅ NEW
    this.isConnectingTransition = false, // ✅ NEW
    this.drawBackground = false, // ✅ CHANGED: Default false - let parent gradient show through
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.42;

    // ✅ IMPORTANT: Only draw background if enabled (allows parent gradient to show through)
    if (drawBackground) {
      final bgPaint = Paint()..color = const Color(0xFF0F172A);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);
    }
    // If drawBackground is false, don't draw anything - let parent gradient show through

    _drawRadarBase(canvas, center, radius);

    for (final track in tracks.values) {
      final fade = track.fadeFor(nowMs);
      if (fade <= 0) continue;

      final normalized = _normalizeRssi(track.stats.emaRssi ?? -80);
      // Base angle from peer ID (deterministic position)
      final baseAngle = _angleFor(track.id) + _jitterFor(track.id, 0.28);
      // Rotate radar based on local heading (if available)
      // Local heading 0° = North, radar top = 0° (up)
      // When local device rotates, radar rotates opposite direction
      final headingOffset = localHeadingDeg != null 
          ? -localHeadingDeg! * (math.pi / 180) // Negative: rotate radar opposite to device rotation
          : 0.0;
      final angle = baseAngle + headingOffset;
      final radial = _radialFor(radius, normalized, track.id);
      final position = center + Offset(math.cos(angle), math.sin(angle)) * radial;

      final stdDev = track.stats.stdDev;
      final stability = (1.0 - (stdDev / 6.0)).clamp(0.0, 1.0);
      final pulse = _pulse(repaint.value, track.id, stability);

      // ✨ Hafif peer blob (more organic glow)
      final baseRadius = lerpDouble(radius * 0.025, radius * 0.065, normalized)!;
      final blobRadius = baseRadius * pulse;

      // ✅ NEW: Color changes based on validation state
      Color baseColor;
      if (focusCandidatePeerId == track.id) {
        if (validationFailed) {
          // ❌ FAIL: Red blink (fast tremor)
          final blinkOpacity = 0.5 + 0.5 * math.sin(repaint.value * math.pi * 8); // Fast blink
          baseColor = Color.lerp(Colors.red, Colors.red.withOpacity(0.3), blinkOpacity) ?? Colors.red;
        } else if (pairHandshakeComplete) {
          // ✅ PASS: Green glow (smooth pulse)
          final pulseOpacity = 0.5 + 0.5 * math.sin(repaint.value * math.pi * 2);
          baseColor = Color.lerp(Colors.green, Colors.green.withOpacity(0.5), pulseOpacity) ?? Colors.green;
        } else {
          // 🔄 CONNECTING: Cyan
          baseColor = Colors.cyan;
        }
      } else {
        baseColor = _colorFor(track.id);
      }
      
      // ✨ Daha hafif renkler (organik görünüş)
      final fillColor = baseColor.withOpacity(0.35 * fade);  // Daha açık
      final glowColor = baseColor.withOpacity(0.12 * fade);  // Daha yumuşak
      final strokeColor = baseColor.withOpacity(0.60 * fade); // Daha ince

      // ✨ Yumuşak glow (2-layer gradient effect)
      final outerGlow = Paint()
        ..color = glowColor.withOpacity(0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blobRadius * 1.2);
      canvas.drawCircle(position, blobRadius * 1.8, outerGlow);

      final innerGlow = Paint()
        ..color = glowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blobRadius * 0.4);
      canvas.drawCircle(position, blobRadius * 1.2, innerGlow);

      // ✨ Merkez (daha hafif fill)
      final fillPaint = Paint()..color = fillColor;
      canvas.drawCircle(position, blobRadius * 0.9, fillPaint);

      // ✨ Çok ince ring (opsiyonel)
      if (blobRadius > 3) {
        final ringPaint = Paint()
          ..color = strokeColor.withOpacity(0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = blobRadius * 0.08;
        canvas.drawCircle(position, blobRadius * 0.85, ringPaint);
      }

      // ✨ Pattern sadece büyük blob'lar için
      if (blobRadius > 4) {
        _drawPattern(canvas, position, blobRadius * 0.75, _patternFor(track.id), strokeColor);
      }

      // ✅ REMOVED: Peer heading arrow - keep center heading arrow only
      // Merkezdeki ↑ heading indicator kalıyor
      // if (track.headingDeg != null) {
      //   _drawHeadingArrow(canvas, position, blobRadius * 0.95, track.headingDeg!, fade, baseColor);
      // }

      if (focusCandidatePeerId != null && track.id == focusCandidatePeerId) {
        _drawLockRing(canvas, position, blobRadius, fade, baseColor);
        
        // Enhanced lock effect for connecting/handshake
        if (focusCandidateLocked || pairHandshakeComplete) {
          _drawLockEffect(canvas, position, blobRadius, fade, baseColor);
        }
      }
    }
    
    // Center spinner for connecting/handshake
    if ((focusCandidateLocked || pairHandshakeComplete) && focusCandidatePeerId != null) {
      _drawCenterSpinner(canvas, center, radius, isConnectingTransition);
    }
  }

  void _drawRadarBase(Canvas canvas, Offset center, double radius) {
    // ✨ Hafif radar grid
    final ringPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)  // Daha hafif
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.03)  // Çok hafif çizgiler
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // 4 daire (grid)
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * (i / 4), ringPaint);
    }
    
    // ✨ Sweep line (dönen ışın) - klasik radar gibi
    final sweepAngle = (repaint.value * math.pi * 2); // 360° döner
    final sweepOpacity = 0.15;
    
    // Sweep gradient: merkezden parlak, kenara doğru soluk
    final sweepPaint = Paint()
      ..color = Colors.cyan.withOpacity(sweepOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0);
    
    canvas.save();
    canvas.translate(center.dx, center.dy);
    
    // 30° sweep arc
    final sweepPath = Path();
    sweepPath.addArc(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      sweepAngle,
      math.pi / 6, // 30° sweeping arc
    );
    canvas.drawPath(sweepPath, sweepPaint);
    
    // ✅ NEW: Pulsing sonar ring (yeşil puls halkaları)
    final sonarPulse = repaint.value % 1.0; // 0.0 to 1.0
    final sonarRadius = sonarPulse * radius;
    final sonarOpacity = math.max(0, 1.0 - sonarPulse) * 0.4; // Fade out
    final sonarRingPaint = Paint()
      ..color = Colors.green.withOpacity(sonarOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.0);
    
    if (sonarRadius > 5) {
      canvas.drawCircle(Offset.zero, sonarRadius, sonarRingPaint);
    }
    
    // Center crosshair (çok hafif)
    final crossPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(-radius * 0.15, 0), Offset(radius * 0.15, 0), crossPaint);
    canvas.drawLine(Offset(0, -radius * 0.15), Offset(0, radius * 0.15), crossPaint);
    
    // Center dot (pulsing)
    final centerDotOpacity = 0.3 + 0.2 * math.sin(repaint.value * math.pi * 2 * 0.5);
    final centerDotPaint = Paint()
      ..color = Colors.cyan.withOpacity(centerDotOpacity);
    canvas.drawCircle(Offset.zero, 2.0, centerDotPaint);
    
    canvas.restore();
    
    // ✅ REMOVED: Small north arrow outside radar ring
  }

  void _drawPattern(Canvas canvas, Offset center, double radius, int variant, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.2
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    switch (variant) {
      case 0:
        canvas.drawCircle(Offset(0, -radius * 0.35), radius * 0.12, paint..style = PaintingStyle.fill);
        break;
      case 1:
        canvas.drawCircle(Offset.zero, radius * 0.45, paint..style = PaintingStyle.stroke);
        break;
      case 2:
        canvas.drawLine(Offset(-radius * 0.4, -radius * 0.3), Offset(radius * 0.4, radius * 0.3), paint);
        break;
      case 3:
        canvas.drawLine(Offset(-radius * 0.4, 0), Offset(radius * 0.4, 0), paint);
        canvas.drawLine(Offset(0, -radius * 0.4), Offset(0, radius * 0.4), paint);
        break;
      case 4:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: radius * 0.7, height: radius * 0.35),
            Radius.circular(radius * 0.2),
          ),
          paint..style = PaintingStyle.stroke,
        );
        break;
      case 5:
        canvas.drawCircle(Offset(radius * 0.25, 0), radius * 0.12, paint..style = PaintingStyle.fill);
        canvas.drawCircle(Offset(-radius * 0.25, 0), radius * 0.12, paint..style = PaintingStyle.fill);
        break;
      case 6:
        final path = Path()
          ..moveTo(0, -radius * 0.45)
          ..lineTo(radius * 0.4, radius * 0.4)
          ..lineTo(-radius * 0.4, radius * 0.4)
          ..close();
        canvas.drawPath(path, paint..style = PaintingStyle.stroke);
        break;
      default:
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: radius * 0.5),
          math.pi * 0.2,
          math.pi * 1.2,
          false,
          paint..style = PaintingStyle.stroke,
        );
        break;
    }
    canvas.restore();
  }

  void _drawHeadingArrow(Canvas canvas, Offset center, double radius, double headingDeg, double fade, Color base) {
    final angle = (headingDeg - 90) * (math.pi / 180);
    final paint = Paint()..color = base.withOpacity(0.85 * fade);
    final path = Path();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final tip = Offset(0, -radius);
    final left = Offset(-radius * 0.25, -radius * 0.55);
    final right = Offset(radius * 0.25, -radius * 0.55);
    path.moveTo(tip.dx, tip.dy);
    path.lineTo(left.dx, left.dy);
    path.lineTo(right.dx, right.dy);
    path.close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _drawLockRing(Canvas canvas, Offset center, double radius, double fade, Color base) {
    // ✨ Hafif pulse ring
    final speed = readySoon ? 2.0 : 1.2;  // Daha yavaş
    final phase = _hash01(focusCandidatePeerId!, 31) * math.pi * 2;
    final v = (math.sin((repaint.value * math.pi * 2 * speed) + phase) * 0.5 + 0.5);
    
    final ringRadius = radius * (0.95 + 0.2 * v);
    final ringOpacity = (0.15 + 0.25 * v) * fade;  // Daha hafif

    final ringPaint = Paint()
      ..color = base.withOpacity(ringOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12  // Daha ince
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.08);
    
    canvas.drawCircle(center, ringRadius, ringPaint);
    
    // ✨ Subtle secondary ring (daha hafif)
    final secondaryRadius = radius * (0.75 + 0.15 * v);
    final secondaryOpacity = (0.08 + 0.12 * v) * fade;
    
    final secondaryPaint = Paint()
      ..color = base.withOpacity(secondaryOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.08
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.1);
    
    canvas.drawCircle(center, secondaryRadius, secondaryPaint);
  }
  
  void _drawLockEffect(Canvas canvas, Offset center, double radius, double fade, Color base) {
    // ✨ Hafif lock effect (validation passed)
    final lockSpeed = 0.8;
    final lockPhase = _hash01(focusCandidatePeerId!, 47) * math.pi * 2;
    final lockV = (math.sin((repaint.value * math.pi * 2 * lockSpeed) + lockPhase) * 0.5 + 0.5);
    
    // ✨ Outer pulse ring (daha hafif)
    final outerRingRadius = radius * (1.15 + 0.1 * lockV);
    final outerRingOpacity = (0.2 + 0.2 * lockV) * fade;
    final outerRingPaint = Paint()
      ..color = base.withOpacity(outerRingOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.12);
    canvas.drawCircle(center, outerRingRadius, outerRingPaint);
    
    // ✨ Subtle inner glow
    final innerGlowRadius = radius * (0.5 + 0.15 * lockV);
    final innerGlowOpacity = (0.15 + 0.1 * lockV) * fade;
    final innerGlowPaint = Paint()
      ..color = base.withOpacity(innerGlowOpacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.2);
    canvas.drawCircle(center, innerGlowRadius, innerGlowPaint);
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

  double _normalizeRssi(double rssi) {
    const minRssi = -95.0;
    const maxRssi = -35.0;
    final clamped = rssi.clamp(minRssi, maxRssi) as double;
    return (clamped - minRssi) / (maxRssi - minRssi);
  }

  double _radialFor(double maxRadius, double normalized, String peerId) {
    final base = lerpDouble(maxRadius * 0.85, maxRadius * 0.18, normalized)!;
    final jitter = (_hash01(peerId, 7) - 0.5) * maxRadius * 0.08;
    return (base + jitter).clamp(maxRadius * 0.1, maxRadius * 0.9);
  }

  double _angleFor(String peerId) => _hash01(peerId, 3) * math.pi * 2;

  double _jitterFor(String peerId, double scale) => (_hash01(peerId, 11) - 0.5) * scale;

  double _pulse(double t, String peerId, double stability) {
    final phase = _hash01(peerId, 19) * math.pi * 2;
    final freq = lerpDouble(0.6, 1.6, 1.0 - stability)!;
    final amp = lerpDouble(0.12, 0.04, 1.0 - stability)!;
    return 1.0 + amp * math.sin((t * math.pi * 2 * freq) + phase);
  }

  int _patternFor(String peerId) => (_hash(peerId, 23) % 8).abs();

  Color _colorFor(String peerId) {
    final hue = (_hash(peerId, 5) % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.72, 0.55).toColor();
  }

  int _hash(String input, int salt) {
    var hash = 0x811C9DC5 ^ salt;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  double _hash01(String input, int salt) {
    final h = _hash(input, salt);
    return (h & 0xfffffff) / 0xfffffff;
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.tracks != tracks ||
        oldDelegate.focusCandidatePeerId != focusCandidatePeerId ||
        oldDelegate.readySoon != readySoon ||
        oldDelegate.focusCandidateLocked != focusCandidateLocked ||
        oldDelegate.pairHandshakeComplete != pairHandshakeComplete ||
        oldDelegate.localHeadingDeg != localHeadingDeg ||
        oldDelegate.validationFailed != validationFailed ||
        oldDelegate.isConnectingTransition != isConnectingTransition; // ✅ NEW: Repaint on transition
  }
}

class _PeerTrack {
  final String id;
  final RollingStats stats = RollingStats();
  int lastSeenMs = 0;
  double? headingDeg;

  _PeerTrack({required this.id});

  void update({required PeerInfo peer, required int nowMs}) {
    lastSeenMs = nowMs;
    headingDeg = peer.heading;
    stats.push(peer.rssi.toDouble());
  }

  double fadeFor(int nowMs) {
    final dt = nowMs - lastSeenMs;
    if (dt <= 1500) return 1.0;
    final t = (dt - 1500) / 800;
    return (1.0 - t).clamp(0.0, 1.0);
  }
}

class RollingStats {
  static const int _maxSamples = 10;
  final List<double> _samples = [];
  double? emaRssi;

  void push(double value) {
    const alpha = 0.25;
    emaRssi = emaRssi == null ? value : emaRssi! + alpha * (value - emaRssi!);
    _samples.add(value);
    if (_samples.length > _maxSamples) {
      _samples.removeAt(0);
    }
  }

  double get stdDev {
    if (_samples.length < 2) return 0.0;
    final mean = _samples.reduce((a, b) => a + b) / _samples.length;
    var sum = 0.0;
    for (final v in _samples) {
      final d = v - mean;
      sum += d * d;
    }
    return math.sqrt(sum / _samples.length);
  }
}

/// Painter for connection transition overlay animation
class _ConnectionTransitionPainter extends CustomPainter {
  final Animation<double> animation;
  final String? focusCandidatePeerId;
  final Map<String, _PeerTrack> tracks;

  _ConnectionTransitionPainter({
    required this.animation,
    required this.focusCandidatePeerId,
    required this.tracks,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.42;
    
    // Find target peer position
    Offset? targetPosition;
    Color? targetColor;
    
    if (focusCandidatePeerId != null) {
      final track = tracks[focusCandidatePeerId];
      if (track != null) {
        final normalized = _normalizeRssi(track.stats.emaRssi ?? -80);
        final angle = _angleFor(track.id) + _jitterFor(track.id, 0.28);
        final radial = _radialFor(radius, normalized, track.id);
        targetPosition = center + Offset(math.cos(angle), math.sin(angle)) * radial;
        targetColor = _colorFor(track.id);
      }
    }
    
    // If no target found, use center
    targetPosition ??= center;
    targetColor ??= Colors.cyan;
    
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

  // Helper methods (copied from _RadarPainter)
  double _normalizeRssi(double rssi) {
    const minRssi = -95.0;
    const maxRssi = -35.0;
    final clamped = rssi.clamp(minRssi, maxRssi) as double;
    return (clamped - minRssi) / (maxRssi - minRssi);
  }

  double _radialFor(double maxRadius, double normalized, String peerId) {
    // ✅ FIX: Handle null from lerpDouble to avoid NaN
    final base = lerpDouble(maxRadius * 0.85, maxRadius * 0.18, normalized) ?? maxRadius * 0.5;
    final jitter = (_hash01(peerId, 7) - 0.5) * maxRadius * 0.08;
    return (base + jitter).clamp(maxRadius * 0.1, maxRadius * 0.9);
  }

  double _angleFor(String peerId) => _hash01(peerId, 3) * math.pi * 2;

  double _jitterFor(String peerId, double scale) => (_hash01(peerId, 11) - 0.5) * scale;

  Color _colorFor(String peerId) {
    final hue = (_hash(peerId, 5) % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.72, 0.55).toColor();
  }

  int _hash(String input, int salt) {
    var hash = 0x811C9DC5 ^ salt;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  double _hash01(String input, int salt) {
    final h = _hash(input, salt);
    return (h & 0xfffffff) / 0xfffffff;
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
    return oldDelegate.animation != animation ||
        oldDelegate.focusCandidatePeerId != focusCandidatePeerId;
  }
}
