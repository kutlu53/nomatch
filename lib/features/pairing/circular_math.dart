import 'dart:math' as math;

/// Circular (angular) math utilities for yaw/heading calculations
class CircularMath {
  /// Normalize angle to [-180, 180] range
  static double wrap180(double angle) {
    var wrapped = angle % 360;
    if (wrapped > 180) wrapped -= 360;
    if (wrapped < -180) wrapped += 360;
    return wrapped;
  }

  /// Normalize angle to [0, 360) range
  static double wrap360(double angle) {
    var wrapped = angle % 360;
    if (wrapped < 0) wrapped += 360;
    return wrapped;
  }

  /// Shortest circular distance between two angles (always positive, [0, 180])
  static double shortestDistance(double angle1, double angle2) {
    var diff = wrap180(angle1 - angle2);
    return diff.abs();
  }

  /// Circular mean of angles (in degrees)
  /// Returns angle in [0, 360) range
  static double circularMean(List<double> angles) {
    if (angles.isEmpty) return 0;
    
    double sinSum = 0;
    double cosSum = 0;
    
    for (final angle in angles) {
      final rad = angle * math.pi / 180;
      sinSum += math.sin(rad);
      cosSum += math.cos(rad);
    }
    
    final meanRad = math.atan2(sinSum / angles.length, cosSum / angles.length);
    return wrap360(meanRad * 180 / math.pi);
  }

  /// Circular median of angles (in degrees)
  /// Uses angular distance to find point with min total distance
  static double circularMedian(List<double> angles) {
    if (angles.isEmpty) return 0;
    if (angles.length == 1) return angles[0];
    
    // Normalize all angles
    final normalized = angles.map((a) => wrap360(a)).toList();
    
    // Find angle with minimum total circular distance to all others
    double minTotalDist = double.infinity;
    double medianAngle = 0;
    
    for (final candidate in normalized) {
      double totalDist = 0;
      for (final angle in normalized) {
        totalDist += shortestDistance(candidate, angle);
      }
      if (totalDist < minTotalDist) {
        minTotalDist = totalDist;
        medianAngle = candidate;
      }
    }
    
    return medianAngle;
  }

  /// Circular standard deviation (in degrees)
  /// Measures spread of angles around circular mean
  static double circularStd(List<double> angles) {
    if (angles.isEmpty) return 0;
    if (angles.length == 1) return 0;
    
    final mean = circularMean(angles);
    
    double sumSquaredDist = 0;
    for (final angle in angles) {
      final dist = shortestDistance(angle, mean);
      sumSquaredDist += dist * dist;
    }
    
    return math.sqrt(sumSquaredDist / angles.length);
  }

  /// Check if angles are approximately equal (within tolerance)
  /// Uses shortest circular distance
  static bool areApproxEqual(double angle1, double angle2, double toleranceDeg) {
    return shortestDistance(angle1, angle2) <= toleranceDeg;
  }

  /// Linear standard deviation (for non-angular values like magnetic strength)
  static double linearStd(List<double> values) {
    if (values.isEmpty) return 0;
    if (values.length == 1) return 0;
    
    final mean = values.reduce((a, b) => a + b) / values.length;
    double sumSquaredDiff = 0;
    
    for (final val in values) {
      sumSquaredDiff += (val - mean) * (val - mean);
    }
    
    return math.sqrt(sumSquaredDiff / values.length);
  }
}
