package com.example.nomatch

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.*

/// Tilt-compensated yaw fusion using rotation vector
class OrientationFusionManager(context: Context) : SensorEventListener {
  private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
  private val rotationVectorSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
  private val magneticFieldSensor = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
  
  private var onSampleCallback: ((Map<String, Any>) -> Unit)? = null
  
  private val rotationMatrix = FloatArray(9)
  private val orientationAngles = FloatArray(3)
  private var lastMagStrengthUT = 40.0 // Default ~Earth field
  private var lastMagAccuracy = 1
  
  /// Start sensor fusion
  fun start(onSample: (Map<String, Any>) -> Unit) {
    this.onSampleCallback = onSample
    
    // Register rotation vector listener (tilt-compensated)
    rotationVectorSensor?.let {
      sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_FASTEST)
    }
    
    // Register magnetic field listener (for magnitude and accuracy)
    magneticFieldSensor?.let {
      sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_FASTEST)
    }
    
    android.util.Log.d("ORIENT-Android", "✅ Sensor fusion started (rotation vector + mag field)")
  }
  
  /// Stop sensor fusion
  fun stop() {
    sensorManager.unregisterListener(this)
    android.util.Log.d("ORIENT-Android", "✅ Sensor fusion stopped")
  }
  
  override fun onSensorChanged(event: SensorEvent) {
    when (event.sensor.type) {
      Sensor.TYPE_ROTATION_VECTOR -> {
        // Convert rotation vector to rotation matrix
        SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
        
        // Extract orientation angles (pitch, roll, azimuth/yaw)
        SensorManager.getOrientation(rotationMatrix, orientationAngles)
        
        // orientationAngles[0] = azimuth (yaw, radians, [-π, π])
        var yawRad = orientationAngles[0].toDouble()
        
        // Convert to degrees and normalize to [0, 360)
        var yawDeg = yawRad * 180.0 / Math.PI
        if (yawDeg < 0) {
          yawDeg += 360.0
        }
        
        val sampleData = mapOf(
          "yawDeg" to yawDeg,
          "magStrengthUT" to lastMagStrengthUT,
          "accuracy" to lastMagAccuracy,
          "timestampMs" to System.currentTimeMillis(),
        )
        
        onSampleCallback?.invoke(sampleData)
      }
      
      Sensor.TYPE_MAGNETIC_FIELD -> {
        // Calculate magnetic field magnitude
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        lastMagStrengthUT = sqrt(x*x + y*y + z*z).toDouble()
        
        // Map accuracy (0=unreliable, 1=low, 2=medium, 3=high) to our scale
        // We use: -1=uncalibrated, 0=low, 1=medium, 2=high
        lastMagAccuracy = when (event.accuracy) {
          SensorManager.SENSOR_STATUS_UNRELIABLE -> 0
          SensorManager.SENSOR_STATUS_ACCURACY_LOW -> 0
          SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM -> 1
          SensorManager.SENSOR_STATUS_ACCURACY_HIGH -> 2
          else -> 0
        }
      }
    }
  }
  
  override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
    // No action needed
  }
}
