import CoreMotion
import Flutter

class OrientationVectorManager: NSObject {
    private let motionManager = CMMotionManager()
    private let magnetometerManager = CMMotionManager()
    private let updateInterval = 0.05 // 20Hz
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    private var lastMagnetometerData: CMCalibratedMagneticField?

    func initializeWithChannel(_ channel: FlutterEventChannel) {
        self.eventChannel = channel
        channel.setStreamHandler(self)
        print("[OV-iOS] ✅ OrientationVectorManager initialized")
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("[OV-iOS] ❌ Device motion not available")
            return
        }

        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(
            using: .xMagneticNorthZVertical,
            to: .main
        ) { [weak self] _, _ in
            self?.processMotionData()
        }

        print("[OV-iOS] ✅ Started device motion updates (20Hz)")
    }

    private func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
        print("[OV-iOS] ⏹️  Stopped device motion updates")
    }

    private func processMotionData() {
        guard let motion = motionManager.deviceMotion else { return }

        // Get attitude quaternion
        let att = motion.attitude
        let quat = att.quaternion

        // Convert quaternion to rotation matrix
        let rotMatrix = quaternionToRotationMatrix(
            w: quat.w,
            x: quat.x,
            y: quat.y,
            z: quat.z
        )

        // Forward device in device coordinates = [0, 1, 0] (top of screen)
        let forwardDevice: [Double] = [0, 1, 0]

        // Transform to world: forward_world = R * forward_device
        var forwardWorld: [Double] = [0, 0, 0]
        for i in 0..<3 {
            for j in 0..<3 {
                forwardWorld[i] += rotMatrix[i * 3 + j] * forwardDevice[j]
            }
        }

        // Get magnetometer magnitude from device motion
        let magField = motion.magneticField
        let magMagnitude = sqrt(
            magField.field.x * magField.field.x +
            magField.field.y * magField.field.y +
            magField.field.z * magField.field.z
        )

        // Convert accuracy enum to Int (-1, 0, 1, 2)
        let magAccuracy: Int
        switch magField.accuracy {
        case .uncalibrated:
            magAccuracy = -1
        case .low:
            magAccuracy = 0
        case .medium:
            magAccuracy = 1
        case .high:
            magAccuracy = 2
        @unknown default:
            magAccuracy = -1
        }

        // Emit event
        let data: [String: Any] = [
            "fx": forwardWorld[0],
            "fy": forwardWorld[1],
            "fz": forwardWorld[2],
            "magMag": magMagnitude,
            "magAccuracy": magAccuracy,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]

        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(data)
        }
    }

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

        // Compute 3x3 rotation matrix from normalized quaternion (row-major)
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

    deinit {
        stopMotionUpdates()
    }
}

extension OrientationVectorManager: FlutterStreamHandler {
    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = events
        startMotionUpdates()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        stopMotionUpdates()
        return nil
    }
}
