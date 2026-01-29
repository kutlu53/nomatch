import 'package:flutter/foundation.dart';
import 'dart:math' as math;

/// Raw orientation vector sample from native platform
/// Represents phone's forward direction in world coordinates (WORLD frame)
@immutable
class OrientationVectorSample {
  /// Forward direction in world coordinates (normalized or not, platform-dependent)
  final double fx; // X component
  final double fy; // Y component
  final double fz; // Z component

  /// Magnetometer magnitude in microTesla (μT)
  /// Valid range typically [20, 80]
  final double? magnetometerMagnitude;

  /// Magnetometer accuracy level (0=low, 1=medium, 2=high, -1=uncalibrated)
  final int? magnetometerAccuracy;

  /// Timestamp when sample was captured (milliseconds since epoch)
  final int timestamp;

  const OrientationVectorSample({
    required this.fx,
    required this.fy,
    required this.fz,
    this.magnetometerMagnitude,
    this.magnetometerAccuracy,
    required this.timestamp,
  });

  /// Normalize forward vector to unit length
  OrientationVectorSample normalized() {
    final mag = math.sqrt(fx * fx + fy * fy + fz * fz);
    if (mag < 0.001) return this;
    return OrientationVectorSample(
      fx: fx / mag,
      fy: fy / mag,
      fz: fz / mag,
      magnetometerMagnitude: magnetometerMagnitude,
      magnetometerAccuracy: magnetometerAccuracy,
      timestamp: timestamp,
    );
  }

  /// Project forward vector onto horizontal plane and normalize
  /// Result: (fx, fy, 0) normalized
  List<double> horizontalProjection() {
    final hx = fx;
    final hy = fy;
    final mag = math.sqrt(hx * hx + hy * hy);
    if (mag < 0.001) return [0, 0]; // Degenerate case
    return [hx / mag, hy / mag];
  }

  @override
  String toString() =>
      'OrVecSample(f=[${fx.toStringAsFixed(3)}, ${fy.toStringAsFixed(3)}, ${fz.toStringAsFixed(3)}], magMag=${magnetometerMagnitude?.toStringAsFixed(1)}, t=$timestamp)';
}
