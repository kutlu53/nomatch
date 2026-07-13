import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app/pairing_manager.dart';
import '../../theme/game_colors.dart';
import '../radar/radar_rings_painter.dart';

/// Ice Silver color - same as triangle color in radar mode
const Color _circleColor = Color(0xFFEDEBFF);

/// Colors for peer dot states
const Color _dotColorIdle = Color(0xFFEDEBFF);      // Ice Silver
const Color _dotColorRequesting = GameColors.purple; // Purple - we sent request
const Color _dotColorRequested = GameColors.purple;  // Purple - they sent request
const Color _dotColorMatched = GameColors.lime;      // Lime green - matched!

/// Public mode pairing view for metro/bus environments.
/// 
/// Features:
/// - Large app logo in the center with circle border
/// - Discovered peers shown as dots outside the circle
/// - Dot distance from circle based on signal strength (RSSI)
/// - Tap on dot to request pairing
/// - BLE auto-starts when entering this view (no tap needed on logo)
class PublicPairingView extends StatelessWidget {
  final bool isScanning;
  final List<DiscoveredPeer> discoveredPeers;
  final void Function(String peerId)? onPeerTap;

  const PublicPairingView({
    super.key,
    required this.isScanning,
    this.discoveredPeers = const [],
    this.onPeerTap,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    // Radar modundaki ilk (en içteki) halka ile aynı boyut: maxRadius * 0.25, maxRadius = min(w,h) * 0.42
    final circleSize = math.min(screenSize.width, screenSize.height) * 0.21;
    final logoSize = circleSize * 0.85; // Logo fills most of the circle
    final center = Offset(screenSize.width / 2, screenSize.height / 2);
    
    return Stack(
      clipBehavior: Clip.hardEdge, // ✅ Prevent any overflow from rendering outside
      children: [
        // Radar modundaki halkalarla aynı görünüm
        RadarRingsWidget(isScanning: isScanning),

        // Peer dots (behind the logo circle)
        ...discoveredPeers.asMap().entries.map((entry) {
          final peer = entry.value;
          return _PeerDot(
            key: ValueKey(peer.id),
            peer: peer,
            circleRadius: circleSize / 2,
            center: center,
            onTap: onPeerTap != null ? () => onPeerTap!(peer.id) : null,
          );
        }),
        
        // Logo with circle - no tap needed, BLE auto-starts in public mode
        // IgnorePointer: dekorasyonlu Container daire içindeki dokunuşları
        // yutuyordu; daireye yakın dot'lara basmak bazen boşa gidiyordu.
        IgnorePointer(
          child: Center(
            child: Opacity(
              opacity: 0.25, // %75 saydam
              child: Container(
                width: circleSize,
                height: circleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _circleColor.withValues(alpha: 0.6),
                    width: 2.0,
                  ),
                ),
                child: Center(
                  child: Image.asset(
                    'assets/branding/logo.png',
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A dot representing a discovered peer
class _PeerDot extends StatefulWidget {
  final DiscoveredPeer peer;
  final double circleRadius;
  final Offset center;
  final VoidCallback? onTap;

  const _PeerDot({
    super.key,
    required this.peer,
    required this.circleRadius,
    required this.center,
    this.onTap,
  });

  @override
  State<_PeerDot> createState() => _PeerDotState();
}

class _PeerDotState extends State<_PeerDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _scaleAnimation;

  /// RSSI kaynaklı konum zıplamasını önlemek için yumuşatılmış mesafe.
  /// Her güncellemede yeni değere %30 ağırlıkla yaklaşır (düşük geçişli filtre);
  /// dot yerinde küçük adımlarla kayar, kullanıcı basarken hedef kaçmaz.
  late double _smoothedDistance;

  /// Dokunuşun başladığı global konum (parmak kayması toleransı için).
  Offset? _pointerDownPosition;

  @override
  void initState() {
    super.initState();
    _smoothedDistance = widget.peer.normalizedDistance;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    // Opacity pulse
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Scale pulse for active states
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _updateAnimation();
  }
  
  @override
  void didUpdateWidget(covariant _PeerDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peer.state != widget.peer.state) {
      _updateAnimation();
    }
    // Yeni RSSI değerine sıçramak yerine yumuşak geçiş yap
    _smoothedDistance =
        _smoothedDistance * 0.7 + widget.peer.normalizedDistance * 0.3;
  }
  
  void _updateAnimation() {
    final state = widget.peer.state;
    if (state == PublicPeerState.requesting || 
        state == PublicPeerState.requested ||
        state == PublicPeerState.matched) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }
  
  Color _getDotColor() {
    switch (widget.peer.state) {
      case PublicPeerState.idle:
        return _dotColorIdle;
      case PublicPeerState.requesting:
        return _dotColorRequesting;
      case PublicPeerState.requested:
        return _dotColorRequested;
      case PublicPeerState.matched:
        return _dotColorMatched;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    
    // Deterministik ama daha eşit dağılan konum: peer ID hash'ini golden-angle
    // (≈137.5°) ile çarparak modulo-360 kümelenmesini önle. Aynı ID → aynı açı.
    const goldenAngle = 2.399963229728653; // radyan (137.507764°)
    final hash = widget.peer.id.hashCode & 0x7fffffff;
    final baseAngle = (hash * goldenAngle) % (2 * math.pi);
    
    // Distance from circle: closer RSSI = closer to circle.
    // Ham RSSI yerine yumuşatılmış değer: dot her sinyal güncellemesinde
    // zıplamaz, kullanıcı basarken hedef yerinden kaçmaz.
    final normalizedDist = _smoothedDistance;

    // Min distance from circle edge: 25px (very close)
    // Max distance from circle edge: 90px (far)
    final distanceFromCircle = 25 + (1 - normalizedDist) * 65;
    final totalRadius = widget.circleRadius + distanceFromCircle;

    // Calculate position
    var x = widget.center.dx + math.cos(baseAngle) * totalRadius;
    var y = widget.center.dy + math.sin(baseAngle) * totalRadius;

    // Bigger dot size: 16-28px based on signal strength
    final baseDotSize = 16 + normalizedDist * 12;
    // Max possible dot size (with scale pulse)
    const maxScale = 1.3;
    final maxDotSize = baseDotSize * maxScale;
    // Dokunma alanı: en küçük dot'ta bile Apple HIG minimumu (44pt) üstünde
    // kalsın diye 48px tabanlı. Pulse animasyonundan bağımsız sabit boyut —
    // dokunma hedefi kare kare değişmez.
    final tapSize = math.max(48.0, maxDotSize + 20);
    final halfTap = tapSize / 2;

    // ✅ FIX: Clamp position so the dot (including tap area) stays within screen bounds
    x = x.clamp(halfTap, screenSize.width - halfTap);
    y = y.clamp(halfTap, screenSize.height - halfTap);
    
    final dotColor = _getDotColor();
    final isActive = widget.peer.state != PublicPeerState.idle;
    
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = isActive ? _scaleAnimation.value : 1.0;
        final opacity = isActive ? _pulseAnimation.value : 0.7;
        final dotSize = baseDotSize * scale;
        
        return Positioned(
          left: x - halfTap,
          top: y - halfTap,
          // GestureDetector yerine Listener: ekran yatay PageView içinde
          // olduğu için tap, drag ile gesture arena'da yarışıp kaybedebiliyordu
          // (hareketli metro/otobüste parmak kayması > 18px slop → tap iptal).
          // Listener arena'ya girmez; kendi geniş toleransımızla dokunuşu
          // her koşulda yakalarız.
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              _pointerDownPosition = event.position;
            },
            onPointerUp: (event) {
              final down = _pointerDownPosition;
              _pointerDownPosition = null;
              if (down == null || widget.onTap == null) return;
              // Sarsıntı toleransı: parmak 30px'e kadar kayabilir, yine tap sayılır
              if ((event.position - down).distance <= 30.0) {
                widget.onTap!();
              }
            },
            onPointerCancel: (_) => _pointerDownPosition = null,
            child: Container(
              width: tapSize,
              height: tapSize,
              alignment: Alignment.center,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor.withValues(alpha: opacity),
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.4 * opacity),
                      blurRadius: dotSize * 0.8,
                      spreadRadius: isActive ? 4 : 2,
                    ),
                    if (isActive)
                      BoxShadow(
                        color: dotColor.withValues(alpha: 0.2),
                        blurRadius: dotSize * 1.5,
                        spreadRadius: 8,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
