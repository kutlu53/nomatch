package com.example.nomatch

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nomatch/ble_advertising"
    private val COMPASS_CHANNEL = "com.nomatch/compass"
    private var blePlugin: NomatchP2pBlePlugin? = null
    private var orientationVectorManager: OrientationVectorManager? = null
    
    // ✅ NEW: Sensor Fusion for compass heading
    private var sensorFusionManager: SensorFusionManager? = null
    private var compassChannel: MethodChannel? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // BLE plugin kullan (iOS ile uyumlu)
        blePlugin = NomatchP2pBlePlugin()
        flutterEngine.plugins.add(blePlugin!!)
        
        // Setup method channel for advertising control
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAdvertising" -> {
                        // Android tarafında advertising zaten NomatchP2pBlePlugin tarafından yönetiliyor
                        // Bu method sadece iOS uyumluluğu için var
                        result.success(null)
                    }
                    "stopAdvertising" -> {
                        // Aynı şekilde, Android advertising daha üst seviyede yönetiliyor
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        
        // ✅ NEW: Setup compass channel (Sensor Fusion - matches iOS)
        compassChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COMPASS_CHANNEL)
        compassChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startCompass" -> {
                    android.util.Log.d("COMPASS-Android", "🧭 Starting Sensor Fusion compass...")
                    startSensorFusionCompass()
                    result.success(null)
                }
                "stopCompass" -> {
                    android.util.Log.d("COMPASS-Android", "🛑 Stopping Sensor Fusion compass")
                    stopSensorFusionCompass()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        
        // ✅ Setup orientation vector streaming for face-to-face detection
        orientationVectorManager = OrientationVectorManager(this, flutterEngine)
    }
    
    // ✅ NEW: Start Sensor Fusion compass (TYPE_ROTATION_VECTOR)
    private fun startSensorFusionCompass() {
        if (sensorFusionManager != null) {
            android.util.Log.d("COMPASS-Android", "⚠️ Sensor Fusion already running")
            return
        }
        
        sensorFusionManager = SensorFusionManager(this)
        sensorFusionManager?.start { heading ->
            // Send heading to Flutter on main thread
            Handler(Looper.getMainLooper()).post {
                compassChannel?.invokeMethod("heading", heading)
            }
        }
        android.util.Log.d("COMPASS-Android", "✅ Sensor Fusion compass started")
    }
    
    // ✅ NEW: Stop Sensor Fusion compass
    private fun stopSensorFusionCompass() {
        sensorFusionManager?.stop()
        sensorFusionManager = null
        android.util.Log.d("COMPASS-Android", "✅ Sensor Fusion compass stopped")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        orientationVectorManager?.stop()
        stopSensorFusionCompass()
    }
}
