package com.example.nomatch

import android.content.Context
import android.util.Log
import androidx.annotation.NonNull
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.ConnectionsClient
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import android.app.Activity
import android.os.Build
import android.Manifest
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.UUID

class NomatchP2pPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler, ActivityAware {
    companion object {
        private const val TAG = "NomatchP2p"
        private const val METHOD_CHANNEL = "nomatch_p2p/methods"
        private const val EVENT_CHANNEL = "nomatch_p2p/events"
    }

    private var applicationContext: Context? = null
    private var connectionsClient: ConnectionsClient? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private var appInstanceId: String? = null
    private var sessionId: String? = null
    private var localName: String = "nomatch"

    private var connectedEndpointId: String? = null

    // Nearby uses a serviceId to scope discovery/advertising.
    private val serviceId: String
        get() = applicationContext?.packageName ?: "com.example.nomatch"

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "attached")
        applicationContext = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "detached")
        stopInternal()

        methodChannel?.setMethodCallHandler(null)
        methodChannel = null

        eventChannel?.setStreamHandler(null)
        eventChannel = null

        eventSink = null
        connectionsClient = null
        applicationContext = null
        activity = null
        activityBinding = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.d(TAG, "event listen")
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        Log.d(TAG, "event cancel")
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "method=" + call.method)
        when (call.method) {
            "init" -> {
                requestPermissionsInternal()
                result.success(null)
                return
            }
            "initialize" -> {
                val id = call.argument<String>("appInstanceId")
                if (id.isNullOrBlank()) {
                    emitError(code = "invalidArgument", message = "Missing appInstanceId")
                    result.error("invalidArgument", "Missing appInstanceId", null)
                    return
                }
                initializeInternal(id)
                result.success(null)
            }

            "startHosting" -> {
                val displayNameHash = call.argument<String>("displayNameHash") ?: "nomatch"
                val _sessionConfigJson = call.argument<String>("sessionConfigJson") ?: "{}"
                startHostingInternal(displayNameHash)
                result.success(null)
            }

            "startDiscovery" -> {
                val _sessionConfigJson = call.argument<String>("sessionConfigJson") ?: "{}"
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
                    emitError(code = "invalidArgument", message = "Missing peerId")
                    result.error("invalidArgument", "Missing peerId", null)
                    return
                }
                connectInternal(peerId)
                result.success(null)
            }

            "send" -> {
                val payload = call.argument<String>("payload")
                if (payload == null) {
                    emitError(code = "invalidArgument", message = "Missing payload")
                    result.error("invalidArgument", "Missing payload", null)
                    return
                }
                sendInternal(payload)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun requestPermissionsInternal() {
        val act = activity ?: return
        val perms = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            perms.add(Manifest.permission.BLUETOOTH_SCAN)
            perms.add(Manifest.permission.BLUETOOTH_CONNECT)
        }
        ActivityCompat.requestPermissions(act, perms.toTypedArray(), 4242)
    }

    private fun initializeInternal(id: String) {
        appInstanceId = id
        sessionId = UUID.randomUUID().toString()

        val ctx = applicationContext
        if (ctx != null) {
            connectionsClient = Nearby.getConnectionsClient(ctx)
        }

        emitState("idle")
    }

    private fun startHostingInternal(displayNameHash: String) {
        localName = displayNameHash
        val client = connectionsClient
        if (client == null) {
            emitError(code = "notInitialized", message = "ConnectionsClient is null")
            return
        }

        emitState("hosting")

        val options = AdvertisingOptions.Builder()
            .setStrategy(Strategy.P2P_STAR)
            .build()

        client.startAdvertising(
            localName,
            serviceId,
            connectionLifecycleCallback,
            options
        ).addOnFailureListener { e ->
            emitError(code = "internal", message = "startAdvertising failed: ${e.message}")
        }
    }

    private fun startDiscoveryInternal() {
        val client = connectionsClient
        if (client == null) {
            emitError(code = "notInitialized", message = "ConnectionsClient is null")
            return
        }

        emitState("discovering")

        val options = DiscoveryOptions.Builder()
            .setStrategy(Strategy.P2P_STAR)
            .build()

        client.startDiscovery(
            serviceId,
            endpointDiscoveryCallback,
            options
        ).addOnFailureListener { e ->
            emitError(code = "internal", message = "startDiscovery failed: ${e.message}")
        }
    }

    private fun stopInternal() {
        val client = connectionsClient
        if (client != null) {
            client.stopDiscovery()
            client.stopAdvertising()
            client.stopAllEndpoints()
        }
        connectedEndpointId = null
        emitState("idle")
    }

    private fun connectInternal(peerId: String) {
        val client = connectionsClient
        if (client == null) {
            emitError(code = "notInitialized", message = "ConnectionsClient is null")
            return
        }

        emitState("connecting")

        client.requestConnection(
            localName,
            peerId,
            connectionLifecycleCallback
        ).addOnFailureListener { e ->
            emitError(code = "internal", message = "requestConnection failed: ${e.message}")
        }
    }

    private fun sendInternal(payloadJson: String) {
        val client = connectionsClient
        val endpointId = connectedEndpointId
        if (client == null) {
            emitError(code = "notInitialized", message = "ConnectionsClient is null")
            return
        }
        if (endpointId.isNullOrBlank()) {
            emitError(code = "notConnected", message = "No connected endpoint")
            return
        }

        val bytes = payloadJson.toByteArray(StandardCharsets.UTF_8)
        client.sendPayload(endpointId, Payload.fromBytes(bytes)).addOnFailureListener { e ->
            emitError(code = "sendFailed", message = "sendPayload failed: ${e.message}")
        }
    }

    private val endpointDiscoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            val obj = JSONObject()
            obj.put("event", "peer_discovered")
            obj.put("peerId", endpointId)
            // Note: Nearby Connections doesn't provide RSSI directly
            // We'll use connection quality as a proxy after connection
            obj.put("rssi", -60) // Default medium range estimate
            obj.put("meta", JSONObject())
            emit(obj)
        }

        override fun onEndpointLost(endpointId: String) {
            // No-op for now.
        }
    }

    private val connectionLifecycleCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, connectionInfo: ConnectionInfo) {
            // Auto-accept.
            connectionsClient?.acceptConnection(endpointId, payloadCallback)
        }

        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
            if (result.status.isSuccess) {
                connectedEndpointId = endpointId
                
                // Leader Election: Deterministik lider seçimi
                // appInstanceId daha BÜYÜK olan cihaz lider olur
                val myId = appInstanceId ?: ""
                val peerId = endpointId
                val isLeader = myId > peerId
                
                val obj = JSONObject()
                obj.put("event", "connected")
                obj.put("sessionId", sessionId ?: "")
                obj.put("peerId", endpointId)
                obj.put("isLeader", isLeader)
                emit(obj)
                emitState("connected")
            } else {
                emitError(code = "internal", message = "connection failed: ${result.status.statusCode}")
            }
        }

        override fun onDisconnected(endpointId: String) {
            if (connectedEndpointId == endpointId) {
                connectedEndpointId = null
            }
            val obj = JSONObject()
            obj.put("event", "disconnected")
            obj.put("sessionId", sessionId)
            obj.put("peerId", endpointId)
            obj.put("reason", "transportLost")
            emit(obj)
            emitState("idle")
        }
    }

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            val bytes = payload.asBytes()
            if (bytes == null) return
            val msg = String(bytes, StandardCharsets.UTF_8)

            val obj = JSONObject()
            obj.put("event", "message_received")
            obj.put("sessionId", sessionId)
            obj.put("fromPeerId", endpointId)
            obj.put("message", msg)
            emit(obj)
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {
            // No-op.
        }
    }

    private fun emitState(state: String) {
        val obj = JSONObject()
        obj.put("event", "state_changed")
        obj.put("state", state)
        obj.put("sessionId", sessionId)
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
        eventSink?.success(obj.toString())
    }

    // ActivityAware
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener { requestCode, permissions, grantResults ->
            if (requestCode == 4242) {
                val obj = JSONObject()
                obj.put("event", "permission_result")
                val map = JSONObject()
                var allGranted = true
                for (i in permissions.indices) {
                    val granted = grantResults[i] == 0
                    map.put(permissions[i], granted)
                    if (!granted) allGranted = false
                }
                obj.put("results", map)
                emit(obj)
                if (allGranted) {
                    methodChannel?.invokeMethod("onReady", null)
                }
                return@addRequestPermissionsResultListener true
            }
            return@addRequestPermissionsResultListener false
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activity = null
        activityBinding = null
    }
}

