import 'package:flutter/foundation.dart';

/// Phone head orientation detected from accelerometer
enum HeadOrientation {
  HEAD_UP,      // Z-axis > +7.0 (baş yukarı)
  HEAD_DOWN,    // Z-axis < -7.0 (baş aşağı)
  SIDEWAYS,     // Yatay pozisyon
  TILTED,       // Eğik pozisyon
  UNKNOWN,      // Belirsiz
}

/// Accelerometer reading
@immutable
class AccelerometerReading {
  final double x;
  final double y;
  final double z;

  const AccelerometerReading({
    required this.x,
    required this.y,
    required this.z,
  });

  bool get isLevel => x.abs() < 3.0 && y.abs() < 3.0;

  @override
  String toString() => 'Accel(x=${x.toStringAsFixed(2)}, y=${y.toStringAsFixed(2)}, z=${z.toStringAsFixed(2)})';
}

/// Synchronization result
@immutable
class SyncResult {
  final bool isSynced;
  final double confidence;      // 0.0 - 1.0
  final int scorePoints;        // 0 - 4
  final String headingStatus;
  final String accelStatus;
  final String zAxisStatus;
  final String levelStatus;
  final String orientationStatus;

  const SyncResult({
    required this.isSynced,
    required this.confidence,
    required this.scorePoints,
    required this.headingStatus,
    required this.accelStatus,
    required this.zAxisStatus,
    required this.levelStatus,
    required this.orientationStatus,
  });

  @override
  String toString() =>
      'SyncResult(synced=$isSynced, conf=${(confidence * 100).toStringAsFixed(0)}%, score=$scorePoints/4)';
}

/// Phone orientation validation result
@immutable
class PhoneOrientationValidationResult {
  final HeadOrientation orientation;
  final bool isLevel;
  final double zValue;

  const PhoneOrientationValidationResult({
    required this.orientation,
    required this.isLevel,
    required this.zValue,
  });

  String get label {
    switch (orientation) {
      case HeadOrientation.HEAD_UP:
        return '⬆️ HEAD_UP';
      case HeadOrientation.HEAD_DOWN:
        return '⬇️ HEAD_DOWN';
      case HeadOrientation.SIDEWAYS:
        return '↔️ SIDEWAYS';
      case HeadOrientation.TILTED:
        return '🔄 TILTED';
      case HeadOrientation.UNKNOWN:
        return '❓ UNKNOWN';
    }
  }

  @override
  String toString() => 'PhoneOrientation($label, level=$isLevel, z=${zValue.toStringAsFixed(2)})';
}

/// Accelerometer calibration result
@immutable
class AccelCalibrationResult {
  final bool isValid;
  final double avgX;
  final double avgY;
  final double avgZ;
  final int sampleCount;

  const AccelCalibrationResult({
    required this.isValid,
    required this.avgX,
    required this.avgY,
    required this.avgZ,
    required this.sampleCount,
  });

  @override
  String toString() =>
      'AccelCalib(valid=$isValid, avg=(${avgX.toStringAsFixed(2)}, ${avgY.toStringAsFixed(2)}, ${avgZ.toStringAsFixed(2)}), n=$sampleCount)';
}

/// Constants for heading synchronization
class HeadingSyncConstants {
  static const double GRAVITY = 9.81;
  
  // Heading thresholds
  static const double HEADING_TOLERANCE = 30.0;  // ±30° around 180°
  static const double HEADING_EXPECTED = 180.0;
  static const double HEADING_MIN = 150.0;       // 180 - 30
  static const double HEADING_MAX = 210.0;       // 180 + 30

  // Accelerometer thresholds
  static const double HEAD_UP_THRESHOLD = 7.0;   // Z > 7.0
  static const double HEAD_DOWN_THRESHOLD = -7.0; // Z < -7.0
  static const double Z_AXIS_TOLERANCE = 3.0;    // |z1| ≈ |z2| within 3.0
  static const double LEVEL_THRESHOLD = 3.0;     // X,Y < 3.0 for level
  
  // Validation thresholds
  static const int MIN_SCORE_POINTS = 3;         // Need 3 out of 4
  static const double MIN_CONFIDENCE = 0.75;     // 75%
  
  // Moving average
  static const int MOVING_AVERAGE_WINDOW = 10;   // Last 10 readings
  
  // Anomaly detection
  static const double ANOMALY_THRESHOLD = 30.0;  // 30° change in 50ms
  static const int FAILURE_THRESHOLD = 3;        // 3 fails = disconnect
}
