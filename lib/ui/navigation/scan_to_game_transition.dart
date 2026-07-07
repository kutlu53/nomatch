import 'dart:ui';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SCAN TO GAME TRANSITION - Premium Cinematic Transition
// ═══════════════════════════════════════════════════════════════════════════════

/// Orchestrates the cinematic transition from scan/match screen to game screen.
/// 
/// Timeline (~240ms total):
/// - Hold (0-60ms): SecretLink holds, background darkens slightly
/// - Reveal (60-240ms): Game fades in with subtle scale, SecretLink fades out
/// 
/// No glow, no slide, no confetti - just fade, small scale, very subtle blur.
class ScanToGameTransition extends StatefulWidget {
  /// Current UI state
  final ScanToGameState state;
  
  /// The scan/radar screen content
  final Widget scanChild;
  
  /// The game screen content
  final Widget gameChild;
  
  /// The secret link overlay (two dots + connection)
  final Widget? secretLinkOverlay;
  
  /// Called when game screen is fully visible
  final VoidCallback? onGameShown;

  const ScanToGameTransition({
    super.key,
    required this.state,
    required this.scanChild,
    required this.gameChild,
    this.secretLinkOverlay,
    this.onGameShown,
  });

  @override
  State<ScanToGameTransition> createState() => _ScanToGameTransitionState();
}

/// States for the scan-to-game transition
enum ScanToGameState {
  scan,      // Showing scan/radar screen
  matched,   // Match animation playing (SecretLink visible)
  transitioning, // Transitioning to game
  game,      // Showing game screen
}

class _ScanToGameTransitionState extends State<ScanToGameTransition>
    with TickerProviderStateMixin {
  
  late final AnimationController _transitionController;
  
  // Hold phase (0-60ms / 240ms = 0-0.25)
  late final Animation<double> _holdDarkenAnim;
  
  // Reveal phase (60-240ms / 240ms = 0.25-1.0)
  late final Animation<double> _gameOpacityAnim;
  late final Animation<double> _gameScaleAnim;
  late final Animation<double> _gameBlurAnim;
  
  // SecretLink fade (last 120ms = 0.5-1.0)
  late final Animation<double> _linkScaleAnim;
  late final Animation<double> _linkFadeAnim;

  @override
  void initState() {
    super.initState();
    
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    
    // Hold: background darkens (0-60ms)
    _holdDarkenAnim = Tween<double>(begin: 0.0, end: 0.04).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.0, 0.25, curve: Curves.easeOut),
      ),
    );
    
    // Game reveal: opacity (60-240ms)
    _gameOpacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.25, 1.0, curve: Curves.easeInOut),
      ),
    );
    
    // Game reveal: scale (60-240ms)
    _gameScaleAnim = Tween<double>(begin: 0.985, end: 1.0).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.25, 1.0, curve: Curves.easeOut),
      ),
    );
    
    // Game reveal: blur clears (60-240ms)
    _gameBlurAnim = Tween<double>(begin: 2.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.25, 1.0, curve: Curves.easeOut),
      ),
    );
    
    // SecretLink: scale pulse (0-50% then 50-100% of transition)
    _linkScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.06), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _transitionController,
      curve: Curves.easeInOut,
    ));
    
    // SecretLink: fade out (last 120ms = 0.5-1.0)
    _linkFadeAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
      ),
    );
    
    _transitionController.addStatusListener(_onTransitionStatus);
  }
  
  void _onTransitionStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onGameShown?.call();
    }
  }

  @override
  void didUpdateWidget(covariant ScanToGameTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.state != oldWidget.state) {
      if (widget.state == ScanToGameState.transitioning) {
        _transitionController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _transitionController.removeStatusListener(_onTransitionStatus);
    _transitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showGame = widget.state == ScanToGameState.transitioning || 
                     widget.state == ScanToGameState.game;
    final showScan = widget.state != ScanToGameState.game;
    final showLink = widget.state == ScanToGameState.matched || 
                     widget.state == ScanToGameState.transitioning;

    return AnimatedBuilder(
      animation: _transitionController,
      builder: (context, child) {
        return Stack(
          children: [
            // Layer 1: Scan content (fades out during transition)
            if (showScan)
              Positioned.fill(
                child: Opacity(
                  opacity: widget.state == ScanToGameState.transitioning
                      ? (1.0 - _gameOpacityAnim.value * 0.5) // Partial fade
                      : 1.0,
                  child: widget.scanChild,
                ),
              ),
            
            // Layer 2: Darken overlay during hold phase
            if (widget.state == ScanToGameState.transitioning && _holdDarkenAnim.value > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withValues(alpha: _holdDarkenAnim.value),
                  ),
                ),
              ),
            
            // Layer 3: SecretLink overlay (scales and fades)
            if (showLink && widget.secretLinkOverlay != null)
              Center(
                child: Transform.scale(
                  scale: widget.state == ScanToGameState.transitioning
                      ? _linkScaleAnim.value
                      : 1.0,
                  child: Opacity(
                    opacity: widget.state == ScanToGameState.transitioning
                        ? _linkFadeAnim.value
                        : 1.0,
                    child: widget.secretLinkOverlay,
                  ),
                ),
              ),
            
            // Layer 4: Game content (fades in with scale and blur)
            if (showGame)
              Positioned.fill(
                child: _GameEntryAnimation(
                  opacity: widget.state == ScanToGameState.game 
                      ? 1.0 
                      : _gameOpacityAnim.value,
                  scale: widget.state == ScanToGameState.game 
                      ? 1.0 
                      : _gameScaleAnim.value,
                  blur: widget.state == ScanToGameState.game 
                      ? 0.0 
                      : _gameBlurAnim.value,
                  child: widget.gameChild,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Game entry animation widget with opacity, scale, and blur
class _GameEntryAnimation extends StatelessWidget {
  final double opacity;
  final double scale;
  final double blur;
  final Widget child;

  const _GameEntryAnimation({
    required this.opacity,
    required this.scale,
    required this.blur,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    Widget result = child;
    
    // Apply blur only when needed (performance)
    if (blur > 0.01) {
      result = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: TileMode.decal,
        ),
        child: result,
      );
    }
    
    // Apply scale
    if (scale != 1.0) {
      result = Transform.scale(
        scale: scale,
        child: result,
      );
    }
    
    // Apply opacity
    if (opacity < 1.0) {
      result = Opacity(
        opacity: opacity,
        child: result,
      );
    }
    
    return RepaintBoundary(child: result);
  }
}
