import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/game_colors.dart';
import '../../theme/app_background.dart';
import '../../theme/design_tokens.dart';
import '../../ui/widgets/brand_indicators.dart';
import 'game_engine.dart';
import 'game_state.dart';
import 'models.dart';

/// ✅ PERFORMANCE: Debug logging control
const bool _kGameScreenDebug = false; // UI logs are usually too verbose
void _gsLog(String msg) {
  if (_kGameScreenDebug) print(msg);
}

/// ✅ OPTIMIZATION: Image precache helper
class _ImagePrecacher {
  static final Set<String> _precachedAssets = {};
  
  static Future<void> precacheIfNeeded(BuildContext context, String? asset) async {
    if (asset == null || _precachedAssets.contains(asset)) return;
    
    try {
      await precacheImage(AssetImage(asset), context);
      _precachedAssets.add(asset);
      _gsLog('[PRECACHE] ✅ Precached: $asset');
    } catch (e) {
      _gsLog('[PRECACHE] ⚠️ Failed to precache $asset: $e');
    }
  }
  
}

class GameScreen extends StatefulWidget {
  final GameEngine engine;
  final VoidCallback onOpenShare;
  final VoidCallback onReset; // ✅ NEW: Reset callback for terminalFail
  final Stream<bool>? connectionStatus; // ✅ NEW: BLE connection status stream

  const GameScreen({
    super.key,
    required this.engine,
    required this.onOpenShare,
    required this.onReset,
    this.connectionStatus,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  RoundSnapshot? _snap;
  late final StreamSubscription<RoundSnapshot> _sub;
  StreamSubscription<bool>? _connectionSub;
  bool _disposed = false;
  bool _shareScreenRequested = false;
  int? _selectedInRound;
  bool _isReconnecting = false;
  late AnimationController _reconnectPulseController;
  late AnimationController _fadeInController;
  late Animation<double> _fadeInAnimation;

  // UX-4: Başarı animasyonu tap-to-skip için iptal edilebilir timer
  Timer? _shareTimer;

  // UX-3: Oyun içi uzun basış çıkış
  Timer? _exitLongPressTimer;
  bool _exitLongPressActive = false;
  late AnimationController _exitProgressController;

  @override
  void initState() {
    super.initState();
    
    // Ekran açılış fade-in
    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeInAnimation = CurvedAnimation(parent: _fadeInController, curve: Curves.easeIn);
    _fadeInController.forward();

    // ✅ Reconnect pulse animation
    _reconnectPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // UX-3: Çıkış uzun basış progress animasyonu
    _exitProgressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    
    // ✅ Listen to connection status
    _connectionSub = widget.connectionStatus?.listen((isConnected) {
      if (mounted) {
        setState(() => _isReconnecting = !isConnected);
        _gsLog('[GAME-SCREEN] 📡 Connection status: ${isConnected ? "✅ Connected" : "⚠️ Reconnecting..."}');
      }
    });
    
    // ✅ SAFETY: Check initial engine state - if already terminal, something is wrong
    final initialPhase = widget.engine.state.phase;
    _gsLog('[GAME-SCREEN] 🆕 initState - initial engine phase: $initialPhase');
    if (initialPhase == GamePhase.terminalSuccess || initialPhase == GamePhase.terminalFail) {
      _gsLog('[GAME-SCREEN] ⚠️ WARNING: Engine started in terminal state! This should not happen.');
    }
    
    // ✅ FIX: Initialize _snap from current engine state to avoid loading spinner
    final currentRound = widget.engine.state.currentRound;
    if (currentRound != null && widget.engine.state.phase == GamePhase.playing) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _snap = RoundSnapshot(
        sessionId: '', // Will be updated by stream
        peerId: '',
        isLeader: false,
        roundNumber: currentRound.rid,
        startedAtMs: now,
        deadlineMs: currentRound.deadlineMs,
        localChoice: currentRound.localChoice?.name,
        localRevision: currentRound.localRev,
        localFinal: currentRound.localFinal,
        peerChoice: currentRound.peerChoice?.name,
        peerRevision: currentRound.peerRev,
        peerFinal: currentRound.peerFinal,
        terminal: null, // ✅ null = no terminal state yet
        phase: GamePhase.playing,
        topAsset: currentRound.topAsset,
        bottomAsset: currentRound.bottomAsset,
      );
      _gsLog('[GAME-SCREEN] ✅ Initialized _snap from engine state - rid=${currentRound.rid}');
    }
    
    _sub = widget.engine.snapshots.listen((s) {
      // ✅ CRITICAL: Check mounted FIRST before any operations
      if (!mounted) {
        _gsLog('[GAME-SCREEN] ⚠️ Not mounted - ignoring event');
        return;
      }
      
      if (_disposed) {
        _gsLog('[GAME-SCREEN] 🛑 Disposed - ignoring snapshot, cancelling subscription');
        _sub.cancel();
        return;
      }
      
      // ✅ OPTIMIZATION: Skip rebuild if snapshot unchanged
      final oldSnap = _snap;
      final needsRebuild = oldSnap == null || 
          oldSnap.phase != s.phase || 
          oldSnap.roundNumber != s.roundNumber ||
          oldSnap.localChoice != s.localChoice ||
          oldSnap.peerChoice != s.peerChoice ||
          oldSnap.terminal != s.terminal ||
          oldSnap.topAsset != s.topAsset ||      // ✅ Asset değişikliklerini de kontrol et
          oldSnap.bottomAsset != s.bottomAsset;
      
      if (!needsRebuild) {
        _gsLog('[GAME-SCREEN] ⏭️ Skip rebuild - unchanged snapshot');
        return; // Skip unnecessary rebuilds
      }
      
      _gsLog('[GAME-SCREEN] 🔄 Rebuild triggered - rid=${s.roundNumber}, phase=${s.phase}, top=${s.topAsset != null}');
      
      // ✅ SAFETY: Log phase transitions
      if (oldSnap?.phase != s.phase) {
        _gsLog('[GAME-SCREEN] 🔄 Phase changed: ${oldSnap?.phase} -> ${s.phase}');
        
        // ✅ FIX: Reset state flags when game restarts (pairing phase = new game)
        if (s.phase == GamePhase.pairing || s.phase == GamePhase.playing) {
          if (oldSnap?.phase == GamePhase.terminalFail || oldSnap?.phase == GamePhase.terminalSuccess) {
            _gsLog('[GAME-SCREEN] 🔄 Game restart detected - resetting state flags');
            _shareScreenRequested = false;
            _selectedInRound = null;
          }
        }
      }
      
      setState(() => _snap = s);
      
      // ✅ When success, show animation then share (3 sec animation)
      if (s.phase == GamePhase.terminalSuccess) {
        if (_shareScreenRequested) {
          _gsLog('[GAME-SCREEN] ⚠️ Share screen already requested, ignoring duplicate');
          return;
        }
        
        // ✅ SAFETY: Only proceed if we have played at least 5 rounds
        final similarity = widget.engine.state.similarity;
        if (similarity < 5) {
          _gsLog('[GAME-SCREEN] ⚠️ terminalSuccess but similarity=$similarity (not 5)! IGNORING spurious event.');
          return;
        }
        
        _gsLog('[GAME-SCREEN] 🎉 terminalSuccess - animation playing (similarity=$similarity)');
        // UX-4: Timer iptal edilebilir → tap-to-skip mümkün.
        _shareTimer?.cancel();
        _shareTimer = Timer(const Duration(milliseconds: 3200), () {
          if (_disposed || !mounted || _shareScreenRequested) return;
          _shareScreenRequested = true;
          _gsLog('[GAME-SCREEN] 🎉 3.2 sec passed - calling onOpenShare()');
          widget.onOpenShare();
        });
      }
      
      // ✅ When failure, show animation (retry button will appear after animation)
      if (s.phase == GamePhase.terminalFail) {
        // ✅ SAFETY: Only proceed if we have 5 differences
        final difference = widget.engine.state.difference;
        if (difference < 5) {
          _gsLog('[GAME-SCREEN] ⚠️ terminalFail but difference=$difference (not 5)! IGNORING spurious event.');
          return;
        }
        
        _gsLog('[GAME-SCREEN] ❌ terminalFail - animation playing (difference=$difference)');
        // ✅ NO AUTO-RESET: User must tap retry button
      }
    });
  }

  @override
  void dispose() {
    _gsLog('[GAME-SCREEN] 🛑 Disposing GameScreen...');
    _disposed = true;
    _gsLog('[GAME-SCREEN] 🛑 Immediately cancelling subscription on dispose...');
    _sub.cancel();
    _connectionSub?.cancel();
    _shareTimer?.cancel();
    _exitLongPressTimer?.cancel();
    _fadeInController.dispose();
    _reconnectPulseController.dispose();
    _exitProgressController.dispose();
    _gsLog('[GAME-SCREEN] 🛑 Subscription cancelled immediately');
    super.dispose();
    _gsLog('[GAME-SCREEN] ✅ GameScreen disposed completely');
  }

  @override
  Widget build(BuildContext context) {
    if (_disposed) {
      _gsLog('[GAME-SCREEN] 🛑 Build called but screen disposed - returning empty');
      return const SizedBox.shrink();
    }
    
    final snap = _snap;
    _gsLog('[GAME-SCREEN] 🎮 BUILD CALLED - snap=$snap, phase=${snap?.phase}, rid=${snap?.roundNumber}');
    
    // ✅ OPTIMIZATION: Precache current round images
    if (snap != null) {
      _ImagePrecacher.precacheIfNeeded(context, snap.topAsset);
      _ImagePrecacher.precacheIfNeeded(context, snap.bottomAsset);
    }
    
    return FadeTransition(
      opacity: _fadeInAnimation,
      child: SizedBox.expand(
      child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // UX-3: Oyun sırasında 3 sn uzun basış → çıkış. terminalFail/Success
          // fazlarında _FailureAnimationOverlay / _SuccessAnimationOverlay kendi
          // gesture'larını yakalar; bu handler yalnızca playing fazında devreye girer.
          onLongPressStart: (_) {
            if (_snap?.phase != GamePhase.playing) return;
            setState(() => _exitLongPressActive = true);
            _exitProgressController.forward(from: 0);
            _exitLongPressTimer = Timer(const Duration(seconds: 3), () {
              // ✅ FIX: Faz burada YENİDEN kontrol edilir. Basılı tutma son
              // turda başlayıp bu 3 sn içinde oyun kazanılırsa, eskiden reset
              // yine de ateşlenip kazanılan oyunu siliyordu.
              if (!mounted) return;
              if (_snap?.phase != GamePhase.playing) {
                _gsLog('[GAME-SCREEN] ⚠️ Exit hold aborted - game ended during hold');
                setState(() => _exitLongPressActive = false);
                _exitProgressController.reset();
                return;
              }
              widget.onReset();
            });
          },
          onLongPressEnd: (_) {
            _exitLongPressTimer?.cancel();
            _exitProgressController.reverse();
            if (mounted) setState(() => _exitLongPressActive = false);
          },
          // ✅ FIX: Sistem jesti/arama araya girerse onLongPressEnd hiç
          // gelmez; timer kurulu kalıp saniyeler sonra reset atabilirdi.
          onLongPressCancel: () {
            _exitLongPressTimer?.cancel();
            _exitProgressController.reverse();
            if (mounted) setState(() => _exitLongPressActive = false);
          },
          child: LayoutBuilder(
            builder: (context, c) {
              final h = c.maxHeight;
              final halfH = h / 2;

              _gsLog('[GAME-SCREEN] ⚠️ LayoutBuilder constraint: maxHeight=$h, maxWidth=${c.maxWidth}');

              // ✅ Bu round'da seçim yapıldı mı kontrol et
              final currentRound = snap?.roundNumber ?? 0;
              final alreadySelectedThisRound = _selectedInRound == currentRound;
              
              // ✅ Tıklama engeli: bu round'da zaten seçildiyse VEYA reconnect sırasında
              final tapDisabled = alreadySelectedThisRound || _isReconnecting;

              // ✅ İlk round yüklenene kadar sadece gradient göster
              final hasVisuals = snap != null && snap.topAsset != null && snap.bottomAsset != null;
              
              return Stack(
                fit: StackFit.expand,
                children: [
                // ✅ LOADING STATE: İlk round yüklenene kadar (yazısız, evrensel)
                if (!hasVisuals)
                  const Center(
                    child: PulseLoader(size: 56, color: GameColors.purple),
                  ),
                  
                // ✅ TOP HALF (with tap handling) - only show when visuals ready
                if (hasVisuals)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: halfH,
                  child: RepaintBoundary(
                    child: AnimatedOpacity(
                      opacity: _isReconnecting ? 0.5 : 1.0,
                      duration: Motion.base,
                      child: IgnorePointer(
                      ignoring: snap.phase != GamePhase.playing || tapDisabled || _isReconnecting,
                      child: AnimatedSwitcher(
                        duration: Motion.base,
                        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                        child: _HalfBoard(
                          key: ValueKey(snap.roundNumber),
                          isTop: true,
                          choice: snap.peerChoice,
                          phase: snap.phase,
                          terminal: snap.terminal,
                          asset: snap.topAsset,
                          availableHeight: halfH, // ✅ Ekran yarısı
                          onTap: () {
                            // ✅ Round kontrolü
                            if (_selectedInRound == currentRound) {
                              _gsLog('[GAME-SCREEN] 🚫 Already selected in this round - tap ignored');
                              return;
                            }
                            
                            _gsLog('[GAME-SCREEN] ✅ TAP ACCEPTED - round=$currentRound, choice=top');
                            _selectedInRound = currentRound;
                            widget.engine.select('top');
                            setState(() {}); // Rebuild to update IgnorePointer
                          },
                        ),
                      ),
                    ),
                    ),
                  ),
                ),
                
                // ✅ BOTTOM HALF (with tap handling) - only show when visuals ready
                if (hasVisuals)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: halfH,
                  child: RepaintBoundary(
                    child: AnimatedOpacity(
                      opacity: _isReconnecting ? 0.5 : 1.0,
                      duration: Motion.base,
                      child: IgnorePointer(
                      ignoring: snap.phase != GamePhase.playing || tapDisabled || _isReconnecting,
                      child: AnimatedSwitcher(
                        duration: Motion.base,
                        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                        child: _HalfBoard(
                          key: ValueKey(snap.roundNumber),
                          isTop: false,
                          choice: snap.localChoice,
                          phase: snap.phase,
                          terminal: snap.terminal,
                          asset: snap.bottomAsset,
                          availableHeight: halfH, // ✅ Ekran yarısı
                          onTap: () {
                            // ✅ Round kontrolü
                            if (_selectedInRound == currentRound) {
                              _gsLog('[GAME-SCREEN] 🚫 Already selected in this round - tap ignored');
                              return;
                            }
                            
                            _gsLog('[GAME-SCREEN] ✅ TAP ACCEPTED - round=$currentRound, choice=bottom');
                            _selectedInRound = currentRound;
                            widget.engine.select('bottom');
                            setState(() {}); // Rebuild to update IgnorePointer
                          },
                        ),
                      ),
                    ),
                    ),
                  ),
                ),

                // ✅ SUCCESS ANIMATION OVERLAY (RepaintBoundary: isolate from main tree)
                if (snap?.phase == GamePhase.terminalSuccess)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: _SuccessAnimationOverlay(
                        // UX-4: Tapa animasyonu atla, anında share ekranına geç.
                        onTap: () {
                          _shareTimer?.cancel();
                          if (!_shareScreenRequested) {
                            _shareScreenRequested = true;
                            widget.onOpenShare();
                          }
                        },
                      ),
                    ),
                  ),

                // ✅ FAILURE ANIMATION OVERLAY (RepaintBoundary: isolate from main tree)
                // ✅ Also show during 'restarting' phase (green arrow before game starts)
                // ✅ AnimatedSwitcher for smooth fade-out transition
                // ✅ FIX: IgnorePointer when phase is playing - overlay fade-out shouldn't block taps
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: snap?.phase == GamePhase.playing,
                    child: AnimatedSwitcher(
                      duration: Motion.base,
                      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                      child: (snap?.phase == GamePhase.terminalFail || snap?.phase == GamePhase.restarting)
                        ? RepaintBoundary(
                            key: const ValueKey('failure_overlay'),
                            child: _FailureAnimationOverlay(
                              engine: widget.engine,
                              onTimeout: () {
                                _gsLog('[GAME-SCREEN] ⏱️ Timeout - full reset to pairing');
                                widget.onReset();
                              },
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('no_overlay')),
                    ),
                  ),
                ),

                // UX-3: Uzun basış çıkış — merkezdeki progress ring
                if (_exitLongPressActive)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: AnimatedBuilder(
                          animation: _exitProgressController,
                          builder: (context, _) => ProgressRing(
                            value: _exitProgressController.value,
                            size: 80,
                            color: GameColors.purple,
                          ),
                        ),
                      ),
                    ),
                  ),

                // ✅ RECONNECT INDICATOR — karartma overlay + merkezde pulse eden turuncu halka
                if (_isReconnecting)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _reconnectPulseController,
                        builder: (context, child) {
                          final pulse = _reconnectPulseController.value;
                          return Container(
                            color: Colors.black.withValues(alpha: 0.45),
                            child: Center(
                              child: Container(
                                width: 56 + (pulse * 12),
                                height: 56 + (pulse * 12),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: GameColors.reconnecting.withValues(alpha: 0.4 + (pulse * 0.6)),
                                    width: 3 + (pulse * 2),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: GameColors.reconnecting.withValues(alpha: 0.2 + (pulse * 0.3)),
                                      blurRadius: 16 + (pulse * 8),
                                      spreadRadius: 2,
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
              ],
            );
          },
        ),
      ),
    ),
    );
  }
}

class _HalfBoard extends StatefulWidget {
  final bool isTop;
  final String? choice;
  final GamePhase phase;
  final RoundTerminal? terminal;
  final String? asset;
  final VoidCallback? onTap;
  final double availableHeight; // ✅ Ekran yarısının yüksekliği

  const _HalfBoard({
    super.key,
    required this.isTop,
    required this.choice,
    required this.phase,
    required this.terminal,
    this.asset,
    this.onTap,
    this.availableHeight = 400, // Default fallback
  });

  @override
  State<_HalfBoard> createState() => _HalfBoardState();
}

class _HalfBoardState extends State<_HalfBoard> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  bool _alreadyTapped = false; // ✅ Bu round'da tıklandı mı (key değişince sıfırlanır)

  late final AnimationController _bounceController;
  late final Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    // 1.0 → 1.07 → 1.0 (seçim yerleşti hissi)
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.07), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.07, end: 1.0), weight: 65),
    ]).animate(CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _choiceColor(widget.choice);

    // ✅ Görsel boyutu: ekran yarısının %85'i (biraz boşluk bırak)
    final imageSize = (widget.availableHeight * 0.85).clamp(200.0, 500.0);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        child: GestureDetector(
          onTapDown: (_) {
            if (!_alreadyTapped) {
              setState(() => _pressed = true);
            }
          },
          onTapUp: (_) {
            if (_alreadyTapped) return; // ✅ Zaten tıklandıysa ignore et
            _alreadyTapped = true; // ✅ Hemen kilitle!
            setState(() => _pressed = false);
            HapticFeedback.selectionClick();
            _bounceController.forward(from: 0);
            widget.onTap?.call();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedBuilder(
            animation: _bounceController,
            builder: (context, child) => Transform.scale(
              scale: _bounceController.isAnimating ? _bounceAnimation.value : 1.0,
              child: child,
            ),
            child: AnimatedScale(
              scale: _pressed ? 0.96 : 1.0,
              duration: const Duration(milliseconds: 50),
              curve: Curves.easeOut,
              child: AnimatedContainer(
              duration: const Duration(milliseconds: 50),
              decoration: BoxDecoration(
                color: InkPlum.surface.withValues(alpha: _pressed ? 0.8 : 0.6),
                borderRadius: Radii.brLg,
                boxShadow: [
                  // ✅ Normal gölge
                  BoxShadow(
                    color: InkPlum.edge.withValues(alpha: _pressed ? 0.4 : 0.7),
                    blurRadius: _pressed ? 8 : 20,
                    offset: Offset(0, _pressed ? 2 : 8),
                    spreadRadius: _pressed ? 0 : 2,
                  ),
                  // ✅ Seçim parlaklığı (glow) - sadece basılıyken
                  if (_pressed)
                    BoxShadow(
                      color: GameColors.purple.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                ],
                border: Border.all(
                  color: _pressed 
                      ? GameColors.borderLight  // Parlak border
                      : GameColors.borderSubtle,
                  width: _pressed ? 3 : 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: SizedBox(
                  width: imageSize,
                  height: imageSize,
                  child: widget.asset != null
                      ? Image.asset(
                          widget.asset!,
                          key: ValueKey<String>(widget.asset ?? 'empty'),
                          width: imageSize,
                          height: imageSize,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return CustomPaint(
                              painter: _BlobPainter(color: c),
                              size: Size.square(imageSize),
                            );
                          },
                        )
                      : CustomPaint(
                          key: ValueKey<String>(widget.choice ?? 'empty'),
                          painter: _BlobPainter(color: c),
                          size: Size.square(imageSize),
                        ),
                ),
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }

  static Color _choiceColor(String? choice) {
    switch (choice) {
      case 'top':
        return GameColors.choiceTop.withValues(alpha: GameColors.opacityHigh);
      case 'bottom':
        return GameColors.choiceBottom.withValues(alpha: GameColors.opacityHigh);
      case GameEngine.noSelectionChoice:
        return GameColors.choiceNone.withValues(alpha: GameColors.opacityLow);
      default:
        return GameColors.choiceDefault.withValues(alpha: GameColors.opacitySubtle);
    }
  }
}

class _BlobPainter extends CustomPainter {
  final Color color;
  const _BlobPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;
    final p = Paint()..color = color;
    canvas.drawCircle(c, r * 0.62, p);
    canvas.drawCircle(c.translate(r * 0.16, -r * 0.12), r * 0.26, p..color = color.withValues(alpha: color.a * 0.75));
    canvas.drawCircle(c.translate(-r * 0.14, r * 0.18), r * 0.22, p..color = color.withValues(alpha: color.a * 0.55));
  }

  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) => oldDelegate.color != color;
}


// ✅ NEW: Success animation overlay
class _SuccessAnimationOverlay extends StatefulWidget {
  final VoidCallback? onTap;
  const _SuccessAnimationOverlay({this.onTap});

  @override
  State<_SuccessAnimationOverlay> createState() => _SuccessAnimationOverlayState();
}

class _SuccessAnimationOverlayState extends State<_SuccessAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Material(
        color: InkPlum.base,
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: _SuccessAnimationPainter(animation: _controller),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ✅ Success animation painter - harmony theme
class _SuccessAnimationPainter extends CustomPainter {
  final AnimationController animation;

  _SuccessAnimationPainter({required this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = (animation.value).clamp(0.0, 1.0);
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 80.0;

    // ✅ Success colors: Ink Plum compatible
    const primaryColor = GameColors.successPrimary;
    const accentColor = GameColors.successAccent;

    // Phase 1: Glow pulse (0.0 - 0.4)
    if (t < 0.4) {
      final glowT = (t / 0.4).clamp(0.0, 1.0);
      final glowOpacity = (lerpDouble(0.0, 1.0, glowT) ?? 0.0).clamp(0.0, 1.0);
      final glowRadius = (lerpDouble(0, radius * 1.5, glowT) ?? 0.0).clamp(0.0, double.infinity);

      final glowPaint = Paint()
        ..color = primaryColor.withValues(alpha: glowOpacity * 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius * 2);
      canvas.drawCircle(center, glowRadius, glowPaint);
    }

    // Phase 2: Rings converge (0.2 - 0.75)
    if (t >= 0.2 && t < 0.75) {
      final ringT = ((t - 0.2) / 0.55).clamp(0.0, 1.0);
      final easeT = Curves.easeInOut.transform(ringT);

      const ring1Start = radius * 1.5;
      const ring2Start = radius * 1.8;
      final ring1Radius = lerpDouble(ring1Start, 0, easeT)!;
      final ring2Radius = lerpDouble(ring2Start, 0, easeT)!;

      final ringOpacity = lerpDouble(0.1, 1.0, ringT)!;

      final ringPaint = Paint()
        ..color = primaryColor.withValues(alpha: ringOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = lerpDouble(3.0, 16.0, ringT)!
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lerpDouble(6.0, 20.0, ringT)!);

      if (ring1Radius > 0) {
        canvas.drawCircle(center, ring1Radius, ringPaint);
      }
      if (ring2Radius > 0) {
        canvas.drawCircle(center, ring2Radius, ringPaint);
      }

      if (ringT > 0.5) {
        final mergeT = ((ringT - 0.5) / 0.5).clamp(0.0, 1.0);
        final mergeRadius = lerpDouble(0, radius * 0.5, mergeT)!;
        final mergeOpacity = lerpDouble(0.0, 0.8, mergeT)!;

        final mergePaint = Paint()
          ..color = accentColor.withValues(alpha: mergeOpacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, mergeRadius * 1.2);
        canvas.drawCircle(center, mergeRadius, mergePaint);
      }
    }

    // Phase 3: Harmony symbol (0.75 - 1.0)
    if (t >= 0.75) {
      final fadeT = ((t - 0.75) / 0.25).clamp(0.0, 1.0);
      final fadeOpacity = lerpDouble(0.8, 0.0, fadeT)!;
      final fadeRadius = lerpDouble(radius * 0.4, radius * 0.8, fadeT)!;

      final fadePaint = Paint()
        ..color = primaryColor.withValues(alpha: fadeOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, fadeRadius * 0.8);
      canvas.drawCircle(center, fadeRadius, fadePaint);

      final pulseWave = math.sin(fadeT * math.pi * 2) * 0.2;
      const symbolOpacity = 0.95;
      final symbolRadius = radius * (0.25 + fadeT * 0.2 + pulseWave);

      // Harmony symbol - two interlocking circles (purple + lime from brand)
      final paint1 = Paint()
        ..color = GameColors.purple.withValues(alpha: symbolOpacity)
        ..strokeWidth = symbolRadius * 0.25
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final paint2 = Paint()
        ..color = GameColors.lime.withValues(alpha: symbolOpacity)
        ..strokeWidth = symbolRadius * 0.25
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawCircle(center + Offset(-symbolRadius * 0.25, 0), symbolRadius * 0.4, paint1);
      canvas.drawCircle(center + Offset(symbolRadius * 0.25, 0), symbolRadius * 0.4, paint2);
    }
  }

  @override
  bool shouldRepaint(covariant _SuccessAnimationPainter oldDelegate) => true;
}

// ✅ NEW: Failure animation overlay
class _FailureAnimationOverlay extends StatefulWidget {
  final GameEngine engine;
  final VoidCallback onTimeout;
  
  const _FailureAnimationOverlay({
    required this.engine,
    required this.onTimeout,
  });

  @override
  State<_FailureAnimationOverlay> createState() => _FailureAnimationOverlayState();
}

class _FailureAnimationOverlayState extends State<_FailureAnimationOverlay>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _buttonController;
  late AnimationController _waitingPulseController;
  late AnimationController _restartingController; // ✅ NEW: Green arrow animation
  bool _animationComplete = false;
  bool _isRestarting = false; // ✅ NEW: Track restarting state
  bool _peerRetryHandled = false; // Peer retry gelince timer yeniden başlatıldı mı
  Timer? _timeoutTimer;
  late StreamSubscription<GameState> _engineSub;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    
    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    
    _waitingPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    // ✅ NEW: Restarting animation (green arrow scale + pulse)
    _restartingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    
    // Listen to engine state for peer retry updates AND restarting phase
    _engineSub = widget.engine.states.listen((state) {
      if (mounted) {
        // Restarting phase: yeşil ok göster, timer'ı iptal et
        if (state.phase == GamePhase.restarting && !_isRestarting) {
          _gsLog('[FAILURE-OVERLAY] 🚀 RESTARTING phase detected - showing green arrow!');
          _isRestarting = true;
          _timeoutTimer?.cancel();
          _restartingController.forward();
        }

        // Peer retry bastı: local'e taze 10 saniye ver.
        // Peer göstergesi (pulsing dot) zaten ekranda belirir; bu timer yeniden
        // başlatma, local kullanıcının o göstergeye tepki vermesi için süre tanır.
        if (widget.engine.peerRetryIntent &&
            !_peerRetryHandled &&
            _animationComplete &&
            !widget.engine.localRetryIntent &&
            !_isRestarting) {
          _peerRetryHandled = true;
          _timeoutTimer?.cancel();
          _gsLog('[FAILURE-OVERLAY] 👥 Peer retry geldi - 10s timer yenilendi');
          _timeoutTimer = Timer(const Duration(seconds: 10), () {
            if (mounted && !widget.engine.localRetryIntent) {
              _gsLog('[FAILURE-OVERLAY] ⏱️ Uzatılmış süre doldu - tam reset');
              widget.onTimeout();
            }
          });
        }

        setState(() {});
      }
    });

    _controller.forward().then((_) {
      if (mounted) {
        setState(() => _animationComplete = true);
        _buttonController.forward();

        // Local kullanıcı retry basmadıysa 10 saniye sonra sıfırla.
        // Peer retry bastıysa _engineSub listener timer'ı yeniden başlatır.
        _timeoutTimer = Timer(const Duration(seconds: 10), () {
          if (mounted && !widget.engine.localRetryIntent) {
            _gsLog('[FAILURE-OVERLAY] ⏱️ 10 saniye geçti - tam reset');
            widget.onTimeout();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _buttonController.dispose();
    _waitingPulseController.dispose();
    _restartingController.dispose();
    _timeoutTimer?.cancel();
    _engineSub.cancel();
    super.dispose();
  }
  
  void _onRetryPressed() {
    if (widget.engine.localRetryIntent) return; // Already pressed
    
    _gsLog('[FAILURE-OVERLAY] 🔄 Retry button pressed - sending intent');
    _timeoutTimer?.cancel(); // Cancel timeout - user is engaged
    widget.engine.sendRetryIntent();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // ✅ NEW: When restarting, show green triangle (like radar match animation)
    if (_isRestarting) {
      return AnimatedBuilder(
        animation: _restartingController,
        builder: (context, child) {
          // ✅ Scale in with elastic effect, then fade out via AnimatedSwitcher
          return Material(
            color: InkPlum.base,
            child: Center(
              child: Transform.scale(
                scale: Curves.elasticOut.transform(_restartingController.value),
                child: const CustomPaint(
                  size: Size(120, 120),
                  painter: _GreenTrianglePainter(
                    opacity: 1.0,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    
    return GestureDetector(
      // Herhangi bir yere uzun basınca ana eşleşme ekranına dön.
      onLongPress: () {
        _gsLog('[FAILURE-OVERLAY] 👆 Long press - ana ekrana dönülüyor');
        _timeoutTimer?.cancel();
        widget.onTimeout();
      },
      child: Material(
      color: InkPlum.base,
      child: Stack(
        children: [
          // Failure animation
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  painter: _FailureAnimationPainter(animation: _controller),
                );
              },
            ),
          ),
          
          // ✅ Retry button (appears after animation)
          if (_animationComplete)
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Center(
                child: FadeTransition(
                  opacity: _buttonController,
                  child: ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _buttonController,
                      curve: Curves.elasticOut,
                    ),
                    // Retry butonu alanına uzun basınca dış GestureDetector'ın
                    // onLongPress'i (hard reset) tetiklenmesin diye absorb ediyoruz.
                    child: GestureDetector(
                      onLongPress: () {},
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ✅ Peer waiting indicator (if peer pressed but not us)
                        if (widget.engine.peerRetryIntent && !widget.engine.localRetryIntent)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: AnimatedBuilder(
                              animation: _waitingPulseController,
                              builder: (context, child) {
                                return Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: GameColors.retryActive.withValues(
                                      alpha: 0.5 + _waitingPulseController.value * 0.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: GameColors.retryActive.withValues(alpha: 0.4),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),

                        GestureDetector(
                          onTap: _onRetryPressed,
                          child: AnimatedContainer(
                            duration: Motion.base,
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.engine.localRetryIntent
                                  ? GameColors.retryActive.withValues(alpha: 0.3)
                                  : GameColors.interactiveLight.withValues(alpha: 0.15),
                              border: Border.all(
                                color: widget.engine.localRetryIntent
                                    ? GameColors.retryActive.withValues(alpha: 0.8)
                                    : GameColors.borderLight,
                                width: 2,
                              ),
                            ),
                            child: widget.engine.localRetryIntent
                                ? AnimatedBuilder(
                                    animation: _waitingPulseController,
                                    builder: (context, child) {
                                      return Icon(
                                        Icons.check_rounded,
                                        color: GameColors.retryActive.withValues(
                                          alpha: 0.7 + _waitingPulseController.value * 0.3,
                                        ),
                                        size: 36,
                                      );
                                    },
                                  )
                                : Icon(
                                    Icons.refresh_rounded,
                                    color: GameColors.interactiveLight.withValues(alpha: GameColors.opacityHigh),
                                    size: 36,
                                  ),
                          ),
                        ),
                      ],
                    ),
                    ), // GestureDetector (long-press absorber)
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }
}

// ✅ Failure animation painter - red X theme
class _FailureAnimationPainter extends CustomPainter {
  final AnimationController animation;

  _FailureAnimationPainter({required this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = (animation.value).clamp(0.0, 1.0);
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 80.0;

    // ✅ Failure colors: Ink Plum compatible
    const primaryColor = GameColors.failurePrimary;
    const accentColor = GameColors.failureAccent;

    // Phase 1: Glow pulse (0.0 - 0.4)
    if (t < 0.4) {
      final glowT = (t / 0.4).clamp(0.0, 1.0);
      final glowOpacity = (lerpDouble(0.0, 1.0, glowT) ?? 0.0).clamp(0.0, 1.0);
      final glowRadius = (lerpDouble(0, radius * 1.5, glowT) ?? 0.0).clamp(0.0, double.infinity);

      final glowPaint = Paint()
        ..color = primaryColor.withValues(alpha: glowOpacity * 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius * 2);
      canvas.drawCircle(center, glowRadius, glowPaint);
    }

    // Phase 2: Rings converge (0.2 - 0.75)
    if (t >= 0.2 && t < 0.75) {
      final ringT = ((t - 0.2) / 0.55).clamp(0.0, 1.0);
      final easeT = Curves.easeInOut.transform(ringT);

      const ring1Start = radius * 1.5;
      const ring2Start = radius * 1.8;
      final ring1Radius = lerpDouble(ring1Start, 0, easeT)!;
      final ring2Radius = lerpDouble(ring2Start, 0, easeT)!;

      final ringOpacity = lerpDouble(0.1, 1.0, ringT)!;

      final ringPaint = Paint()
        ..color = primaryColor.withValues(alpha: ringOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = lerpDouble(3.0, 16.0, ringT)!
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lerpDouble(6.0, 20.0, ringT)!);

      if (ring1Radius > 0) {
        canvas.drawCircle(center, ring1Radius, ringPaint);
      }
      if (ring2Radius > 0) {
        canvas.drawCircle(center, ring2Radius, ringPaint);
      }

      if (ringT > 0.5) {
        final mergeT = ((ringT - 0.5) / 0.5).clamp(0.0, 1.0);
        final mergeRadius = lerpDouble(0, radius * 0.5, mergeT)!;
        final mergeOpacity = lerpDouble(0.0, 0.8, mergeT)!;

        final mergePaint = Paint()
          ..color = accentColor.withValues(alpha: mergeOpacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, mergeRadius * 1.2);
        canvas.drawCircle(center, mergeRadius, mergePaint);
      }
    }

    // Phase 3: X mark (0.75 - 1.0)
    if (t >= 0.75) {
      final fadeT = ((t - 0.75) / 0.25).clamp(0.0, 1.0);
      final fadeOpacity = lerpDouble(0.8, 0.0, fadeT)!;
      final fadeRadius = lerpDouble(radius * 0.4, radius * 0.8, fadeT)!;

      final fadePaint = Paint()
        ..color = primaryColor.withValues(alpha: fadeOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, fadeRadius * 0.8);
      canvas.drawCircle(center, fadeRadius, fadePaint);

      final pulseWave = math.sin(fadeT * math.pi * 2) * 0.2;
      const xOpacity = 0.95;
      final xRadius = radius * (0.25 + fadeT * 0.2 + pulseWave);

      final paint = Paint()
        ..color = GameColors.failureGlow.withValues(alpha: xOpacity)
        ..strokeWidth = xRadius * 0.25
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(center.dx - xRadius * 0.35, center.dy - xRadius * 0.35);
      path.lineTo(center.dx + xRadius * 0.35, center.dy + xRadius * 0.35);
      path.moveTo(center.dx + xRadius * 0.35, center.dy - xRadius * 0.35);
      path.lineTo(center.dx - xRadius * 0.35, center.dy + xRadius * 0.35);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FailureAnimationPainter oldDelegate) => true;
}

// ✅ NEW: Green triangle painter for restart animation (matches radar screen)
class _GreenTrianglePainter extends CustomPainter {
  final double opacity;

  const _GreenTrianglePainter({
    this.opacity = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerX = w * 0.5;
    final centerY = h * 0.5;

    // Main upward-pointing triangle (same as radar screen)
    final arrowPath = Path();
    arrowPath.moveTo(centerX, centerY - h * 0.35); // Top point
    arrowPath.lineTo(centerX + w * 0.35, centerY + h * 0.25); // Bottom right
    arrowPath.lineTo(centerX - w * 0.35, centerY + h * 0.25); // Bottom left
    arrowPath.close();

    // Notch cutout
    final notchPath = Path();
    notchPath.moveTo(centerX - w * 0.20, centerY + h * 0.22);
    notchPath.lineTo(centerX + w * 0.20, centerY + h * 0.22);
    notchPath.lineTo(centerX, centerY + h * 0.35);
    notchPath.close();

    // Combined path with cutout
    final combinedPath = Path();
    combinedPath.fillType = PathFillType.evenOdd;
    combinedPath.addPath(arrowPath, Offset.zero);
    combinedPath.addPath(notchPath, Offset.zero);

    // Draw the green triangle
    final paint = Paint()
      ..color = GameColors.lime.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(combinedPath, paint);
  }

  @override
  bool shouldRepaint(covariant _GreenTrianglePainter oldDelegate) {
    return oldDelegate.opacity != opacity;
  }
}
