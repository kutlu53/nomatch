import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/game_colors.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// START TRIANGLE BUTTON - Premium Minimal Interaction
// ═══════════════════════════════════════════════════════════════════════════════

/// Color constants
const Color _triangleColorDefault = Color(0xFFEDEBFF); // Ice Silver
const Color _triangleColorConnected = GameColors.purple; // Purple when BLE connected
const Color _triangleColorMatched = GameColors.lime; // Lime when full match
const Color _ringPulseColor = Color(0xFFEDEBFF);
const Color _sweepHighlightColor = Color(0xFF7B5CFF);

/// Triangle button states
enum TriangleState {
  idle,      // Default - Ice Silver
  scanning,  // Scanning - Ice Silver with sweep
  connected, // BLE connected - Purple
  matched,   // Full match - Lime
}

/// Premium start/scan triangle button with micro-interactions.
/// 
/// Features:
/// - Tap: Scale 1.0→0.94→1.0 with expanding ring pulse
/// - Scanning: Sweep highlight + notch drift
/// - Connected: Smooth transition to purple
/// - Matched: Smooth transition to lime
/// - No text, no sound, minimal glow
class StartTriangleButton extends StatefulWidget {
  final bool isScanning;
  final TriangleState triangleState;
  final VoidCallback onTap;

  const StartTriangleButton({
    super.key,
    required this.isScanning,
    this.triangleState = TriangleState.idle,
    required this.onTap,
  });

  @override
  State<StartTriangleButton> createState() => _StartTriangleButtonState();
}

class _StartTriangleButtonState extends State<StartTriangleButton>
    with TickerProviderStateMixin {
  // Tap scale animation
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;
  
  // Ring pulse animation (expanding ring on tap)
  late final AnimationController _ringPulseController;
  
  // Scanning sweep animation
  late final AnimationController _sweepController;
  
  // Notch drift animation
  late final AnimationController _driftController;
  late final Animation<double> _driftAnimation;
  
  // ✅ Color transition animation
  late final AnimationController _colorController;
  Color _currentColor = _triangleColorDefault;
  Color _targetColor = _triangleColorDefault;

  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    
    // Scale animation (tap feedback) - 80ms down, 160ms up with slight bounce
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeOutBack,
      ),
    );
    
    // Ring pulse animation - 220ms expand + fade
    _ringPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    
    // Sweep highlight animation (scanning) - 1.8s loop
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    
    // Notch drift animation (scanning) - 1.6s back and forth
    _driftController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _driftAnimation = Tween<double>(begin: -1.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _driftController,
        curve: Curves.easeInOut,
      ),
    );
    
    // ✅ Color transition (400ms smooth)
    _colorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _colorController.addListener(() {
      setState(() {});
    });
    
    _updateScanningState();
    _updateColorState();
  }

  @override
  void didUpdateWidget(covariant StartTriangleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isScanning != widget.isScanning) {
      _updateScanningState();
    }
    if (oldWidget.triangleState != widget.triangleState) {
      _updateColorState();
    }
  }

  void _updateScanningState() {
    if (widget.isScanning) {
      _sweepController.repeat();
      _driftController.repeat(reverse: true);
    } else {
      _sweepController.stop();
      _driftController.stop();
      _driftController.value = 0.5; // Reset to center
    }
  }
  
  void _updateColorState() {
    // ✅ Determine target color based on state
    final newTargetColor = switch (widget.triangleState) {
      TriangleState.idle => _triangleColorDefault,
      TriangleState.scanning => _triangleColorDefault,
      TriangleState.connected => _triangleColorConnected,
      TriangleState.matched => _triangleColorMatched,
    };
    
    if (newTargetColor != _targetColor) {
      _currentColor = Color.lerp(_currentColor, _targetColor, _colorController.value) ?? _currentColor;
      _targetColor = newTargetColor;
      _colorController.forward(from: 0.0);
    }
  }
  
  Color get _animatedColor {
    return Color.lerp(_currentColor, _targetColor, 
      Curves.easeOut.transform(_colorController.value)) ?? _targetColor;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _ringPulseController.dispose();
    _sweepController.dispose();
    _driftController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (_isPressed) return;
    _isPressed = true;
    HapticFeedback.lightImpact();
    _scaleController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (!_isPressed) return;
    _isPressed = false;
    _scaleController.reverse();
    // Trigger ring pulse on tap complete
    _ringPulseController.forward(from: 0.0);
    widget.onTap();
  }

  void _onTapCancel() {
    if (!_isPressed) return;
    _isPressed = false;
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isConnectedOrMatched = widget.triangleState == TriangleState.connected || 
                                  widget.triangleState == TriangleState.matched;
    
    return RepaintBoundary(
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 140,
          height: 140,
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _scaleAnimation,
              _ringPulseController,
              _sweepController,
              _driftAnimation,
              _colorController,
            ]),
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Ring pulse overlay (tap feedback) - expanding ring
                    if (_ringPulseController.value > 0 && _ringPulseController.value < 1.0)
                      CustomPaint(
                        size: const Size(140, 140),
                        painter: _RingPulsePainter(
                          progress: _ringPulseController.value,
                        ),
                      ),
                    
                    // Main triangle
                    CustomPaint(
                      size: const Size(120, 120),
                      painter: _TrianglePainter(
                        color: _animatedColor,
                        opacity: (widget.isScanning || isConnectedOrMatched) ? 1.0 : 0.6,
                        sweepProgress: widget.isScanning ? _sweepController.value : null,
                        notchDrift: widget.isScanning ? _driftAnimation.value : 0.0,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRIANGLE PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _TrianglePainter extends CustomPainter {
  final Color color;
  final double opacity;
  final double? sweepProgress; // null = no sweep, 0.0-1.0 = sweep position
  final double notchDrift; // -1.0 to 1.0 for notch Y drift

  const _TrianglePainter({
    required this.color,
    required this.opacity,
    this.sweepProgress,
    this.notchDrift = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerX = w * 0.5;
    final centerY = h * 0.5;

    // Main upward-pointing triangle
    final arrowPath = Path();
    arrowPath.moveTo(centerX, centerY - h * 0.35); // Top point
    arrowPath.lineTo(centerX + w * 0.35, centerY + h * 0.25); // Bottom right
    arrowPath.lineTo(centerX - w * 0.35, centerY + h * 0.25); // Bottom left
    arrowPath.close();

    // Notch with drift
    final notchY = notchDrift * 2.0; // ±2px drift
    final notchPath = Path();
    notchPath.moveTo(centerX - w * 0.20, centerY + h * 0.22 + notchY);
    notchPath.lineTo(centerX + w * 0.20, centerY + h * 0.22 + notchY);
    notchPath.lineTo(centerX, centerY + h * 0.35 + notchY);
    notchPath.close();

    // Combined path with cutout
    final combinedPath = Path();
    combinedPath.fillType = PathFillType.evenOdd;
    combinedPath.addPath(arrowPath, Offset.zero);
    combinedPath.addPath(notchPath, Offset.zero);

    // Draw sweep highlight if scanning
    if (sweepProgress != null) {
      canvas.save();
      canvas.clipPath(combinedPath);
      
      // Sweep band (30° angle, moving left to right)
      final sweepX = w * (-0.3 + sweepProgress! * 1.6); // -30% to 130%
      final bandWidth = w * 0.15;
      
      final sweepPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            _sweepHighlightColor.withOpacity(0.0),
            _sweepHighlightColor.withOpacity(0.20),
            _sweepHighlightColor.withOpacity(0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(sweepX - bandWidth/2, 0, bandWidth, h));
      
      canvas.drawRect(
        Rect.fromLTWH(sweepX - bandWidth/2, 0, bandWidth, h),
        sweepPaint,
      );
      
      canvas.restore();
    }

    // Main fill
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.fill;
    canvas.drawPath(combinedPath, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.opacity != opacity ||
        oldDelegate.sweepProgress != sweepProgress ||
        oldDelegate.notchDrift != notchDrift;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RING PULSE PAINTER (Tap Feedback) - Expanding ring effect
// ═══════════════════════════════════════════════════════════════════════════════

class _RingPulsePainter extends CustomPainter {
  final double progress; // 0.0 to 1.0

  const _RingPulsePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    // Ring expands from triangle edge outward
    final minRadius = math.min(size.width, size.height) * 0.35;
    final maxRadius = math.min(size.width, size.height) * 0.55;
    final radius = minRadius + (maxRadius - minRadius) * progress;
    
    // Opacity: fade in quickly, then fade out
    final opacity = progress < 0.3 
        ? (progress / 0.3) // Fade in 0-30%
        : 1.0 - ((progress - 0.3) / 0.7); // Fade out 30-100%

    final paint = Paint()
      ..color = _ringPulseColor.withOpacity(0.15 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _RingPulsePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

