import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/pairing_manager.dart';
import '../../theme/design_tokens.dart';
import '../../theme/game_colors.dart';
import '../radar/radar_rings_painter.dart';

/// Ice Silver color - same as triangle color in radar mode
const Color _circleColor = Color(0xFFEDEBFF);

/// Colors for peer dot states
const Color _dotColorIdle = Color(0xFFEDEBFF);      // Ice Silver
const Color _dotColorRequesting = GameColors.purple; // Mor - biz istek attık
const Color _dotColorMatched = GameColors.lime;      // Lime - eşleşti!

/// Public mode pairing view for metro/bus environments.
///
/// Features:
/// - Large app logo in the center with circle border
/// - Discovered peers shown as dots outside the circle
/// - Dot distance from circle based on signal strength (RSSI)
/// - Tap on dot to request pairing
/// - BLE auto-starts when entering this view (no tap needed on logo)
class PublicPairingView extends StatefulWidget {
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
  State<PublicPairingView> createState() => _PublicPairingViewState();
}

class _PublicPairingViewState extends State<PublicPairingView> {
  // ✅ UI: Listeden silinen peer'lar aniden kaybolmasın — kısa bir çıkış
  // animasyonu (küçülüp solma) boyunca burada tutulur, sonra atılır.
  final Map<String, DiscoveredPeer> _exiting = {};
  final Map<String, Timer> _exitTimers = {};

  @override
  void didUpdateWidget(covariant PublicPairingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentIds = {for (final p in widget.discoveredPeers) p.id};

    // Listeden çıkanları çıkış animasyonu için beklet
    for (final p in oldWidget.discoveredPeers) {
      if (!currentIds.contains(p.id) && !_exiting.containsKey(p.id)) {
        _exiting[p.id] = p;
        _exitTimers[p.id] = Timer(const Duration(milliseconds: 340), () {
          if (!mounted) return;
          setState(() {
            _exiting.remove(p.id);
            _exitTimers.remove(p.id);
          });
        });
      }
    }

    // Peer geri geldiyse çıkış animasyonunu iptal et (normal listede çizilir)
    for (final id in currentIds) {
      if (_exiting.remove(id) != null) {
        _exitTimers.remove(id)?.cancel();
      }
    }
  }

  @override
  void dispose() {
    for (final t in _exitTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

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
        RadarRingsWidget(isScanning: widget.isScanning),

        // Peer dots (behind the logo circle)
        ...widget.discoveredPeers.map((peer) {
          return _PeerDot(
            key: ValueKey(peer.id),
            peer: peer,
            circleRadius: circleSize / 2,
            center: center,
            onTap:
                widget.onPeerTap != null ? () => widget.onPeerTap!(peer.id) : null,
          );
        }),

        // ✅ UI: Çıkış animasyonu oynayan (listeden yeni silinmiş) dotlar
        ..._exiting.values.map((peer) {
          return _PeerDot(
            key: ValueKey('exit_${peer.id}'),
            peer: peer,
            circleRadius: circleSize / 2,
            center: center,
            onTap: null,
            exiting: true,
          );
        }),

        // Logo with circle - no tap needed, BLE auto-starts in public mode
        // IgnorePointer: dekorasyonlu Container daire içindeki dokunuşları
        // yutuyordu; daireye yakın dot'lara basmak bazen boşa gidiyordu.
        IgnorePointer(
          child: Center(
            child: _CenterLogo(
              circleSize: circleSize,
              logoSize: logoSize,
              hasPeers: widget.discoveredPeers.isNotEmpty,
            ),
          ),
        ),
      ],
    );
  }
}

/// ✅ UI: Merkez logo — hayalet %25 opaklık yerine bilinçli bir odak:
/// mor→lime degrade çember, halkalarla uyumlu yavaş "nefes" ölçeği ve
/// yakında telefon bulununca hafif parlama.
class _CenterLogo extends StatefulWidget {
  final double circleSize;
  final double logoSize;
  final bool hasPeers;

  const _CenterLogo({
    required this.circleSize,
    required this.logoSize,
    required this.hasPeers,
  });

  @override
  State<_CenterLogo> createState() => _CenterLogoState();
}

class _CenterLogoState extends State<_CenterLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _breath,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_breath.value);
        return Transform.scale(scale: 1.0 + 0.04 * t, child: child);
      },
      child: AnimatedOpacity(
        duration: Motion.slow,
        // Peer bulununca merkez hafifçe canlanır: "burası aktif" sinyali.
        opacity: widget.hasPeers ? 0.70 : 0.50,
        child: SizedBox(
          width: widget.circleSize,
          height: widget.circleSize,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const CustomPaint(painter: _GradientRingPainter()),
              Center(
                child: Image.asset(
                  'assets/branding/logo.png',
                  width: widget.logoSize,
                  height: widget.logoSize,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mor→lime degrade çember (merkez logonun kenarlığı).
class _GradientRingPainter extends CustomPainter {
  const _GradientRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          GameColors.purple.withValues(alpha: 0.80),
          _circleColor.withValues(alpha: 0.35),
          GameColors.lime.withValues(alpha: 0.55),
        ],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(
      size.center(Offset.zero),
      size.width / 2 - 1,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GradientRingPainter oldDelegate) => false;
}

/// A dot representing a discovered peer
class _PeerDot extends StatefulWidget {
  final DiscoveredPeer peer;
  final double circleRadius;
  final Offset center;
  final VoidCallback? onTap;

  /// ✅ UI: true ise dot listeden silinmiştir; çıkış animasyonu oynar.
  final bool exiting;

  const _PeerDot({
    super.key,
    required this.peer,
    required this.circleRadius,
    required this.center,
    this.onTap,
    this.exiting = false,
  });

  @override
  State<_PeerDot> createState() => _PeerDotState();
}

class _PeerDotState extends State<_PeerDot> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _scaleAnimation;

  // ✅ UI: Doğuş/çıkış animasyonu — dot pat diye belirmek yerine easeOutBack
  // ile büyüyerek doğar; silinince küçülüp solarak gider.
  late final AnimationController _entryController;
  late final Animation<double> _entryScale;
  late final Animation<double> _entryFade;

  // ✅ UI: Dokunma geri bildirimi (haptic + anlık büyüme).
  bool _pressed = false;

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

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      reverseDuration: const Duration(milliseconds: 300),
    );
    _entryScale = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
    // Fade ayrı eğri kullanır: easeOutBack 1.0'ı aşabilir, opaklıkta geçersiz.
    _entryFade = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    if (widget.exiting) {
      _entryController.value = 1.0;
      _entryController.reverse();
    } else {
      _entryController.forward();
    }

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
    if (state == PublicPeerState.requested) {
      // ✅ UI: "Gelen istek" — dışa yayılan halka dalgası (tek yönlü döngü).
      _pulseController.duration = const Duration(milliseconds: 1400);
      _pulseController.repeat();
    } else if (state == PublicPeerState.requesting ||
        state == PublicPeerState.matched) {
      _pulseController.duration = const Duration(milliseconds: 800);
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  Color _getDotColor() {
    switch (widget.peer.state) {
      case PublicPeerState.idle:
        return _dotColorIdle;
      case PublicPeerState.requesting:
        return _dotColorRequesting;
      case PublicPeerState.requested:
        // ✅ UI: Dot nötr kalır; "gelen istek" mesajını mor halka dalgası verir.
        // (Eskiden requesting ile aynı mordu — kullanıcı dokunmanın kabul mü
        // iptal mi olacağını ayırt edemiyordu.)
        return _dotColorIdle;
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

    // ✅ UI: Mesafe değişimi tween ile süzülür — dot zıplamak yerine kayar.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _smoothedDistance),
      duration: Motion.slow,
      curve: Curves.easeOut,
      builder: (context, normalizedDist, _) {
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
        final state = widget.peer.state;
        final isRequested = state == PublicPeerState.requested;
        final isActive = state != PublicPeerState.idle;

        return AnimatedBuilder(
          animation: Listenable.merge([_pulseController, _entryController]),
          builder: (context, child) {
            // Requested durumunda dot sabit durur (mesajı halka dalgası taşır);
            // diğer aktif durumlarda mevcut nabız ölçek/opaklığı kullanılır.
            final pulseScale =
                (isActive && !isRequested) ? _scaleAnimation.value : 1.0;
            final opacity = isRequested
                ? 0.95
                : (isActive ? _pulseAnimation.value : 0.7);
            final dotSize = baseDotSize * pulseScale;

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
                  if (widget.onTap != null) {
                    // ✅ UI: Anlık dokunma geri bildirimi (diğer ekranlarla aynı dil).
                    HapticFeedback.lightImpact();
                    setState(() => _pressed = true);
                  }
                },
                onPointerUp: (event) {
                  final down = _pointerDownPosition;
                  _pointerDownPosition = null;
                  if (_pressed) setState(() => _pressed = false);
                  if (down == null || widget.onTap == null) return;
                  // Sarsıntı toleransı: parmak 30px'e kadar kayabilir, yine tap sayılır
                  if ((event.position - down).distance <= 30.0) {
                    widget.onTap!();
                  }
                },
                onPointerCancel: (_) {
                  _pointerDownPosition = null;
                  if (_pressed) setState(() => _pressed = false);
                },
                child: FadeTransition(
                  opacity: _entryFade,
                  child: ScaleTransition(
                    scale: _entryScale,
                    child: SizedBox(
                      width: tapSize,
                      height: tapSize,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // ✅ UI: "Gelen istek" halka dalgaları — iki kademeli,
                          // dışa doğru büyüyüp solan mor halkalar (gelen çağrı dili).
                          if (isRequested)
                            for (final phase in const [0.0, 0.5])
                              _RippleRing(
                                t: (_pulseController.value + phase) % 1.0,
                                baseSize: baseDotSize,
                              ),

                          // Dot'un kendisi
                          AnimatedScale(
                            scale: _pressed ? 1.15 : 1.0,
                            duration: Motion.instant,
                            child: Container(
                              width: dotSize,
                              height: dotSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dotColor.withValues(alpha: opacity),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        dotColor.withValues(alpha: 0.4 * opacity),
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Dışa doğru yayılan tek bir "gelen istek" halkası.
class _RippleRing extends StatelessWidget {
  /// 0..1 — dalganın yaşam döngüsü (0: dot boyutu, 1: tamamen yayıldı/soldu).
  final double t;
  final double baseSize;

  const _RippleRing({required this.t, required this.baseSize});

  @override
  Widget build(BuildContext context) {
    final size = baseSize * (1.0 + 1.8 * t);
    final opacity = (1.0 - t) * 0.55;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: GameColors.purple.withValues(alpha: opacity),
          width: 2,
        ),
      ),
    );
  }
}
