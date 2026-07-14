import Flutter
import UIKit
import CoreBluetooth
import CoreMotion

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var bleAdvertisingManager: BLEAdvertisingManager?
  private let motionManager = CMMotionManager()
  private var orientationFusionManager: OrientationFusionManager?
  private var orientationVectorManager: OrientationVectorManager?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Setup BLE advertising method channel
    let controller = window?.rootViewController as! FlutterViewController
    let bleChannel = FlutterMethodChannel(
      name: "com.nomatch/ble_advertising",
      binaryMessenger: controller.binaryMessenger
    )
    
    // ✅ NEW: Setup magnetometer calibration check channel
    let magnetometerChannel = FlutterMethodChannel(
      name: "com.nomatch/magnetometer",
      binaryMessenger: controller.binaryMessenger
    )
    
    // ✅ NEW: Setup orientation fusion channel (tilt-compensated yaw)
    let orientationChannel = FlutterMethodChannel(
      name: "com.nomatch/orientation_fusion",
      binaryMessenger: controller.binaryMessenger
    )
    
    // ✅ NEW: Setup orientation vector event channel (for face-to-face detection)
    let orientationVectorEventChannel = FlutterEventChannel(
      name: "com.nomatch/orientation_vector",
      binaryMessenger: controller.binaryMessenger
    )
    
    // ✅ NEW: Setup compass channel (real heading from magnetometer)
    let compassChannel = FlutterMethodChannel(
      name: "com.nomatch/compass",
      binaryMessenger: controller.binaryMessenger
    )
    
    bleAdvertisingManager = BLEAdvertisingManager()
    
    // ✅ Setup BLE peripheral write reception channel
    let blePeripheralChannel = FlutterMethodChannel(
      name: "com.nomatch/ble_peripheral_writes",
      binaryMessenger: controller.binaryMessenger
    )
    
    // ✅ NEW: Initialize orientation vector manager
    orientationVectorManager = OrientationVectorManager()
    orientationVectorManager?.initializeWithChannel(orientationVectorEventChannel)
    
    // ✅ NEW: Magnetometer calibration check handler
    magnetometerChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "checkMagnetometerAccuracy":
        let accuracy = Int(self?.motionManager.deviceMotion?.magneticField.accuracy.rawValue ?? -1)
        print("[MAGN-iOS] 🧲 Magnetometer accuracy check: \(accuracy)")
        
        // CMCalibratedMagneticField.Accuracy rawValues:
        // -1 = Uncalibrated, 0 = Low, 1 = Medium, 2 = High
        let isCalibrated = accuracy >= 0
        result([
          "isCalibrated": isCalibrated,
          "accuracy": accuracy,
          "accuracyLabel": self?._getAccuracyLabel(accuracy) ?? "Unknown"
        ])
        
      case "startMagnetometerUpdates":
        self?.motionManager.deviceMotionUpdateInterval = 0.1
        if self?.motionManager.isDeviceMotionAvailable ?? false {
          self?.motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
          print("[MAGN-iOS] ✅ Started magnetometer updates")
          result(true)
        } else {
          print("[MAGN-iOS] ❌ Magnetometer not available")
          result(false)
        }
        
      case "stopMagnetometerUpdates":
        self?.motionManager.stopDeviceMotionUpdates()
        print("[MAGN-iOS] ✅ Stopped magnetometer updates")
        result(nil)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    // ✅ NEW: Orientation fusion handler
    orientationChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "startOrientationFusion":
        let eventChannelName = call.arguments as? String ?? "com.nomatch/orientation_samples"
        let eventChannel = FlutterEventChannel(
          name: eventChannelName,
          binaryMessenger: controller.binaryMessenger
        )
        
        let fusionManager = OrientationFusionManager()
        self?.orientationFusionManager = fusionManager
        
        let streamHandler = OrientationStreamHandler(fusionManager: fusionManager)
        eventChannel.setStreamHandler(streamHandler)
        
        print("[ORIENT-iOS] ✅ Orientation fusion event channel configured")
        result(nil)
        
      case "stopOrientationFusion":
        self?.orientationFusionManager?.stop()
        print("[ORIENT-iOS] ✅ Orientation fusion stopped")
        result(nil)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    // ✅ NEW: Compass handler (real heading from magnetometer)
    compassChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "startCompass":
        print("[COMPASS-iOS] 🧭 Starting real compass...")
        self?.startCompass(compassChannel)
        result(nil)
        
      case "stopCompass":
        print("[COMPASS-iOS] 🛑 Stopping compass")
        self?.stopCompass()
        result(nil)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    bleChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      print("[BLE-iOS] 📞 Method channel call received")
      print("[BLE-iOS]   └─ Method: \(call.method)")
      print("[BLE-iOS]   └─ Arguments: \(call.arguments ?? [:])")
      print("[BLE-iOS]   └─ Time: \(Date())")
      
      switch call.method {
      case "startAdvertising":
        // Use Nomatch-specific UUIDs (must match Dart side)
        let nomatchServiceUuid = "550e8400-e29b-41d4-a716-446655440000"
        let args = call.arguments as? [String: Any]
        let deviceName = args?["deviceName"] as? String ?? "nomatch-device"
        
        print("[BLE-iOS] 🚀 startAdvertising method called")
        print("[BLE-iOS]   └─ Service UUID: \(nomatchServiceUuid) (Nomatch)")
        print("[BLE-iOS]   └─ Device Name: \(deviceName)")
        
        // Set up callback to forward writes from central to Dart (only set once)
        if self?.bleAdvertisingManager?.onCharacteristicWrite == nil {
          print("[BLE-iOS] 🔧 Setting up write callback for the first time")
          self?.bleAdvertisingManager?.onCharacteristicWrite = { [weak self] data in
            print("[BLE-iOS] ✍️ WRITE RECEIVED from central: \(data.count) bytes")
            print("[BLE-iOS]   └─ First 50 bytes: \(Array(data.prefix(50)))")
            // Convert Data to [UInt8] for Dart
            let bytes = [UInt8](data)
            print("[BLE-iOS]   └─ Sending to Dart via blePeripheralChannel...")
            // Send the data back to Dart via peripheral channel on MAIN THREAD
            DispatchQueue.main.async {
              print("[BLE-iOS]   └─ Invoking blePeripheralChannel.invokeMethod with \(bytes.count) bytes")
              blePeripheralChannel.invokeMethod("onWrite", arguments: bytes)
            }
          }
        } else {
          print("[BLE-iOS] ℹ️ Write callback already set, reusing existing callback")
        }
        
        self?.bleAdvertisingManager?.startAdvertising(
          serviceUuid: nomatchServiceUuid,
          deviceName: deviceName
        ) { error in
          if let error = error {
            print("[BLE-iOS] ❌ startAdvertising failed!")
            print("[BLE-iOS]   └─ Error code: ADV_ERROR")
            print("[BLE-iOS]   └─ Error message: \(error.localizedDescription)")
            result(FlutterError(code: "ADV_ERROR", message: error.localizedDescription, details: nil))
          } else {
            print("[BLE-iOS] ✅ startAdvertising completed successfully!")
            print("[BLE-iOS]   └─ BLE advertising is now ACTIVE with Nomatch service UUID")
            result(nil)
          }
        }
        
      case "stopAdvertising":
        print("[BLE-iOS] 🛑 stopAdvertising method called")
        
        self?.bleAdvertisingManager?.stopAdvertising { error in
          if let error = error {
            print("[BLE-iOS] ❌ stopAdvertising failed!")
            print("[BLE-iOS]   └─ Error: \(error.localizedDescription)")
            result(FlutterError(code: "ADV_ERROR", message: error.localizedDescription, details: nil))
          } else {
            print("[BLE-iOS] ✅ stopAdvertising completed")
            print("[BLE-iOS]   └─ BLE advertising is now INACTIVE")
            result(nil)
          }
        }
        
      case "getDeviceId":
        // Return unique device UUID
        let deviceUUID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
        print("[BLE-iOS] 📱 Device UUID: \(deviceUUID)")
        result(deviceUUID)
        
      default:
        print("[BLE-iOS] ❌ Unknown method: \(call.method)")
        result(FlutterMethodNotImplemented)
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // ✅ Sensor Fusion compass using CMDeviceMotion.attitude
  // Combines: Accelerometer + Gyroscope + Magnetometer
  private var headingBuffer: [Double] = []
  private let headingBufferSize = 5
  // ✅ FIX: Timer normal bir stored property'de tutulur. Eskiden
  // objc_setAssociatedObject'e Swift string literal'i anahtar olarak
  // veriliyordu — köprülenen iki literal aynı pointer olmayabildiği için
  // stopCompass timer'ı bulamıyor, her eşleşme denemesinde yeni bir 5 Hz
  // timer birikiyordu (BLE'yi boğan heading seli).
  private var compassTimer: Timer?

  private func startCompass(_ channel: FlutterMethodChannel) {
    print("[FUSION-iOS] 🧭 Starting Sensor Fusion (CMDeviceMotion.attitude)")

    // ✅ FIX: Yenisini kurmadan önce varsa eski timer'ı kapat.
    compassTimer?.invalidate()
    compassTimer = nil

    // Use xMagneticNorthZVertical for absolute heading reference
    // ⚠️ 200ms interval (5 Hz) - faster rates overload BLE and cause disconnection
    motionManager.deviceMotionUpdateInterval = 0.2
    motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical)

    let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
      guard let self = self,
            let motion = self.motionManager.deviceMotion else { return }
      
      // Get heading from fused device motion (0-360°)
      // attitude.yaw is the azimuth angle in radians
      var heading = motion.attitude.yaw * 180 / .pi
      if heading < 0 {
        heading += 360
      }
      
      // Apply circular smoothing
      let smoothedHeading = self.smoothHeading(heading)

      // Manyetometre doğruluğunu logla (kalibrasyon sorunlarını tespit için)
      let magAccuracy = motion.magneticField.accuracy
      if magAccuracy == .uncalibrated || magAccuracy == .low {
        print("[FUSION-iOS] ⚠️ Düşük mag doğruluğu: \(magAccuracy.rawValue) — yön güvenilmeyebilir")
      }

      // Send to Flutter
      channel.invokeMethod("heading", arguments: smoothedHeading)
    }
    
    // Store timer to prevent deallocation
    compassTimer = timer
    print("[FUSION-iOS] ✅ Sensor Fusion started")
  }
  
  /// Smooth heading using circular mean (handles 0/360 wraparound)
  private func smoothHeading(_ newHeading: Double) -> Double {
    headingBuffer.append(newHeading)
    if headingBuffer.count > headingBufferSize {
      headingBuffer.removeFirst()
    }
    
    if headingBuffer.count < 2 {
      return newHeading
    }
    
    // Circular mean
    var sinSum = 0.0
    var cosSum = 0.0
    
    for h in headingBuffer {
      let rad = h * .pi / 180
      sinSum += sin(rad)
      cosSum += cos(rad)
    }
    
    var meanRad = atan2(sinSum, cosSum)
    var meanDeg = meanRad * 180 / .pi
    if meanDeg < 0 {
      meanDeg += 360
    }
    
    return meanDeg
  }
  
  private func stopCompass() {
    motionManager.stopDeviceMotionUpdates()
    headingBuffer.removeAll()

    // Stop timer
    compassTimer?.invalidate()
    compassTimer = nil

    print("[FUSION-iOS] ✅ Sensor Fusion stopped")
  }
  
  // ✅ Helper: Convert accuracy rawValue to human-readable label
  private func _getAccuracyLabel(_ accuracy: Int) -> String {
    switch accuracy {
    case -1:
      return "Uncalibrated"
    case 0:
      return "Low"
    case 1:
      return "Medium"
    case 2:
      return "High"
    default:
      return "Unknown"
    }
  }
}
