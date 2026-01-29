import Foundation
import CoreMotion

/// Tilt-compensated yaw fusion using device motion
class OrientationFusionManager: NSObject {
  private let motionManager = CMMotionManager()
  private let operationQueue = OperationQueue()
  private var onSampleCallback: (([String: Any]) -> Void)?
  
  private let sampleRate = 50.0 // Hz
  
  override init() {
    super.init()
    operationQueue.maxConcurrentOperationCount = 1
  }
  
  /// Start sensor fusion (CMMotionManager with device motion)
  func start(onSample: @escaping ([String: Any]) -> Void) {
    guard motionManager.isDeviceMotionAvailable else {
      print("[ORIENT-iOS] ❌ Device motion not available")
      return
    }
    
    self.onSampleCallback = onSample
    
    motionManager.deviceMotionUpdateInterval = 1.0 / sampleRate
    
    // Use xMagneticNorthZVertical reference frame for tilt-compensated heading
    motionManager.startDeviceMotionUpdates(
      using: .xMagneticNorthZVertical,
      to: operationQueue
    ) { [weak self] motion, error in
      if let error = error {
        print("[ORIENT-iOS] ❌ Motion update error: \(error)")
        return
      }
      
      guard let motion = motion else { return }
      self?.processSample(motion)
    }
    
    print("[ORIENT-iOS] ✅ Sensor fusion started (50 Hz, xMagneticNorthZVertical)")
  }
  
  /// Stop sensor fusion
  func stop() {
    motionManager.stopDeviceMotionUpdates()
    print("[ORIENT-iOS] ✅ Sensor fusion stopped")
  }
  
  /// Process device motion sample and extract tilt-compensated yaw
  private func processSample(_ motion: CMDeviceMotion) {
    // Get attitude (tilt-compensated)
    let attitude = motion.attitude
    
    // Extract yaw (rotation around Z-axis, vertical)
    // attitude.yaw is already in radians, range [-π, π]
    var yawDeg = attitude.yaw * 180.0 / .pi
    
    // Normalize to [0, 360)
    if yawDeg < 0 {
      yawDeg += 360
    }
    
    // Get magnetic field info
    let magField = motion.magneticField
    let magStrengthUT = sqrt(
      magField.field.x * magField.field.x +
      magField.field.y * magField.field.y +
      magField.field.z * magField.field.z
    )
    
    // Convert accuracy enum to int (0=low, 1=medium, 2=high)
    let accuracyInt: Int
    switch magField.accuracy {
    case .uncalibrated:
      accuracyInt = -1
    case .low:
      accuracyInt = 0
    case .medium:
      accuracyInt = 1
    case .high:
      accuracyInt = 2
    @unknown default:
      accuracyInt = 0
    }
    
    let sampleData: [String: Any] = [
      "yawDeg": yawDeg,
      "magStrengthUT": magStrengthUT,
      "accuracy": accuracyInt,
      "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
    ]
    
    DispatchQueue.main.async {
      self.onSampleCallback?(sampleData)
    }
  }
}
