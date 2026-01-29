import 'dart:math' as math;

/// Heading normalizasyonu ve açı hesaplaması
class HeadingNormalizer {
  /// Heading değerini 0-360 aralığına normalize et
  static double normalizeHeading(double heading) {
    var normalized = heading % 360;
    if (normalized < 0) {
      normalized += 360;
    }
    return normalized;
  }

  /// İki açı arasındaki en kısa farkı hesapla (-180 ile +180 arası)
  /// Örnek: getAngularDifference(10, 350) = 20° (350-10 değil, 10'a gitmesi daha yakın)
  static double getAngularDifference(double angle1, double angle2) {
    var diff = normalizeHeading(angle1 - angle2);

    // En kısa yolu seç
    if (diff > 180) {
      diff -= 360;
    }

    return diff;
  }

  /// Heading değerlerinin ortalama farkını hesapla (kalibrasyon için)
  /// Her iki listede aynı sayıda okuma olmalı
  static double getAverageAngularDifference(
      List<double> readings1, List<double> readings2) {
    if (readings1.length != readings2.length || readings1.isEmpty) {
      throw Exception("Okuma sayıları eşit olmalı");
    }

    double sumDiff = 0;
    for (int i = 0; i < readings1.length; i++) {
      sumDiff += getAngularDifference(readings1[i], readings2[i]);
    }

    return sumDiff / readings1.length;
  }
}

/// Kalibrasyon sistemi - İki telefon heading'ini senkronize etmek için
class HeadingSyncCalibration {
  final List<double> _phone1Readings = [];
  final List<double> _phone2Readings = [];
  late double _calibrationOffset;
  bool _isCalibrated = false;

  /// Kalibrasyon için okuma kaydet (en az 5, ideal 10+ okuma)
  void recordCalibrationReading(double phone1Heading, double phone2Heading) {
    _phone1Readings.add(phone1Heading);
    _phone2Readings.add(phone2Heading);
  }

  /// Kalibrasyon verilerini analiz et
  bool analyzeCalibration({required double expectedDifference}) {
    if (_phone1Readings.length < 5) {
      print("❌ Kalibrasyon için en az 5 okuma gerekli (şu an: ${_phone1Readings.length})");
      return false;
    }

    // Ortalama farkı hesapla
    _calibrationOffset =
        HeadingNormalizer.getAverageAngularDifference(
            _phone1Readings, _phone2Readings);

    // Tolerans kontrolü
    double tolerance = 30;
    double diff = HeadingNormalizer.getAngularDifference(
        _calibrationOffset, expectedDifference);

    if (diff.abs() > tolerance) {
      print("❌ Kalibrasyon başarısız!");
      print("   Beklenen: ${expectedDifference.toStringAsFixed(2)}°");
      print("   Ölçülen: ${_calibrationOffset.toStringAsFixed(2)}°");
      print("   Fark: ${diff.abs().toStringAsFixed(2)}° (Tolerans: ±$tolerance°)");
      return false;
    }

    _isCalibrated = true;
    print("✅ Kalibrasyon başarılı!");
    print("   Offset: ${_calibrationOffset.toStringAsFixed(2)}°");
    return true;
  }

  /// Kalibrasyon sonucunu al
  double getCalibrationOffset() => _calibrationOffset;

  bool isCalibrated() => _isCalibrated;

  /// Kalibrasyon verilerini sıfırla
  void reset() {
    _phone1Readings.clear();
    _phone2Readings.clear();
    _isCalibrated = false;
  }

  /// Toplanmış okuma sayısı
  int getReadingCount() => _phone1Readings.length;
}

/// Reel-zamanlı senkronizasyon kontrolü
class HeadingSyncValidator {
  final double calibrationOffset;
  final double tolerance;

  HeadingSyncValidator({
    required this.calibrationOffset,
    this.tolerance = 30,
  });

  /// İki telefon senkron mu kontrol et
  SyncResult validateSync(double phone1Heading, double phone2Heading) {
    // Heading'leri normalize et
    var normalized1 = HeadingNormalizer.normalizeHeading(phone1Heading);
    var normalized2 = HeadingNormalizer.normalizeHeading(phone2Heading);

    // Kalibrasyonu uygula
    var adjustedPhone2 = HeadingNormalizer.normalizeHeading(
        normalized2 + calibrationOffset);

    // Fark hesapla
    var actualDifference =
        HeadingNormalizer.getAngularDifference(normalized1, adjustedPhone2);

    // Teorik fark: 180° (baş kısımlar karşı karşıya)
    double expectedDifference = 180;
    double errorMargin =
        HeadingNormalizer.getAngularDifference(actualDifference, expectedDifference);

    bool isSynced = errorMargin.abs() <= tolerance;

    return SyncResult(
      isSynced: isSynced,
      phone1Heading: normalized1,
      phone2Heading: normalized2,
      adjustedPhone2Heading: adjustedPhone2,
      actualDifference: actualDifference,
      expectedDifference: expectedDifference,
      errorMargin: errorMargin,
      confidence: _calculateConfidence(errorMargin),
    );
  }

  double _calculateConfidence(double errorMargin) {
    // 0°: 100% güven, tolerance: 0% güven
    return math.max(0, 1 - (errorMargin.abs() / tolerance));
  }
}

/// Senkronizasyon kontrol sonucu
class SyncResult {
  final bool isSynced;
  final double phone1Heading;
  final double phone2Heading;
  final double adjustedPhone2Heading;
  final double actualDifference;
  final double expectedDifference;
  final double errorMargin;
  final double confidence;

  SyncResult({
    required this.isSynced,
    required this.phone1Heading,
    required this.phone2Heading,
    required this.adjustedPhone2Heading,
    required this.actualDifference,
    required this.expectedDifference,
    required this.errorMargin,
    required this.confidence,
  });

  @override
  String toString() {
    return '''
═══════════════════════════════════════
📱 HEADING SİNKRON KONTROLü
═══════════════════════════════════════
Telefon 1: ${phone1Heading.toStringAsFixed(2)}°
Telefon 2: ${phone2Heading.toStringAsFixed(2)}° → Ayarlanmış: ${adjustedPhone2Heading.toStringAsFixed(2)}°

Beklenen fark: ${expectedDifference.toStringAsFixed(2)}°
Ölçülen fark: ${actualDifference.toStringAsFixed(2)}°
Hata payı: ${errorMargin.abs().toStringAsFixed(2)}°

${isSynced ? '✅ SİNKRENİZE OLMUŞ' : '❌ SİNKRENİZE DEĞİL'}
Güven seviyesi: ${(confidence * 100).toStringAsFixed(1)}%
═══════════════════════════════════════
''';
  }
}
