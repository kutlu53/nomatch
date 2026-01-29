import '../models/heading_models.dart';
import 'heading_normalizer.dart';

/// Heading kalibrasyonu - Offset öğrenme sistemi
class HeadingSyncCalibration {
  final List<double> _phone1Readings = [];
  final List<double> _phone2Readings = [];
  double? _calibrationOffset;

  /// Okuma ekle (her iki telefonda)
  void recordCalibrationReading(double heading1, double heading2) {
    _phone1Readings.add(heading1);
    _phone2Readings.add(heading2);
  }

  /// Kalibrasyonu analiz et
  /// expectedDifference: Beklenen heading farkı (genelde 180°)
  bool analyzeCalibration(double expectedDifference) {
    const minReadings = 5;

    if (_phone1Readings.length < minReadings ||
        _phone2Readings.length < minReadings) {
      return false;
    }

    // Ortalama fark hesapla
    final avgDiff =
        HeadingNormalizer.getAverageAngularDifference(
      _phone1Readings,
      _phone2Readings,
    );

    // Kontrol: beklenen farktan ±30°?
    final errorMargin = (avgDiff.abs() - expectedDifference.abs()).abs();
    if (errorMargin > HeadingSyncConstants.HEADING_TOLERANCE) {
      return false;
    }

    _calibrationOffset = avgDiff;
    return true;
  }

  /// Kalibrasyon offset'ini al
  double? getCalibrationOffset() => _calibrationOffset;

  /// Kalibrasyon sıfırla
  void reset() {
    _phone1Readings.clear();
    _phone2Readings.clear();
    _calibrationOffset = null;
  }

  /// Kaç okuma yapıldığını al
  int get readingCount => _phone1Readings.length;

  /// Kalibrasyon yapılmış mı?
  bool get isCalibrated => _calibrationOffset != null;

  @override
  String toString() =>
      'HeadingSyncCalibration(readings=$readingCount, offset=$_calibrationOffset)';
}
