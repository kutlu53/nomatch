import 'dart:math' as math;
import 'heading_sync.dart';

double normalizeDeg(double deg) {
  var v = deg % 360;
  if (v < 0) v += 360;
  return v;
}

double angleDiffDeg(double a, double b) {
  final na = normalizeDeg(a);
  final nb = normalizeDeg(b);
  var diff = (na - nb).abs();
  if (diff > 180) diff = 360 - diff;
  return diff;
}

/// Public version of opposite angle difference calculation
/// Returns the absolute difference from 180° (perfect opposite)
/// Example: oppositeDiffDeg(0, 180) = 0, oppositeDiffDeg(0, 200) = 20
double oppositeDiffDeg(double heading1, double heading2) {
  double diff = ((heading1 - heading2).abs() - 180).abs();
  if (diff > 180) diff = 360 - diff;
  return diff;
}

/// Pairing phase states (simplified)
enum PairingPhase {
  idle,              // Uygulama açık ama pairing kapalı
  searchingFlat,     // Masada, peer arıyor
  ready,             // Peer bulundu, bağlanabilir!
}

/// Peer information for validation
class PeerInfo {
  final String id;
  final double rssi;        // Signal strength (dBm)
  final bool? isFlat;       // Peer masada mı? (optional, not used in validation)
  final double? heading;    // Peer yönü (0-360°) (optional, not used in validation)
  final double? accelX;
  final double? accelY;
  final double? accelZ;
  final int? lastSeenMs;

  const PeerInfo({
    required this.id,
    required this.rssi,
    this.isFlat,
    this.heading,
    this.accelX,
    this.accelY,
    this.accelZ,
    this.lastSeenMs,
  });
}

/// Simplified pairing validator
/// 
/// - Peer list boş değilse "ready"
/// - "closest peer" seçimi RSSI/first-peer bazlı
/// - Heading/isFlat bekleme yok
/// - ✨ NEW: Advanced heading sync support (kalibrasyon, confidence, validation)
class PairingValidator {
  String? _targetPeerId;
  String? _lastDecisionReason;
  String? get lastDecisionReason => _lastDecisionReason;
  
  // ✨ NEW: Heading sync sistemi
  HeadingSyncCalibration? _calibration;
  HeadingSyncValidator? _validator;
  bool _headingSyncEnabled = false;
  
  /// Heading sync'i etkinleştir
  void enableHeadingSync() {
    _headingSyncEnabled = true;
    _calibration = HeadingSyncCalibration();
    print("✨ Heading sync sistemi etkinleştirildi");
  }
  
  /// Heading sync'i devre dışı bırak
  void disableHeadingSync() {
    _headingSyncEnabled = false;
    _calibration = null;
    _validator = null;
    print("⚙️ Heading sync sistemi devre dışı bırakıldı");
  }
  
  /// Kalibrasyon için heading okuması ekle
  void recordCalibrationReading(double phone1Heading, double phone2Heading) {
    if (!_headingSyncEnabled || _calibration == null) return;
    
    _calibration!.recordCalibrationReading(phone1Heading, phone2Heading);
    final count = _calibration!.getReadingCount();
    print("📊 Kalibrasyon okuması kaydedildi: $count/10");
  }
  
  /// Kalibrasyon analiz et
  bool analyzeHeadingCalibration() {
    if (!_headingSyncEnabled || _calibration == null) return false;
    
    final success = _calibration!.analyzeCalibration(expectedDifference: 180.0);
    
    if (success) {
      // Validator oluştur
      _validator = HeadingSyncValidator(
        calibrationOffset: _calibration!.getCalibrationOffset(),
        tolerance: 30,
      );
      print("✅ Heading sync validator hazır!");
    }
    
    return success;
  }
  
  /// Reel-zamanlı heading senkronizasyon kontrolü
  SyncResult? validateHeadingSync(double phone1Heading, double phone2Heading) {
    if (!_headingSyncEnabled || _validator == null) return null;
    
    return _validator!.validateSync(phone1Heading, phone2Heading);
  }
  
  /// Heading sync kalibrasyonu hazır mı?
  bool isHeadingSyncCalibrated() {
    if (!_headingSyncEnabled || _calibration == null) return false;
    return _calibration!.isCalibrated();
  }
  
  /// Heading sync'i sıfırla (kalibrasyon baştan)
  void resetHeadingSync() {
    if (_calibration != null) {
      _calibration!.reset();
    }
    _validator = null;
    print("🔄 Heading sync sıfırlandı");
  }
  
  /// Check current pairing phase
  /// 
  /// Simplified: peer list boş değilse "ready"
  PairingPhase checkPhase({
    required double accelX,
    required double accelY,
    required double accelZ,
    required double? heading,
    required List<PeerInfo> peers,
  }) {
    // ✅ Basitleştirilmiş: Peer list boş değilse "ready"
    if (peers.isEmpty) {
      _targetPeerId = null;
      _lastDecisionReason = 'no_peers';
      return PairingPhase.searchingFlat;
    }
    
    // ✅ Closest peer seçimi (RSSI/first-peer bazlı)
    final targetPeer = _selectClosestPeer(peers);
    
    if (targetPeer == null) {
      _targetPeerId = null;
      _lastDecisionReason = 'no_target_peer';
      return PairingPhase.searchingFlat;
    }
    
    _targetPeerId = targetPeer.id;
    _lastDecisionReason = 'ready_peer_found';
    return PairingPhase.ready;
  }
  
  /// Select closest peer based on RSSI (signal strength)
  /// 
  /// - RSSI varsa en yüksek RSSI'yi seç
  /// - RSSI eşitse veya yoksa ilk peer'ı seç (first-peer)
  /// - Heading/isFlat kullanılmaz
  PeerInfo? _selectClosestPeer(List<PeerInfo> peers) {
    if (peers.isEmpty) return null;
    
    // RSSI bazlı seçim: en yüksek RSSI'yi seç
    PeerInfo? best;
    for (final peer in peers) {
      if (best == null) {
        best = peer;
      } else if (peer.rssi > best.rssi) {
        best = peer;
      } else if (peer.rssi == best.rssi) {
        // RSSI eşitse peerId lexicographic karşılaştırma (deterministic)
        if (peer.id.compareTo(best.id) < 0) {
          best = peer;
        }
      }
    }
    
    return best;
  }
  
  /// Get current target peer ID (if any)
  String? get targetPeerId => _targetPeerId;
}
