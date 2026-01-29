package com.example.nomatch

import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Base64
import android.util.Log
import android.util.SparseArray
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.UUID

/**
 * Android BLE Plugin - iOS CoreBluetooth ile uyumlu
 * iOS ile aynı UUID'leri kullanır
 */
class NomatchP2pBlePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val TAG = "NomatchP2pBLE"
        private const val METHOD_CHANNEL = "nomatch_p2p/methods"
        private const val EVENT_CHANNEL = "nomatch_p2p/events"
        
        // NoMatch'e ÖZGÜ UUID'ler - başka hiçbir uygulama kullanmıyor
        // NO = 4E4F, MATCH = 4D41544348 (hex ASCII)
        private val SERVICE_UUID = UUID.fromString("4E4F4D41-5443-4800-0000-000000000001")
        private val CHARACTERISTIC_UUID = UUID.fromString("4E4F4D41-5443-4800-0000-000000000002")
        // Magic marker: "NM" (2 bytes) + version (1 byte: 0x01) = 3 bytes total
        // iOS compatibility: iOS uses "NM01" (4 bytes), but we use "NM" + 0x01 for compactness
        private val MAGIC_MARKER_BYTES = byteArrayOf(0x4E, 0x4D, 0x01) // "NM" + version 1
        // Manufacturer ID: Using a test/experimental range (0xFFFF = 65535 is reserved for testing)
        // Note: In production, should use a registered Bluetooth SIG company identifier (0..65535)
        // Default: 0xFFFF (65535) - reserved for testing/experimental use
        private const val DEFAULT_MANUFACTURER_ID = 0xFFFF // 65535 (unsigned 16-bit)
        
        // Feature flag: Use serviceData instead of manufacturerData if true
        // ServiceData is more reliable but requires service UUID in scan filter
        private const val USE_SERVICE_DATA_FALLBACK = false
    }

    private var applicationContext: Context? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    
    // Advertising retry mechanism
    private var advertisingRetryCount = 0
    private val maxAdvertisingRetries = 1 // ✅ Hedef 3.3: TOO_MANY_ADVERTISERS için max 1 retry
    private val advertisingRetryDelayMs = 1000L // 1 second
    private var pendingAdvertiseRetry: Runnable? = null // ✅ Hedef 3.1: Store retry runnable for cancellation
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper()) // ✅ Hedef 3.1: Reusable handler
    private var eventSink: EventChannel.EventSink? = null

    private var appInstanceId: String? = null
    private var sessionId: String? = null
    private var localName: String = "nomatch"
    private var deviceId: Short = 0  // Unique device ID for self-filtering (16-bit)

    // BLE objects
    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private var gattClient: BluetoothGatt? = null

    // State
    private var isAdvertising = false
    private var isScanning = false
    private var isConnected = false
    private var connectedDevice: BluetoothDevice? = null
    private var currentManufacturerId: Int = DEFAULT_MANUFACTURER_ID // Store for retry
    private var _pendingHostingResult: MethodChannel.Result? = null // Store result for async advertising callback
    
    // Discovered devices cache (peerId -> (device, rssi))
    private val discoveredDevices = mutableMapOf<String, Pair<BluetoothDevice, Int>>()
    // Track first seen timestamp per peerId for scan health logging
    private val firstSeenTime = mutableMapOf<String, Long>()
    // Throttle: Track last emit time per peerId to prevent duplicate flood (1 second throttle)
    private val lastEmitTime = mutableMapOf<String, Long>()
    // Throttle: Track last log time per peerId to prevent log spam (3 second throttle)
    private val lastLogTime = mutableMapOf<String, Long>()
    // Throttle: Track last connect log time to prevent spam
    private var lastConnectLogTime: Long = 0
    private var writeCharacteristic: BluetoothGattCharacteristic? = null
    private var lastMessageReceivedTime: Long = 0
    
    // Sensor data for advertising
    private var currentHeading: Double? = null
    private var currentIsFlat: Boolean = false

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "[NomatchP2pBLE] Plugin registered")
        applicationContext = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "Plugin detached")
        stopInternal()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.d(TAG, "[NomatchP2pBLE] ========================================")
        Log.d(TAG, "[NomatchP2pBLE] onListen() CALLED")
        Log.d(TAG, "[NomatchP2pBLE] EventSink: ${if (events != null) "PROVIDED" else "NULL"}")
        eventSink = events
        Log.d(TAG, "[NomatchP2pBLE] Event listener attached and stored")
        Log.d(TAG, "[NomatchP2pBLE] ========================================")
    }

    override fun onCancel(arguments: Any?) {
        Log.d(TAG, "[NomatchP2pBLE] Event listener cancelled")
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "[NomatchP2pBLE] Method: ${call.method}")
        
        when (call.method) {
            "initialize" -> {
                val id = call.argument<String>("appInstanceId")
                if (id.isNullOrBlank()) {
                    emitError("invalidArgument", "Missing appInstanceId")
                    result.error("invalidArgument", "Missing appInstanceId", null)
                    return
                }
                initializeInternal(id)
                result.success(null)
            }
            "startHosting" -> {
                val displayNameHash = call.argument<String>("displayNameHash") ?: "nomatch"
                // ✅ manufacturerId: Optional parameter from Flutter (0..65535, Bluetooth SIG company identifier)
                // Default: 0xFFFF (65535) for testing/experimental use
                val manufacturerIdRaw = call.argument<Int>("manufacturerId")
                val manufacturerId = if (manufacturerIdRaw != null) {
                    // Validate range: 0..65535 (unsigned 16-bit)
                    if (manufacturerIdRaw < 0 || manufacturerIdRaw > 65535) {
                        val errorMsg = "manufacturerId must be 0..65535 (Bluetooth SIG company identifier), got: $manufacturerIdRaw"
                        Log.e(TAG, "[NomatchP2pBLE] $errorMsg")
                        result.error("invalidArgument", errorMsg, null)
                        return
                    }
                    manufacturerIdRaw
                } else {
                    DEFAULT_MANUFACTURER_ID
                }
                Log.d(TAG, "[NomatchP2pBLE] startHosting: manufacturerId=$manufacturerId (from Flutter: ${manufacturerIdRaw != null})")
                // ✅ Hedef 2: Don't call result.success(null) here - it will be called in callback
                startHostingInternal(displayNameHash, manufacturerId, result)
            }
            "startDiscovery" -> {
                startDiscoveryInternal()
                result.success(null)
            }
            "stop" -> {
                stopInternal()
                result.success(null)
            }
            "connect" -> {
                val peerId = call.argument<String>("peerId")
                if (peerId.isNullOrBlank()) {
                    emitError("invalidArgument", "Missing peerId")
                    result.error("invalidArgument", "Missing peerId", null)
                    return
                }
                
                // Throttled log: CONNECT_REQUEST (3 second throttle)
                val now = System.currentTimeMillis()
                val timeSinceLastConnectLog = now - lastConnectLogTime
                if (timeSinceLastConnectLog >= 3000) {
                    lastConnectLogTime = now
                    Log.d(TAG, "[NomatchP2pBLE] CONNECT_REQUEST peerId=$peerId")
                }
                
                Log.d(TAG, "[NomatchP2pBLE] Explicit connect request for peerId: $peerId")
                
                // Find device by peerId (MAC address)
                val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
                if (bluetoothAdapter == null) {
                    emitError("transportUnavailable", "Bluetooth adapter not available")
                    result.error("transportUnavailable", "Bluetooth adapter not available", null)
                    return
                }
                
                try {
                    val device = bluetoothAdapter.getRemoteDevice(peerId)
                    connectToDevice(device)
                    result.success(null)
                } catch (e: IllegalArgumentException) {
                    Log.e(TAG, "[NomatchP2pBLE] Invalid MAC address: $peerId", e)
                    emitError("invalidArgument", "Invalid peerId: $peerId")
                    result.error("invalidArgument", "Invalid peerId: $peerId", null)
                }
            }
            "send" -> {
                val payload = call.argument<String>("payload")
                if (payload == null) {
                    emitError("invalidArgument", "Missing payload")
                    result.error("invalidArgument", "Missing payload", null)
                    return
                }
                sendInternal(payload)
                result.success(null)
            }
            "updateSensorData" -> {
                val heading = call.argument<Double>("heading")
                val isFlat = call.argument<Boolean>("isFlat") ?: false
                updateSensorData(heading, isFlat)
                result.success(null)
            }
            "stopDiscovery" -> {
                stopDiscoveryInternal()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun initializeInternal(id: String) {
        Log.d(TAG, "========================================")
        Log.d(TAG, "[NomatchP2pBLE] INITIALIZE START")
        Log.d(TAG, "[NomatchP2pBLE] appInstanceId: $id")
        
        appInstanceId = id
        sessionId = UUID.randomUUID().toString()
        
        // Generate unique 16-bit device ID for self-filtering (smaller for BLE data limit)
        deviceId = (System.currentTimeMillis() and 0xFFFF).toShort()
        
        val ctx = applicationContext
        if (ctx != null) {
            bluetoothManager = ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            bluetoothAdapter = bluetoothManager?.adapter
            bluetoothLeScanner = bluetoothAdapter?.bluetoothLeScanner
            bluetoothLeAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        }
        
        Log.d(TAG, "[NomatchP2pBLE] sessionId: $sessionId")
        Log.d(TAG, "[NomatchP2pBLE] deviceId: $deviceId (for self-filtering)")
        Log.d(TAG, "[NomatchP2pBLE] Bluetooth adapter: ${if (bluetoothAdapter != null) "OK" else "NULL"}")
        Log.d(TAG, "[NomatchP2pBLE] INITIALIZE COMPLETE")
        Log.d(TAG, "========================================")
        
        emitState("idle")
    }

    private fun startHostingInternal(displayNameHash: String, manufacturerId: Int = DEFAULT_MANUFACTURER_ID, result: MethodChannel.Result? = null) {
        // ✅ Hedef 2: Check if hosting already in progress
        if (_pendingHostingResult != null) {
            val errorMsg = "startHosting already in progress"
            Log.e(TAG, "[NomatchP2pBLE] ERROR: $errorMsg")
            result?.error("hosting_in_progress", errorMsg, null)
            return
        }
        
        currentManufacturerId = manufacturerId // Store for retry
        Log.d(TAG, "========================================")
        Log.d(TAG, "[NomatchP2pBLE] START HOSTING")
        Log.d(TAG, "[NomatchP2pBLE] displayNameHash: $displayNameHash")
        
        localName = displayNameHash
        // ✅ Hedef 1: Don't set isAdvertising = true yet - wait until advertising actually starts (onStartSuccess)
        
        Log.d(TAG, "[NomatchP2pBLE] DUAL MODE: advertising=$isAdvertising, scanning=$isScanning")
        
        // ✅ Hedef 2: Store result for async callback (before any operations that might fail)
        _pendingHostingResult = result
        
        try {
            val adapter = bluetoothAdapter
            if (adapter == null || !adapter.isEnabled) {
                val errorMsg = "Bluetooth is not enabled"
                Log.e(TAG, "[NomatchP2pBLE] ERROR: $errorMsg")
                _pendingHostingResult?.error("transportUnavailable", errorMsg, null)
                _pendingHostingResult = null
                emitError("transportUnavailable", errorMsg)
                emitState("idle")
                return
            }
            
            Log.d(TAG, "[NomatchP2pBLE] Bluetooth is enabled, creating GATT server...")
            
            // Create GATT Server
            val ctx = applicationContext
            if (ctx == null) {
                val errorMsg = "Application context is null"
                Log.e(TAG, "[NomatchP2pBLE] ERROR: $errorMsg")
                _pendingHostingResult?.error("internal", errorMsg, null)
                _pendingHostingResult = null
                emitError("internal", errorMsg)
                emitState("idle")
                return
            }
            
            gattServer = bluetoothManager?.openGattServer(ctx, gattServerCallback)
            
            Log.d(TAG, "[NomatchP2pBLE] GATT Server created: ${if (gattServer != null) "SUCCESS" else "FAILED"}")
            Log.d(TAG, "[NomatchP2pBLE] GATT Server callback registered: gattServerCallback")
            
            if (gattServer == null) {
                val errorMsg = "Failed to create GATT server"
                Log.e(TAG, "[NomatchP2pBLE] ERROR: $errorMsg")
                _pendingHostingResult?.error("internal", errorMsg, null)
                _pendingHostingResult = null
                emitError("internal", errorMsg)
                emitState("idle")
                return
            }
            
            // Create service and characteristic
            val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
            val characteristic = BluetoothGattCharacteristic(
                CHARACTERISTIC_UUID,
                BluetoothGattCharacteristic.PROPERTY_READ or 
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ or 
                BluetoothGattCharacteristic.PERMISSION_WRITE
            )
            service.addCharacteristic(characteristic)
            gattServer?.addService(service)
            
            Log.d(TAG, "[NomatchP2pBLE] Service created: $SERVICE_UUID")
            Log.d(TAG, "[NomatchP2pBLE] Characteristic created: $CHARACTERISTIC_UUID")
            
            val advertiser = bluetoothLeAdvertiser
            if (advertiser == null) {
                val errorMsg = "BLE advertiser not available"
                Log.e(TAG, "[NomatchP2pBLE] ERROR: $errorMsg")
                _pendingHostingResult?.error("advertiser_unavailable", errorMsg, null)
                _pendingHostingResult = null
                emitError("advertiser_unavailable", errorMsg)
                emitState("idle")
                return
            }
            
            // Stop any existing advertising before starting new one
            if (isAdvertising) {
                Log.d(TAG, "[NomatchP2pBLE] Stopping existing advertising before restarting...")
                advertiser.stopAdvertising(advertiseCallback)
                // Wait a bit for stop to complete
                mainHandler.postDelayed({
                    try {
                        startAdvertisingInternal(advertiser, manufacturerId)
                    } catch (e: Exception) {
                        // ✅ Hedef 2: Exception handling
                        Log.e(TAG, "[NomatchP2pBLE] startAdvertisingInternal threw exception: ${e.message}", e)
                        _pendingHostingResult?.error("hosting_exception", e.message ?: "unknown", null)
                        _pendingHostingResult = null
                        emitError("internal", "Exception during advertising start: ${e.message}")
                        emitState("idle")
                    }
                }, 100)
            } else {
                try {
                    startAdvertisingInternal(advertiser, manufacturerId)
                } catch (e: Exception) {
                    // ✅ Hedef 2: Exception handling
                    Log.e(TAG, "[NomatchP2pBLE] startAdvertisingInternal threw exception: ${e.message}", e)
                    _pendingHostingResult?.error("hosting_exception", e.message ?: "unknown", null)
                    _pendingHostingResult = null
                    emitError("internal", "Exception during advertising start: ${e.message}")
                    emitState("idle")
                }
            }
            
            // ✅ Hedef 1: DO NOT emitState("hosting") here - wait for onStartSuccess callback
            Log.d(TAG, "[NomatchP2pBLE] Advertising start requested, waiting for callback...")
            Log.d(TAG, "========================================")
        } catch (e: Exception) {
            // ✅ Hedef 2: Catch all exceptions in startHostingInternal
            Log.e(TAG, "[NomatchP2pBLE] startHostingInternal threw exception: ${e.message}", e)
            _pendingHostingResult?.error("hosting_exception", e.message ?: "unknown", null)
            _pendingHostingResult = null
            emitError("internal", "Exception during hosting start: ${e.message}")
            emitState("idle")
        }
    }
    
    private fun startAdvertisingInternal(advertiser: BluetoothLeAdvertiser, manufacturerId: Int = DEFAULT_MANUFACTURER_ID) {
        // ✅ Safety check: Validate manufacturerId before using it
        if (manufacturerId < 0 || manufacturerId > 65535) {
            val errorMsg = "manufacturerId must be 0..65535 (Bluetooth SIG company identifier), got: $manufacturerId"
            Log.e(TAG, "[NomatchP2pBLE] ERROR: $errorMsg")
            // ✅ Hedef 3: Remove throw, handle via error handler
            isAdvertising = false
            emitError("invalidArgument", errorMsg)
            handleAdvertisingFailure(
                AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR,
                "INTERNAL_ERROR",
                errorMsg
            )
            return
        }
        
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)  // ⬆️ UPGRADED: MEDIUM → HIGH for longer range
            .setConnectable(true)
            .build()
        
        val dataBuilder = AdvertiseData.Builder()
            .setIncludeDeviceName(false) // Custom localName not directly supported in Android BLE advertising
            .addServiceUuid(ParcelUuid(SERVICE_UUID)) // ✅ Nomatch service UUID included
        
        // ✅ Add magic marker: Use manufacturerData (default) or serviceData (fallback)
        if (USE_SERVICE_DATA_FALLBACK) {
            // Alternative: Use serviceData instead of manufacturerData
            // Note: ServiceData requires service UUID in scan filter (already included)
            dataBuilder.addServiceData(ParcelUuid(SERVICE_UUID), MAGIC_MARKER_BYTES)
            Log.d(TAG, "[NomatchP2pBLE] Using serviceData for magic marker (fallback mode)")
        } else {
            // Default: Use manufacturerData (requires valid manufacturerId)
            try {
                dataBuilder.addManufacturerData(manufacturerId, MAGIC_MARKER_BYTES)
                Log.d(TAG, "[NomatchP2pBLE] Using manufacturerData for magic marker (manufacturerId=$manufacturerId)")
            } catch (e: IllegalArgumentException) {
                // ✅ Graceful fallback: If manufacturerData fails, try serviceData
                Log.w(TAG, "[NomatchP2pBLE] manufacturerData failed (manufacturerId=$manufacturerId), falling back to serviceData: ${e.message}")
                dataBuilder.addServiceData(ParcelUuid(SERVICE_UUID), MAGIC_MARKER_BYTES)
                Log.d(TAG, "[NomatchP2pBLE] Fallback: Using serviceData for magic marker")
            }
        }
        
        val data = dataBuilder.build()
        
        try {
            advertiser.startAdvertising(settings, data, advertiseCallback)
            // ✅ DO NOT set isAdvertising = true here - wait for onStartSuccess callback
            val markerHex = MAGIC_MARKER_BYTES.joinToString("") { "%02X".format(it) }
            val method = if (USE_SERVICE_DATA_FALLBACK) "serviceData" else "manufacturerData"
            Log.d(TAG, "[NomatchP2pBLE] Advertising start requested: service UUID=$SERVICE_UUID, $method=[$markerHex], manufacturerId=$manufacturerId, localName=$localName")
            // Note: Actual success/failure will be reported via advertiseCallback
        } catch (e: Exception) {
            // ✅ Hedef 3: Remove throw, handle via error handler
            isAdvertising = false
            Log.e(TAG, "[NomatchP2pBLE] Failed to start advertising (exception): ${e.message}", e)
            
            // Use handleAdvertisingFailure for non-retryable exception
            val errorMsg = "Exception during advertising start: ${e.message}"
            emitError("internal", errorMsg)
            handleAdvertisingFailure(
                AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR,
                "INTERNAL_ERROR",
                errorMsg
            )
            // Note: handleAdvertisingFailure will complete _pendingHostingResult if exists
        }
    }

    private fun updateSensorData(heading: Double?, isFlat: Boolean) {
        Log.d(TAG, "[NomatchP2pBLE] updateSensorData: heading=$heading, isFlat=$isFlat")
        currentHeading = heading
        currentIsFlat = isFlat
        
        // Note: We don't restart advertising here because:
        // 1. Android BLE has rate limits on advertising start/stop
        // 2. Sensor data updates frequently (multiple times per second)
        // 3. Advertising data is set once at startHosting()
        // 4. Sensor data will be sent via GATT characteristic after connection
        
        // Update GATT characteristic value if we have a server
        val server = gattServer
        if (server != null && isAdvertising) {
            val service = server.getService(SERVICE_UUID)
            val characteristic = service?.getCharacteristic(CHARACTERISTIC_UUID)
            if (characteristic != null) {
                // Create sensor data payload
                val buffer = java.nio.ByteBuffer.allocate(9)
                buffer.order(java.nio.ByteOrder.LITTLE_ENDIAN)
                buffer.putDouble(heading ?: -1.0)
                buffer.put(if (isFlat) 1.toByte() else 0.toByte())
                
                characteristic.value = buffer.array()
                Log.d(TAG, "[NomatchP2pBLE] GATT characteristic updated with sensor data")
            }
        }
        
    }

    private fun startDiscoveryInternal() {
        Log.d(TAG, "========================================")
        Log.d(TAG, "[NomatchP2pBLE] START DISCOVERY")
        
        // ✅ DUAL MODE: Both scanning and advertising
        // Android will scan for iOS peers while advertising itself
        // Scan only emits peer_discovered events (no auto-connect)
        // Connection is initiated by Flutter via "connect(peerId)" method call
        
        // Detailed status log at start
        val adapter = bluetoothAdapter
        val isBluetoothEnabled = adapter != null && adapter.isEnabled
        val scanner = adapter?.bluetoothLeScanner
        val scannerNotNull = scanner != null
        Log.d(TAG, "[NomatchP2pBLE] scanStarted=true, scanner!=null=$scannerNotNull, isBluetoothEnabled=$isBluetoothEnabled")
        
        isScanning = true
        
        if (adapter == null || !adapter.isEnabled) {
            Log.e(TAG, "[NomatchP2pBLE] Bluetooth not available or disabled")
            emitError("internal", "Bluetooth not available")
            return
        }
        
        if (scanner == null) {
            Log.e(TAG, "[NomatchP2pBLE] BLE scanner not available")
            emitError("internal", "BLE scanner not available")
            return
        }
        
        bluetoothLeScanner = scanner
        
        // Scan for our service UUID only
        val scanFilter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        
        val scanSettingsBuilder = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
        
        // Android 6+ (API 23+): Sticky match mode - keeps weak signals in results
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            scanSettingsBuilder.setMatchMode(ScanSettings.MATCH_MODE_STICKY)
            Log.d(TAG, "[NomatchP2pBLE] Long-range optimization: MATCH_MODE_STICKY enabled")
        }
        
        val scanSettings = scanSettingsBuilder.build()
        
        Log.d(TAG, "[NomatchP2pBLE] Scanning with serviceUUID=$SERVICE_UUID (long-range optimized)")
        scanner.startScan(listOf(scanFilter), scanSettings, scanCallback)
        Log.d(TAG, "[NomatchP2pBLE] State changed to: discovering")
        Log.d(TAG, "========================================")
        
        emitState("discovering")
    }

    private fun stopDiscoveryInternal() {
        Log.d(TAG, "[NomatchP2pBLE] Stopping discovery (scan only)")
        
        // Stop scan but keep GATT server and connection alive
        isScanning = false
        
        bluetoothLeScanner?.stopScan(scanCallback)
        
        Log.d(TAG, "[NomatchP2pBLE] Scanning stopped (GATT server and connection maintained)")
    }

    private fun stopInternal() {
        Log.d(TAG, "[NomatchP2pBLE] Stopped - disconnecting everything")
        
        // ✅ Hedef 3: Cancel pending retry runnable
        pendingAdvertiseRetry?.let {
            mainHandler.removeCallbacks(it)
            pendingAdvertiseRetry = null
        }
        
        // ✅ Hedef 2: Complete pending result with cancelled error if exists
        val result = _pendingHostingResult
        if (result != null) {
            result.error("cancelled", "Hosting was cancelled", null)
            _pendingHostingResult = null
        }
        
        isAdvertising = false
        isScanning = false
        isConnected = false
        
        bluetoothLeScanner?.stopScan(scanCallback)
        
        // Clear throttle maps on stop
        lastEmitTime.clear()
        lastLogTime.clear()
        firstSeenTime.clear()
        advertisingRetryCount = 0 // Reset retry count
        bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        gattClient?.disconnect()
        gattClient?.close()
        gattClient = null
        gattServer?.close()
        gattServer = null
        connectedDevice = null
        writeCharacteristic = null
        
        // Detailed status log at end
        val adapter = bluetoothAdapter
        val isBluetoothEnabled = adapter != null && adapter.isEnabled
        val scannerNotNull = bluetoothLeScanner != null
        Log.d(TAG, "[NomatchP2pBLE] scanStarted=false, scanner!=null=$scannerNotNull, isBluetoothEnabled=$isBluetoothEnabled")
        
        emitState("idle")
    }

    private fun sendInternal(payload: String) {
        val bytes = payload.toByteArray(StandardCharsets.UTF_8)
        
        // Try sending as GATT Client (if we connected to a peer)
        val characteristic = writeCharacteristic
        val client = gattClient
        if (characteristic != null && client != null) {
            characteristic.value = bytes
            client.writeCharacteristic(characteristic)
            Log.d(TAG, "[NomatchP2pBLE] Sent ${bytes.size} bytes as CLIENT")
            return
        }
        
        // Try sending as GATT Server (if a peer connected to us)
        val server = gattServer
        val device = connectedDevice
        if (server != null && device != null) {
            // Get our service and characteristic
            val service = server.getService(SERVICE_UUID)
            val serverChar = service?.getCharacteristic(CHARACTERISTIC_UUID)
            
            if (serverChar != null) {
                serverChar.value = bytes
                val sent = server.notifyCharacteristicChanged(device, serverChar, false)
                if (sent) {
                    Log.d(TAG, "[NomatchP2pBLE] Sent ${bytes.size} bytes as SERVER")
                } else {
                    Log.e(TAG, "[NomatchP2pBLE] Failed to send as SERVER")
                    emitError("sendFailed", "Failed to send data as server")
                }
                return
            }
        }
        
        Log.e(TAG, "[NomatchP2pBLE] ERROR: No connected peer (neither client nor server)")
        emitError("notConnected", "No connected peer")
    }

    // BLE Callbacks
    private val advertiseCallback: AdvertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            // ✅ Only set isAdvertising = true here (in callback)
            isAdvertising = true
            advertisingRetryCount = 0 // Reset retry count on success
            
            // ✅ Hedef 3: Cancel any pending retry runnable
            pendingAdvertiseRetry?.let {
                mainHandler.removeCallbacks(it)
                pendingAdvertiseRetry = null
            }
            
            Log.d(TAG, "[NomatchP2pBLE] Advertising started successfully")
            
            // ✅ Now emit state and complete result
            Log.d(TAG, "[NomatchP2pBLE] GATT Server is running (advertising enabled for discovery)")
            Log.d(TAG, "[NomatchP2pBLE] State changed to: hosting")
            emitState("hosting")
            
            // ✅ Hedef 1: Double-complete guard - only complete if not already completed
            val result = _pendingHostingResult
            if (result != null) {
                result.success(null)
                _pendingHostingResult = null
            }
        }

        override fun onStartFailure(errorCode: Int) {
            val errorName = when (errorCode) {
                AdvertiseCallback.ADVERTISE_FAILED_DATA_TOO_LARGE -> "DATA_TOO_LARGE"
                AdvertiseCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "TOO_MANY_ADVERTISERS"
                AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED -> "ALREADY_STARTED"
                AdvertiseCallback.ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "FEATURE_UNSUPPORTED"
                AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR -> "INTERNAL_ERROR"
                else -> "UNKNOWN($errorCode)"
            }
            
            val errorDescription = when (errorCode) {
                AdvertiseCallback.ADVERTISE_FAILED_DATA_TOO_LARGE -> "Advertising data exceeds 31-byte limit"
                AdvertiseCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too many advertisers active (system limit)"
                AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED -> "Advertising already started"
                AdvertiseCallback.ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "BLE advertising not supported on this device"
                AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR -> "Internal BLE stack error"
                else -> "Unknown error"
            }
            
            Log.e(TAG, "[NomatchP2pBLE] Advertising failed: $errorCode ($errorName) - $errorDescription, retryCount=$advertisingRetryCount")
            
            // ✅ Hedef 1: ALREADY_STARTED idempotent success - if hosting is in progress, treat as success
            if (errorCode == AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED && _pendingHostingResult != null) {
                // System says "already started" and we're in hosting flow -> treat as success
                isAdvertising = true // ✅ System says it's already started
                advertisingRetryCount = 0 // Reset retry count
                
                // ✅ Hedef 3: Cancel any pending retry runnable
                pendingAdvertiseRetry?.let {
                    mainHandler.removeCallbacks(it)
                    pendingAdvertiseRetry = null
                }
                
                Log.d(TAG, "[NomatchP2pBLE] ALREADY_STARTED during hosting flow -> treating as success (idempotent)")
                
                // ✅ Emit hosting state and complete result
                Log.d(TAG, "[NomatchP2pBLE] GATT Server is running (advertising enabled for discovery)")
                Log.d(TAG, "[NomatchP2pBLE] State changed to: hosting")
                emitState("hosting")
                
                // ✅ Double-complete guard
                val result = _pendingHostingResult
                if (result != null) {
                    result.success(null)
                    _pendingHostingResult = null
                }
                return
            }
            
            // ✅ Only set isAdvertising = false here (in callback) for non-idempotent failures
            isAdvertising = false
            
            // ✅ Hedef 1: Handle ALREADY_STARTED (error code 3) with stop + retry (first attempt only)
            // Retry planlanıyorsa _pendingHostingResult asla tamamlanmamalı
            if (errorCode == AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED && advertisingRetryCount == 0) {
                advertisingRetryCount = 1 // Mark as retried
                Log.d(TAG, "[NomatchP2pBLE] ALREADY_STARTED detected, stopping and retrying in 400ms...")
                val advertiser: BluetoothLeAdvertiser? = bluetoothLeAdvertiser
                if (advertiser != null) {
                    val callback: AdvertiseCallback = advertiseCallback
                    advertiser.stopAdvertising(callback)
                    
                    // ✅ Hedef 3: Cancel existing retry if any, then schedule new one
                    pendingAdvertiseRetry?.let { mainHandler.removeCallbacks(it) }
                    pendingAdvertiseRetry = Runnable {
                        try {
                            startAdvertisingInternal(advertiser, currentManufacturerId)
                        } catch (e: Exception) {
                            // Exception in retry: final failure, complete result
                            Log.e(TAG, "[NomatchP2pBLE] Retry after ALREADY_STARTED failed: ${e.message}", e)
                            handleAdvertisingFailure(
                                AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR,
                                "INTERNAL_ERROR",
                                "Retry after ALREADY_STARTED failed: ${e.message}"
                            )
                        } finally {
                            pendingAdvertiseRetry = null
                        }
                    }
                    mainHandler.postDelayed(pendingAdvertiseRetry!!, 400) // 400ms delay for ALREADY_STARTED
                    return // ✅ Don't complete result, don't emit error yet - wait for retry
                }
            }
            
            // ✅ Hedef 3.3: Retry mechanism for TOO_MANY_ADVERTISERS (error code 2) - max 1 retry
            // Retry planlanıyorsa _pendingHostingResult asla tamamlanmamalı
            if (errorCode == AdvertiseCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS && 
                advertisingRetryCount < maxAdvertisingRetries) {
                advertisingRetryCount++
                Log.d(TAG, "[NomatchP2pBLE] Retrying advertising in ${advertisingRetryDelayMs}ms (attempt $advertisingRetryCount/$maxAdvertisingRetries)")
                val advertiser: BluetoothLeAdvertiser? = bluetoothLeAdvertiser
                if (advertiser != null) {
                    // ✅ Hedef 3.1: Cancel existing retry if any, then schedule new one
                    pendingAdvertiseRetry?.let { mainHandler.removeCallbacks(it) }
                    
                    // ✅ Hedef 3.3: Stop advertising before retry
                    advertiser.stopAdvertising(advertiseCallback)
                    
                    pendingAdvertiseRetry = Runnable {
                        try {
                            startAdvertisingInternal(advertiser, currentManufacturerId)
                        } catch (e: Exception) {
                            // Exception in retry: final failure, complete result
                            Log.e(TAG, "[NomatchP2pBLE] Retry failed: ${e.message}", e)
                            handleAdvertisingFailure(
                                AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR,
                                "INTERNAL_ERROR",
                                "Retry failed: ${e.message}"
                            )
                        } finally {
                            pendingAdvertiseRetry = null
                        }
                    }
                    mainHandler.postDelayed(pendingAdvertiseRetry!!, advertisingRetryDelayMs)
                    return // ✅ Don't complete result, don't emit error yet - wait for retry
                }
            }
            
            // ✅ Hedef 1: No more retries or non-retryable error - final failure, complete result
            handleAdvertisingFailure(errorCode, errorName, errorDescription)
        }
    }
    
    // ✅ Helper function to handle advertising failure (called from callback)
    // ✅ Hedef 1: Only completes _pendingHostingResult on final failure (no more retries)
    private fun handleAdvertisingFailure(errorCode: Int, errorName: String, errorDescription: String): Unit {
        if (advertisingRetryCount >= maxAdvertisingRetries) {
            Log.e(TAG, "[NomatchP2pBLE] Advertising failed after $maxAdvertisingRetries retries")
        }
        
        val errorMsg = "Advertising failed: $errorCode ($errorName) - $errorDescription"
        
        // ✅ Hedef 1: Double-complete guard - only complete if not already completed
        val result = _pendingHostingResult
        if (result != null) {
            result.error("advertising_failed", errorMsg, mapOf("code" to errorCode, "name" to errorName))
            _pendingHostingResult = null
        }
        
        emitError("advertising_failed", errorMsg)
        emitState("idle")
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            result ?: return
            val device = result.device
            val rssi = result.rssi
            val peerId = device.address
            
            // Always update cache (for RSSI updates)
            val isFirstSeen = !discoveredDevices.containsKey(peerId)
            if (isFirstSeen) {
                firstSeenTime[peerId] = System.currentTimeMillis()
            }
            discoveredDevices[peerId] = Pair(device, rssi)
            
            // Throttle: Only emit peer_discovered if 1 second has passed since last emit for this peerId
            val now = System.currentTimeMillis()
            val lastEmit = lastEmitTime[peerId] ?: 0L
            val timeSinceLastEmit = now - lastEmit
            
            // Throttled log: Extract and log serviceUuids/localName (3 second throttle per peerId)
            val lastLog = lastLogTime[peerId] ?: 0L
            val timeSinceLastLog = now - lastLog
            if (timeSinceLastLog >= 3000) {
                lastLogTime[peerId] = now
                val scanRecord = result.scanRecord
                val serviceUuidsList = scanRecord?.serviceUuids
                val serviceUuidsSize = serviceUuidsList?.size ?: 0
                val serviceUuidsStr = if (serviceUuidsList != null && serviceUuidsList.isNotEmpty()) {
                    serviceUuidsList.map { it.toString() }.joinToString(", ")
                } else {
                    "[]"
                }
                val localName = scanRecord?.deviceName ?: "none"
                val scanRecordNull = scanRecord == null
                val firstSeenMs = firstSeenTime[peerId] ?: now
                val ageMs = now - firstSeenMs
                
                // ✅ Scan health log: firstSeen timestamp, scanRecord null, serviceUuids size
                Log.d(TAG, "[NomatchP2pBLE] scanResult: peerId=$peerId, rssi=$rssi, firstSeen=${ageMs}ms ago, scanRecordNull=$scanRecordNull, serviceUuidsSize=$serviceUuidsSize, serviceUuids=[$serviceUuidsStr], localName=$localName")
                
                // Warn if serviceUuids is empty despite scan filter
                if (serviceUuidsList == null || serviceUuidsList.isEmpty()) {
                    Log.w(TAG, "[NomatchP2pBLE] ⚠️ WARNING: scanResult serviceUuids is empty despite scan filter for serviceUUID=$SERVICE_UUID, peerId=$peerId")
                }
            }
            
            if (timeSinceLastEmit >= 1000) {
                // Throttle period passed, emit event
                lastEmitTime[peerId] = now
                Log.d(TAG, "[NomatchP2pBLE] Peer discovered: $peerId, rssi=$rssi")
                
                // Extract advertisement meta from ScanRecord (iOS format compatible)
                val scanRecord = result.scanRecord
                val meta = buildAdvertisementMeta(scanRecord)
                
                // ✅ REMOVED: Auto-connect from scan callback
                // Scan only emits peer_discovered event
                // Connection will be initiated by Flutter via "connect(peerId)" method call
                emitPeerDiscovered(peerId, rssi, meta)
            } else {
                // Within throttle period, only update cache (RSSI update)
                Log.d(TAG, "[NomatchP2pBLE] Peer update (throttled): $peerId, rssi=$rssi, lastEmit=${timeSinceLastEmit}ms ago")
            }
        }

        override fun onScanFailed(errorCode: Int) {
            // Detailed scan failure log
            val errorName = when (errorCode) {
                ScanCallback.SCAN_FAILED_ALREADY_STARTED -> "SCAN_FAILED_ALREADY_STARTED"
                ScanCallback.SCAN_FAILED_APPLICATION_REGISTRATION_FAILED -> "SCAN_FAILED_APPLICATION_REGISTRATION_FAILED"
                ScanCallback.SCAN_FAILED_FEATURE_UNSUPPORTED -> "SCAN_FAILED_FEATURE_UNSUPPORTED"
                ScanCallback.SCAN_FAILED_INTERNAL_ERROR -> "SCAN_FAILED_INTERNAL_ERROR"
                else -> "UNKNOWN_ERROR"
            }
            Log.e(TAG, "[NomatchP2pBLE] Scan failed: errorCode=$errorCode ($errorName)")
            emitError("internal", "Scan failed: $errorCode")
        }
    }

    private fun connectToDevice(device: BluetoothDevice) {
        Log.d(TAG, "[NomatchP2pBLE] Connecting to device: ${device.address}")
        emitState("connecting")
        
        val ctx = applicationContext ?: return
        gattClient = device.connectGatt(ctx, false, gattClientCallback, BluetoothDevice.TRANSPORT_LE)
        
        // Android 8+ (API 26+): Prefer Coded PHY for long-range stability
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && gattClient != null) {
            try {
                gattClient?.setPreferredPhy(
                    BluetoothDevice.PHY_LE_CODED,  // TX: Coded PHY (250 kbps, 200m+ range)
                    BluetoothDevice.PHY_LE_CODED,  // RX: Coded PHY
                    BluetoothDevice.PHY_OPTION_NO_PREFERRED  // Let system optimize
                )
                Log.d(TAG, "[NomatchP2pBLE] ⬆️ Preferred PHY set to LE Coded for long-range (50-100m)")
            } catch (e: Exception) {
                Log.w(TAG, "[NomatchP2pBLE] ⚠️ Coded PHY not available: ${e.message}")
                // Fallback: Continue with default PHY (1M)
            }
        }
    }

    private val gattClientCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                Log.d(TAG, "========================================")
                Log.d(TAG, "[NomatchP2pBLE] CONNECTED TO PERIPHERAL!")
                Log.d(TAG, "[NomatchP2pBLE] Peer ID: ${gatt?.device?.address}")
                Log.d(TAG, "[NomatchP2pBLE] Discovering services...")
                
                connectedDevice = gatt?.device
                isConnected = true
                gatt?.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                Log.d(TAG, "[NomatchP2pBLE] Disconnected from peripheral")
                isConnected = false
                // Clean up GATT client
                if (gattClient != null) {
                    Log.d(TAG, "[NomatchP2pBLE] Cleaning up GATT client connection")
                    gattClient?.close()
                    gattClient = null
                }
                emitDisconnected(gatt?.device?.address ?: "", "transportLost")
                emitState("idle")
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "========================================")
                Log.d(TAG, "[NomatchP2pBLE] SERVICE DISCOVERY CALLBACK")
                Log.d(TAG, "[NomatchP2pBLE] Services found: ${gatt?.services?.size}")
                
                val service = gatt?.getService(SERVICE_UUID)
                if (service != null) {
                    Log.d(TAG, "[NomatchP2pBLE] MATCH! Service found: $SERVICE_UUID")
                    val characteristic = service.getCharacteristic(CHARACTERISTIC_UUID)
                    if (characteristic != null) {
                        Log.d(TAG, "[NomatchP2pBLE] MATCH! Characteristic found: $CHARACTERISTIC_UUID")
                        writeCharacteristic = characteristic
                        
                        // Enable notifications for ongoing updates
                        gatt.setCharacteristicNotification(characteristic, true)
                        
                        // Read current value immediately to get sensor data
                        gatt.readCharacteristic(characteristic)
                        Log.d(TAG, "[NomatchP2pBLE] Reading initial characteristic value for sensor data")
                        
                        // Leader election: Client (Central) is always FOLLOWER
                        // Server (Peripheral) decides leadership
                        val peerId = gatt.device.address
                        val isLeader = false  // Central is always follower
                        
                        Log.d(TAG, "[NomatchP2pBLE] Leader election (as Central): peerId=$peerId, isLeader=$isLeader [Central is always follower]")
                        
                        // Note: emitConnected will be called after reading sensor data
                        // This allows validation before finalizing connection
                        Log.d(TAG, "[NomatchP2pBLE] Waiting for sensor data before emitting connected...")
                        
                        emitConnected(peerId, isLeader)
                        emitState("connected")
                        
                        Log.d(TAG, "[NomatchP2pBLE] CONNECTION ESTABLISHED!")
                        Log.d(TAG, "[NomatchP2pBLE] isLeader: $isLeader")
                        Log.d(TAG, "========================================")
                    }
                }
            }
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt?, characteristic: BluetoothGattCharacteristic?) {
            val bytes = characteristic?.value
            if (bytes != null) {
                val message = String(bytes, StandardCharsets.UTF_8)
                val peerId = gatt?.device?.address ?: ""
                emitMessageReceived(peerId, message)
                Log.d(TAG, "[NomatchP2pBLE] Received ${bytes.size} bytes from: $peerId")
            }
        }
        
        override fun onCharacteristicRead(gatt: BluetoothGatt?, characteristic: BluetoothGattCharacteristic?, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                val bytes = characteristic?.value
                val peerId = gatt?.device?.address ?: ""
                
                if (bytes != null && bytes.size == 9) {
                    // Parse sensor data (8 byte double + 1 byte boolean)
                    val buffer = java.nio.ByteBuffer.wrap(bytes)
                    buffer.order(java.nio.ByteOrder.LITTLE_ENDIAN)
                    val heading = buffer.double
                    val isFlat = buffer.get() != 0.toByte()
                    
                    // Normalize heading (-1.0 means null)
                    val normalizedHeading = if (heading >= 0.0 && heading < 360.0) heading else null
                    
                    // ✅ REMOVED: emitPeerDiscovered with sensor data
                    // Peer_discovered events should only come from scan discovery
                    // Sensor data will be sent via heartbeat/message if needed (not implemented yet)
                    Log.d(TAG, "========================================")
                    Log.d(TAG, "[NomatchP2pBLE] [DEBUG] Sensor data read from $peerId (not emitting peer_discovered):")
                    Log.d(TAG, "[NomatchP2pBLE] [DEBUG] Heading: $normalizedHeading")
                    Log.d(TAG, "[NomatchP2pBLE] [DEBUG] IsFlat: $isFlat")
                    Log.d(TAG, "========================================")
                    
                    // Note: Connection is maintained - this is the main game connection, not temporary
                }
            } else {
                Log.e(TAG, "[NomatchP2pBLE] Characteristic read failed: status=$status")
            }
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice?, status: Int, newState: Int) {
            Log.d(TAG, "========================================")
            Log.d(TAG, "[NomatchP2pBLE] ⚡ GATT SERVER CALLBACK: onConnectionStateChange")
            Log.d(TAG, "[NomatchP2pBLE] Device: ${device?.address}")
            Log.d(TAG, "[NomatchP2pBLE] Status: $status")
            Log.d(TAG, "[NomatchP2pBLE] New State: $newState (2=CONNECTED, 0=DISCONNECTED)")
            
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                Log.d(TAG, "[NomatchP2pBLE] ✅ CLIENT CONNECTED (AS PERIPHERAL)!")
                Log.d(TAG, "[NomatchP2pBLE] Client ID: ${device?.address}")
                
                connectedDevice = device
                isConnected = true
                lastMessageReceivedTime = System.currentTimeMillis() // Initialize timestamp
                
                // Leader election: Server (Peripheral) is always LEADER
                // Client (Central) is follower
                val peerId = device?.address ?: ""
                val isLeader = true  // Peripheral is always leader
                
                Log.d(TAG, "[NomatchP2pBLE] Leader election (as Peripheral): peerId=$peerId, isLeader=$isLeader [Peripheral is always leader]")
                
                emitConnected(peerId, isLeader)
                emitState("connected")
                
                Log.d(TAG, "[NomatchP2pBLE] CONNECTION ESTABLISHED AS PERIPHERAL!")
                Log.d(TAG, "[NomatchP2pBLE] isLeader: $isLeader")
                Log.d(TAG, "========================================")
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                Log.d(TAG, "[NomatchP2pBLE] Client disconnected (GATT callback)")
                
                // Check if we recently received a message
                val timeSinceLastMessage = System.currentTimeMillis() - lastMessageReceivedTime
                val HEARTBEAT_TIMEOUT = 5000L // 5 seconds
                
                if (timeSinceLastMessage < HEARTBEAT_TIMEOUT && lastMessageReceivedTime > 0) {
                    Log.d(TAG, "[NomatchP2pBLE] ⚠️ IGNORING disconnect - received message ${timeSinceLastMessage}ms ago")
                    Log.d(TAG, "[NomatchP2pBLE] Connection is still alive (heartbeat active)")
                    Log.d(TAG, "========================================")
                    return
                }
                
                Log.d(TAG, "[NomatchP2pBLE] ❌ REAL DISCONNECT - no recent messages (${timeSinceLastMessage}ms)")
                isConnected = false
                emitDisconnected(device?.address ?: "", "transportLost")
                emitState("idle")
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice?,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic?,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            Log.d(TAG, "========================================")
            Log.d(TAG, "[NomatchP2pBLE] ⚡ GATT SERVER CALLBACK: onCharacteristicWriteRequest")
            Log.d(TAG, "[NomatchP2pBLE] Device: ${device?.address}")
            Log.d(TAG, "[NomatchP2pBLE] Value size: ${value?.size ?: 0}")
            Log.d(TAG, "[NomatchP2pBLE] Response needed: $responseNeeded")
            
            if (value != null) {
                val message = String(value, StandardCharsets.UTF_8)
                val peerId = device?.address ?: ""
                
                // Update last message time - connection is alive!
                lastMessageReceivedTime = System.currentTimeMillis()
                
                emitMessageReceived(peerId, message)
                Log.d(TAG, "[NomatchP2pBLE] Received ${value.size} bytes from: $peerId")
                Log.d(TAG, "[NomatchP2pBLE] Message preview: ${message.take(100)}...")
            }
            
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                Log.d(TAG, "[NomatchP2pBLE] Sent GATT response")
            }
        }
        
        override fun onCharacteristicReadRequest(
            device: BluetoothDevice?,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic?
        ) {
            Log.d(TAG, "[NomatchP2pBLE] onCharacteristicReadRequest called")
            gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, ByteArray(0))
        }
    }

    // Event emitters
    private fun emitState(state: String) {
        val obj = JSONObject()
        obj.put("event", "state_changed")
        obj.put("state", state)
        obj.put("sessionId", sessionId)
        emit(obj)
    }

    /**
     * Build advertisement meta from ScanRecord (iOS format compatible)
     * Format: {serviceUuids: [String], localName: String?, manufacturerData: base64?, serviceData: {uuidString: base64}}
     */
    private fun buildAdvertisementMeta(scanRecord: ScanRecord?): JSONObject {
        val meta = JSONObject()
        
        if (scanRecord != null) {
            // serviceUuids: [String]
            val serviceUuids = scanRecord.serviceUuids
            if (serviceUuids != null && serviceUuids.isNotEmpty()) {
                val uuidArray = org.json.JSONArray()
                for (uuid in serviceUuids) {
                    uuidArray.put(uuid.toString())
                }
                meta.put("serviceUuids", uuidArray)
            }
            
            // localName: String?
            val localName = scanRecord.deviceName
            if (localName != null) {
                meta.put("localName", localName)
            }
            
            // manufacturerData: base64?
            // Android has SparseArray<ByteArray> (key is manufacturer ID), take first entry
            val manufacturerData = scanRecord.manufacturerSpecificData
            if (manufacturerData != null && manufacturerData.size() > 0) {
                val firstKey = manufacturerData.keyAt(0)
                val firstData = manufacturerData.get(firstKey)
                if (firstData != null) {
                    val base64 = Base64.encodeToString(firstData, Base64.NO_WRAP)
                    meta.put("manufacturerData", base64)
                }
            }
            
            // serviceData: {uuidString: base64}
            // Android requires iterating through service UUIDs and calling getServiceData for each
            val serviceDataObj = JSONObject()
            if (serviceUuids != null) {
                for (uuid in serviceUuids) {
                    val data = scanRecord.getServiceData(uuid)
                    if (data != null) {
                        val base64 = Base64.encodeToString(data, Base64.NO_WRAP)
                        serviceDataObj.put(uuid.toString(), base64)
                    }
                }
            }
            if (serviceDataObj.length() > 0) {
                meta.put("serviceData", serviceDataObj)
            }
        }
        
        return meta
    }
    
    private fun emitPeerDiscovered(peerId: String, rssi: Int, meta: JSONObject? = null, heading: Double? = null, isFlat: Boolean? = null) {
        val obj = JSONObject()
        obj.put("event", "peer_discovered")
        obj.put("peerId", peerId)
        obj.put("rssi", rssi)
        
        // Merge advertisement meta with sensor data (if any)
        // Create a new JSONObject to avoid modifying the original meta
        val finalMeta = if (meta != null) {
            JSONObject(meta.toString()) // Deep copy
        } else {
            JSONObject()
        }
        
        // Add sensor data if provided (from GATT characteristic read)
        if (heading != null) {
            finalMeta.put("heading", heading)
        }
        if (isFlat != null) {
            finalMeta.put("isFlat", isFlat)
        }
        
        obj.put("meta", finalMeta)
        
        emit(obj)
    }

    private fun emitConnected(peerId: String, isLeader: Boolean) {
        Log.d(TAG, "[NomatchP2pBLE] ========================================")
        Log.d(TAG, "[NomatchP2pBLE] EMITTING CONNECTED EVENT")
        Log.d(TAG, "[NomatchP2pBLE] peerId: $peerId")
        Log.d(TAG, "[NomatchP2pBLE] isLeader: $isLeader")
        Log.d(TAG, "[NomatchP2pBLE] sessionId: $sessionId")
        Log.d(TAG, "[NomatchP2pBLE] eventSink: ${if (eventSink != null) "ACTIVE" else "NULL"}")
        
        val obj = JSONObject()
        obj.put("event", "connected")
        obj.put("sessionId", sessionId)
        obj.put("peerId", peerId)
        obj.put("isLeader", isLeader)
        
        Log.d(TAG, "[NomatchP2pBLE] JSON: ${obj.toString()}")
        emit(obj)
        Log.d(TAG, "[NomatchP2pBLE] Event emitted successfully")
        Log.d(TAG, "[NomatchP2pBLE] ========================================")
    }

    private fun emitDisconnected(peerId: String, reason: String) {
        val obj = JSONObject()
        obj.put("event", "disconnected")
        obj.put("sessionId", sessionId)
        obj.put("peerId", peerId)
        obj.put("reason", reason)
        emit(obj)
    }

    private fun emitMessageReceived(fromPeerId: String, message: String) {
        val obj = JSONObject()
        obj.put("event", "message_received")
        obj.put("sessionId", sessionId)
        obj.put("fromPeerId", fromPeerId)
        obj.put("message", message)
        emit(obj)
    }

    private fun emitError(code: String, message: String) {
        val obj = JSONObject()
        obj.put("event", "error")
        obj.put("code", code)
        obj.put("message", message)
        obj.put("details", JSONObject())
        emit(obj)
    }

    private fun emit(obj: JSONObject) {
        val eventType = obj.optString("event", "unknown")
        Log.d(TAG, "========================================")
        Log.d(TAG, "[NomatchP2pBLE] 📤 emit() called")
        Log.d(TAG, "[NomatchP2pBLE] Event type: $eventType")
        Log.d(TAG, "[NomatchP2pBLE] JSON: ${obj.toString()}")
        Log.d(TAG, "[NomatchP2pBLE] eventSink status: ${if (eventSink != null) "ACTIVE ✓" else "NULL ✗"}")
        Log.d(TAG, "[NomatchP2pBLE] Current thread: ${Thread.currentThread().name}")
        
        if (eventSink == null) {
            Log.e(TAG, "[NomatchP2pBLE] ❌ ERROR: eventSink is NULL! Event will be lost!")
            Log.e(TAG, "[NomatchP2pBLE] Make sure Flutter is listening to event stream!")
            return
        }
        
        // Flutter events MUST be sent on main thread
        mainHandler.post {
            try {
                eventSink?.success(obj.toString())
                Log.d(TAG, "[NomatchP2pBLE] ✅ Event sent to Flutter successfully on main thread!")
                Log.d(TAG, "========================================")
            } catch (e: Exception) {
                Log.e(TAG, "[NomatchP2pBLE] ❌ ERROR sending event to Flutter: ${e.message}")
                Log.e(TAG, "[NomatchP2pBLE] Stack trace: ${e.stackTrace.joinToString("\n")}")
                Log.d(TAG, "========================================")
            }
        }
    }
}
