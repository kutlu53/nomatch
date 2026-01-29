import 'package:flutter/foundation.dart';

/// Single orientation sample from native sensor fusion
@immutable
class OrientationSample {
  /// Tilt-compensated yaw in degrees (0–360)
  final double yawDeg;
  
  /// Magnetic field strength in µT (microtesla)
  final double magStrengthUT;
  
  /// Sensor accuracy level (0=low, 1=medium, 2=high)
  final int accuracy;
  
  /// Timestamp (milliseconds since epoch)
  final int timestampMs;

  const OrientationSample({
    required this.yawDeg,
    required this.magStrengthUT,
    required this.accuracy,
    required this.timestampMs,
  });

  /// Age of sample in milliseconds (relative to provided reference time)
  int ageMs(int referenceTimeMs) => referenceTimeMs - timestampMs;

  @override
  String toString() =>
      'OrientationSample(yaw=${yawDeg.toStringAsFixed(1)}°, magStr=${magStrengthUT.toStringAsFixed(1)}µT, acc=$accuracy, t=$timestampMs)';
}

/// Statistics of a valid orientation window
@immutable
class WindowStats {
  /// Circular median yaw (degrees)
  final double medianYaw;
  
  /// Circular standard deviation (degrees)
  final double yawStd;
  
  /// Average magnetic strength (µT)
  final double avgMagStrength;
  
  /// Standard deviation of magnetic strength (µT)
  final double magStrengthStd;
  
  /// Minimum sensor accuracy observed
  final int minAccuracy;
  
  /// Number of samples in window
  final int sampleCount;
  
  /// Duration of window (milliseconds)
  final int durationMs;

  const WindowStats({
    required this.medianYaw,
    required this.yawStd,
    required this.avgMagStrength,
    required this.magStrengthStd,
    required this.minAccuracy,
    required this.sampleCount,
    required this.durationMs,
  });

  /// Check if window meets stability criteria
  bool isValid({
    required double maxYawStd,
    required double minMagStrength,
    required double maxMagStrength,
    required double maxMagStrengthStd,
    required int minAccuracy,
  }) {
    return yawStd <= maxYawStd &&
        avgMagStrength >= minMagStrength &&
        avgMagStrength <= maxMagStrength &&
        magStrengthStd <= maxMagStrengthStd &&
        this.minAccuracy >= minAccuracy;
  }

  @override
  String toString() =>
      'WindowStats(yaw=${medianYaw.toStringAsFixed(1)}°±${yawStd.toStringAsFixed(1)}°, mag=${avgMagStrength.toStringAsFixed(1)}±${magStrengthStd.toStringAsFixed(1)}µT, acc=$minAccuracy, n=$sampleCount, dur=${durationMs}ms)';
}

/// Face-to-face detection result
@immutable
class FaceToFaceResult {
  /// Both devices have valid stable windows
  final bool bothValid;
  
  /// Yaw difference between devices (degrees, absolute value)
  final double yawDifference;
  
  /// True if yaw difference ≈ 180° (within tolerance)
  final bool isFaceToFace;
  
  /// Duration of stable face-to-face condition (milliseconds)
  final int stableDurationMs;
  
  /// Stats for device A
  final WindowStats? statsA;
  
  /// Stats for device B
  final WindowStats? statsB;

  const FaceToFaceResult({
    required this.bothValid,
    required this.yawDifference,
    required this.isFaceToFace,
    required this.stableDurationMs,
    this.statsA,
    this.statsB,
  });

  @override
  String toString() =>
      'FaceToFaceResult(valid=$bothValid, diff=${yawDifference.toStringAsFixed(1)}°, f2f=$isFaceToFace, stable=${stableDurationMs}ms)';
}
