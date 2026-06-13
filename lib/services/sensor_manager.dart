import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import '../core/debug_config.dart';

/// Manages device sensors (accelerometer) to detect if phone is flat
class SensorManager {
  static const double flatThreshold = 7.0; // Z-axis must be > this to consider phone flat (raw m/s², ~9.8 is flat, 7.0 allows ~45° tilt tolerance)
  static const int bufferSize = 10; // Longer buffer for stability
  static const int _throttleMs = 100; // ✅ OPTIMIZATION: Process max 10 times per second
  
  final _flatController = StreamController<bool>.broadcast();
  Stream<bool> get flatUpdates => _flatController.stream;
  
  StreamSubscription? _accelerometerSub;
  bool _isFlat = false;
  bool get isFlat => _isFlat;
  
  final List<bool> _flatBuffer = [];
  DateTime? _lastProcessTime; // ✅ OPTIMIZATION: Throttle sensor events

  /// Start listening to accelerometer
  Future<void> start() async {
    sensorLog('📱 Starting sensor manager (throttled to ${1000 ~/ _throttleMs} Hz)');
    
    _accelerometerSub = accelerometerEvents.listen((event) {
      // ✅ OPTIMIZATION: Throttle sensor events to reduce CPU load
      final now = DateTime.now();
      if (_lastProcessTime != null && 
          now.difference(_lastProcessTime!).inMilliseconds < _throttleMs) {
        return; // Skip this event
      }
      _lastProcessTime = now;
      
      // Accelerometer gives x, y, z in m/s²
      // When phone is FLAT on table: z-axis (up/down gravity) is ~9.8 (positive)
      // When phone is HELD UP vertically: z-axis is near 0, y-axis is ~9.8
      // z > 0.85 (normalized from 9.8) means phone is flat on table
      
      final zAbs = event.z.abs();
      final flatDetected = zAbs > flatThreshold;
      
      _flatBuffer.add(flatDetected);
      if (_flatBuffer.length > bufferSize) {
        _flatBuffer.removeAt(0);
      }
      
      // Vote: need majority (>60%) to confirm state
      final flatCount = _flatBuffer.where((f) => f).length;
      final threshold = (bufferSize * 0.6).ceil(); // 60% majority
      final newIsFlat = flatCount >= threshold;
      
      if (newIsFlat != _isFlat) {
        _isFlat = newIsFlat;
        _flatController.add(_isFlat);
      }
    });
  }

  /// Stop listening
  Future<void> stop() async {
    sensorLog('🛑 Stopping sensor manager');
    await _accelerometerSub?.cancel();
  }

  /// Clean up
  Future<void> dispose() async {
    await stop();
    await _flatController.close();
  }
}
