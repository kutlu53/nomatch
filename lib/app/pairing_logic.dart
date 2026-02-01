import 'dart:async';

/// Pairing state machine
enum PairingState {
  idle,           // Başlangıç
  hostingReady,   // isFlat=true, hosting aktif
  peerSearching,  // Peer arıyor
  preConnected,   // BLE bağlandı, heading kontrol bekleniyor
  headingValidating, // Heading kontrol devam ediyor
  connected,      // Heading geçti, leader belirleniyor
  game,           // Oyun ekranına geç
  gameReady,      // Oyun başlamaya hazır
  playing,        // Oyun içinde
  failed,         // Hata
}

class PairingResult {
  final bool success;
  final String? peerId;
  final String? sessionId;
  final bool isLeader;
  final String? errorReason;

  PairingResult({
    required this.success,
    this.peerId,
    this.sessionId,
    this.isLeader = false,
    this.errorReason,
  });
}

class HeadingValidation {
  /// Target heading difference for face-to-face validation
  /// 180° = Telefon BAŞLARI (kamera tarafı) karşı karşıya
  /// 0°   = Telefon ŞARJ PORTLARI karşı karşıya
  static const double targetHeading = 180.0; // Baş kısımlar karşı karşıya
  static const double tolerance = 30.0;       // ±30° tolerans (production)
  
  static const double magnetometerOffset = 0.0; // (legacy - kept for compatibility)

  /// Check if two headings are facing each other (180° ±30°)
  static bool isFacingEachOther(double heading1, double heading2) {
    // Apply magnetometer offset to both headings
    final adjustedHeading1 = (heading1 + magnetometerOffset) % 360;
    final adjustedHeading2 = (heading2 + magnetometerOffset) % 360;
    
    final diff = (adjustedHeading1 - adjustedHeading2).abs();
    // Normalize to 0-180
    final normalized = diff > 180 ? 360 - diff : diff;
    // Check if close to 180°
    return (normalized >= targetHeading - tolerance) && 
           (normalized <= targetHeading + tolerance);
  }

  /// Get angle difference
  static double getAngleDifference(double heading1, double heading2) {
    final diff = (heading1 - heading2).abs();
    return diff > 180 ? 360 - diff : diff;
  }
}

class LeaderAlgorithm {
  /// Select leader based on device ID (lexicographic comparison)
  static bool selectLeader(String deviceId1, String deviceId2) {
    // deviceId1 < deviceId2 => deviceId1 is leader
    return deviceId1.compareTo(deviceId2) < 0;
  }

  /// Generate session ID from both device IDs and timestamp
  static String generateSessionId(String leaderId, String followerId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${leaderId.substring(0, 8)}_${followerId.substring(0, 8)}_$timestamp';
  }
}
