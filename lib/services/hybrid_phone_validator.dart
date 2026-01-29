import '../models/heading_models.dart';
import 'heading_normalizer.dart';
import 'phone_orientation_validator.dart';

/// Hibrit Validator: Heading + Accelerometre + Z-Axis + Orientation
/// 4 kontrol kategorisinde 3 PASS gerekli
class HybridPhoneValidator {
  final List<double> _headingHistory = [];
  int _failureCount = 0;

  /// Reel-zamanlı senkronizasyon kontrolü
  /// score = 0-4 puan
  /// confidence = score / 4 (0.0 - 1.0)
  /// isSynced = score >= 3
  SyncResult validatePhoneOrientation({
    required double heading1,
    required double heading2,
    required AccelerometerReading accel1,
    required AccelerometerReading accel2,
    double calibrationOffset = 0.0,
  }) {
    int scorePoints = 0;
    final statusList = <String>[];

    // ===== CHECK 1: HEADING VALIDATION =====
    final h2Adjusted = HeadingNormalizer.normalizeHeading(heading2 + calibrationOffset);
    final headingDiff = HeadingNormalizer.getAngularDifference(heading1, h2Adjusted);
    final headingErrorMargin = (headingDiff.abs() - 180).abs();
    final headingValid = headingErrorMargin <= HeadingSyncConstants.HEADING_TOLERANCE;

    if (headingValid) {
      scorePoints += 1;
      statusList.add('✅ HEADING');
    } else {
      statusList.add('❌ HEADING (diff=${headingDiff.toStringAsFixed(1)}°)');
    }

    // ===== CHECK 2: PHONE ORIENTATION (Accel) =====
    final ori1 = PhoneOrientationValidator.detectHeadOrientation(
      accel1.x,
      accel1.y,
      accel1.z,
    );
    final ori2 = PhoneOrientationValidator.detectHeadOrientation(
      accel2.x,
      accel2.y,
      accel2.z,
    );
    final accelValid = PhoneOrientationValidator.isHeadOrientationOpposite(ori1, ori2);

    if (accelValid) {
      scorePoints += 1;
      statusList.add('✅ ORIENTATION (${ori1.label} vs ${ori2.label})');
    } else {
      statusList.add('❌ ORIENTATION (${ori1.label} vs ${ori2.label})');
    }

    // ===== CHECK 3: Z-AXIS VALIDATION =====
    final zAxisValid = PhoneOrientationValidator.areZAxisOpposite(
      accel1.z,
      accel2.z,
      tolerance: HeadingSyncConstants.Z_AXIS_TOLERANCE,
    );

    if (zAxisValid) {
      scorePoints += 1;
      statusList.add('✅ Z-AXIS (${accel1.z.toStringAsFixed(1)} vs ${accel2.z.toStringAsFixed(1)})');
    } else {
      statusList.add('❌ Z-AXIS');
    }

    // ===== CHECK 4: LEVEL VALIDATION =====
    final levelValid = PhoneOrientationValidator.areBothLevel(accel1, accel2);

    if (levelValid) {
      scorePoints += 1;
      statusList.add('✅ LEVEL');
    } else {
      statusList.add('❌ LEVEL');
    }

    // ===== FINAL DECISION =====
    final isSynced = scorePoints >= HeadingSyncConstants.MIN_SCORE_POINTS;
    final confidence = scorePoints / 4.0;

    // Anomaly detection
    _headingHistory.add(heading1);
    if (_headingHistory.length > HeadingSyncConstants.MOVING_AVERAGE_WINDOW) {
      _headingHistory.removeAt(0);
    }

    // Track failures
    if (isSynced) {
      _failureCount = 0;
    } else {
      _failureCount += 1;
    }

    return SyncResult(
      isSynced: isSynced && _failureCount < HeadingSyncConstants.FAILURE_THRESHOLD,
      confidence: confidence,
      scorePoints: scorePoints,
      headingStatus: statusList.where((s) => s.contains('HEADING')).first,
      accelStatus: statusList.where((s) => s.contains('ORIENTATION')).first,
      zAxisStatus: statusList.where((s) => s.contains('Z-AXIS')).first,
      levelStatus: statusList.where((s) => s.contains('LEVEL')).first,
      orientationStatus: 'MultiCheck',
    );
  }

  /// Başarısızlık sayacını sıfırla
  void resetFailureCount() => _failureCount = 0;

  /// Geçerli başarısızlık sayısı
  int get failureCount => _failureCount;

  /// Geçerli başarısızlık eşiğine kaç başarısızlık kaldı?
  int get failuresBeforeDisconnect =>
      HeadingSyncConstants.FAILURE_THRESHOLD - _failureCount;
}
