import Foundation
import CoreBluetooth

class BLEAdvertisingManager: NSObject, CBPeripheralManagerDelegate {
  private var peripheralManager: CBPeripheralManager?
  private var nomatchService: CBMutableService?
  private var serviceAddedSemaphore: DispatchSemaphore?
  var onCharacteristicWrite: ((_ data: Data) -> Void)?  // Callback for write events
  // ✅ FIX: Peripheral manager hazır olmadan gelen advertise isteği bekletilir
  // ve poweredOn olunca otomatik başlatılır. Eskiden istek sessizce düşüyordu:
  // soğuk açılışta hemen taramaya basan telefon karşı tarafça hiç görülmüyordu.
  private var pendingAdvertise: (serviceUuid: String, deviceName: String)?
  
  // Nomatch-specific UUIDs (must match Dart side)
  static let NOMATCH_SERVICE_UUID = CBUUID(string: "550e8400-e29b-41d4-a716-446655440000")
  static let NOMATCH_CHAR_TX_RX = CBUUID(string: "550e8400-e29b-41d4-a716-446655440001")
  static let NOMATCH_CHAR_CONTROL = CBUUID(string: "550e8400-e29b-41d4-a716-446655440002")
  
  override init() {
    super.init()
    peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
  }
  
  func startAdvertising(serviceUuid: String, deviceName: String, completion: @escaping (Error?) -> Void) {
    print("[BLE-ADV] 🚀 Starting BLE advertising")
    print("[BLE-ADV]   Service UUID: \(serviceUuid)")
    print("[BLE-ADV]   Device Name: \(deviceName)")
    
    guard let peripheral = peripheralManager, peripheral.state == .poweredOn else {
      // ✅ FIX: Henüz hazır değil (soğuk açılış / BT kapalı). İsteği beklet;
      // poweredOn gelince peripheralManagerDidUpdateState otomatik başlatır.
      print("[BLE-ADV] ⏳ Peripheral manager not ready - advertise request queued")
      pendingAdvertise = (serviceUuid: serviceUuid, deviceName: deviceName)
      completion(nil)
      return
    }
    
    // Check if service already exists (don't create duplicates)
    if nomatchService != nil {
      print("[BLE-ADV] ℹ️ Nomatch service already exists - not creating duplicate")
      // Just update device name and start advertising again
      let advertisingData: [String: Any] = [
        CBAdvertisementDataServiceUUIDsKey: [BLEAdvertisingManager.NOMATCH_SERVICE_UUID],
        CBAdvertisementDataLocalNameKey: deviceName
      ]
      
      peripheral.startAdvertising(advertisingData)
      print("[BLE-ADV] ✅ Advertising started with existing service")
      print("[BLE-ADV]   └─ Device name: \(deviceName)")
      completion(nil)
      return
    }
    
    // Create Nomatch service with custom UUIDs
    let txRxChar = CBMutableCharacteristic(
      type: BLEAdvertisingManager.NOMATCH_CHAR_TX_RX,
      properties: [.read, .write, .notify],
      value: nil,
      permissions: [.readable, .writeable]
    )
    
    let controlChar = CBMutableCharacteristic(
      type: BLEAdvertisingManager.NOMATCH_CHAR_CONTROL,
      properties: [.read, .write],
      value: nil,
      permissions: [.readable, .writeable]
    )
    
    let service = CBMutableService(type: BLEAdvertisingManager.NOMATCH_SERVICE_UUID, primary: true)
    service.characteristics = [txRxChar, controlChar]
    
    // Create semaphore to wait for service to be added
    serviceAddedSemaphore = DispatchSemaphore(value: 0)
    
    // Add service to peripheral
    peripheral.add(service)
    nomatchService = service
    
    print("[BLE-ADV] ✅ Nomatch service created with UUID: \(BLEAdvertisingManager.NOMATCH_SERVICE_UUID)")
    print("[BLE-ADV]   └─ Characteristic 1: \(BLEAdvertisingManager.NOMATCH_CHAR_TX_RX)")
    print("[BLE-ADV]   └─ Characteristic 2: \(BLEAdvertisingManager.NOMATCH_CHAR_CONTROL)")
    
    // Start advertising after service is confirmed added
    DispatchQueue.global().async { [weak self] in
      // Wait for service to be added (max 5 seconds)
      let result = self?.serviceAddedSemaphore?.wait(timeout: .now() + 5.0)
      
      DispatchQueue.main.async {
        let advertisingData: [String: Any] = [
          CBAdvertisementDataServiceUUIDsKey: [BLEAdvertisingManager.NOMATCH_SERVICE_UUID],
          CBAdvertisementDataLocalNameKey: deviceName
        ]
        
        peripheral.startAdvertising(advertisingData)
        print("[BLE-ADV] ✅ Advertising started successfully!")
        print("[BLE-ADV]   └─ Device name: \(deviceName)")
        print("[BLE-ADV]   └─ Advertising data keys: \(advertisingData.keys.joined(separator: ", "))")
        
        completion(nil)
      }
    }
  }
  
  func stopAdvertising(completion: @escaping (Error?) -> Void) {
    print("[BLE-ADV] 🛑 Stopping BLE advertising")
    
    guard let peripheral = peripheralManager else {
      completion(NSError(domain: "BLE", code: -1, userInfo: nil))
      return
    }
    
    peripheral.stopAdvertising()
    // ✅ FIX: Durdurma isteği bekleyen yayını da iptal etmeli.
    pendingAdvertise = nil
    print("[BLE-ADV] ✅ Advertising stopped")

    completion(nil)
  }
  
  // MARK: - CBPeripheralManagerDelegate
  
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    switch peripheral.state {
    case .poweredOn:
      print("[BLE-ADV] ✅ Bluetooth is powered ON")
      // ✅ FIX: Hazır olmadan gelen advertise isteğini şimdi başlat.
      if let pending = pendingAdvertise {
        pendingAdvertise = nil
        print("[BLE-ADV] 🔁 Starting queued advertise request")
        startAdvertising(serviceUuid: pending.serviceUuid, deviceName: pending.deviceName) { error in
          if let error = error {
            print("[BLE-ADV] ❌ Queued advertise failed: \(error.localizedDescription)")
          }
        }
      }
    case .poweredOff:
      print("[BLE-ADV] ❌ Bluetooth is powered OFF")
    case .resetting:
      print("[BLE-ADV] ⚠️ Bluetooth is resetting")
    case .unauthorized:
      print("[BLE-ADV] ❌ Bluetooth access unauthorized")
    case .unsupported:
      print("[BLE-ADV] ❌ Bluetooth not supported")
    default:
      print("[BLE-ADV] ❓ Bluetooth state unknown")
    }
  }
  
  func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
    if let error = error {
      print("[BLE-ADV] ❌ Failed to add service: \(error.localizedDescription)")
    } else {
      print("[BLE-ADV] ✅ Service added successfully: \(service.uuid)")
      // Signal that service has been added
      if service.uuid == BLEAdvertisingManager.NOMATCH_SERVICE_UUID {
        print("[BLE-ADV] 🔔 Nomatch service confirmed added - signaling semaphore")
        serviceAddedSemaphore?.signal()
      }
    }
  }
  
  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didReceiveRead request: CBATTRequest
  ) {
    print("[BLE-ADV] 📖 Received read request for: \(request.characteristic.uuid)")
    peripheral.respond(to: request, withResult: .success)
  }
  
  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didReceiveWrite requests: [CBATTRequest]
  ) {
    for request in requests {
      print("[BLE-ADV] ✍️ Received write request for: \(request.characteristic.uuid)")
      print("[BLE-ADV]   └─ Data size: \(request.value?.count ?? 0) bytes")
      
      // Respond to client
      peripheral.respond(to: request, withResult: .success)
      
      // Forward data to Dart if callback is set
      if let data = request.value {
        if request.characteristic.uuid == BLEAdvertisingManager.NOMATCH_CHAR_TX_RX {
          print("[BLE-ADV] ✅ Message characteristic write - forwarding to Dart")
          print("[BLE-ADV]   └─ Callback set: \(onCharacteristicWrite != nil)")
          onCharacteristicWrite?(data)
        } else {
          print("[BLE-ADV] ⚠️ Write to different characteristic: \(request.characteristic.uuid)")
        }
      }
    }
  }
}
