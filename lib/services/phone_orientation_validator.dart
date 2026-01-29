import '../models/heading_models.dart';

/// Telefon başının yönünü tespit et ve kontrol et
class PhoneOrientationValidator {
  /// Accelerometer verilerinden telefon başının yönünü tespit et
  static PhoneOrientationValidationResult detectHeadOrientation(
    double accelX,
    double accelY,
    double accelZ,
  ) {
    final isLevel = accelX.abs() < 3.0 && accelY.abs() < 3.0;

    HeadOrientation orientation;

    if (!isLevel) {
      orientation = HeadOrientation.TILTED;
    } else if (accelZ > HeadingSyncConstants.HEAD_UP_THRESHOLD) {
      orientation = HeadOrientation.HEAD_UP;
    } else if (accelZ < HeadingSyncConstants.HEAD_DOWN_THRESHOLD) {
      orientation = HeadOrientation.HEAD_DOWN;
    } else if (accelX.abs() > 3.0 || accelY.abs() > 3.0) {
      orientation = HeadOrientation.SIDEWAYS;
    } else {
      orientation = HeadOrientation.UNKNOWN;
    }

    return PhoneOrientationValidationResult(
      orientation: orientation,
      isLevel: isLevel,
      zValue: accelZ,
    );
  }

  /// İki telefon başının zıt yönde olup olmadığını kontrol et
  /// HEAD_UP vs HEAD_DOWN = true
  /// Diğer kombinasyonlar = false
  static bool isHeadOrientationOpposite(
    HeadOrientation ori1,
    HeadOrientation ori2,
  ) {
    return (ori1 == HeadOrientation.HEAD_UP &&
            ori2 == HeadOrientation.HEAD_DOWN) ||
        (ori1 == HeadOrientation.HEAD_DOWN &&
            ori2 == HeadOrientation.HEAD_UP);
  }

  /// Z-axis değerlerinin uyumlu olup olmadığını kontrol et
  /// |z1| ≈ |z2| (fark < tolerance)?
  static bool isZAxisValid(
    double z1,
    double z2, {
    required double tolerance,
  }) {
    final z1Abs = z1.abs();
    final z2Abs = z2.abs();
    final diff = (z1Abs - z2Abs).abs();
    return diff < tolerance;
  }

  /// Her iki telefon da level (düz) mi?
  static bool areBothLevel(
    AccelerometerReading accel1,
    AccelerometerReading accel2,
  ) {
    return accel1.isLevel && accel2.isLevel;
  }

  /// Z-axis değerleri zıt işaretli ve uyumlu mu?
  /// (One positive > 7, one negative < -7)?
  static bool areZAxisOpposite(
    double z1,
    double z2, {
    required double tolerance,
  }) {
    final z1Positive = z1 > HeadingSyncConstants.HEAD_UP_THRESHOLD;
    final z1Negative = z1 < HeadingSyncConstants.HEAD_DOWN_THRESHOLD;
    final z2Positive = z2 > HeadingSyncConstants.HEAD_UP_THRESHOLD;
    final z2Negative = z2 < HeadingSyncConstants.HEAD_DOWN_THRESHOLD;

    final opposite = (z1Positive && z2Negative) || (z1Negative && z2Positive);
    final compatible = isZAxisValid(z1, z2, tolerance: tolerance);

    return opposite && compatible;
  }
}
