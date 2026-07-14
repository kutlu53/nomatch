/// BLE Constants for cross-platform P2P
/// 
/// Service and characteristic UUIDs for NoMatch P2P over BLE
class BleConstants {
  // ✅ NOMATCH CUSTOM UUIDs (must match iOS BLEAdvertisingManager.swift)
  static const String nomatchServiceUUID = '550e8400-e29b-41d4-a716-446655440000';
  static const String nomatchCharTxRx = '550e8400-e29b-41d4-a716-446655440001';
  static const String nomatchCharControl = '550e8400-e29b-41d4-a716-446655440002';
  
  // Legacy Service UUID - unique identifier for NoMatch P2P over BLE
  static const String serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
  
  // Legacy Characteristics
  static const String discoveryCharUuid = '0000fff1-0000-1000-8000-00805f9b34fb';
  static const String messageCharUuid = '0000fff2-0000-1000-8000-00805f9b34fb';
  static const String sensorCharUuid = '0000fff3-0000-1000-8000-00805f9b34fb';
  
  // Advertisement data keys
  static const String advDeviceIdKey = 'deviceId';
  static const String advSessionIdKey = 'sessionId';
  
  // MTU size for BLE (maximum transmission unit)
  static const int mtuSize = 512;
  
  // Scan/advertise timeouts
  static const Duration scanTimeout = Duration(seconds: 30);
  static const Duration advertiseTimeout = Duration(minutes: 5);
  
  // Connection parameters
  // Increased from 10s to 20s to allow GATT service discovery to complete
  // (discovery can take up to ~10-12 seconds on iOS simulators)
  static const Duration connectionTimeout = Duration(seconds: 20);
  static const Duration reconnectDelay = Duration(seconds: 2);
  
  // RSSI alt sınırı — radar modu farklı masalardaki yabancıların uzak
  // mesafeden eşleşmesi için tasarlandı, menzil olabildiğince geniş tutulur.
  // -100 dBm pratikte gürültü tabanı: radyonun duyabildiği her cihaz geçer.
  static const int minRssi = -100;
}
