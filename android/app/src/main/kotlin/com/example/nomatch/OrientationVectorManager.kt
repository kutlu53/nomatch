package com.example.nomatch

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import kotlin.math.*

class OrientationVectorManager(
    private val context: Context,
    flutterEngine: FlutterEngine
) : SensorEventListener {

    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val rotationVectorSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private val magnetometerSensor = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)

    private var eventSink: EventChannel.EventSink? = null
    private var isListening = false

    // Buffers for sensor data
    private var lastRotationMatrix = FloatArray(9)
    private var lastMagnetometerMagnitude = 0f
    private var lastMagnetometerAccuracy = -1

    init {
        val channel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.nomatch/orientation_vector"
        )
        channel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                start()
            }

            override fun onCancel(arguments: Any?) {
                stop()
                eventSink = null
            }
        })
        Log.d("OrientationVectorManager", "[OV-Android] Initialized")
    }

    private fun start() {
        if (isListening) return
        
        if (rotationVectorSensor != null) {
            sensorManager.registerListener(this, rotationVectorSensor, SensorManager.SENSOR_DELAY_FASTEST)
            Log.d("OrientationVectorManager", "[OV-Android] ✅ Listening to rotation vector")
        } else {
            Log.w("OrientationVectorManager", "[OV-Android] ❌ Rotation vector sensor not available")
        }

        if (magnetometerSensor != null) {
            sensorManager.registerListener(this, magnetometerSensor, SensorManager.SENSOR_DELAY_FASTEST)
            Log.d("OrientationVectorManager", "[OV-Android] ✅ Listening to magnetometer")
        }

        isListening = true
    }

    fun stop() {
        if (!isListening) return
        sensorManager.unregisterListener(this)
        isListening = false
        Log.d("OrientationVectorManager", "[OV-Android] ⏹️ Stopped")
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> {
                // Convert rotation vector to rotation matrix
                val rotMatrix = FloatArray(9)
                SensorManager.getRotationMatrixFromVector(rotMatrix, event.values)
                lastRotationMatrix = rotMatrix

                // Compute forward direction in world coordinates
                // Device forward = [0, 1, 0] (top of screen in portrait)
                val forwardDevice = floatArrayOf(0f, 1f, 0f)
                val forwardWorld = FloatArray(3)

                // Forward_world = R * forward_device
                for (i in 0..2) {
                    forwardWorld[i] =
                        lastRotationMatrix[i * 3] * forwardDevice[0] +
                        lastRotationMatrix[i * 3 + 1] * forwardDevice[1] +
                        lastRotationMatrix[i * 3 + 2] * forwardDevice[2]
                }

                // Emit event
                val data = mapOf(
                    "fx" to forwardWorld[0].toDouble(),
                    "fy" to forwardWorld[1].toDouble(),
                    "fz" to forwardWorld[2].toDouble(),
                    "magMag" to lastMagnetometerMagnitude.toDouble(),
                    "magAccuracy" to lastMagnetometerAccuracy,
                    "timestamp" to System.currentTimeMillis()
                )
                eventSink?.success(data)
            }

            Sensor.TYPE_MAGNETIC_FIELD -> {
                // Compute magnetometer magnitude and update accuracy
                lastMagnetometerMagnitude = sqrt(
                    event.values[0] * event.values[0] +
                    event.values[1] * event.values[1] +
                    event.values[2] * event.values[2]
                )
                lastMagnetometerAccuracy = event.accuracy
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
        if (sensor.type == Sensor.TYPE_MAGNETIC_FIELD) {
            lastMagnetometerAccuracy = accuracy
        }
    }
}
