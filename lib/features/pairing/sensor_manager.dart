import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:nomatch/services/rotation_vector_processor.dart';

/// Sensor data for pairing validation
class SensorData {
  final double accelX;
  final double accelY;
  final double accelZ;
  final double? heading; // 0-360° (null if not available)
  final bool isFlat;
  
  const SensorData({
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.heading,
    required this.isFlat,
  });
  
  factory SensorData.initial() => const SensorData(
    accelX: 0,
    accelY: 0,
    accelZ: 0,
    heading: null,
    isFlat: false,
  );
}

/// Manages accelerometer and magnetometer sensors
class SensorManager {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<MagnetometerEvent>? _magnetoSub;
  
  // ✅ NEW: Platform channel for iOS magnetometer calibration check
  static const platform = MethodChannel('com.nomatch/magnetometer');
  
  final StreamController<SensorData> _controller = StreamController<SensorData>.broadcast();
  Stream<SensorData> get sensorStream => _controller.stream;
  
  // Current sensor values
  double _accelX = 0;
  double _accelY = 0;
  double _accelZ = 0;
  double? _heading;
  
  // Magnetometer raw values for heading calculation
  double _magX = 0;
  double _magY = 0;
  double _magZ = 0;
  
  // ✅ NEW: Flat detection smoothing (10-sample rolling average)
  final List<bool> _flatSamples = [];
  static const int _flatSampleWindow = 10;
  bool _smoothedIsFlat = false;
  
  // ✅ NEW: Device orientation correction
  // iOS: Portrait=0, LandscapeRight=90, Landscape=-90, PortraitUpsideDown=180
  double _orientationAngle = 0.0;
  
  // ✅ NEW: Heading history for debugging and smoothing
  final List<double> _headingHistory = [];
  static const int _headingHistorySize = 20;
  
  // ✅ NEW: Face-to-face detection
  late FaceToFaceDetector _faceToFaceDetector;
  StreamSubscription<dynamic>? _rotationVectorSub; // Platform channel for rotation vector
  static const rotationVectorChannel = MethodChannel('com.nomatch/rotation_vector');
  
  // Rotation matrix (3x3) from device motion / rotation vector
  RotationMatrix? _currentRotationMatrix;
  
  // Magnetometer magnitude history for stability check
  final List<double> _magnetometerMagnitudes = [];
  
  bool _isActive = false;
  
  /// Start listening to sensors
  Future<void> start() async {
    if (_isActive) return;
    _isActive = true;
    
    // ✅ NEW: Initialize face-to-face detector
    _faceToFaceDetector = FaceToFaceDetector();
    
    // ✅ NEW: Check magnetometer calibration on iOS
    await _checkMagnetometerCalibration();
    
    // Listen to accelerometer (for flat detection)
    _accelSub = accelerometerEventStream().listen((event) {
      _accelX = event.x;
      _accelY = event.y;
      _accelZ = event.z;
      _emitCurrentData();
    });
    
    // Listen to magnetometer (for heading/compass)
    _magnetoSub = magnetometerEventStream().listen((event) {
      _magX = event.x;
      _magY = event.y;
      _magZ = event.z;
      
      // Track magnetometer magnitude for stability check
      final magnitude = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      _magnetometerMagnitudes.add(magnitude);
      if (_magnetometerMagnitudes.length > 200) {
        _magnetometerMagnitudes.removeAt(0); // Keep last 200 samples
      }
      
      _updateHeading();
      _updateFaceToFaceDetection();
      _emitCurrentData();
    });
    
    // ✅ NEW: Listen to rotation vector from platform channel (for face-to-face)
    _setupRotationVectorListener();
  }
  
  /// ✅ NEW: Check magnetometer calibration status on iOS
  /// Guides user to Compass app if uncalibrated
  Future<void> _checkMagnetometerCalibration() async {
    try {
      final result = await platform.invokeMethod<Map>('checkMagnetometerAccuracy');
      
      if (result != null) {
        final isCalibrated = result['isCalibrated'] as bool? ?? false;
        final accuracy = result['accuracy'] as int? ?? -1;
        final accuracyLabel = result['accuracyLabel'] as String? ?? 'Unknown';
        
        print('[MAGN] 🧲 Magnetometer calibration check:');
        print('[MAGN]   - Is Calibrated: $isCalibrated');
        print('[MAGN]   - Accuracy Level: $accuracyLabel (raw: $accuracy)');
        
        if (!isCalibrated) {
          print('[MAGN] ⚠️ WARNING: Magnetometer is UNCALIBRATED!');
          print('[MAGN] 💡 SUGGESTION: Open Compass app and rotate phone in "8" pattern');
        } else {
          print('[MAGN] ✅ Magnetometer is properly calibrated');
        }
      }
    } catch (e) {
      print('[MAGN] ❌ Error checking magnetometer: $e');
    }
  }
  
  /// ✅ NEW: Set device orientation correction angle (call from app coordinator)
  /// iOS: Portrait=0°, LandscapeRight=90°, PortraitUpsideDown=180°
  /// This corrects for the fact that magnetometer X/Y axes rotate with screen orientation
  void setOrientationCorrection(double angleInDegrees) {
    _orientationAngle = angleInDegrees;
    print('[SENS] 🔄 Device orientation correction set to: $_orientationAngle°');
  }
  
  /// Stop listening to sensors
  void stop() {
    if (!_isActive) return;
    _isActive = false;
    
    _accelSub?.cancel();
    _accelSub = null;
    
    _magnetoSub?.cancel();
    _magnetoSub = null;
    
    _rotationVectorSub?.cancel();
    _rotationVectorSub = null;
  }
  
  /// Calculate heading from rotation matrix (fused sensor data)
  /// Returns 0-360° where 0° is North
  /// Uses device's forward direction from rotation matrix for accuracy
  void _updateHeading() {
    // ✅ NEW: Try to use rotation matrix first (more accurate, accounts for tilt)
    if (_currentRotationMatrix != null) {
      final forward = _getForwardDirectionWorldCoordinates();
      if (forward != null) {
        // Forward direction in world coordinates: [x, y, z]
        // Heading = atan2(y, x) in horizontal plane
        double headingRad = math.atan2(forward.y, forward.x);
        double headingDeg = headingRad * (180 / math.pi);
        
        // Normalize to 0-360
        if (headingDeg < 0) {
          headingDeg += 360;
        }
        
        _heading = headingDeg;
        _headingHistory.add(headingDeg);
        if (_headingHistory.length > _headingHistorySize) {
          _headingHistory.removeAt(0);
        }
        
        // 🔍 Log every 10th sample
        if (_headingHistory.length % 10 == 0) {
          final avgHeading = _headingHistory.reduce((a, b) => a + b) / _headingHistory.length;
          print('[SENS] 🧭 Heading (from Rotation Matrix):');
          print('[SENS]   - Forward: $forward');
          print('[SENS]   - Heading: ${headingDeg.toStringAsFixed(1)}°');
          print('[SENS]   - Average (last ${_headingHistory.length}): ${avgHeading.toStringAsFixed(1)}°');
        }
        return;
      }
    }
    
    // ✅ FALLBACK: Use raw magnetometer if rotation matrix not available yet
    if (_magX == 0 && _magY == 0) {
      _heading = null;
      return;
    }

    double headingRad = math.atan2(_magY, _magX);
    double headingDeg = headingRad * (180 / math.pi);

    // Normalize to 0-360
    if (headingDeg < 0) {
      headingDeg += 360;
    }

    // 📱 Device orientation correction
    headingDeg += _orientationAngle;
    headingDeg = headingDeg % 360;

    _headingHistory.add(headingDeg);
    if (_headingHistory.length > _headingHistorySize) {
      _headingHistory.removeAt(0);
    }

    _heading = headingDeg;
    
    // 🔍 Log every 10th sample
    if (_headingHistory.length % 10 == 0) {
      final avgHeading = _headingHistory.reduce((a, b) => a + b) / _headingHistory.length;
      print('[SENS] 🧭 Heading (from Magnetometer - Fallback):');
      print('[SENS]   - Raw (atan2): magX=$_magX, magY=$_magY → ${headingDeg.toStringAsFixed(1)}°');
      print('[SENS]   - Accel: X=${_accelX.toStringAsFixed(2)}, Y=${_accelY.toStringAsFixed(2)}, Z=${_accelZ.toStringAsFixed(2)}');
      print('[SENS]   - Average (last ${_headingHistory.length}): ${avgHeading.toStringAsFixed(1)}°');
    }
  }
  
  /// Emit current sensor data
  void _emitCurrentData() {
    // ✅ Use smoothed flat detection (10-sample average)
    _smoothedIsFlat = _checkIsFlat_Smoothed();
    
    _controller.add(SensorData(
      accelX: _accelX,
      accelY: _accelY,
      accelZ: _accelZ,
      heading: _heading,
      isFlat: _smoothedIsFlat,
    ));
  }
  
  /// ✅ NEW: Smoothed flat detection (prevents flickering)
  /// Uses 10-sample rolling average + majority voting
  /// Requires 7/10 samples to consider flat
  bool _checkIsFlat_Smoothed() {
    final newFlat = _checkIsFlat_Raw();
    
    // Add to window
    _flatSamples.add(newFlat);
    if (_flatSamples.length > _flatSampleWindow) {
      _flatSamples.removeAt(0);
    }
    
    // Majority voting: 7+ out of 10 = flat
    final flatCount = _flatSamples.where((f) => f).length;
    final threshold = (_flatSampleWindow * 0.7).ceil();
    return flatCount >= threshold;
  }
  
  /// Check if phone is flat on table (raw, unsmoothed)
  bool _checkIsFlat_Raw() {
    final zAbs = _accelZ.abs();
    final xAbs = _accelX.abs();
    final yAbs = _accelY.abs();
    
    return zAbs >= 8.5 && 
           zAbs <= 10.5 && 
           xAbs < 3.0 && 
           yAbs < 3.0;
  }
  
  /// Deprecated: Use _checkIsFlat_Smoothed() instead
  @deprecated
  bool _checkIsFlat() => _checkIsFlat_Raw();
  
  /// Get current sensor data immediately (without stream)
  SensorData getCurrentData() {
    return SensorData(
      accelX: _accelX,
      accelY: _accelY,
      accelZ: _accelZ,
      heading: _heading,
      isFlat: _smoothedIsFlat, // ✅ Use smoothed value
    );
  }
  
  /// ✅ NEW: Setup rotation vector listener from platform channel
  void _setupRotationVectorListener() {
    rotationVectorChannel.setMethodCallHandler((call) async {
      if (call.method == 'onRotationVector') {
        final List<dynamic> rotMatrix = call.arguments['rotationMatrix'] as List<dynamic>;
        final rotationMatrixDoubles = rotMatrix.cast<double>();
        _currentRotationMatrix = RotationMatrix.fromArray(rotationMatrixDoubles);
      }
      return null;
    });
  }

  /// ✅ NEW: Get forward direction vector in world coordinates
  /// Phone forward axis depends on screen orientation:
  /// - Portrait: Y-axis points forward
  /// - Landscape: X-axis points forward
  /// This method extracts the forward direction using the rotation matrix
  Vector3? _getForwardDirectionWorldCoordinates() {
    if (_currentRotationMatrix == null) return null;

    // Default: Y-axis (for portrait) is "forward" in device coordinates
    final deviceForward = [0.0, 1.0, 0.0]; // Y-axis in device coords

    // Transform to world coordinates using rotation matrix
    final worldForward = _currentRotationMatrix!.multiplyVector(deviceForward);
    return Vector3(worldForward[0], worldForward[1], worldForward[2]);
  }

  /// ✅ NEW: Update face-to-face detector with current sensor data
  void _updateFaceToFaceDetection() {
    final forward = _getForwardDirectionWorldCoordinates();
    if (forward == null) return;

    final accelMag = math.sqrt(_accelX * _accelX + _accelY * _accelY + _accelZ * _accelZ);
    final magnetoMag =
        math.sqrt(_magX * _magX + _magY * _magY + _magZ * _magZ);

    if (_currentRotationMatrix != null) {
      _faceToFaceDetector.addSample(
        forwardWorldDirection: forward,
        magnetometerMagnitude: magnetoMag,
        accelMagnitude: accelMag,
        rotationMatrix: _currentRotationMatrix!,
      );
    }
  }

  /// ✅ NEW: Get current face-to-face detection result
  FaceToFaceResult? getFaceToFaceResult() {
    if (!_faceToFaceDetector.isBufferReady) return null;
    return _faceToFaceDetector.detect();
  }

  /// ✅ NEW: Reset face-to-face detector
  void resetFaceToFaceDetector() {
    _faceToFaceDetector.clear();
  }

  /// Dispose resources
  void dispose() {
    stop();
    _rotationVectorSub?.cancel();
    _controller.close();
  }
}
