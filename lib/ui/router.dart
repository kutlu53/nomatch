import 'package:flutter/material.dart';
import 'dart:developer' as dev;
import 'dart:math' as math;

import '../app/pairing_manager.dart';
import '../app/app_state.dart';
import '../app/pairing_logic.dart';
import '../features/pairing/flashlight_signal.dart';
import 'color_palette_manager.dart';
import 'pairing_failed_screen.dart';
import 'pairing_success_screen.dart';
import 'splash_screen.dart';
import '../features/game/game_screen.dart';
import '../features/game/game_share_screen.dart';
import '../features/game/game_state.dart'; // ✅ For GamePhase check
import 'widgets/radar_pairing_view.dart';

/// Router maps PairingState -> screen widgets
class AppRouter extends StatelessWidget {
  final PairingManager pairingManager;
  final AppViewState viewState;

  const AppRouter({
    super.key,
    required this.pairingManager,
    required this.viewState,
  });

  @override
  Widget build(BuildContext context) {
    final state = viewState.pairingState;
    dev.log('AppRouter: pairing_state=$state');

    return switch (state) {
      PairingState.idle ||
      PairingState.hostingReady ||
      PairingState.peerSearching ||
      PairingState.preConnected ||
      PairingState.headingValidating =>
        PairingScreen(pairingManager: pairingManager, state: viewState),
      PairingState.connected => PairingSuccessScreen(pairingManager: pairingManager),
      PairingState.game || PairingState.gameReady || PairingState.playing => GameScreen(
        engine: pairingManager.gameEngine!,
        onOpenShare: () {
          // ✅ DEFENSIVE: Check if game is really in terminal state before opening share
          final phase = pairingManager.gameEngine?.state.phase;
          print('[ROUTER] 🎮 onOpenShare called - phase=$phase');
          
          if (phase != GamePhase.terminalSuccess) {
            print('[ROUTER] ⚠️ onOpenShare called but phase=$phase (not terminalSuccess), IGNORING');
            return;
          }
          
          print('[ROUTER] 🎮 Phase is terminalSuccess - pushing GameShareScreen...');
          try {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) {
                  print('[ROUTER] 🎮 GameShareScreen builder called');
                  return GameShareScreen(
                    engine: pairingManager.gameEngine!,
                    onReset: () async {
                      print('[ROUTER] 🎮 Player reset - returning to pairing');
                      await pairingManager.stop(); // Stop BLE and reset
                      if (context.mounted) {
                        print('[ROUTER] 🎮 Popping share screen');
                        Navigator.of(context).pop(); // Pop share screen
                      }
                    },
                  );
                },
              ),
            );
            print('[ROUTER] 🎮 Navigator.push completed');
          } catch (e) {
            print('[ROUTER] ❌ ERROR in onOpenShare: $e');
          }
        },
        onReset: () async {
          print('[ROUTER] ❌ terminalFail - resetting to pairing');
          await pairingManager.stop(); // Stop BLE and reset
        },
      ),
      PairingState.failed => PairingFailedScreen(pairingManager: pairingManager),
    };
  }
}

class PairingScreen extends StatefulWidget {
  final PairingManager pairingManager;
  final AppViewState state;

  const PairingScreen({
    super.key,
    required this.pairingManager,
    required this.state,
  });

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

// GradientType artık ColorPaletteManager'dan geliyor

class _PairingScreenState extends State<PairingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late ColorPalette _selectedPalette = ColorPalette.cosmicConnection;
  late GradientType _selectedGradient = GradientType.linear;
  bool _showGradientStep = false; // Track if showing gradient selector
  bool _torchEnabled = false; // Flashlight state
  bool _pairingStarted = false; // Track if pairing button was tapped
  final FlashlightSignal _flashlight = FlashlightSignal();

  @override
  void initState() {
    super.initState();
    dev.log('PairingScreen: initiated');
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    // NOTE: DO NOT repeat() here - animation only starts on button tap
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _flashlight.dispose(); // Clean up flashlight
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final pairingState = state.pairingState;
    final paletteManager = ColorPaletteManager();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: paletteManager.currentGradient,
        ),
        child: GestureDetector(
          onLongPress: () {
            dev.log('[UI] Long press detected - showing color palette');
            _showColorPaletteDialog(context);
          },
          child: Stack(
            children: [
              // Radar view (transparent - let gradient show through)
              Positioned.fill(
                child: RadarPairingView(
                  peers: [], // TODO: Pass from PairingManager
                  focusCandidatePeerId: null,
                  readySoon: pairingState == PairingState.hostingReady,
                  focusCandidateLocked: pairingState == PairingState.preConnected,
                  pairHandshakeComplete: pairingState == PairingState.connected,
                  isConnectingTransition:
                      pairingState == PairingState.preConnected,
                  localHeadingDeg: state.ourHeading,
                  validationFailed: pairingState == PairingState.failed,
                  // 🎨 IMPORTANT: Don't draw background - let parent gradient show through
                ),
              ),

              // Central animated arrow (tap to start/stop pairing)
              Center(
                child: GestureDetector(
                  onTap: () async {
                    if (_pairingStarted) {
                      // Stop pairing
                      dev.log('[UI] ⏹️ Stopping pairing');
                      setState(() {
                        _pairingStarted = false;
                      });
                      
                      // Stop animation
                      _pulseController.stop();
                      
                      // Stop BLE pairing
                      await widget.pairingManager.stop();
                      
                      return;
                    }
                    
                    // Start pairing
                    dev.log('[UI] ▶️ Starting pairing');
                    setState(() {
                      _pairingStarted = true;
                    });
                    
                    // Start animation
                    _pulseController.repeat(reverse: true);
                    
                    // Start BLE pairing with retry (wait for phone to be flat)
                    const maxRetries = 20; // ~10 seconds
                    int retries = 0;
                    bool success = false;
                    
                    while (retries < maxRetries && !success && _pairingStarted) {
                      final result = await widget.pairingManager.start(
                        isPhoneFlat: state.isPhoneFlat,
                      );
                      
                      if (result.success) {
                        success = true;
                        break;
                      }
                      
                      retries++;
                      dev.log('[UI] ⏳ Pairing retry $retries/$maxRetries (isFlat=${state.isPhoneFlat})');
                      
                      // Wait before retry (check if still running)
                      await Future.delayed(const Duration(milliseconds: 500));
                    }
                    
                    if (!success && _pairingStarted) {
                      dev.log('[UI] ❌ Pairing failed after $maxRetries retries');
                    }
                  },
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) {
                      final v = _pulseController.value;
                      // ✅ BEKLEME: Sabit, hafif soluk
                      // ✅ ARAMA: Nabız animasyonu + sonar halkaları
                      final scale = _pairingStarted 
                        ? (0.95 + (v * 0.1)) // Subtle pulse 0.95x - 1.05x
                        : 1.0; // Static when waiting
                      return Transform.scale(
                        scale: scale,
                        child: CustomPaint(
                          painter: _ArrowPainter(
                            color: const Color(0xFFF5F5F5), // Pearl white
                            opacity: _pairingStarted ? 1.0 : 0.6, // Dimmed before tap
                            isSearching: _pairingStarted, // ✅ NEW: Sonar rings
                            animationValue: v, // ✅ NEW: Animation phase
                          ),
                          size: const Size(120, 120),
                        ),
                      );
                    },
                  ),
                ),
              ),


              // Flashlight toggle (top right) - active during pairing (phone is flat)
              Positioned(
                top: 50,
                right: 20,
                child: GestureDetector(
                  onTap: state.isPhoneFlat
                    ? () async {
                    // Only toggle if phone is flat (hosting ready means flat)
                        setState(() {
                      _torchEnabled = !_torchEnabled;
                    });
                    
                    // Control torch
                    if (_torchEnabled) {
                      await _flashlight.startBlinking();
                    } else {
                      await _flashlight.stopBlinking();
                    }
                  } : null, // Disabled if phone not flat
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.transparent, // No background color
                      border: Border.all(
                        color: const Color(0xFFF5F5F5).withOpacity(
                          state.isPhoneFlat ? 0.8 : 0.3 // Dimmed if phone not flat
                        ),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _torchEnabled ? Icons.toggle_on : Icons.toggle_off,
                      color: state.isPhoneFlat
                          ? (_torchEnabled 
                              ? const Color(0xFFF5F5F5) // Bright pearl white when on
                              : const Color(0xFFF5F5F5).withOpacity(0.5)) // Pearl white dimmed when off
                          : const Color(0xFFF5F5F5).withOpacity(0.2), // Very dimmed when phone not flat
                      size: 28,
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

  void _showColorPaletteDialog(BuildContext context) {
    setState(() {
      _showGradientStep = false; // Show color step first
    });

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          content: SizedBox(
            width: double.maxFinite,
            child: !_showGradientStep
                ? _buildColorPaletteGrid(context, setState)
                : _buildGradientTypeGrid(context, setState),
          ),
        ),
      ),
    );
  }

  Widget _buildColorPaletteGrid(BuildContext context, StateSetter setState) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: ColorPalette.values.length,
      itemBuilder: (context, index) {
        final palette = ColorPalette.values[index];
        final colors = palette.colors;
        final isSelected = _selectedPalette == palette;

        return GestureDetector(
          onTap: () {
            this.setState(() {
              _selectedPalette = palette;
              _showGradientStep = true;
              dev.log('[UI] Selected palette: ${palette.emoji}');
              // ✅ ColorPaletteManager'a kaydet
              ColorPaletteManager().setPalette(palette);
            });
            setState(() {}); // Rebuild dialog
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white,
                width: isSelected ? 4 : 0,
              ),
            ),
            child: Center(
              child: Text(
                palette.emoji,
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGradientTypeGrid(BuildContext context, StateSetter setState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Back button
        GestureDetector(
          onTap: () {
            this.setState(() {
              _showGradientStep = false;
            });
            setState(() {}); // Rebuild dialog
          },
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.withOpacity(0.2),
            ),
            child: const Center(
              child: Text('← ', style: TextStyle(fontSize: 24)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: GradientType.values.map((type) {
            final isSelected = _selectedGradient == type;
            return GestureDetector(
              onTap: () {
                Navigator.pop(context);
                this.setState(() {
                  _selectedGradient = type;
                  dev.log('[UI] Selected gradient: ${type.name}');
                  // ✅ ColorPaletteManager'a kaydet ve persist et
                  ColorPaletteManager().setGradientType(type);
                  ColorPaletteManager().saveTheme(); // ✅ Kalıcı kaydet
                });
              },
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.grey,
                    width: isSelected ? 3 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.withOpacity(0.2),
                ),
                child: Center(
                  child: Text(
                    _getGradientEmoji(type),
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Gradient _getGradient(ColorPalette palette) {
    final colors = palette.colors;
    return switch (_selectedGradient) {
      GradientType.linear => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
        stops: const [0.0, 0.3, 0.7, 1.0],
      ),
      GradientType.radial => RadialGradient(
        center: Alignment.center,
        radius: 1.5,
        colors: colors,
        stops: const [0.0, 0.3, 0.7, 1.0],
      ),
      GradientType.sweep => SweepGradient(
        center: Alignment.center,
        colors: colors,
        stops: const [0.0, 0.3, 0.7, 1.0],
        startAngle: 0.0,
        endAngle: math.pi * 2,
      ),
      GradientType.vertical => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
        stops: const [0.0, 0.3, 0.7, 1.0],
      ),
      GradientType.horizontal => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: colors,
        stops: const [0.0, 0.3, 0.7, 1.0],
      ),
      GradientType.corner => LinearGradient(
        begin: Alignment.bottomRight,
        end: Alignment.topLeft,
        colors: colors,
        stops: const [0.0, 0.3, 0.7, 1.0],
      ),
    };
  }

  String _getGradientName(GradientType type) {
    return switch (type) {
      GradientType.linear => '↖️ Diagonal',
      GradientType.radial => '⭕ Radial',
      GradientType.sweep => '🌀 Sweep',
      GradientType.vertical => '⬍ Vertical',
      GradientType.horizontal => '⬌ Horizontal',
      GradientType.corner => '↙️ Corner',
    };
  }

  String _getGradientEmoji(GradientType type) {
    return switch (type) {
      GradientType.linear => '↖️',
      GradientType.radial => '⭕',
      GradientType.sweep => '🌀',
      GradientType.vertical => '⬍',
      GradientType.horizontal => '⬌',
      GradientType.corner => '↙️',
    };
  }

  String _getStateLabel(PairingState state) {
    return switch (state) {
      PairingState.idle => '🔄 Initializing',
      PairingState.hostingReady => '📡 Ready to Pair',
      PairingState.peerSearching => '',
      PairingState.preConnected => '🔗 Validating Heading',
      PairingState.headingValidating => '🧭 Validating Face-to-Face',
      PairingState.connected => '✅ Connected',
      PairingState.game => '🎮 Starting Game',
      PairingState.failed => '❌ Pairing Failed',
      PairingState.gameReady => '🎮 Game Ready',
      PairingState.playing => '🎮 Playing',
    };
  }
}

class _StarPainter extends CustomPainter {
  final Color color;
  const _StarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerX = w * 0.5;
    final centerY = h * 0.5;

    // ✨ Up arrow with notch
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Glow effect
    final glowPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10)
      ..style = PaintingStyle.fill;

    // Three-point star (compass N shape)
    // Top point (North)
    final point1 = Offset(centerX, centerY - h * 0.40);
    // Bottom-right point
    final point2 = Offset(centerX + w * 0.35, centerY + h * 0.25);
    // Bottom-left point
    final point3 = Offset(centerX - w * 0.35, centerY + h * 0.25);

    // Main star path
    final mainTrianglePath = Path();
    mainTrianglePath.moveTo(point1.dx, point1.dy); // Top
    mainTrianglePath.lineTo(point2.dx, point2.dy); // Bottom-right
    mainTrianglePath.lineTo(point3.dx, point3.dy); // Bottom-left
    mainTrianglePath.close();

    // Negative triangle cutout in center (pointing up, creating the N shape with gaps)
    final negativeTrianglePath = Path();
    negativeTrianglePath.moveTo(centerX - w * 0.18, centerY + h * 0.08); // Left inner point
    negativeTrianglePath.lineTo(centerX + w * 0.18, centerY + h * 0.08); // Right inner point
    negativeTrianglePath.lineTo(centerX, centerY - h * 0.15); // Top inner point (pointing up)
    negativeTrianglePath.close();

    // Combine paths using FillType.evenOdd to create the cutout
    final combinedPath = Path();
    combinedPath.fillType = PathFillType.evenOdd;
    combinedPath.addPath(mainTrianglePath, Offset.zero);
    combinedPath.addPath(negativeTrianglePath, Offset.zero);

    // Draw glow first
    canvas.drawPath(mainTrianglePath, glowPaint);
    
    // Draw main shape with negative space
    canvas.drawPath(combinedPath, paint);
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Arrow painter with notch at bottom (upward triangle with V-cutout)
/// Enhanced with sonar rings when searching
class _ArrowPainter extends CustomPainter {
  final Color color;
  final double opacity;
  final bool isSearching; // ✅ NEW: Active search mode
  final double animationValue; // ✅ NEW: For sonar animation (0.0 - 1.0)
  
  const _ArrowPainter({
    required this.color,
    this.opacity = 1.0,
    this.isSearching = false,
    this.animationValue = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerX = w * 0.5;
    final centerY = h * 0.5;
    final center = Offset(centerX, centerY);

    // ✅ SONAR RINGS (only when searching)
    if (isSearching) {
      // 3 sonar rings at different phases
      for (int i = 0; i < 3; i++) {
        final phase = (animationValue + (i * 0.33)) % 1.0;
        final ringRadius = w * 0.3 + (phase * w * 0.5); // Expand outward
        final ringOpacity = (1.0 - phase) * 0.4; // Fade out as they expand
        
        final sonarPaint = Paint()
          ..color = color.withOpacity(ringOpacity * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0);
        
        canvas.drawCircle(center, ringRadius, sonarPaint);
      }
    }

    // ✅ GLOW (stronger when searching)
    final glowIntensity = isSearching ? 0.35 : 0.15;
    final glowRadius = isSearching ? 15.0 : 8.0;
    final glowPaint = Paint()
      ..color = color.withOpacity(glowIntensity * opacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius)
      ..style = PaintingStyle.fill;

    // Main upward-pointing triangle
    final arrowPath = Path();
    arrowPath.moveTo(centerX, centerY - h * 0.35); // Top point
    arrowPath.lineTo(centerX + w * 0.35, centerY + h * 0.25); // Bottom right
    arrowPath.lineTo(centerX - w * 0.35, centerY + h * 0.25); // Bottom left
    arrowPath.close();

    // Notch (inverted triangle cutout at bottom center) - longer/deeper
    final notchPath = Path();
    notchPath.moveTo(centerX - w * 0.20, centerY + h * 0.22); // Left base of notch
    notchPath.lineTo(centerX + w * 0.20, centerY + h * 0.22); // Right base of notch
    notchPath.lineTo(centerX, centerY + h * 0.35); // Bottom point of notch (deeper)
    notchPath.close();

    // Combined path with cutout
    final combinedPath = Path();
    combinedPath.fillType = PathFillType.evenOdd;
    combinedPath.addPath(arrowPath, Offset.zero);
    combinedPath.addPath(notchPath, Offset.zero);

    // Draw glow
    canvas.drawPath(arrowPath, glowPaint);
    
    // ✅ ARROW FILL
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.fill;
    canvas.drawPath(combinedPath, paint);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) =>
      oldDelegate.color != color || 
      oldDelegate.opacity != opacity ||
      oldDelegate.isSearching != isSearching ||
      oldDelegate.animationValue != animationValue;
}
