import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../core/debug_config.dart';

/// Heading validation using Sensor Fusion
/// 
/// Uses device's fused orientation sensors:
/// - iOS: CMDeviceMotion.attitude (Accel + Gyro + Mag fusion)
/// - Android: TYPE_ROTATION_VECTOR (Accel + Gyro + Mag fusion)
/// - Web: Not supported (graceful fallback)
/// 
/// This provides much more stable heading than magnetometer alone.
class HeadingValidator {
  static const platform = MethodChannel('com.nomatch/compass');

  // Heading buffer for stability
  final List<double> _headingBuffer = [];
  static const int bufferSize = 10; // Buffer for averaging
  
  double _currentHeading = 0.0;
  double get currentHeading => _currentHeading;
  
  bool _isStable = false;
  bool get isStable => _isStable;
  
  // ✅ FIX: Recreate controller if closed
  StreamController<double>? _headingController;
  Stream<double> get headingUpdates {
    _ensureController();
    return _headingController!.stream;
  }
  
  void _ensureController() {
    if (_headingController == null || _headingController!.isClosed) {
      headingLog('🔄 Creating new heading stream controller');
      _headingController = StreamController<double>.broadcast();
    }
  }

  /// Start listening to device compass/heading (Sensor Fusion)
  Future<void> start() async {
    _ensureController(); // ✅ Ensure controller exists before starting
    _headingBuffer.clear(); // ✅ Clear buffer for fresh start
    
    if (kIsWeb) {
      headingLog('🌐 Web platform - heading validation skipped');
    } else {
      headingLog('🧭 Heading validator started - using Sensor Fusion');
      headingLog('   └─ iOS: CMDeviceMotion.attitude.yaw');
      headingLog('   └─ Android: TYPE_ROTATION_VECTOR');
    }
    
    _startCompass();
  }

  /// Stop listening (but don't close stream permanently)
  Future<void> stop() async {
    headingLog('🛑 Stopping heading validator');
    // Native pusulayı durdur — MethodChannel üzerinden geldiği için subscription
    // cancel'ı yetmez, native tarafı da açıkça durdurmak gerekir.
    try {
      await platform.invokeMethod('stopCompass');
      headingLog('✅ Native compass stopped');
    } catch (e) {
      headingLog('⚠️ stopCompass failed (ignored): $e');
    }
  }

  /// Update heading value
  void updateHeading(double heading) {
    _currentHeading = heading % 360.0;
    _headingBuffer.add(_currentHeading);
    
    if (_headingBuffer.length > bufferSize) {
      _headingBuffer.removeAt(0);
    }

    // Check stability (low variance in buffer)
    _isStable = _checkStability();
    
    // ✅ FIX: Only emit if controller exists and not closed
    if (_headingController != null && !_headingController!.isClosed) {
      _headingController!.add(_currentHeading);
    }
  }

  /// Check if heading is stable
  bool _checkStability() {
    if (_headingBuffer.length < bufferSize) return false;
    
    final mean = _headingBuffer.reduce((a, b) => a + b) / _headingBuffer.length;
    final variance = _headingBuffer
        .map((h) => (h - mean) * (h - mean))
        .reduce((a, b) => a + b) / _headingBuffer.length;
    final stdDev = math.sqrt(variance);
    
    // Stable if standard deviation < 10°
    return stdDev < 10.0;
  }

  /// Start Sensor Fusion heading updates
  void _startCompass() {
    // ✅ Web platform doesn't have native compass - skip gracefully
    if (kIsWeb) {
      headingLog('⚠️ Web platform detected - compass not available');
      headingLog('   └─ Heading validation disabled on web');
      // Set a default heading for web testing
      _currentHeading = 0.0;
      _isStable = true;
      return;
    }
    
    try {
      // Listen to fused heading stream from native
      platform.setMethodCallHandler((call) async {
        if (call.method == 'heading') {
          final heading = (call.arguments as num).toDouble();
          updateHeading(heading);
        }
        return null;
      });
      
      // Tell native to start sensor fusion
      platform.invokeMethod('startCompass').then((_) {
        headingLog('✅ Sensor Fusion compass started');
      }).catchError((e) {
        headingLog('❌ Failed to start Sensor Fusion: $e');
      });
    } catch (e) {
      headingLog('❌ Sensor Fusion initialization error: $e');
    }
  }

  /// Permanently dispose (only call when app is shutting down)
  Future<void> dispose() async {
    headingLog('🗑️ Disposing heading validator permanently');
    try {
      await platform.invokeMethod('stopCompass');
    } catch (_) {}
    await _headingController?.close();
    _headingController = null;
  }
}
