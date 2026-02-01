import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../ui/color_palette_manager.dart';
import 'game_engine.dart';
import 'game_state.dart';
import 'models.dart';

/// ✅ OPTIMIZATION: Image precache helper
class _ImagePrecacher {
  static final Set<String> _precachedAssets = {};
  
  static Future<void> precacheIfNeeded(BuildContext context, String? asset) async {
    if (asset == null || _precachedAssets.contains(asset)) return;
    
    try {
      await precacheImage(AssetImage(asset), context);
      _precachedAssets.add(asset);
      print('[PRECACHE] ✅ Precached: $asset');
    } catch (e) {
      print('[PRECACHE] ⚠️ Failed to precache $asset: $e');
    }
  }
  
  static void clear() {
    _precachedAssets.clear();
  }
}

class GameScreen extends StatefulWidget {
  final GameEngine engine;
  final VoidCallback onOpenShare;
  final VoidCallback onReset; // ✅ NEW: Reset callback for terminalFail

  const GameScreen({
    super.key,
    required this.engine,
    required this.onOpenShare,
    required this.onReset,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  RoundSnapshot? _snap;
  late final StreamSubscription<RoundSnapshot> _sub;
  bool _disposed = false;
  bool _shareScreenRequested = false; // ✅ NEW: Prevent duplicate share screen calls
  int? _selectedInRound; // ✅ Bu round'da seçim yapıldı mı (round numarası)

  @override
  void initState() {
    super.initState();
    
    // ✅ SAFETY: Check initial engine state - if already terminal, something is wrong
    final initialPhase = widget.engine.state.phase;
    print('[GAME-SCREEN] 🆕 initState - initial engine phase: $initialPhase');
    if (initialPhase == GamePhase.terminalSuccess || initialPhase == GamePhase.terminalFail) {
      print('[GAME-SCREEN] ⚠️ WARNING: Engine started in terminal state! This should not happen.');
    }
    
    _sub = widget.engine.snapshots.listen((s) {
      // ✅ CRITICAL: Check mounted FIRST before any operations
      if (!mounted) {
        print('[GAME-SCREEN] ⚠️ Not mounted - ignoring event');
        return;
      }
      
      if (_disposed) {
        print('[GAME-SCREEN] 🛑 Disposed - ignoring snapshot, cancelling subscription');
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
          oldSnap.terminal != s.terminal;
      
      if (!needsRebuild) {
        return; // Skip unnecessary rebuilds
      }
      
      // ✅ SAFETY: Log phase transitions
      if (oldSnap?.phase != s.phase) {
        print('[GAME-SCREEN] 🔄 Phase changed: ${oldSnap?.phase} -> ${s.phase}');
      }
      
      setState(() => _snap = s);
      
      // ✅ When success, show animation then share (3 sec animation)
      if (s.phase == GamePhase.terminalSuccess) {
        if (_shareScreenRequested) {
          print('[GAME-SCREEN] ⚠️ Share screen already requested, ignoring duplicate');
          return;
        }
        
        // ✅ SAFETY: Only proceed if we have played at least 5 rounds
        final similarity = widget.engine.state.similarity;
        if (similarity < 5) {
          print('[GAME-SCREEN] ⚠️ terminalSuccess but similarity=$similarity (not 5)! IGNORING spurious event.');
          return;
        }
        
        print('[GAME-SCREEN] 🎉 terminalSuccess - animation playing (similarity=$similarity)');
        print('[GAME-SCREEN] 🎉 Waiting 3.2 sec before calling onOpenShare()');
        Future.delayed(const Duration(milliseconds: 3200), () {
          if (_disposed || !mounted) {
            print('[GAME-SCREEN] 🛑 Screen disposed/unmounted before onOpenShare()');
            return;
          }
          if (_shareScreenRequested) {
            print('[GAME-SCREEN] ⚠️ Share screen already requested, ignoring');
            return;
          }
          _shareScreenRequested = true;
          print('[GAME-SCREEN] 🎉 3.2 sec passed - calling onOpenShare()');
          widget.onOpenShare();
          print('[GAME-SCREEN] 🎉 onOpenShare() called');
        });
      }
      
      // ✅ When failure, show animation then RESET (not share screen)
      if (s.phase == GamePhase.terminalFail) {
        if (_shareScreenRequested) {
          print('[GAME-SCREEN] ⚠️ Reset already requested, ignoring duplicate');
          return;
        }
        
        // ✅ SAFETY: Only proceed if we have 5 differences
        final difference = widget.engine.state.difference;
        if (difference < 5) {
          print('[GAME-SCREEN] ⚠️ terminalFail but difference=$difference (not 5)! IGNORING spurious event.');
          return;
        }
        
        print('[GAME-SCREEN] ❌ terminalFail - animation playing (difference=$difference)');
        Future.delayed(const Duration(milliseconds: 3200), () {
          if (_disposed || !mounted) {
            print('[GAME-SCREEN] 🛑 Screen disposed/unmounted before onReset()');
            return;
          }
          if (_shareScreenRequested) {
            print('[GAME-SCREEN] ⚠️ Reset already requested, ignoring');
            return;
          }
          _shareScreenRequested = true;
          print('[GAME-SCREEN] ❌ Animation done - resetting app');
          widget.onReset(); // ✅ Reset instead of opening share screen
        });
      }
    });
  }

  @override
  void dispose() {
    print('[GAME-SCREEN] 🛑 Disposing GameScreen...');
    _disposed = true;
    print('[GAME-SCREEN] 🛑 Immediately cancelling subscription on dispose...');
    _sub.cancel();
    print('[GAME-SCREEN] 🛑 Subscription cancelled immediately');
    super.dispose();
    print('[GAME-SCREEN] ✅ GameScreen disposed completely');
  }

  @override
  Widget build(BuildContext context) {
    if (_disposed) {
      print('[GAME-SCREEN] 🛑 Build called but screen disposed - returning empty');
      return const SizedBox.shrink();
    }
    
    final snap = _snap;
    print('[GAME-SCREEN] 🎮 BUILD CALLED - snap=$snap, phase=${snap?.phase}, rid=${snap?.roundNumber}');
    
    // ✅ OPTIMIZATION: Precache current round images
    if (snap != null) {
      _ImagePrecacher.precacheIfNeeded(context, snap.topAsset);
      _ImagePrecacher.precacheIfNeeded(context, snap.bottomAsset);
    }
    
    // ✅ Get palette colors
    final paletteManager = ColorPaletteManager();
    final palette = paletteManager.currentPalette;
    final colors = palette.colors;
    
    // ✅ Fallback if colors is empty
    final finalColors = colors.isEmpty ? const [
      Color(0xFF1a1a2e),
      Color(0xFF16213e),
      Color(0xFF0f3460),
    ] : colors;
    
    print('[GAME-SCREEN] 🎨 Palette: ${palette.emoji}, Colors count: ${finalColors.length}');
    print('[GAME-SCREEN] 🎨 First color: ${finalColors[0]}, Last color: ${finalColors[finalColors.length - 1]}');
    
    return SizedBox.expand(
      child: Container(
        decoration: BoxDecoration(
          gradient: paletteManager.currentGradient,
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // ❌ REMOVED: onDoubleTap was causing accidental ShareScreen opens
          // ShareScreen only opens when game reaches terminal state
          child: LayoutBuilder(
            builder: (context, c) {
              final h = c.maxHeight;
              final halfH = h / 2;

              print('[GAME-SCREEN] ⚠️ LayoutBuilder constraint: maxHeight=$h, maxWidth=${c.maxWidth}');

              // ✅ Bu round'da seçim yapıldı mı kontrol et
              final currentRound = snap?.roundNumber ?? 0;
              final alreadySelectedThisRound = _selectedInRound == currentRound;
              
              // ✅ Tıklama engeli: sadece bu round'da zaten seçildiyse
              // NOT: Cooldown kaldırıldı - engine zaten localFinal ile koruma yapıyor
              final tapDisabled = alreadySelectedThisRound;

              // ✅ İlk round yüklenene kadar sadece gradient göster
              final hasVisuals = snap != null && snap.topAsset != null && snap.bottomAsset != null;
              
              return Stack(
                fit: StackFit.expand,
                children: [
                // ✅ LOADING STATE: İlk round yüklenene kadar (yazısız, evrensel)
                if (!hasVisuals)
                  Center(
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                  
                // ✅ TOP HALF (with tap handling) - only show when visuals ready
                if (hasVisuals)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: halfH,
                  child: RepaintBoundary(
                    child: IgnorePointer(
                      ignoring: snap?.phase != GamePhase.playing || tapDisabled,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                        child: _HalfBoard(
                          key: ValueKey(snap?.roundNumber),
                          isTop: true,
                          choice: snap?.peerChoice,
                          phase: snap?.phase ?? GamePhase.playing,
                          terminal: snap?.terminal,
                          asset: snap?.topAsset,
                          onTap: () {
                            // ✅ Round kontrolü
                            if (_selectedInRound == currentRound) {
                              print('[GAME-SCREEN] 🚫 Already selected in this round - tap ignored');
                              return;
                            }
                            
                            print('[GAME-SCREEN] ✅ TAP ACCEPTED - round=$currentRound, choice=top');
                            _selectedInRound = currentRound;
                            widget.engine.select('top');
                            setState(() {}); // Rebuild to update IgnorePointer
                          },
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
                    child: IgnorePointer(
                      ignoring: snap?.phase != GamePhase.playing || tapDisabled,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                        child: _HalfBoard(
                          key: ValueKey(snap?.roundNumber),
                          isTop: false,
                          choice: snap?.localChoice,
                          phase: snap?.phase ?? GamePhase.playing,
                          terminal: snap?.terminal,
                          asset: snap?.bottomAsset,
                          onTap: () {
                            // ✅ Round kontrolü
                            if (_selectedInRound == currentRound) {
                              print('[GAME-SCREEN] 🚫 Already selected in this round - tap ignored');
                              return;
                            }
                            
                            print('[GAME-SCREEN] ✅ TAP ACCEPTED - round=$currentRound, choice=bottom');
                            _selectedInRound = currentRound;
                            widget.engine.select('bottom');
                            setState(() {}); // Rebuild to update IgnorePointer
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // ✅ SUCCESS ANIMATION OVERLAY (RepaintBoundary: isolate from main tree)
                if (snap?.phase == GamePhase.terminalSuccess)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: _SuccessAnimationOverlay(),
                    ),
                  ),

                // ✅ FAILURE ANIMATION OVERLAY (RepaintBoundary: isolate from main tree)
                if (snap?.phase == GamePhase.terminalFail)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: _FailureAnimationOverlay(),
                    ),
                  ),

                // ✅ RESULT OVERLAY
                if (snap?.phase == GamePhase.share && snap?.terminal != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _ResultOverlay(terminal: snap!.terminal!),
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

  const _HalfBoard({
    super.key,
    required this.isTop,
    required this.choice,
    required this.phase,
    required this.terminal,
    this.asset,
    this.onTap,
  });

  @override
  State<_HalfBoard> createState() => _HalfBoardState();
}

class _HalfBoardState extends State<_HalfBoard> {
  bool _pressed = false;
  bool _alreadyTapped = false; // ✅ Bu round'da tıklandı mı (key değişince sıfırlanır)

  @override
  Widget build(BuildContext context) {
    final c = _choiceColor(widget.choice);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
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
            widget.onTap?.call();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 50),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 50),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(_pressed ? 0.4 : 0.3),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  // ✅ Normal gölge
                  BoxShadow(
                    color: Colors.black.withOpacity(_pressed ? 0.2 : 0.5),
                    blurRadius: _pressed ? 8 : 20,
                    offset: Offset(0, _pressed ? 2 : 8),
                    spreadRadius: _pressed ? 0 : 2,
                  ),
                  // ✅ Seçim parlaklığı (glow) - sadece basılıyken
                  if (_pressed)
                    BoxShadow(
                      color: Colors.white.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                ],
                border: Border.all(
                  color: _pressed 
                      ? Colors.white.withOpacity(0.8)  // Parlak border
                      : Colors.white.withOpacity(0.2),
                  width: _pressed ? 3 : 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: widget.asset != null
                    ? Image.asset(
                        widget.asset!,
                        key: ValueKey<String>(widget.asset ?? 'empty'),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return CustomPaint(
                            painter: _BlobPainter(color: c),
                            size: const Size.square(220),
                          );
                        },
                      )
                    : CustomPaint(
                        key: ValueKey<String>(widget.choice ?? 'empty'),
                        painter: _BlobPainter(color: c),
                        size: const Size.square(220),
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
        return Colors.tealAccent.withOpacity(0.85);
      case 'bottom':
        return Colors.orangeAccent.withOpacity(0.85);
      case GameEngine.noSelectionChoice:
        return Colors.white.withOpacity(0.10);
      default:
        return Colors.white.withOpacity(0.04);
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
    canvas.drawCircle(c.translate(r * 0.16, -r * 0.12), r * 0.26, p..color = color.withOpacity(color.opacity * 0.75));
    canvas.drawCircle(c.translate(-r * 0.14, r * 0.18), r * 0.22, p..color = color.withOpacity(color.opacity * 0.55));
  }

  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) => oldDelegate.color != color;
}


class _ResultOverlay extends StatefulWidget {
  final RoundTerminal terminal;
  const _ResultOverlay({required this.terminal});

  @override
  State<_ResultOverlay> createState() => _ResultOverlayState();
}

class _ResultOverlayState extends State<_ResultOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = switch (widget.terminal) {
      RoundTerminal.match => Colors.greenAccent.withOpacity(0.18),
      RoundTerminal.mismatch => Colors.redAccent.withOpacity(0.18),
      RoundTerminal.localNoSelection => Colors.yellowAccent.withOpacity(0.16),
      RoundTerminal.peerNoSelection => Colors.cyanAccent.withOpacity(0.16),
      RoundTerminal.bothNoSelection => Colors.white.withOpacity(0.12),
    };

    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) {
        return ColoredBox(
          color: base.withOpacity(base.opacity * (0.65 + 0.35 * _a.value)),
          child: Center(
            child: Transform.scale(
              scale: 0.92 + 0.06 * _a.value,
              child: CustomPaint(
                painter: _ResultMarkPainter(terminal: widget.terminal),
                size: const Size.square(240),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ResultMarkPainter extends CustomPainter {
  final RoundTerminal terminal;
  const _ResultMarkPainter({required this.terminal});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;

    final color = switch (terminal) {
      RoundTerminal.match => Colors.greenAccent.withOpacity(0.9),
      RoundTerminal.mismatch => Colors.redAccent.withOpacity(0.9),
      RoundTerminal.localNoSelection => Colors.yellowAccent.withOpacity(0.9),
      RoundTerminal.peerNoSelection => Colors.cyanAccent.withOpacity(0.9),
      RoundTerminal.bothNoSelection => Colors.white.withOpacity(0.65),
    };

    final p = Paint()..color = color;
    final ring = Paint()
      ..color = color.withOpacity(color.opacity * 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;

    canvas.drawCircle(c, r * 0.55, ring);
    canvas.drawCircle(c.translate(r * 0.10, -r * 0.08), r * 0.18, p);
    canvas.drawCircle(c.translate(-r * 0.12, r * 0.10), r * 0.14, p..color = color.withOpacity(color.opacity * 0.75));
  }

  @override
  bool shouldRepaint(covariant _ResultMarkPainter oldDelegate) => oldDelegate.terminal != terminal;
}

// ✅ NEW: Success animation overlay
class _SuccessAnimationOverlay extends StatefulWidget {
  const _SuccessAnimationOverlay();

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
    return Material(
      color: Colors.black.withOpacity(0.9),
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
    final radius = 80.0;

    // ✅ Success colors: Green/Blue for harmony
    final primaryColor = Colors.green.shade700;
    final accentColor = Colors.blue.shade600;

    // Phase 1: Glow pulse (0.0 - 0.4)
    if (t < 0.4) {
      final glowT = (t / 0.4).clamp(0.0, 1.0);
      final glowOpacity = (lerpDouble(0.0, 1.0, glowT) ?? 0.0).clamp(0.0, 1.0);
      final glowRadius = (lerpDouble(0, radius * 1.5, glowT) ?? 0.0).clamp(0.0, double.infinity);

      final glowPaint = Paint()
        ..color = primaryColor.withOpacity(glowOpacity * 0.5)
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
        ..color = primaryColor.withOpacity(ringOpacity)
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
          ..color = accentColor.withOpacity(mergeOpacity)
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
        ..color = primaryColor.withOpacity(fadeOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, fadeRadius * 0.8);
      canvas.drawCircle(center, fadeRadius, fadePaint);

      final pulseWave = math.sin(fadeT * math.pi * 2) * 0.2;
      final symbolOpacity = 0.95;
      final symbolRadius = radius * (0.25 + fadeT * 0.2 + pulseWave);

      // Harmony symbol - two interlocking circles
      final paint1 = Paint()
        ..color = Colors.green.shade400.withOpacity(symbolOpacity)
        ..strokeWidth = symbolRadius * 0.25
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final paint2 = Paint()
        ..color = Colors.blue.shade400.withOpacity(symbolOpacity)
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
  const _FailureAnimationOverlay();

  @override
  State<_FailureAnimationOverlay> createState() => _FailureAnimationOverlayState();
}

class _FailureAnimationOverlayState extends State<_FailureAnimationOverlay>
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
    return Material(
      color: Colors.black.withOpacity(0.9),
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _FailureAnimationPainter(animation: _controller),
            );
          },
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
    final radius = 80.0;

    final primaryColor = Colors.red.shade900;
    final accentColor = Colors.orange.shade800;

    // Phase 1: Glow pulse (0.0 - 0.4)
    if (t < 0.4) {
      final glowT = (t / 0.4).clamp(0.0, 1.0);
      final glowOpacity = (lerpDouble(0.0, 1.0, glowT) ?? 0.0).clamp(0.0, 1.0);
      final glowRadius = (lerpDouble(0, radius * 1.5, glowT) ?? 0.0).clamp(0.0, double.infinity);

      final glowPaint = Paint()
        ..color = primaryColor.withOpacity(glowOpacity * 0.5)
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
        ..color = primaryColor.withOpacity(ringOpacity)
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
          ..color = accentColor.withOpacity(mergeOpacity)
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
        ..color = primaryColor.withOpacity(fadeOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, fadeRadius * 0.8);
      canvas.drawCircle(center, fadeRadius, fadePaint);

      final pulseWave = math.sin(fadeT * math.pi * 2) * 0.2;
      final xOpacity = 0.95;
      final xRadius = radius * (0.25 + fadeT * 0.2 + pulseWave);

      final paint = Paint()
        ..color = Colors.red.shade400.withOpacity(xOpacity)
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
