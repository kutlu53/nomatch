import CoreMotion
import Foundation

/// Manages device motion and rotation vector computation
class RotationVectorManager: NSObject {
    private let motionManager = CMMotionManager()
    private let updateInterval = 0.05 // 50ms for ~20Hz updates
    private var flutterMethodChannel: FlutterMethodChannel?
    
    func initializeWithChannel(_ channel: FlutterMethodChannel) {
        self.flutterMethodChannel = channel
        startMotionUpdates()
    }
    
    /// Start motion updates (accelerometer, gyroscope, magnetometer)
    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("[RV-iOS] ❌ Device motion not available")
            return
        }
        
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(
            using: .xMagneticNorthZVertical,
            to: .main
        ) { [weak self] _, _ in
            self?.processDeviceMotion()
        }
        
        print("[RV-iOS] ✅ Device motion updates started (interval: \(updateInterval * 1000)ms)")
    }
    
    /// Process device motion and send rotation matrix to Flutter
    private func processDeviceMotion() {
        guard let motion = motionManager.deviceMotion else { return }
        
        // Get attitude (quaternion) from device motion
        let attitude = motion.attitude
        
        // Convert CMQuaternion to rotation matrix
        // CMAttitude provides quaternion property
        let quat = attitude.quaternion
        let rotationMatrix = quaternionToRotationMatrix(
            w: quat.w,
            x: quat.x,
            y: quat.y,
            z: quat.z
        )
        
        // Send to Flutter via method channel
        DispatchQueue.main.async { [weak self] in
            self?.flutterMethodChannel?.invokeMethod(
                "onRotationVector",
                arguments: [
                    "rotationMatrix": rotationMatrix,
                    "timestamp": Date().timeIntervalSince1970,
                ]
            )
        }
    }
    
    /// Convert quaternion to 3x3 rotation matrix (row-major)
    /// Input: (w, x, y, z)
    /// Output: [m00, m01, m02, m10, m11, m12, m20, m21, m22]
    private func quaternionToRotationMatrix(
        w: Double,
        x: Double,
        y: Double,
        z: Double
    ) -> [Double] {
        // Normalize quaternion
        let norm = sqrt(w * w + x * x + y * y + z * z)
        let qw = w / norm
        let qx = x / norm
        let qy = y / norm
        let qz = z / norm
        
        // Compute rotation matrix from quaternion
        let m00 = 1 - 2 * (qy * qy + qz * qz)
        let m01 = 2 * (qx * qy - qw * qz)
        let m02 = 2 * (qx * qz + qw * qy)
        
        let m10 = 2 * (qx * qy + qw * qz)
        let m11 = 1 - 2 * (qx * qx + qz * qz)
        let m12 = 2 * (qy * qz - qw * qx)
        
        let m20 = 2 * (qx * qz - qw * qy)
        let m21 = 2 * (qy * qz + qw * qx)
        let m22 = 1 - 2 * (qx * qx + qy * qy)
        
        return [
            m00, m01, m02,
            m10, m11, m12,
            m20, m21, m22,
        ]
    }
    
    /// Stop motion updates
    func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
        print("[RV-iOS] ⏹️ Device motion updates stopped")
    }
    
    deinit {
        stopMotionUpdates()
    }
}
