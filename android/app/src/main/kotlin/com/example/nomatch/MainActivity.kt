package com.example.nomatch

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nomatch/ble_advertising"
    private var blePlugin: NomatchP2pBlePlugin? = null
    private var orientationVectorManager: OrientationVectorManager? = null
    
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
        
        // ✅ Setup orientation vector streaming for face-to-face detection
        orientationVectorManager = OrientationVectorManager(this, flutterEngine)
    }
    
    override fun onDestroy() {
        super.onDestroy()
        orientationVectorManager?.stop()
    }
}
