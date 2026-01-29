import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/app_coordinator.dart';
import '../app/app_phase.dart';
import 'color_palette_manager.dart';

/// Split image game view.
///
/// - No text/icons.
/// - Tap feedback is a short scale animation.
/// - Round "time pressure" is expressed as a subtle dark mask that increases opacity
///   as the deadline approaches (no progress bar).
class GameScreen extends StatefulWidget {
  final AppViewState state;
  final AppCoordinator coordinator;

  const GameScreen({
    super.key,
    required this.state,
    required this.coordinator,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

enum _TapHalf { none, top, bottom }

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late final AnimationController _tapA = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  
  late final AnimationController _transitionA = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  _TapHalf _tapHalf = _TapHalf.none;
  bool _tapLockedThisRound = false;
  int? _lastRidSeen;

  // Cached image providers so rebuilds don't re-create providers.
  int? _cachedQid;
  
  // ✅ SYNC: First question render tracking (only once)
  bool _firstQuestionRenderLogged = false;
  ImageProvider? _topProvider;
  ImageProvider? _bottomProvider;
  Widget? _topImage;
  Widget? _bottomImage;
  bool _loggedNullQuestion = false;
  final Map<String, ImageStream> _imageStreams = {};
  final Map<String, ImageStreamListener> _imageStreamListeners = {};

  // Time source for mask opacity (UI-only).
  Ticker? _ticker;
  int _nowMs = 0;

  @override
  void initState() {
    super.initState();
    
    // Ekranı açık tut (oyun sırasında)
    if (!kIsWeb) {
      WakelockPlus.enable();
    }
    
    _tapA.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _tapA.reverse();
      }
      if (s == AnimationStatus.dismissed) {
        if (mounted) setState(() => _tapHalf = _TapHalf.none);
      }
    });
    _maybeStartStopTicker();
    _transitionA.value = 1.0; // Başlangıçta tam görünür
  }

  @override
  void didUpdateWidget(covariant GameScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Web preview modunda rid değişmez, qid'ye göre kontrol et
    final qid = widget.state.currentQuestion?.qid;
    final oldQid = oldWidget.state.currentQuestion?.qid;
    
    if (qid != null && qid != oldQid) {
      _tapLockedThisRound = false;
      _tapHalf = _TapHalf.none;
      _tapA.reset();
      
      // Soru değişti: geçiş animasyonu
      _transitionA.forward(from: 0.0);
    }

    _maybeStartStopTicker();
  }

  @override
  void dispose() {
    // Wakelock'u devre dışı bırak
    if (!kIsWeb) {
      WakelockPlus.disable();
    }
    
    _ticker?.dispose();
    _ticker = null;
    _clearImageDebugListeners();
    _tapA.dispose();
    _transitionA.dispose();
    _firstQuestionRenderLogged = false; // Reset for next game
    super.dispose();
  }

  void _maybeStartStopTicker() {
    final playing = widget.state.phase == AppPhase.playing && widget.state.game.currentRound != null;
    if (!playing) {
      _ticker?.stop();
      return;
    }
    _ticker ??= createTicker((_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Small UI update; keep it minimal.
      if (now != _nowMs) {
        setState(() => _nowMs = now);
      }
    });
    if (!_ticker!.isActive) {
      _nowMs = DateTime.now().millisecondsSinceEpoch;
      _ticker!.start();
    }
  }

  bool get _localFinal => widget.state.game.currentRound?.localFinal == true;

  void _onTapTop() {
    if (_localFinal || _tapLockedThisRound) return;
    _tapLockedThisRound = true;
    setState(() => _tapHalf = _TapHalf.top);
    unawaited(_tapA.forward(from: 0));
    widget.coordinator.onLocalTapTop();
  }

  void _onTapBottom() {
    if (_localFinal || _tapLockedThisRound) return;
    _tapLockedThisRound = true;
    setState(() => _tapHalf = _TapHalf.bottom);
    unawaited(_tapA.forward(from: 0));
    widget.coordinator.onLocalTapBottom();
  }

  void _ensureProviders() {
    final q = widget.state.currentQuestion;
    if (q == null) {
      if (!_loggedNullQuestion) {
        _loggedNullQuestion = true;
        dev.log("GAME_UI: currentQuestion is null (no qid to render)");
        print("GAME_UI: currentQuestion is null (no qid to render)");
      }
      _cachedQid = null;
      _topProvider = null;
      _bottomProvider = null;
      _topImage = null;
      _bottomImage = null;
      _clearImageDebugListeners();
      return;
    }
    _loggedNullQuestion = false;
    if (_cachedQid == q.qid) return;
    final isFirstQuestion = _cachedQid == null;
    _cachedQid = q.qid;
    _clearImageDebugListeners();
    dev.log("GAME_UI: using qid=${q.qid} top=${q.topAsset} bottom=${q.bottomAsset}");
    print("GAME_UI: using qid=${q.qid} top=${q.topAsset} bottom=${q.bottomAsset}");
    
    // ✅ SYNC: Schedule first question render log (only for first question, once)
    if (isFirstQuestion && !_firstQuestionRenderLogged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _firstQuestionRenderLogged) return;
        _firstQuestionRenderLogged = true;
        final firstFrameAtMs = DateTime.now().millisecondsSinceEpoch;
        final pendingStartAtMs = widget.state.game.pendingGameStartAtMs;
        final renderDriftMs = pendingStartAtMs != null 
            ? firstFrameAtMs - pendingStartAtMs 
            : null;
        print("[SYNC] QUESTION_RENDER firstFrameAtMs=$firstFrameAtMs, pendingStartAtMs=$pendingStartAtMs, renderDriftMs=$renderDriftMs");
        dev.log("[SYNC] QUESTION_RENDER firstFrameAtMs=$firstFrameAtMs, pendingStartAtMs=$pendingStartAtMs, renderDriftMs=$renderDriftMs");
      });
    }
    
    // Validate asset presence once per qid so logs show missing assets.
    unawaited(_checkAssetReadable(q.topAsset, label: "top"));
    unawaited(_checkAssetReadable(q.bottomAsset, label: "bottom"));
    _topProvider = AssetImage(q.topAsset);
    _bottomProvider = AssetImage(q.bottomAsset);
    _attachImageDebug(label: 'top', qid: q.qid, provider: _topProvider!);
    _attachImageDebug(label: 'bottom', qid: q.qid, provider: _bottomProvider!);
    // Cache the Image widgets too, so rebuilds don't construct new Image.asset widgets.
    _topImage = Image(
      image: _topProvider!,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      errorBuilder: (context, error, stackTrace) {
        dev.log("GAME_UI: failed to load top asset: ${q.topAsset}", error: error, stackTrace: stackTrace);
        return const ColoredBox(color: Color(0xFF2a2a2a));
      },
    );
    _bottomImage = Image(
      image: _bottomProvider!,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      errorBuilder: (context, error, stackTrace) {
        dev.log("GAME_UI: failed to load bottom asset: ${q.bottomAsset}", error: error, stackTrace: stackTrace);
        return const ColoredBox(color: Color(0xFF2a2a2a));
      },
    );
  }

  Future<void> _checkAssetReadable(String assetPath, {required String label}) async {
    try {
      await rootBundle.load(assetPath);
      dev.log("GAME_UI: asset ok ($label) $assetPath");
      print("GAME_UI: asset ok ($label) $assetPath");
    } catch (e, st) {
      dev.log("GAME_UI: asset MISSING ($label) $assetPath", error: e, stackTrace: st);
      print("GAME_UI: asset MISSING ($label) $assetPath error=$e");
    }
  }

  void _attachImageDebug({
    required String label,
    required int qid,
    required ImageProvider provider,
  }) {
    final isAsset = provider is AssetImage;
    final isNetwork = provider is NetworkImage;
    final imageKey = isAsset
        ? (provider as AssetImage).assetName
        : (isNetwork ? (provider as NetworkImage).url : provider.toString());
    final resolvedPath = imageKey;

    dev.log(
      "[IMG] qid=$qid label=$label imageKey=$imageKey resolvedPath=$resolvedPath asset=$isAsset network=$isNetwork",
    );

    _imageStreams[label]?.removeListener(_imageStreamListeners[label]!);
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (info, sync) {
        dev.log("[IMG] load ok qid=$qid label=$label size=${info.image.width}x${info.image.height} sync=$sync");
      },
      onError: (error, stackTrace) {
        dev.log("[IMG] load err qid=$qid label=$label", error: error, stackTrace: stackTrace);
      },
    );
    _imageStreams[label] = stream;
    _imageStreamListeners[label] = listener;
    stream.addListener(listener);
  }

  void _clearImageDebugListeners() {
    for (final entry in _imageStreams.entries) {
      final listener = _imageStreamListeners[entry.key];
      if (listener != null) {
        entry.value.removeListener(listener);
      }
    }
    _imageStreams.clear();
    _imageStreamListeners.clear();
  }

  @override
  Widget build(BuildContext context) {
    _ensureProviders();

    final r = widget.state.game.currentRound;
    final playing = widget.state.phase == AppPhase.playing && r != null;

    final maskOpacity = playing ? _maskOpacity(nowMs: _nowMs, deadlineMs: r.deadlineMs) : 0.0;

    final paletteManager = ColorPaletteManager();
    
    return Scaffold(
      backgroundColor: paletteManager.currentPalette.colors.first,
      body: RepaintBoundary(
        child: Stack(
          children: [
            // ✅ Pairing teması ile uyumlu gradient
            Container(
              decoration: BoxDecoration(
                gradient: paletteManager.currentPalette.gradient,
              ),
            ),
            // Kartlar
            AnimatedBuilder(
              animation: _transitionA,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_transitionA.value);
                // Fade + Scale geçişi
                return Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: 0.85 + (0.15 * t),
                    child: Column(
                      children: [
                        Expanded(
                          child: _HalfCard(
                            provider: _topProvider,
                            onTap: _onTapTop,
                            active: _tapHalf == _TapHalf.top,
                            tapAnim: _tapA,
                            enabled: playing,
                            localFinal: _localFinal,
                            cachedImage: _topImage,
                          ),
                        ),
                        const SizedBox(height: 16), // Aradaki boşluk
                        Expanded(
                          child: _HalfCard(
                            provider: _bottomProvider,
                            onTap: _onTapBottom,
                            active: _tapHalf == _TapHalf.bottom,
                            tapAnim: _tapA,
                            enabled: playing,
                            localFinal: _localFinal,
                            cachedImage: _bottomImage,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (playing && maskOpacity > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Colors.black.withOpacity(maskOpacity)),
                ),
              ),
            // Ring progress animation when waiting for game start (startAtMs)
            if (widget.state.game.pendingGameStartAtMs != null)
              _RingProgressOverlay(
                startAtMs: widget.state.game.pendingGameStartAtMs!,
                nowMs: _nowMs,
              ),
          ],
        ),
      ),
    );
  }

  static double _maskOpacity({required int nowMs, required int deadlineMs}) {
    // Opacity should increase as the round progresses.
    const totalMs = 5000;
    const maxOpacity = 0.15;
    final remaining = (deadlineMs - nowMs).clamp(0, totalMs);
    final elapsed = totalMs - remaining;
    final progress = (elapsed / totalMs).clamp(0.0, 1.0);
    return (progress * maxOpacity).clamp(0.0, maxOpacity);
  }
}

class _HalfCard extends StatelessWidget {
  final ImageProvider? provider;
  final VoidCallback onTap;
  final bool active;
  final Animation<double> tapAnim;
  final bool enabled;
  final bool localFinal;
  final Widget? cachedImage;

  const _HalfCard({
    required this.provider,
    required this.onTap,
    required this.active,
    required this.tapAnim,
    required this.enabled,
    required this.localFinal,
    required this.cachedImage,
  });

  @override
  Widget build(BuildContext context) {
    final scale = active ? (1.0 - 0.04 * Curves.easeOut.transform(tapAnim.value.clamp(0.0, 1.0))) : 1.0;
    final flash = active ? (0.10 * (1.0 - tapAnim.value).clamp(0.0, 1.0)) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: RepaintBoundary(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  if (localFinal) return;
                  onTap();
                }
              : null,
          child: AnimatedBuilder(
            animation: tapAnim,
            builder: (context, _) {
              return Transform.scale(
                scale: scale,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                      // Tıklanabilir göstergesi: hafif parlayan çerçeve
                      if (enabled && !localFinal)
                        BoxShadow(
                          color: Colors.white.withOpacity(0.2),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Görsel
                        provider == null
                            ? Container(color: const Color(0xFF2a2a2a))
                            : (cachedImage ?? Container(color: const Color(0xFF2a2a2a))),
                        // Tıklama flash efekti
                        if (flash > 0) 
                          Container(color: Colors.white.withOpacity(flash)),
                        // Tıklanabilir çerçeve animasyonu
                        if (enabled && !localFinal)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Half extends StatelessWidget {
  final ImageProvider? provider;
  final VoidCallback onTap;
  final bool active;
  final Animation<double> tapAnim;
  final bool enabled;
  final bool localFinal;
  final Widget? cachedImage;

  const _Half({
    required this.provider,
    required this.onTap,
    required this.active,
    required this.tapAnim,
    required this.enabled,
    required this.localFinal,
    required this.cachedImage,
  });

  @override
  Widget build(BuildContext context) {
    final base = Colors.transparent;

    final scale = active ? (1.0 - 0.04 * Curves.easeOut.transform(tapAnim.value.clamp(0.0, 1.0))) : 1.0;
    final flash = active ? (0.10 * (1.0 - tapAnim.value).clamp(0.0, 1.0)) : 0.0;

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                // Fully block any second tap once local is final for this round.
                if (localFinal) return;
                onTap();
              }
            : null,
        child: AnimatedBuilder(
          animation: tapAnim,
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Transform.scale(
                  scale: scale,
                  child: ColoredBox(
                    color: base,
                    child: provider == null
                        ? const SizedBox.expand()
                        : (cachedImage ?? const SizedBox.expand()),
                  ),
                ),
                if (flash > 0) ColoredBox(color: Colors.white.withOpacity(flash)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Mini ring progress animation shown while waiting for synchronized game start
class _RingProgressOverlay extends StatelessWidget {
  final int startAtMs;
  final int nowMs;

  const _RingProgressOverlay({
    required this.startAtMs,
    required this.nowMs,
  });

  @override
  Widget build(BuildContext context) {
    final remainingMs = (startAtMs - nowMs).clamp(0, double.infinity).toInt();
    const totalDelayMs = 600; // Expected delay
    final progress = 1.0 - (remainingMs / totalDelayMs).clamp(0.0, 1.0);
    
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: CustomPaint(
            size: const Size(60, 60),
            painter: _RingProgressPainter(progress: progress),
          ),
        ),
      ),
    );
  }
}

class _RingProgressPainter extends CustomPainter {
  final double progress;

  _RingProgressPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    
    // Background ring (subtle)
    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, bgPaint);
    
    // Progress ring
    final progressPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    
    final sweepAngle = 2 * 3.14159 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2, // Start at top
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_RingProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
