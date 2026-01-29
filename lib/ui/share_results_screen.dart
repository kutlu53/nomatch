import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/app_coordinator.dart';
import '../app/app_phase.dart' as app_phase;
import 'color_palette_manager.dart';

/// Share results screen - displays peer's shared information
/// Minimal design - only the information
/// Single tap to copy, double tap to reset
class ShareResultsScreen extends StatefulWidget {
  final AppCoordinator coordinator;
  final AppViewState state;

  const ShareResultsScreen({
    super.key,
    required this.coordinator,
    required this.state,
  });

  @override
  State<ShareResultsScreen> createState() => _ShareResultsScreenState();
}

class _ShareResultsScreenState extends State<ShareResultsScreen> with TickerProviderStateMixin {
  bool _copied = false;
  bool _longPressActive = false;
  Timer? _longPressTimer;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _transitioning = false;

  @override
  void initState() {
    super.initState();
    print("[SHARE_RESULTS] Displaying peer's share info 📱");
    
    // ✅ Setup fade animation
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOutCubic),
    );
    
    // ✅ Auto-reset after 30 seconds (in case peer reset early)
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && !_transitioning) {
        print("[SHARE_RESULTS] ⏱️ Auto-reset timeout (30s) - returning to splash then pairing");
        setState(() => _transitioning = true);
        _fadeController.forward().then((_) {
          if (mounted) {
            widget.coordinator.resetToSplash();
            // After 2 seconds of splash, start pairing
            Future.delayed(const Duration(milliseconds: 2000), () {
              widget.coordinator.startPairingAfterReset();
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  void _onLongPressStart() {
    print("[SHARE_RESULTS] Long press started on non-info area");
    setState(() => _longPressActive = true);
    
    // ✅ 2 second timer to fade and return to splash then pairing
    _longPressTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return; // Safety check
      
      print("[SHARE_RESULTS] 2 second hold reached! Fading to splash... 🔄");
      setState(() => _transitioning = true);
      
      // Start fade animation and reset after
      if (!_fadeController.isAnimating) {
        _fadeController.forward().then((_) {
          if (mounted) {
            print("[SHARE_RESULTS] ✅ Fade complete, resetting to splash...");
            widget.coordinator.resetToSplash();
            // After 2 seconds of splash, start pairing
            Future.delayed(const Duration(milliseconds: 2000), () {
              widget.coordinator.startPairingAfterReset();
            });
          }
        });
      } else {
        print("[SHARE_RESULTS] ⚠️ Animation already running, resetting directly...");
        widget.coordinator.resetToSplash();
        // After 2 seconds of splash, start pairing
        Future.delayed(const Duration(milliseconds: 2000), () {
          widget.coordinator.startPairingAfterReset();
        });
      }
    });
  }

  void _onLongPressEnd() {
    print("[SHARE_RESULTS] Long press ended");
    _longPressTimer?.cancel();
    if (!_transitioning) {
      setState(() => _longPressActive = false);
    }
  }

  void _onLongPress() {
    // ✅ This is called after long press, but we handle reset in timer now
    print("[SHARE_RESULTS] Long press complete");
  }

  void _copyToClipboard(String value) {
    print("[SHARE_RESULTS] Copied to clipboard: $value");
    Clipboard.setData(ClipboardData(text: value));
    
    // Show brief feedback
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.state.incomingShareOffer;
    final phase = widget.state.phase;
    final paletteManager = ColorPaletteManager();

    // ✅ SAFETY: Only show offer if we're in shareResults phase (both shared)
    final shouldShowOffer = offer != null && phase == app_phase.AppPhase.shareResults;
    
    print("[SHARE_RESULTS] Phase: $phase, HasOffer: ${offer != null}, ShouldShow: $shouldShowOffer");

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: paletteManager.currentPalette.gradient,
        ),
        child: SafeArea(
          child: GestureDetector(
            // ✅ Long press on background (NOT on the info text)
            onLongPressStart: (_) => _onLongPressStart(),
            onLongPressEnd: (_) => _onLongPressEnd(),
            behavior: HitTestBehavior.translucent, // Allow passing through to children
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Center(
                child: shouldShowOffer
                    ? GestureDetector(
                        // ✅ Inner detector: Only tap on info (copy)
                        onTap: () => _copyToClipboard(_maskValue(offer.value, offer.kind)),
                        behavior: HitTestBehavior.opaque, // Stop propagation to outer detector
                        child: AnimatedOpacity(
                          opacity: _copied ? 1.0 : (_longPressActive ? 0.5 : 0.8),
                          duration: const Duration(milliseconds: 200),
                          child: AnimatedScale(
                            scale: _longPressActive ? 0.95 : (_copied ? 1.08 : 1.0),
                            duration: const Duration(milliseconds: 300),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // ✅ Shared value (copyable) - YAZISIZ
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 32),
                                  child: Text(
                                    _maskValue(offer.value, offer.kind),
                                    style: TextStyle(
                                      color: _copied ? Colors.green : 
                                             (_longPressActive ? Colors.yellow : Colors.white),
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            '⏳',
                            style: TextStyle(fontSize: 80),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Bekleniyor...',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _maskValue(String value, String kind) {
    // ✅ Show value as is - no masking
    return value;
  }
}
