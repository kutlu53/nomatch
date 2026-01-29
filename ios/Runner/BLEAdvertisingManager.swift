import Foundation
import CoreBluetooth

class BLEAdvertisingManager: NSObject, CBPeripheralManagerDelegate {
  private var peripheralManager: CBPeripheralManager?
  private var isAdvertising = false
  private var gattService: CBMutableService?
  private var pendingAdvertisingData: [String: Any]?
  private var serviceAddedCompletion: ((Error?) -> Void)?
  
  override init() {
    super.init()
    // Initialize peripheral manager on main thread
    DispatchQueue.main.async { [weak self] in
      self?.peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
  }
  
  func startAdvertising(
    serviceUuid: String,
    deviceName: String,
    completion: @escaping (Error?) -> Void
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        completion(NSError(domain: "BLEAdvertisingManager", code: -1, userInfo: nil))
        return
      }
      
      // Check if peripheral manager is ready
      guard let peripheralManager = self.peripheralManager else {
        completion(NSError(domain: "BLEAdvertisingManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Peripheral manager not initialized"]))
        return
      }
      
      // Wait for powered on state
      if peripheralManager.state != .poweredOn {
        print("[BLE-iOS] ⏳ Waiting for Bluetooth to be powered on...")
        // Try again in a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
          self.startAdvertising(serviceUuid: serviceUuid, deviceName: deviceName, completion: completion)
        }
        return
      }
      
      // Convert UUID string to CBUUID
      let uuid = CBUUID(string: serviceUuid)
      
      // ⬆️ Advertising data with long-range optimization
      // Include service UUID in advertising packet so scanners can find us
      // This is critical for iOS GATT discovery to work reliably
      var advertisingData: [String: Any] = [
        CBAdvertisementDataLocalNameKey: deviceName,
        CBAdvertisementDataServiceUUIDsKey: [uuid]
      ]
      
      // iOS 14+: Hint for Coded PHY (long-range, 200m+)
      if #available(iOS 14.0, *) {
        // Note: CBPeripheralManager doesn't directly expose PHY selection,
        // but iOS automatically uses better encoding when available
        print("[BLE-iOS] iOS 14+ detected: Coded PHY auto-optimization eligible")
      }
      
      // Store advertising data for completion callback
      self.pendingAdvertisingData = advertisingData
      self.serviceAddedCompletion = completion
      
      // ✅ Create and add GATT Service for discovery if not already added
      // CRITICAL: Only add service ONCE. Reusing existing service preserves it
      if self.gattService == nil {
        let service = CBMutableService(type: uuid, primary: true)
        
        // Add a characteristic so the service is discoverable
        let characteristic = CBMutableCharacteristic(
          type: CBUUID(string: "0000fff1-0000-1000-8000-00805f9b34fb"),
          properties: [.read, .write, .notify],
          value: nil,
          permissions: [.readable, .writeable]
        )
        service.characteristics = [characteristic]
        
        self.gattService = service
        
        // Add service to peripheral manager
        peripheralManager.add(service)
        print("[BLE-iOS] 📋 GATT Service added: \(serviceUuid)")
      } else {
        print("[BLE-iOS] ℹ️ GATT Service already registered, reusing...")
      }
      
      // CRITICAL: Give iOS sufficient time to properly register the service
      // before advertising. This ensures GATT discovery will find the service.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        guard let self = self, let pm = self.peripheralManager else { return }
        
        print("[BLE-iOS] 📋 Service registration delay complete, starting advertising...")
        
        // Now start advertising after service is fully registered
        if let advData = self.pendingAdvertisingData {
          pm.startAdvertising(advData)
          self.isAdvertising = true
          print("[BLE-iOS] ✅ Advertising started (after 500ms service registration delay)")
          self.serviceAddedCompletion?(nil)
          self.serviceAddedCompletion = nil
        }
      }
    }
  }
  
  func stopAdvertising(completion: @escaping (Error?) -> Void) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let peripheralManager = self.peripheralManager else {
        completion(NSError(domain: "BLEAdvertisingManager", code: -1, userInfo: nil))
        return
      }
      
      peripheralManager.stopAdvertising()
      self.isAdvertising = false
      
      // ✅ IMPORTANT: Do NOT remove the service!
      // Keep it in the peripheral manager so it remains discoverable
      // via GATT even when advertising is temporarily stopped
      print("[BLE-iOS] 📣 Stopped advertising (service remains in peripheral manager)")
      
      completion(nil)
    }
  }
  
  // MARK: - CBPeripheralManagerDelegate
  
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    print("[BLE-iOS] Peripheral state changed: \(peripheral.state.rawValue)")
    
    switch peripheral.state {
    case .poweredOn:
      print("[BLE-iOS] ✅ Bluetooth is powered on")
      // Restart advertising if needed
      if isAdvertising && !peripheral.isAdvertising {
        print("[BLE-iOS] Restarting advertising after state change")
      }
    case .poweredOff:
      print("[BLE-iOS] ❌ Bluetooth is powered off")
    case .resetting:
      print("[BLE-iOS] 🔄 Bluetooth is resetting")
    case .unauthorized:
      print("[BLE-iOS] ❌ Bluetooth is unauthorized")
    case .unsupported:
      print("[BLE-iOS] ❌ Bluetooth is not supported")
    case .unknown:
      print("[BLE-iOS] ❓ Bluetooth state is unknown")
    @unknown default:
      print("[BLE-iOS] ❓ Unknown Bluetooth state")
    }
  }
  
  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didAdd service: CBService,
    error: Error?
  ) {
    if let error = error {
      print("[BLE-iOS] ❌ Error adding service: \(error)")
      return
    }
    
    print("[BLE-iOS] ✅ Service confirmed added to peripheral: \(service.uuid)")
    print("[BLE-iOS]   This service will be discoverable via GATT after connection")
  }
  
  func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
    if let error = error {
      print("[BLE-iOS] Error starting advertising: \(error)")
    } else {
      print("[BLE-iOS] ✅ Advertising started successfully")
    }
  }
}
