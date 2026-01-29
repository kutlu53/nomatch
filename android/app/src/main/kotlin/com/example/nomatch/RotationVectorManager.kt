package com.example.nomatch

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * Android rotation vector sensor manager
 * Sends device rotation matrix to Flutter for face-to-face detection
 */
class RotationVectorManager(
    private val context: Context,
    private val methodChannel: MethodChannel
) : SensorEventListener {

    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val rotationVectorSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private val accelerometerSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val magnetometerSensor = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)

    private val rotationMatrix = FloatArray(9)
    private val inclination = FloatArray(9)
    private var isListening = false

    init {
        Log.d("RotationVectorManager", "[RV-Android] Initialized")
        if (rotationVectorSensor != null) {
            Log.d("RotationVectorManager", "[RV-Android] ✅ Rotation vector sensor available")
        } else {
            Log.w("RotationVectorManager", "[RV-Android] ⚠️ Rotation vector sensor NOT available")
        }
    }

    fun start() {
        if (isListening) return

        // Register rotation vector sensor (most accurate)
        if (rotationVectorSensor != null) {
            sensorManager.registerListener(this, rotationVectorSensor, SensorManager.SENSOR_DELAY_FASTEST)
            Log.d("RotationVectorManager", "[RV-Android] ✅ Started listening to rotation vector")
        }

        // Also register accelerometer for magnitude check
        if (accelerometerSensor != null) {
            sensorManager.registerListener(this, accelerometerSensor, SensorManager.SENSOR_DELAY_FASTEST)
        }

        // Register magnetometer for stability check
        if (magnetometerSensor != null) {
            sensorManager.registerListener(this, magnetometerSensor, SensorManager.SENSOR_DELAY_FASTEST)
        }

        isListening = true
    }

    fun stop() {
        if (!isListening) return
        sensorManager.unregisterListener(this)
        isListening = false
        Log.d("RotationVectorManager", "[RV-Android] ⏹️ Stopped listening to sensors")
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> {
                // Rotation vector: (x, y, z, scalar, accuracy)
                // Convert to rotation matrix
                SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)

                // Send to Flutter
                val rotationMatrixList = rotationMatrix.toList()
                methodChannel.invokeMethod(
                    "onRotationVector",
                    mapOf(
                        "rotationMatrix" to rotationMatrixList,
                        "timestamp" to (System.currentTimeMillis() / 1000.0)
                    )
                )
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
        // No-op
    }
}
