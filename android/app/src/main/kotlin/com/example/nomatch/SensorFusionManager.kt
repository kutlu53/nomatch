package com.example.nomatch

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.*

/**
 * Sensor Fusion Manager for Android
 * 
 * Uses TYPE_ROTATION_VECTOR which combines:
 * - Accelerometer (gravity direction)
 * - Gyroscope (rotation rate)
 * - Magnetometer (magnetic north)
 * 
 * This provides much more stable heading than magnetometer alone.
 * Output is compatible with iOS CMDeviceMotion.attitude.yaw
 */
class SensorFusionManager(context: Context) : SensorEventListener {
    
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    
    // Primary: Rotation Vector (includes magnetometer for absolute heading)
    private val rotationVectorSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    
    // Fallback: Game Rotation Vector (no magnetometer - relative only)
    private val gameRotationSensor = sensorManager.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
    
    // Last resort: Magnetometer only
    private val magnetometerSensor = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
    private val accelerometerSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    
    private var headingCallback: ((Double) -> Unit)? = null
    private var isRunning = false
    private var usingFallback = false
    
    // Matrices for orientation calculation
    private val rotationMatrix = FloatArray(9)
    private val orientationAngles = FloatArray(3)
    
    // For magnetometer fallback
    private val accelerometerReading = FloatArray(3)
    private val magnetometerReading = FloatArray(3)
    
    // Smoothing buffer
    private val headingBuffer = mutableListOf<Double>()
    private val BUFFER_SIZE = 5
    
    /**
     * Start sensor fusion and receive heading updates
     * @param onHeading Callback with heading in degrees (0-360, magnetic north)
     */
    fun start(onHeading: (Double) -> Unit) {
        if (isRunning) {
            android.util.Log.w("FUSION-Android", "⚠️ Already running")
            return
        }
        
        headingCallback = onHeading
        isRunning = true
        
        // Try sensors in order of preference
        // ⚠️ Use 200ms interval (5 Hz) - faster rates overload BLE and cause disconnection
        val sensorDelay = 200000 // microseconds = 200ms
        
        when {
            rotationVectorSensor != null -> {
                // Best option: Full sensor fusion with magnetometer
                sensorManager.registerListener(
                    this,
                    rotationVectorSensor,
                    sensorDelay
                )
                usingFallback = false
                android.util.Log.d("FUSION-Android", "✅ Using TYPE_ROTATION_VECTOR (best) @ 5Hz")
            }
            gameRotationSensor != null && magnetometerSensor != null -> {
                // Fallback: Game rotation + magnetometer manually
                sensorManager.registerListener(this, gameRotationSensor, sensorDelay)
                sensorManager.registerListener(this, magnetometerSensor, sensorDelay)
                usingFallback = true
                android.util.Log.d("FUSION-Android", "⚠️ Using GAME_ROTATION_VECTOR + Magnetometer (fallback) @ 5Hz")
            }
            accelerometerSensor != null && magnetometerSensor != null -> {
                // Last resort: Classic accelerometer + magnetometer
                sensorManager.registerListener(this, accelerometerSensor, sensorDelay)
                sensorManager.registerListener(this, magnetometerSensor, sensorDelay)
                usingFallback = true
                android.util.Log.d("FUSION-Android", "⚠️ Using Accelerometer + Magnetometer (legacy fallback) @ 5Hz")
            }
            else -> {
                android.util.Log.e("FUSION-Android", "❌ No suitable sensors available!")
                isRunning = false
            }
        }
    }
    
    /**
     * Stop sensor fusion
     */
    fun stop() {
        if (!isRunning) return
        
        sensorManager.unregisterListener(this)
        headingCallback = null
        isRunning = false
        headingBuffer.clear()
        
        android.util.Log.d("FUSION-Android", "✅ Sensor fusion stopped")
    }
    
    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> {
                // Best case: Direct rotation vector
                processRotationVector(event.values)
            }
            Sensor.TYPE_GAME_ROTATION_VECTOR -> {
                // Game rotation (needs magnetometer correction)
                processRotationVector(event.values)
            }
            Sensor.TYPE_ACCELEROMETER -> {
                System.arraycopy(event.values, 0, accelerometerReading, 0, 3)
                processLegacyFusion()
            }
            Sensor.TYPE_MAGNETIC_FIELD -> {
                System.arraycopy(event.values, 0, magnetometerReading, 0, 3)
                processLegacyFusion()
            }
        }
    }
    
    /**
     * Process rotation vector sensor data
     */
    private fun processRotationVector(values: FloatArray) {
        // Convert rotation vector to rotation matrix
        SensorManager.getRotationMatrixFromVector(rotationMatrix, values)
        
        // Get orientation angles from rotation matrix
        // orientationAngles[0] = azimuth (yaw) in radians [-π, π]
        // orientationAngles[1] = pitch
        // orientationAngles[2] = roll
        SensorManager.getOrientation(rotationMatrix, orientationAngles)
        
        // Convert azimuth to degrees [0, 360)
        var headingDeg = Math.toDegrees(orientationAngles[0].toDouble())
        if (headingDeg < 0) {
            headingDeg += 360.0
        }
        
        // Apply smoothing
        val smoothedHeading = smoothHeading(headingDeg)
        
        // Send to callback
        headingCallback?.invoke(smoothedHeading)
    }
    
    /**
     * Legacy fusion using accelerometer + magnetometer
     * (for devices without gyroscope)
     */
    private fun processLegacyFusion() {
        // Need both readings
        if (accelerometerReading[0] == 0f && magnetometerReading[0] == 0f) return
        
        // Calculate rotation matrix from accel + mag
        val success = SensorManager.getRotationMatrix(
            rotationMatrix,
            null,
            accelerometerReading,
            magnetometerReading
        )
        
        if (!success) return
        
        // Get orientation
        SensorManager.getOrientation(rotationMatrix, orientationAngles)
        
        // Convert to degrees [0, 360)
        var headingDeg = Math.toDegrees(orientationAngles[0].toDouble())
        if (headingDeg < 0) {
            headingDeg += 360.0
        }
        
        // Apply extra smoothing for legacy (more jittery)
        val smoothedHeading = smoothHeading(headingDeg)
        
        headingCallback?.invoke(smoothedHeading)
    }
    
    /**
     * Smooth heading using circular mean
     */
    private fun smoothHeading(newHeading: Double): Double {
        headingBuffer.add(newHeading)
        if (headingBuffer.size > BUFFER_SIZE) {
            headingBuffer.removeAt(0)
        }
        
        if (headingBuffer.size < 2) {
            return newHeading
        }
        
        // Circular mean (handles 0/360 wraparound)
        var sinSum = 0.0
        var cosSum = 0.0
        
        for (h in headingBuffer) {
            val rad = Math.toRadians(h)
            sinSum += sin(rad)
            cosSum += cos(rad)
        }
        
        var meanRad = atan2(sinSum, cosSum)
        var meanDeg = Math.toDegrees(meanRad)
        if (meanDeg < 0) {
            meanDeg += 360.0
        }
        
        return meanDeg
    }
    
    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
        val accuracyStr = when (accuracy) {
            SensorManager.SENSOR_STATUS_UNRELIABLE -> "UNRELIABLE"
            SensorManager.SENSOR_STATUS_ACCURACY_LOW -> "LOW"
            SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM -> "MEDIUM"
            SensorManager.SENSOR_STATUS_ACCURACY_HIGH -> "HIGH"
            else -> "UNKNOWN"
        }
        android.util.Log.d("FUSION-Android", "📊 ${sensor.name} accuracy: $accuracyStr")
    }
}
