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
    
    bleAdvertisingManager = BLEAdvertisingManager()
    
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
    
    bleChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "startAdvertising":
        let args = call.arguments as? [String: Any]
        let serviceUuid = args?["serviceUuid"] as? String ?? "A8B4D2E1-C0B9-4B5D-A2C1-E8D4F2B6C9A1"
        let deviceName = args?["deviceName"] as? String ?? "NomatchDevice"
        
        self?.bleAdvertisingManager?.startAdvertising(
          serviceUuid: serviceUuid,
          deviceName: deviceName
        ) { error in
          if let error = error {
            print("[BLE-iOS] Error starting advertising: \(error)")
            result(FlutterError(code: "ADV_ERROR", message: error.localizedDescription, details: nil))
          } else {
            print("[BLE-iOS] ✅ BLE advertising started")
            result(nil)
          }
        }
        
      case "stopAdvertising":
        self?.bleAdvertisingManager?.stopAdvertising { error in
          if let error = error {
            print("[BLE-iOS] Error stopping advertising: \(error)")
            result(FlutterError(code: "ADV_ERROR", message: error.localizedDescription, details: nil))
          } else {
            print("[BLE-iOS] ✅ BLE advertising stopped")
            result(nil)
          }
        }
        
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
