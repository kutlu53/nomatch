/// BLE Constants for cross-platform P2P
/// 
/// Service and characteristic UUIDs for NoMatch P2P over BLE
class BleConstants {
  // Service UUID - unique identifier for NoMatch P2P
  static const String serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
  
  // Characteristics
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
  
  // RSSI thresholds for proximity detection
  // RSSI değerleri: 0 dBm (çok yakın) ile -100 dBm (çok uzak) arası
  static const int minRssi = -95;  // ~50m (açık alan)
  static const int maxRssi = -30;  // ~0.5m (çok yakın)
  static const int idealRssi = -70; // ~10m (ideal mesafe)
}
