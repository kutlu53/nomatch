import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'game_engine.dart';
import 'models.dart';

class GameScreen extends StatefulWidget {
  final GameEngine engine;
  final VoidCallback onOpenShare;

  const GameScreen({
    super.key,
    required this.engine,
    required this.onOpenShare,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  RoundSnapshot? _snap;
  late final StreamSubscription<RoundSnapshot> _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.engine.snapshots.listen((s) => setState(() => _snap = s));
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: widget.onOpenShare,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          final halfH = h / 2;

          return Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    SizedBox(
                      height: halfH,
                      child: _HalfBoard(
                        isTop: true,
                        choice: snap?.peerChoice,
                        phase: snap?.phase ?? GamePhase.playing,
                        terminal: snap?.terminal,
                      ),
                    ),
                    SizedBox(
                      height: halfH,
                      child: _HalfBoard(
                        isTop: false,
                        choice: snap?.localChoice,
                        phase: snap?.phase ?? GamePhase.playing,
                        terminal: snap?.terminal,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: halfH,
                height: 2,
                child: ColoredBox(color: Colors.black.withOpacity(0.35)),
              ),
              if (snap != null) ...[
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: snap.phase != GamePhase.playing,
                    child: _ChoiceOverlay(
                      boardWidth: w,
                      boardHeight: halfH,
                      onPick: (choice) => widget.engine.select(choice),
                    ),
                  ),
                ),
              ],
              if (snap?.phase == GamePhase.result && snap?.terminal != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _ResultOverlay(terminal: snap!.terminal!),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HalfBoard extends StatelessWidget {
  final bool isTop;
  final String? choice;
  final GamePhase phase;
  final RoundTerminal? terminal;

  const _HalfBoard({
    required this.isTop,
    required this.choice,
    required this.phase,
    required this.terminal,
  });

  @override
  Widget build(BuildContext context) {
    final base = isTop ? Colors.blueGrey.shade900 : Colors.blueGrey.shade800;
    final c = _choiceColor(choice);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
          end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [
            base,
            base.withOpacity(0.92),
          ],
        ),
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: CustomPaint(
            key: ValueKey<String>(choice ?? 'empty'),
            painter: _BlobPainter(color: c),
            size: const Size.square(220),
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

class _ChoiceOverlay extends StatelessWidget {
  final double boardWidth;
  final double boardHeight;
  final ValueChanged<String> onPick;

  const _ChoiceOverlay({
    required this.boardWidth,
    required this.boardHeight,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    // Bottom half contains two invisible hit zones; no text/icons.
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: boardWidth,
        height: boardHeight,
        child: Row(
          children: [
            Expanded(child: _TapZone(color: Colors.tealAccent.withOpacity(0.06), onTap: () => onPick('top'))),
            Expanded(child: _TapZone(color: Colors.orangeAccent.withOpacity(0.06), onTap: () => onPick('bottom'))),
          ],
        ),
      ),
    );
  }
}

class _TapZone extends StatefulWidget {
  final Color color;
  final VoidCallback onTap;
  const _TapZone({required this.color, required this.onTap});

  @override
  State<_TapZone> createState() => _TapZoneState();
}

class _TapZoneState extends State<_TapZone> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _down ? widget.color.withOpacity(widget.color.opacity * 2.0) : widget.color,
      ),
    );
  }
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
  );

  @override
  void initState() {
    super.initState();
    // Animasyonu başlat - eski cihazlarda uyumluluk için
    _a.repeat(reverse: true);
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  Color _getBaseColor(RoundTerminal terminal) {
    if (terminal == RoundTerminal.match) {
      return Colors.greenAccent.withOpacity(0.18);
    } else if (terminal == RoundTerminal.mismatch) {
      return Colors.redAccent.withOpacity(0.18);
    } else if (terminal == RoundTerminal.localNoSelection) {
      return Colors.yellowAccent.withOpacity(0.16);
    } else if (terminal == RoundTerminal.peerNoSelection) {
      return Colors.cyanAccent.withOpacity(0.16);
    } else {
      // bothNoSelection
      return Colors.white.withOpacity(0.12);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = _getBaseColor(widget.terminal);

    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) {
        // Animasyon değerini kesinlikle 0.0-1.0 arasında sabit tut
        final animValue = _a.value.clamp(0.0, 1.0);
        final opacityValue = (0.65 + 0.35 * animValue).clamp(0.0, 1.0);
        final scaleValue = (0.92 + 0.06 * animValue).clamp(0.92, 0.98);
        
        return ColoredBox(
          color: base.withOpacity(base.opacity * opacityValue),
          child: Center(
            child: Transform.scale(
              scale: scaleValue,
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

  Color _getPainterColor(RoundTerminal terminal) {
    if (terminal == RoundTerminal.match) {
      return Colors.greenAccent.withOpacity(0.9);
    } else if (terminal == RoundTerminal.mismatch) {
      return Colors.redAccent.withOpacity(0.9);
    } else if (terminal == RoundTerminal.localNoSelection) {
      return Colors.yellowAccent.withOpacity(0.9);
    } else if (terminal == RoundTerminal.peerNoSelection) {
      return Colors.cyanAccent.withOpacity(0.9);
    } else {
      // bothNoSelection
      return Colors.white.withOpacity(0.65);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;

    final color = _getPainterColor(terminal);

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

