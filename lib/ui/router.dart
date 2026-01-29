import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'dart:developer' as dev;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/app_coordinator.dart';
import '../app/app_phase.dart';
import '../features/game/game_state.dart';
import 'color_palette_manager.dart';
import 'game_result_screen.dart';
import 'game_screen.dart';
import 'pairing_failed_screen.dart';
import 'pairing_success_screen.dart';
import 'share_results_screen.dart';
import 'share_screen.dart';
import 'share_success_screen.dart';
import 'terminal_fail_screen.dart';
import 'splash_screen.dart';
import 'widgets/radar_pairing_view.dart';

// AppRouter widget maps AppPhase -> screen widgets.

class AppRouter extends StatelessWidget {
  final AppCoordinator coordinator;
  final AppViewState viewState;

  const AppRouter({
    super.key,
    required this.coordinator,
    required this.viewState,
  });

  @override
  Widget build(BuildContext context) {
    final phase = viewState.phase;
    dev.log('AppRouter: phase=$phase');
    
    if (phase == AppPhase.gameResult) {
      print("[ROUTER] ===== ROUTING TO GAME RESULT SCREEN =====");
      print("[ROUTER] Result type: ${viewState.gameResultType}");
    }
    
    return switch (phase) {
      AppPhase.splash => const SplashScreen(),
      AppPhase.pairing => viewState.validationFailed
          ? PairingFailedScreen(coordinator: coordinator)
          : viewState.pairHandshakeComplete
              ? PairingSuccessScreen(coordinator: coordinator)
              : PairingScreen(coordinator: coordinator, state: viewState),
      AppPhase.playing => GameScreen(state: viewState, coordinator: coordinator),
      AppPhase.gameResult => GameResultScreen(
          coordinator: coordinator,
          resultType: viewState.gameResultType ?? GameResultType.failure,
        ),
      AppPhase.share => ShareScreen(state: viewState, coordinator: coordinator),
      AppPhase.shareResults => ShareResultsScreen(
          coordinator: coordinator,
          state: viewState,
        ),
    };
  }
}

class PairingScreen extends StatefulWidget {
  final AppCoordinator coordinator;
  final AppViewState state;
  
  const PairingScreen({
    super.key,
    required this.coordinator,
    required this.state,
  });

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> with TickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  
  late final AnimationController _morphController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800), // Morph süresi
  );
  
  bool _morphStarted = false;
  final _paletteManager = ColorPaletteManager();
  Timer? _paletteLongPressTimer;

  @override
  void initState() {
    super.initState();
    
    // Ekranı açık tut (pairing sırasında)
    if (!kIsWeb) {
      WakelockPlus.enable();
      dev.log('PairingScreen: Wakelock enabled - screen will stay on');
    }
    
    // Kaydedilmiş paleti yükle
    _paletteManager.loadPalette().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant PairingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Start morph animation when transitioning to game
    if (!_morphStarted && 
        oldWidget.state.phase != AppPhase.playing &&
        widget.state.phase == AppPhase.playing) {
      _morphStarted = true;
      _morphController.forward();
    }
  }

  @override
  void dispose() {
    // Wakelock'u devre dışı bırak (ekran normal davranışa döner)
    if (!kIsWeb) {
      WakelockPlus.disable();
      dev.log('PairingScreen: Wakelock disabled - screen can sleep now');
    }
    
    _paletteLongPressTimer?.cancel();
    _a.dispose();
    _morphController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    
    dev.log('PairingScreen: build, phase=${state.phase}');
    return Scaffold(
      body: IgnorePointer(
        ignoring: false,
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Dinamik renk paleti gradient
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: _paletteManager.currentPalette.gradient,
                ),
                child: const SizedBox.expand(),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _startPaletteLongPress,
                onTapUp: (_) => _cancelPaletteLongPress(),
                onTapCancel: _cancelPaletteLongPress,
                child: RadarPairingView(
                  peers: widget.coordinator.discoveredPeers,
                  focusCandidatePeerId: state.focusCandidatePeerId,
                  readySoon: state.pairingReadySoon,
                  focusCandidateLocked: state.focusCandidateLocked,
                  pairHandshakeComplete: state.pairHandshakeComplete,
                  isConnectingTransition: state.isConnectingTransition,
                  localHeadingDeg: state.stableHeadingDeg,
                  validationFailed: state.validationFailed, // ✅ NEW
                ),
              ),
              // Yukarı ok veya onay işareti animasyonu
              Center(
                child: AnimatedBuilder(
                  animation: _a,
                  builder: (context, child) {
                    final v = _a.value;
                    final scale = 0.92 + 0.08 * v;
                    final isGamePhase = state.phase == AppPhase.playing;
                    final dy = isGamePhase ? 0.0 : -10.0 * (v - 0.5);
                    // Opacity 0.0-1.0 arasında olmalı
                    final opacity = (0.6 + 0.3 * v).clamp(0.0, 1.0);
                    
                    return Transform.translate(
                      offset: Offset(0, dy),
                      child: Transform.scale(
                        scale: scale,
                        child: child,
                      ),
                    );
                  },
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Ekran boyutunun küçük olanının %40'ı
                      final screenSize = MediaQuery.of(context).size;
                      final minDimension = screenSize.width < screenSize.height 
                          ? screenSize.width 
                          : screenSize.height;
                      final iconSize = minDimension * 0.4;
                      
                      return AnimatedBuilder(
                        animation: _a,
                        builder: (context, _) {
                          final v = _a.value;
                          final opacity = (0.6 + 0.3 * v).clamp(0.0, 1.0);
                          
                          // Morph animasyonu için ikinci controller'ı kullan
                          return AnimatedBuilder(
                            animation: _morphController,
                            builder: (context, _) {
                              final morphProgress = _morphController.value;
                              
                              return CustomPaint(
                                size: Size(iconSize, iconSize),
                                painter: _PairingMorphPainter(
                                  color: Colors.white.withOpacity(opacity),
                                  greenColor: const Color(0xFF00FF88).withOpacity(opacity),
                                  morphProgress: morphProgress,
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: 44,
                right: 44,
                child: IgnorePointer(
                  ignoring: false,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 32,
                    splashRadius: 20,
                    onPressed: state.stableIsFlat
                        ? () => widget.coordinator.setInviteBeaconEnabled(
                              !state.inviteBeaconEnabled,
                            )
                        : null,
                    icon: Icon(
                      state.inviteBeaconEnabled
                          ? Icons.toggle_on
                          : Icons.toggle_off,
                      color: state.stableIsFlat
                          ? Colors.white.withOpacity(0.9)
                          : Colors.white.withOpacity(0.35),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startPaletteLongPress(TapDownDetails details) {
    _paletteLongPressTimer?.cancel();
    _paletteLongPressTimer = Timer(const Duration(milliseconds: 1500), () {
      _paletteLongPressTimer = null;
      if (!mounted) return;
      _openPaletteSelector();
    });
  }

  void _cancelPaletteLongPress() {
    _paletteLongPressTimer?.cancel();
    _paletteLongPressTimer = null;
  }

  Future<void> _openPaletteSelector() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final palette in ColorPalette.values)
                  InkWell(
                    onTap: () async {
                      await _paletteManager.setPalette(palette);
                      if (!mounted) return;
                      setState(() {});
                      Navigator.of(context).pop();
                    },
                    borderRadius: BorderRadius.circular(40),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: palette.gradient,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          palette.emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class TerminalSuccessScreen extends StatefulWidget {
  final AppCoordinator coordinator;
  const TerminalSuccessScreen({super.key, required this.coordinator});

  @override
  State<TerminalSuccessScreen> createState() => _TerminalSuccessScreenState();
}

class _TerminalSuccessScreenState extends State<TerminalSuccessScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: AnimatedBuilder(
        animation: _a,
        builder: (context, _) {
          final v = _a.value;
          return ColoredBox(
            color: scheme.surface,
            child: Center(
              child: Transform.scale(
                scale: 0.88 + 0.08 * v,
                child: CustomPaint(
                  painter: _MarkPainter(color: scheme.onSurface.withOpacity(0.18), variant: 5),
                  size: const Size.square(260),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SoftDiscPainter extends CustomPainter {
  final Color color;
  const _SoftDiscPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;
    final p = Paint()..color = color;
    canvas.drawCircle(c, r * 0.62, p);
  }

  @override
  bool shouldRepaint(covariant _SoftDiscPainter oldDelegate) => oldDelegate.color != color;
}

class _PulseRingPainter extends CustomPainter {
  final double ring;
  final Color fg;
  final Color bg;

  const _PulseRingPainter({required this.ring, required this.fg, required this.bg});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;

    final pBg = Paint()..color = bg;
    final pFg = Paint()
      ..color = fg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;

    canvas.drawCircle(c, r * 0.55, pBg);
    canvas.drawCircle(c, r * (0.25 + 0.55 * ring), pFg);
  }

  @override
  bool shouldRepaint(covariant _PulseRingPainter oldDelegate) {
    return oldDelegate.ring != ring || oldDelegate.fg != fg || oldDelegate.bg != bg;
  }
}

class _PairingOkPainter extends CustomPainter {
  final Color color;
  const _PairingOkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    final ring = Paint()
      ..color = color.withOpacity(color.opacity * 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08;
    canvas.drawCircle(Offset(cx, cy), w * 0.36, ring);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    path.moveTo(cx - w * 0.18, cy + h * 0.02);
    path.lineTo(cx - w * 0.02, cy + h * 0.18);
    path.lineTo(cx + w * 0.20, cy - h * 0.12);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _PairingOkPainter oldDelegate) => oldDelegate.color != color;
}

class _PairingUpArrowPainter extends CustomPainter {
  final Color color;
  const _PairingUpArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // Dış halka
    final ring = Paint()
      ..color = color.withOpacity(color.opacity * 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06;
    canvas.drawCircle(Offset(cx, cy), w * 0.38, ring);

    // Yukarı ok (büyütülmüş, halka içinde tam ortalanmış)
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    // Ok gövdesi (tam ortada, aşağıdan yukarı)
    path.moveTo(cx, cy + h * 0.18);
    path.lineTo(cx, cy - h * 0.18);
    
    // Sol ok ucu
    path.moveTo(cx, cy - h * 0.18);
    path.lineTo(cx - w * 0.18, cy - h * 0.02);
    
    // Sağ ok ucu
    path.moveTo(cx, cy - h * 0.18);
    path.lineTo(cx + w * 0.18, cy - h * 0.02);
    
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _PairingUpArrowPainter oldDelegate) => oldDelegate.color != color;
}

class _PairingCheckPainter extends CustomPainter {
  final Color color;
  const _PairingCheckPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // Yeşil dış halka (kalın)
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08;
    canvas.drawCircle(Offset(cx, cy), w * 0.38, ring);

    // Onay işareti (checkmark)
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    // Onay işareti çizimi
    path.moveTo(cx - w * 0.18, cy);
    path.lineTo(cx - w * 0.05, cy + h * 0.15);
    path.lineTo(cx + w * 0.20, cy - h * 0.15);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _PairingCheckPainter oldDelegate) => oldDelegate.color != color;
}

class _PairingMorphPainter extends CustomPainter {
  final Color color;
  final Color greenColor;
  final double morphProgress; // 0.0 = ok, 1.0 = onay

  const _PairingMorphPainter({
    required this.color,
    required this.greenColor,
    required this.morphProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final t = morphProgress.clamp(0.0, 1.0);

    // Renk geçişi: beyaz → yeşil
    final currentColor = Color.lerp(color, greenColor, t)!;

    // Dış halka
    final ring = Paint()
      ..color = currentColor.withOpacity(currentColor.opacity * 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06 + (w * 0.02 * t); // Kalınlık artar
    canvas.drawCircle(Offset(cx, cy), w * 0.38, ring);

    // İçerik: Ok'tan onaya morph
    final stroke = Paint()
      ..color = currentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (t < 0.5) {
      // İlk yarı: Ok fade out
      final fade = 1.0 - (t * 2);
      final arrowPaint = stroke..color = currentColor.withOpacity(currentColor.opacity * fade);
      
      final path = Path();
      path.moveTo(cx, cy + h * 0.18);
      path.lineTo(cx, cy - h * 0.18);
      path.moveTo(cx, cy - h * 0.18);
      path.lineTo(cx - w * 0.18, cy - h * 0.02);
      path.moveTo(cx, cy - h * 0.18);
      path.lineTo(cx + w * 0.18, cy - h * 0.02);
      canvas.drawPath(path, arrowPaint);
    } else {
      // İkinci yarı: Onay fade in
      final fade = (t - 0.5) * 2;
      final checkPaint = stroke..color = currentColor.withOpacity(currentColor.opacity * fade);
      
      final path = Path();
      path.moveTo(cx - w * 0.18, cy);
      path.lineTo(cx - w * 0.05, cy + h * 0.15);
      path.lineTo(cx + w * 0.20, cy - h * 0.15);
      canvas.drawPath(path, checkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PairingMorphPainter oldDelegate) {
    return oldDelegate.color != color || 
           oldDelegate.greenColor != greenColor || 
           oldDelegate.morphProgress != morphProgress;
  }
}

class _MarkPainter extends CustomPainter {
  final Color color;
  final int variant;
  const _MarkPainter({required this.color, required this.variant});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;
    final p = Paint()..color = color;

    switch (variant) {
      case 0:
        canvas.drawCircle(c, r * 0.40, p);
        return;
      case 1:
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCircle(center: c.translate(0, -r * 0.10), radius: r * 0.36), const Radius.circular(28)),
          p,
        );
        return;
      case 2:
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCircle(center: c.translate(0, r * 0.10), radius: r * 0.36), const Radius.circular(28)),
          p,
        );
        return;
      case 3:
        canvas.drawCircle(c, r * 0.28, p..color = color.withOpacity(color.opacity * 0.65));
        canvas.drawCircle(c, r * 0.52, p..color = color.withOpacity(color.opacity * 0.25));
        return;
      case 4:
        canvas.drawRect(Rect.fromCenter(center: c, width: r * 0.9, height: r * 0.18), p);
        return;
      case 5:
        canvas.drawCircle(c, r * 0.52, p..style = PaintingStyle.stroke..strokeWidth = 12);
        return;
      case 6:
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: r * 0.9, height: r * 0.5), const Radius.circular(18)),
          p,
        );
        return;
      default:
        canvas.drawCircle(c, r * 0.40, p);
        return;
    }
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) => oldDelegate.color != color || oldDelegate.variant != variant;
}

