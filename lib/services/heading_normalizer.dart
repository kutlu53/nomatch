import 'dart:math' as math;

/// Heading normalizasyonu ve açı hesaplamaları
class HeadingNormalizer {
  /// Heading'i 0-360 aralığına normalize et
  static double normalizeHeading(double heading) {
    var normalized = heading % 360;
    if (normalized < 0) {
      normalized += 360;
    }
    return normalized;
  }

  /// İki heading arasındaki EN KISA farkı hesapla (-180 ile +180)
  /// Örnek: getAngularDifference(10, 350) = 20° (not 340°)
  static double getAngularDifference(double heading1, double heading2) {
    var diff = heading1 - heading2;
    
    // Normalize to [-180, 180]
    if (diff > 180) {
      diff -= 360;
    } else if (diff < -180) {
      diff += 360;
    }
    
    return diff;
  }

  /// N adet heading okuma arasındaki ortalama farkı hesapla
  /// Örnek: getAverageAngularDifference([45, 45.1], [225, 225.1]) ≈ 180
  static double getAverageAngularDifference(
    List<double> headings1,
    List<double> headings2,
  ) {
    if (headings1.isEmpty || headings2.isEmpty) return 0;
    if (headings1.length != headings2.length) return 0;

    double sumDiff = 0;
    for (int i = 0; i < headings1.length; i++) {
      final diff = getAngularDifference(headings1[i], headings2[i]);
      sumDiff += diff;
    }

    return sumDiff / headings1.length;
  }

  /// Heading farkının 180°'ye ne kadar yakın olduğunu kontrol et
  /// 180° ± tolerance aralığında mı?
  static bool isHeading180Degrees(
    double heading1,
    double heading2, {
    required double tolerance,
  }) {
    final diff = getAngularDifference(heading1, heading2);
    final errorMargin = (diff.abs() - 180).abs();
    return errorMargin <= tolerance;
  }

  /// Heading 0-360 aralığına getir (normalize)
  static double wrap360(double heading) => normalizeHeading(heading);

  /// Heading -180 ile +180 aralığına getir
  static double wrap180(double heading) {
    var wrapped = heading % 360;
    if (wrapped > 180) {
      wrapped -= 360;
    }
    if (wrapped < -180) {
      wrapped += 360;
    }
    return wrapped;
  }
}
