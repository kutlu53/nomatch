import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide DisconnectReason;
import 'package:permission_handler/permission_handler.dart';

import '../../core/debug_config.dart';
import '../p2p/p2p_events.dart';
import '../p2p/p2p_messages.dart';
import '../p2p/p2p_codec.dart';
import 'ble_constants.dart';

/// Cross-platform P2P implementation using Bluetooth Low Energy
/// 
/// Supports Android-Android, iOS-iOS, and Android-iOS pairing
class BleP2pPlugin {
  static const platform = MethodChannel('com.nomatch/ble_advertising');
  static const peripheralChannel = MethodChannel('com.nomatch/ble_peripheral_writes');
  
  final StreamController<NomatchP2pEvent> _eventController = StreamController<NomatchP2pEvent>.broadcast();
  
  // Platform method call handler for receiving writes from iOS peripheral
  BleP2pPlugin() {
    platform.setMethodCallHandler(_handlePlatformCall);
    peripheralChannel.setMethodCallHandler(_handlePeripheralCall);
    bleLog('✅ BleP2pPlugin initialized - listening on both channels');
  }
  
  Future<dynamic> _handlePlatformCall(MethodCall call) async {
    bleLog('📞 Platform method call: ${call.method}');
    switch (call.method) {
      case 'onCharacteristicWrite':
        bleLog('✅ onCharacteristicWrite called!');
        _onCharacteristicWriteFromiOS(call.arguments);
        return null;
      default:
        bleLog('⚠️ Unknown method: ${call.method}');
        return null;
    }
  }
  
  Future<dynamic> _handlePeripheralCall(MethodCall call) async {
    bleLog('📞 Peripheral channel call: ${call.method}');
    switch (call.method) {
      case 'onWrite':
        bleLog('✅ onWrite called!');
        _onCharacteristicWriteFromiOS(call.arguments);
        return null;
      default:
        bleLog('⚠️ Unknown method: ${call.method}');
        return null;
    }
  }
  
  void _onCharacteristicWriteFromiOS(dynamic arguments) {
    bleLog('🔍 Processing iOS write - type: ${arguments.runtimeType}');
    if (arguments is List<int>) {
      bleLog('📩 Received write: ${arguments.length} bytes');
      _onMessageReceived(arguments);
    } else if (arguments is List && arguments.isNotEmpty) {
      bleLog('📩 Casting arguments to List<int>');
      final bytes = (arguments as List).cast<int>();
      bleLog('📩 Received write (casted): ${bytes.length} bytes');
      _onMessageReceived(bytes);
    } else {
      bleLog('❌ Invalid args type: ${arguments.runtimeType}');
    }
  }
  
  String? _appInstanceId;
  String? _sessionId;
  String? _peerId;
  bool _isHost = false;
  bool _isScanning = false;
  bool _isAdvertising = false;
  bool _isInitialized = false;
  bool _isDisposed = false;
  
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _messageChar;
  BluetoothCharacteristic? _sensorChar;
  bool _isConnecting = false; // Prevent concurrent connection attempts
  
  // ✅ FIX: Store discovered devices for explicit connect()
  final Map<String, BluetoothDevice> _discoveredDevices = {};
  bool _autoConnectEnabled = true; // Can be disabled by upper layer
  
  // Stream subscriptions for proper cleanup
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<bool>? _isScanningStateSub;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;
  StreamSubscription<List<int>>? _messageStreamSub;
  StreamSubscription<List<int>>? _sensorStreamSub;
  
  Stream<NomatchP2pEvent> get events => _eventController.stream;
  
  /// Initialize BLE P2P plugin
  Future<void> initialize({required String appInstanceId}) async {
    // Idempotent initialization - allow reinit after app restart
    if (_isInitialized && _appInstanceId == appInstanceId) {
      dev.log('BLE_P2P: Already initialized with same appInstanceId, emitting idle state');
      _emitStateChanged('idle');
      return;
    }
    
    // If initialized with different ID, cleanup first
    if (_isInitialized && _appInstanceId != appInstanceId) {
      dev.log('BLE_P2P: Reinitializing with different appInstanceId');
      await _cleanupInternal();
    }
    
    _appInstanceId = appInstanceId;
    _sessionId = _generateSessionId();
    _isInitialized = true;
    
    dev.log('BLE_P2P: Initialized with deviceId=$appInstanceId, sessionId=$_sessionId');
    
    // Check BLE availability
    if (await FlutterBluePlus.isSupported == false) {
      dev.log('BLE_P2P: BLE not supported on this device');
      _emitError('ble_not_supported', 'Bluetooth Low Energy is not supported');
      return;
    }
    
    // Listen to Bluetooth state (cancel previous subscription)
    await _adapterStateSub?.cancel();
    _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
      dev.log('BLE_P2P: Adapter state changed: $state');
      if (state == BluetoothAdapterState.off) {
        _emitError('bluetooth_off', 'Bluetooth is turned off');
      }
    });
    
    _emitStateChanged('idle');
  }
  
  /// Start hosting - advertise as peripheral
  Future<void> startHosting({required String displayNameHash, String? sessionConfigJson}) async {
    dev.log('BLE_P2P: Start hosting as $displayNameHash');
    
    if (_isAdvertising) {
      dev.log('BLE_P2P: Already advertising');
      return;
    }
    
    // Request permissions
    if (!await _requestPermissions()) {
      _emitError('permissions_denied', 'Bluetooth permissions not granted');
      return;
    }
    
    _isHost = true;
    _isAdvertising = true;
    
    // Start native BLE advertising
    try {
      await platform.invokeMethod<void>('startAdvertising', {
        'serviceUuid': BleConstants.serviceUuid,
        'deviceName': _appInstanceId ?? 'NomatchDevice',
      });
      dev.log('[BLE] 📣 Native BLE advertising started via platform channel');
    } catch (e) {
      dev.log('[BLE] ⚠️ Error starting native advertising: $e');
      // Continue anyway - may not be critical
    }
    
    // Start scanning for clients (peripheral can also scan)
    await _startScanning();
    
    _emitStateChanged('hosting');
  }
  
  /// Start discovery - scan for peripherals
  Future<void> startDiscovery() async {
    dev.log('BLE_P2P: Start discovery');
    
    if (_isScanning) {
      dev.log('BLE_P2P: Already scanning');
      return;
    }
    
    // Request permissions
    if (!await _requestPermissions()) {
      _emitError('permissions_denied', 'Bluetooth permissions not granted');
      return;
    }
    
    _isHost = false;
    await _startScanning();
    
    _emitStateChanged('discovering');
  }
  
  /// Connect to a discovered peer
  Future<void> connect({required String peerId}) async {
    dev.log('BLE_P2P: Connect to $peerId');
    
    // ✅ FIX: Actually connect to the stored device
    final device = _discoveredDevices[peerId];
    if (device == null) {
      dev.log('BLE_P2P: ⚠️ Device $peerId not found in discovered devices');
      return;
    }
    
    if (_connectedDevice != null) {
      dev.log('BLE_P2P: ⚠️ Already connected to ${_connectedDevice!.remoteId}');
      return;
    }
    
    if (_isConnecting) {
      dev.log('BLE_P2P: ⚠️ Already connecting, ignoring');
      return;
    }
    
    dev.log('BLE_P2P: 🔗 Explicit connect to $peerId');
    await _connectToDevice(device);
  }

  /// Disconnect from current device without touching advertising/scanning state.
  /// Used to reject a "ghost" connection the upper layer no longer expects
  /// (e.g. arrived after PairingManager's connection timeout already reset).
  Future<void> disconnect() async {
    if (_connectedDevice == null) return;

    dev.log('BLE_P2P: 🔌 Disconnecting ghost connection');

    // Bu disconnect kasıtlı — üst katman için PeerDisconnected event'i
    // emit edilmesin diye dinleyiciyi önce iptal ediyoruz.
    await _connectionStateSub?.cancel();
    _connectionStateSub = null;

    try {
      await _connectedDevice!.disconnect();
    } catch (e) {
      dev.log('BLE_P2P: ⚠️ Error disconnecting ghost device: $e');
    }

    _connectedDevice = null;
    _messageChar = null;
    _sensorChar = null;
    _isConnecting = false;
    _peerId = null;
  }

  /// Enable or disable auto-connect on discovery
  void setAutoConnect(bool enabled) {
    _autoConnectEnabled = enabled;
    dev.log('BLE_P2P: Auto-connect ${enabled ? "enabled" : "disabled"}');
  }
  
  /// Send message to connected peer with retry logic
  Future<void> send(P2pMessage message, {int maxRetries = 3}) async {
    print('[BLE-SEND] 🚀 send() called for ${message.runtimeType}');
    
    if (_messageChar == null) {
      print('[BLE-SEND] ❌ Not connected (_messageChar is null)');
      dev.log('[BLE-SEND] ❌ Not connected, cannot send');
      throw Exception('send failed: not connected');
    }
    
    print('[BLE-SEND] ✅ Connected, proceeding with send');
    
    final json = message.toJson();
    final data = utf8.encode(jsonEncode(json));
    
    // ✅ Retry logic for important messages (share, heartbeat)
    int attempt = 0;
    Exception? lastError;
    
    while (attempt < maxRetries) {
      attempt++;
      try {
        print('[BLE-SEND] 📤 SENDING ${message.runtimeType} (attempt $attempt/$maxRetries, ${data.length} bytes)');
        dev.log('[BLE-SEND] 📤 SENDING MESSAGE to peer (attempt $attempt)');
        dev.log('[BLE-SEND]   └─ Char UUID: ${_messageChar?.uuid}');
        dev.log('[BLE-SEND]   └─ Data size: ${data.length} bytes');
        dev.log('[BLE-SEND]   └─ Type: ${message.runtimeType}');
        
        // BLE has MTU limit, chunk if needed
        await _sendChunked(data);
        
        print('[BLE-SEND] ✅ Sent successfully!');
        dev.log('[BLE-SEND] ✅ Sent ${message.runtimeType}');
        return; // Success, exit retry loop
        
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        print('[BLE-SEND] ⚠️ Send attempt $attempt failed: $e');
        dev.log('[BLE-SEND] ⚠️ Send attempt $attempt failed: $e');
        
        if (attempt < maxRetries) {
          // Wait before retry (exponential backoff)
          final delay = Duration(milliseconds: 200 * attempt);
          print('[BLE-SEND] ⏳ Retrying in ${delay.inMilliseconds}ms...');
          await Future.delayed(delay);
        }
      }
    }
    
    // All retries failed
    print('[BLE-SEND] ❌ Send failed after $maxRetries attempts: $lastError');
    dev.log('[BLE-SEND] ❌ Send failed after $maxRetries attempts: $lastError');
    _emitError('send_failed', lastError.toString());
    // ✅ FIX: Hata sessizce yutulmamalı — keep-alive ve reconnect mekanizmaları
    // kopukluğu bu exception üzerinden algılıyor. Yutulursa _isConnected true
    // kalıyor ve yeniden bağlanma hiç tetiklenmiyordu.
    throw lastError ?? Exception('send failed after $maxRetries attempts');
  }
  
  /// Stop all BLE operations
  Future<void> stop() async {
    dev.log('BLE_P2P: Stop');
    
    // Stop native BLE advertising
    if (_isAdvertising) {
      try {
        await platform.invokeMethod<void>('stopAdvertising');
        dev.log('[BLE] 📣 Native BLE advertising stopped');
      } catch (e) {
        dev.log('[BLE] ⚠️ Error stopping native advertising: $e');
      }
    }
    
    await _disconnect();
    await _stopScanning();
    
    _isHost = false;
    _isAdvertising = false;
    _peerId = null;
    
    _emitStateChanged('idle');
  }
  
  /// 🔄 HARD RESET: Complete BLE cleanup for fresh start
  /// Call this when returning to pairing screen after a game
  Future<void> hardReset() async {
    dev.log('[BLE] 🔄🔄🔄 HARD RESET STARTED 🔄🔄🔄');
    
    // 1. Stop native advertising
    if (_isAdvertising) {
      try {
        await platform.invokeMethod<void>('stopAdvertising');
        dev.log('[BLE] 📣 Native advertising stopped');
      } catch (e) {
        dev.log('[BLE] ⚠️ Error stopping advertising: $e');
      }
    }
    
    // 2. Disconnect BLE device
    if (_connectedDevice != null) {
      try {
        dev.log('[BLE] 🔌 Disconnecting device: ${_connectedDevice!.remoteId}');
        // ✅ FIX: Kasıtlı kapanış — önce dinleyiciyi sustur ki reset sırasında
        // sahte PeerDisconnected event'i üretilmesin.
        await _connectionStateSub?.cancel();
        _connectionStateSub = null;
        await _connectedDevice!.disconnect();
        dev.log('[BLE] ✅ Device disconnected');
      } catch (e) {
        dev.log('[BLE] ⚠️ Error disconnecting: $e');
      }
    }
    
    // 3. Stop scanning
    try {
      await FlutterBluePlus.stopScan();
      dev.log('[BLE] 🔍 Scan stopped');
    } catch (e) {
      dev.log('[BLE] ⚠️ Error stopping scan: $e');
    }
    
    // 4. Cancel ALL stream subscriptions
    await _scanResultsSub?.cancel();
    await _isScanningStateSub?.cancel();
    await _connectionStateSub?.cancel();
    await _messageStreamSub?.cancel();
    await _sensorStreamSub?.cancel();
    
    _scanResultsSub = null;
    _isScanningStateSub = null;
    _connectionStateSub = null;
    _messageStreamSub = null;
    _sensorStreamSub = null;
    
    dev.log('[BLE] 🧹 All subscriptions cancelled');
    
    // 5. Reset ALL state variables
    _connectedDevice = null;
    _messageChar = null;
    _sensorChar = null;
    _peerId = null;
    _sessionId = _generateSessionId(); // Fresh session ID
    _isHost = false;
    _isScanning = false;
    _isAdvertising = false;
    _isConnecting = false;
    _discoveredDevices.clear(); // ✅ Clear stored devices
    _autoConnectEnabled = true; // ✅ Re-enable auto-connect
    
    dev.log('[BLE] 🧹 All state variables reset');
    
    // 6. Small delay to ensure BLE stack is fully cleared
    await Future.delayed(const Duration(milliseconds: 300));
    
    dev.log('[BLE] ✅✅✅ HARD RESET COMPLETE ✅✅✅');
    _emitStateChanged('idle');
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    if (_isDisposed) {
      dev.log('BLE_P2P: Already disposed');
      return;
    }
    
    dev.log('BLE_P2P: Disposing');
    _isDisposed = true;
    
    await stop();
    await _cleanupInternal();
    
    if (!_eventController.isClosed) {
      await _eventController.close();
    }
  }
  
  /// Internal cleanup - cancels all subscriptions
  Future<void> _cleanupInternal() async {
    dev.log('BLE_P2P: Cleanup internal');
    
    // Cancel all stream subscriptions
    await _adapterStateSub?.cancel();
    await _scanResultsSub?.cancel();
    await _isScanningStateSub?.cancel();
    await _connectionStateSub?.cancel();
    await _messageStreamSub?.cancel();
    await _sensorStreamSub?.cancel();
    
    _adapterStateSub = null;
    _scanResultsSub = null;
    _isScanningStateSub = null;
    _connectionStateSub = null;
    _messageStreamSub = null;
    _sensorStreamSub = null;
    
    // Reset state flags
    _isInitialized = false;
    _isScanning = false;
    _isAdvertising = false;
    _isHost = false;
  }
  
  // ============================================================================
  // Private Methods
  // ============================================================================
  
  Future<void> _startScanning() async {
    if (_isScanning) return;
    
    dev.log('BLE_P2P: Start scanning');
    _isScanning = true;
    
    try {
      // Cancel previous subscriptions
      await _scanResultsSub?.cancel();
      await _isScanningStateSub?.cancel();
      
      // IMPORTANT: Subscribe to scan results BEFORE starting scan
      // Otherwise early scan results are lost
      _scanResultsSub = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          _onDeviceDiscovered(r);
        }
      });
      dev.log('BLE_P2P: Subscribed to scan results');
      
      // Listen to scan completion — auto-restart if hosting (radar mode needs continuous scan)
      _isScanningStateSub = FlutterBluePlus.isScanning.listen((scanning) {
        if (!scanning && _isScanning) {
          dev.log('BLE_P2P: Scan timeout — restarting scan');
          _isScanning = false;
          
          // ✅ FIX: Auto-restart scan if we're still hosting (looking for peers)
          if (_isAdvertising && _connectedDevice == null && !_isDisposed) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (!_isScanning && !_isDisposed && _isAdvertising) {
                dev.log('BLE_P2P: 🔄 Restarting scan after timeout');
                _startScanning();
              }
            });
          }
        }
      });
      
      // Start scan without service UUID filter
      // ⚠️ DEBUG: Service UUID advertise data'sında görünmediği için filter kapalı
      // iOS'ta GATT service advertise data'sına otomatik eklenmemiş
      await FlutterBluePlus.startScan(
        // withServices: [Guid(BleConstants.serviceUuid)],  // Temporarily disabled
        timeout: BleConstants.scanTimeout,
      );
      dev.log('BLE_P2P: Scanning WITHOUT service UUID filter (debug mode)');
    } catch (e) {
      dev.log('BLE_P2P: Scan failed: $e');
      _isScanning = false;
      _emitError('scan_failed', e.toString());
    }
  }
  
  Future<void> _stopScanning() async {
    if (!_isScanning) return;
    
    dev.log('BLE_P2P: Stop scanning');
    await FlutterBluePlus.stopScan();
    _isScanning = false;
  }
  
  void _onDeviceDiscovered(ScanResult result) {
    final device = result.device;
    final rssi = result.rssi;
    
    dev.log('[BLE] 📡 DEVICE DISCOVERED: ${device.remoteId} | RSSI: ${rssi}dBm | Name: "${device.platformName}"');
    
    // 🔍 DEBUG: Show all advertisement data
    final advertData = result.advertisementData;
    dev.log('[BLE]   ├─ Service UUIDs: ${advertData.serviceUuids} (count: ${advertData.serviceUuids.length})');
    dev.log('[BLE]   ├─ Manufacturer data keys: ${advertData.manufacturerData.keys.toList()}');
    dev.log('[BLE]   ├─ Service data keys: ${advertData.serviceData.keys.toList()}');
    dev.log('[BLE]   └─ TX Power: ${advertData.txPowerLevel}');
    
    // Filter by advertised service UUID - ONLY connect to Nomatch devices!
    final advertisedServices = result.advertisementData.serviceUuids;
    dev.log('[BLE] 🔍 Checking if device advertises Nomatch service...');
    dev.log('[BLE]   ├─ Looking for: ${BleConstants.nomatchServiceUUID} or ${BleConstants.serviceUuid}');
    dev.log('[BLE]   ├─ Advertised services count: ${advertisedServices.length}');
    
    if (advertisedServices.isEmpty) {
      dev.log('[BLE] ⚠️ ⚠️ Device has NO advertised service UUIDs! Likely not a Nomatch device');
      return;
    }
    
    final hasNomatchService = advertisedServices.any((uuid) {
      final uuidStr = uuid.toString().toLowerCase();
      final matches = uuidStr == BleConstants.nomatchServiceUUID.toLowerCase() ||
                      uuidStr == BleConstants.serviceUuid.toLowerCase();
      dev.log('[BLE]   ├─ Checking UUID: $uuid -> ${matches ? "✅ MATCH" : "❌ no match"}');
      return matches;
    });
    
    if (!hasNomatchService) {
      dev.log('[BLE] ⚠️ Device does NOT advertise Nomatch service, ignoring: ${device.remoteId}');
      return;
    }
    
    dev.log('[BLE] ✅ Device advertises Nomatch service!');
    
    // Filter by RSSI (proximity check)
    if (rssi < BleConstants.minRssi || rssi > BleConstants.maxRssi) {
      dev.log('[BLE] ⚠️ Device RSSI out of range: $rssi (min: ${BleConstants.minRssi}, max: ${BleConstants.maxRssi})');
      return;
    }
    
    // Use device UUID as peer ID (more reliable than name for deduplication)
    final peerId = device.remoteId.toString();
    dev.log('[BLE] ✅ Valid Nomatch peer discovered - ID: $peerId | Name: ${device.platformName} | RSSI: ${rssi}dBm');
    
    // ✅ FIX: Store device for later explicit connect()
    _discoveredDevices[peerId] = device;
    
    // Emit peer discovered event
    _emitPeerDiscovered(peerId, rssi);
    
    // ✅ FIX: Only auto-connect if enabled (PairingManager can disable this)
    if (_autoConnectEnabled && _connectedDevice == null && !_isConnecting) {
      if (_peerId == null || _peerId != peerId) {
        dev.log('[BLE] 🔗 Auto-connecting to $peerId');
        _connectToDevice(device);
      }
    } else if (!_autoConnectEnabled) {
      dev.log('[BLE] ℹ️ Auto-connect disabled - waiting for explicit connect()');
    } else {
      dev.log('[BLE] ℹ️ Cannot connect: _connectedDevice=${_connectedDevice != null}, _isConnecting=$_isConnecting');
    }
  }
  
  Future<void> _connectToDevice(BluetoothDevice device) async {
    dev.log('[BLE] 🔗 Connection sequence started for ${device.remoteId}');
    
    _isConnecting = true; // Prevent concurrent attempts
    
    try {
      dev.log('[BLE] 📞 Initiating BLE connection (timeout: ${BleConstants.connectionTimeout})');
      await device.connect(timeout: BleConstants.connectionTimeout);
      _connectedDevice = device;
      dev.log('[BLE] ✅ BLE connection established');
      
      // Add small delay to ensure service cache is cleared on iOS
      await Future.delayed(Duration(milliseconds: 500));
      
      // Discover services
      dev.log('[BLE] 🔍 Discovering GATT services...');
      List<BluetoothService> services = await device.discoverServices();
      dev.log('[BLE] 📋 Found ${services.length} service(s)');
      
      // Find NoMatch service (check for CUSTOM Nomatch UUID first, then legacy)
      BluetoothService? nomatchService;
      bool hasNomatchService = false;
      for (var service in services) {
        final serviceUuidStr = service.uuid.toString().toLowerCase();
        dev.log('[BLE]   - Service: $serviceUuidStr');
        
        // Check for custom Nomatch UUID (550e8400-e29b-41d4-a716-446655440000)
        if (serviceUuidStr == BleConstants.nomatchServiceUUID.toLowerCase()) {
          nomatchService = service;
          hasNomatchService = true;
          dev.log('[BLE]   ✅ Nomatch service found (custom UUID)!');
          break;
        }
        // Fallback to legacy UUID for compatibility
        else if (serviceUuidStr == BleConstants.serviceUuid.toLowerCase()) {
          nomatchService = service;
          hasNomatchService = true; // Accept legacy service too
          dev.log('[BLE]   ✅ Legacy service found (0000fff0) - accepting for compatibility');
          break;
        }
      }
      
      // Check if this is a valid Nomatch device
      if (!hasNomatchService) {
        dev.log('[BLE] ❌ No valid P2P service found - disconnecting from non-Nomatch device');
        _connectedDevice = null;
        await device.disconnect();
        // ✅ FIX: Bayrak true kalırsa auto-connect kalıcı olarak kilitleniyordu.
        _isConnecting = false;
        _emitError('invalid_device', 'Device does not have P2P service');
        return;
      }
      
      dev.log('[BLE] ✅ P2P service confirmed');
      
      // Cancel previous characteristic subscriptions
      await _messageStreamSub?.cancel();
      await _sensorStreamSub?.cancel();
      await _connectionStateSub?.cancel();
      
      // Find characteristics
      dev.log('[BLE] 🔎 Looking for characteristics...');
      if (nomatchService != null) {
        for (var char in nomatchService.characteristics) {
          final charUuidStr = char.uuid.toString().toLowerCase();
          dev.log('[BLE]   - Characteristic: ${char.uuid}');
          
          // Check for CUSTOM Nomatch UUIDs (primary)
          if (charUuidStr == BleConstants.nomatchCharTxRx.toLowerCase()) {
            _messageChar = char;
            dev.log('[BLE]   ✅ Message characteristic found (Nomatch custom UUID)!');
            
            // Subscribe to notifications using onValueReceived for real-time updates
            await char.setNotifyValue(true);
            _messageStreamSub = char.onValueReceived.listen(_onMessageReceived);
            dev.log('[BLE]   ✅ Message notifications enabled (streaming mode)');
          }
          // Fallback to legacy UUID for compatibility
          else if (charUuidStr == BleConstants.messageCharUuid.toLowerCase()) {
            _messageChar = char;
            dev.log('[BLE]   ✅ Message characteristic found (legacy UUID)!');
            
            await char.setNotifyValue(true);
            _messageStreamSub = char.onValueReceived.listen(_onMessageReceived);
            dev.log('[BLE]   ✅ Message notifications enabled (streaming mode)');
          } 
          else if (charUuidStr == BleConstants.sensorCharUuid.toLowerCase()) {
            _sensorChar = char;
            dev.log('[BLE]   ✅ Sensor characteristic found!');
            await char.setNotifyValue(true);
            _sensorStreamSub = char.onValueReceived.listen((value) {
              dev.log('[BLE] 📡 Received sensor data: ${value.length} bytes');
            });
            dev.log('[BLE]   ✅ Sensor notifications enabled (streaming mode)');
          }
        }
      } else {
        dev.log('[BLE] ⚠️ Service characteristics not available, continuing without characteristic subscriptions');
      }
      
      // ⚠️ NOT: Buradaki isLeader yalnızca ÖN TAHMİNDİR ve güvenilir değildir
      // (myId native, peerId BLE peripheral UUID — farklı namespace'ler).
      // Gerçek lider seçimi PairingManager'da native↔native kimliklerle
      // yapılır ve bu değeri her iki modda da ezip geçer.
      final myId = _appInstanceId ?? '';
      final peerId = device.remoteId.toString();
      _peerId = peerId;
      final isLeader = myId.compareTo(peerId) < 0;
      
      dev.log('[BLE] ✅ ✅ ✅ CONNECTED ✅ ✅ ✅');
      dev.log('[BLE]   - Peer ID: $peerId');
      dev.log('[BLE]   - My ID: $myId');
      dev.log('[BLE]   - Comparison: "$myId".compareTo("$peerId") = ${myId.compareTo(peerId)}');
      dev.log('[BLE]   - Is Leader (myId < peerId)? ${myId.compareTo(peerId) < 0}');
      dev.log('[BLE]   - Role: ${isLeader ? 'LEADER' : 'FOLLOWER'}');
      dev.log('[BLE]   - Session ID: $_sessionId');
      
      // ✅ FIX: Stop scanning after successful connection — no need to discover more peers
      await _stopScanning();
      dev.log('[BLE] 🔍 Scanning stopped after successful connection');
      
      _emitConnected(peerId, isLeader);
      _isConnecting = false; // Connection succeeded, allow new attempts
      
      // Listen to disconnection
      _connectionStateSub = device.connectionState.listen((state) {
        dev.log('[BLE] Connection state changed: $state');
        if (state == BluetoothConnectionState.disconnected) {
          dev.log('[BLE] 🔌 Disconnected from $peerId');
          _onDisconnected(peerId);
        }
      });
      
    } catch (e) {
      dev.log('[BLE] ❌ Connection failed: $e');
      // ✅ FIX: Yarıda kalan bağlantının izleri temizlenmeli. _connectedDevice
      // dolu kalırsa sonraki tüm connect() çağrıları "zaten bağlı" sanılıp
      // sessizce atlanıyor ve eşleşme hard reset'e kadar kilitleniyordu.
      _connectedDevice = null;
      _messageChar = null;
      _sensorChar = null;
      _peerId = null;
      try {
        // Fiziksel link kurulmuş ama servis keşfi patlamış olabilir.
        await device.disconnect();
      } catch (_) {}
      _isConnecting = false; // Connection failed, allow retry
      _emitError('connection_failed', e.toString());
    }
  }
  
  Future<void> _disconnect() async {
    if (_connectedDevice == null) return;

    dev.log('BLE_P2P: Disconnecting');
    // ✅ FIX: Bu disconnect kasıtlı (stop/mod geçişi). Dinleyici iptal
    // edilmeden kapatılırsa PeerDisconnected event'i üretiliyor ve üst
    // katman normal mod geçişini "eşleşme başarısız" sanıyordu.
    await _connectionStateSub?.cancel();
    _connectionStateSub = null;
    try {
      await _connectedDevice!.disconnect();
    } catch (e) {
      dev.log('BLE_P2P: ⚠️ Error disconnecting: $e');
    }
    _connectedDevice = null;
    _messageChar = null;
    _sensorChar = null;
    _isConnecting = false;
  }
  
  void _onDisconnected(String peerId) {
    dev.log('BLE_P2P: Disconnected from $peerId');
    
    _connectedDevice = null;
    _messageChar = null;
    _sensorChar = null;
    
    _emitDisconnected(peerId, 'connection_lost');
  }
  
  // ✅ FIX: Parçalanmış (framed) mesajlar için birleştirme durumu.
  // Başlık: marker(1) + msgId(4) + index(2) + total(2) = 9 bayt.
  // JSON mesajlar '{' (0x7B) ile başladığı için 0x01 marker'ı çakışmaz.
  static const int _chunkMarker = 0x01;
  static const int _chunkHeaderSize = 9;
  int _chunkMsgIdCounter = 0;
  final Map<int, _ChunkBuffer> _chunkBuffers = {};

  /// Başlıklı bir parçayı tampona ekler; mesaj tamamlandıysa bütününü döndürür.
  List<int>? _addChunk(List<int> chunk) {
    final msgId = (chunk[1] << 24) | (chunk[2] << 16) | (chunk[3] << 8) | chunk[4];
    final index = (chunk[5] << 8) | chunk[6];
    final total = (chunk[7] << 8) | chunk[8];
    if (total == 0 || index >= total) return null;

    // Yarıda kopan aktarımların tamponları birikmesin.
    final now = DateTime.now();
    _chunkBuffers.removeWhere((_, b) => now.difference(b.createdAt).inSeconds > 15);

    final buf = _chunkBuffers.putIfAbsent(msgId, () => _ChunkBuffer(total));
    if (buf.total != total) {
      _chunkBuffers.remove(msgId); // tutarsız başlık — baştan başla
      return null;
    }
    buf.parts[index] = chunk.sublist(_chunkHeaderSize);
    if (buf.parts.length < buf.total) return null;

    _chunkBuffers.remove(msgId);
    final data = <int>[];
    for (var i = 0; i < total; i++) {
      final part = buf.parts[i];
      if (part == null) return null;
      data.addAll(part);
    }
    print('[BLE-RECV] 🧩 Reassembled $total chunks into ${data.length} bytes');
    return data;
  }

  /// ✅ OPTIMIZED: Process message in background isolate to avoid main thread blocking
  void _onMessageReceived(List<int> value) async {
    if (value.isEmpty) return;

    // ✅ FIX: Başlıklı parça ise birleştir; mesaj tamamlanana dek bekle.
    // Eskiden her parça ayrı JSON sanılıp çöpe gidiyordu — 509 baytı aşan
    // hiçbir mesaj (ör. uzun ShareOffer) karşıya ulaşamıyordu.
    if (value[0] == _chunkMarker && value.length > _chunkHeaderSize) {
      final complete = _addChunk(value);
      if (complete == null) return;
      value = complete;
    }

    final receiveTime = DateTime.now().millisecondsSinceEpoch;
    print('[BLE-RECV] ⏱️ Message received at $receiveTime (${value.length} bytes)');
    
    try {
      // ✅ Use compute() to parse JSON in background isolate
      final message = await compute(_parseMessageInIsolate, value);
      
      final processTime = DateTime.now().millisecondsSinceEpoch;
      print('[BLE-RECV] ⏱️ Message parsed at $processTime (took ${processTime - receiveTime}ms)');
      dev.log('BLE_P2P: Received ${message.runtimeType}');
      
      _emitMessageReceived(message);
    } catch (e) {
      dev.log('BLE_P2P: Failed to parse message: $e');
    }
  }
  
  Future<void> _sendChunked(List<int> data) async {
    print('[BLE-SEND] 📨 _sendChunked called with ${data.length} bytes');
    dev.log('[BLE-SEND] 📨 _sendChunked called with ${data.length} bytes');
    
    if (_messageChar == null) {
      print('[BLE-SEND] ❌ _messageChar is null! Cannot send');
      dev.log('[BLE-SEND] ❌ _messageChar is null! Cannot send');
      // ✅ FIX: Sessiz dönüş gönderimi "başarılı" gösteriyordu; eş zamanlı
      // disconnect'te üst katman kopukluğu fark edebilsin diye fırlat.
      throw Exception('send failed: not connected (characteristic lost)');
    }
    
    print('[BLE-SEND] ✅ _messageChar found: ${_messageChar?.uuid}');
    dev.log('[BLE-SEND] ✅ _messageChar found: ${_messageChar?.uuid}');
    
    // BLE has MTU limit, send in chunks
    const chunkSize = 512 - 3; // ATT header overhead

    // Tek yazmaya sığıyorsa başlıksız gönder (eski davranış, geriye uyumlu).
    if (data.length <= chunkSize) {
      await _messageChar!.write(data, withoutResponse: false);
      print('[BLE-SEND] ✅ Sent in single write (${data.length} bytes)');
      return;
    }

    // ✅ FIX: Uzun mesajlar başlıklı parçalara bölünür (alıcı _addChunk ile
    // birleştirir). Eskiden başlıksız bölünüyor ve karşıda her parça ayrı
    // JSON sanılıp atılıyordu — uzun mesajlar hiç iletilemiyordu.
    const payloadSize = chunkSize - _chunkHeaderSize;
    final msgId = (_chunkMsgIdCounter++) & 0xFFFFFFFF;
    final total = (data.length + payloadSize - 1) ~/ payloadSize;

    for (int index = 0; index < total; index++) {
      final start = index * payloadSize;
      final end = (start + payloadSize < data.length) ? start + payloadSize : data.length;
      final chunk = <int>[
        _chunkMarker,
        (msgId >> 24) & 0xFF, (msgId >> 16) & 0xFF, (msgId >> 8) & 0xFF, msgId & 0xFF,
        (index >> 8) & 0xFF, index & 0xFF,
        (total >> 8) & 0xFF, total & 0xFF,
        ...data.sublist(start, end),
      ];

      try {
        print('[BLE-SEND] 📤 Writing chunk ${index + 1}/$total (${chunk.length} bytes)');
        await _messageChar!.write(chunk, withoutResponse: false);
      } catch (e) {
        print('[BLE-SEND] ❌ Chunk write failed: $e');
        dev.log('[BLE-SEND] ❌ Chunk write failed: $e');
        rethrow;
      }
    }

    print('[BLE-SEND] ✅ All $total chunks sent!');
    dev.log('[BLE-SEND] ✅ All $total chunks sent!');
  }
  
  Future<bool> _requestPermissions() async {
    // iOS: Bluetooth permissions are automatically granted if declared in Info.plist
    // Android: Request runtime permissions
    
    // Try requesting; if it fails or is not supported (iOS), continue anyway
    try {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.location, // Required for BLE scan on Android
      ].request();
      
      // On iOS, these might return undetermined/denied, but app can still work
      // because iOS grants Bluetooth access automatically if declared in Info.plist
      final allGrantedOrUndetermined = statuses.values.every((status) =>
          status.isGranted || status.isDenied); // isDenied might happen on iOS
      
      dev.log('BLE_P2P: Permission statuses: $statuses');
      return true; // Proceed even if permission status is unclear
    } catch (e) {
      dev.log('BLE_P2P: Permission request error (might be iOS): $e');
      return true; // Assume permission is OK (iOS with Info.plist entry)
    }
  }
  
  String _generateSessionId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
  
  // ============================================================================
  // Event Emission
  // ============================================================================
  
  void _emitStateChanged(String state) {
    final p2pState = _parseState(state);
    _eventController.add(P2pStateChanged(state: p2pState, sessionId: _sessionId));
  }
  
  void _emitPeerDiscovered(String peerId, int rssi) {
    _eventController.add(PeerDiscovered(peerId: peerId, rssi: rssi, meta: const {}));
  }
  
  void _emitConnected(String peerId, bool isLeader) {
    _eventController.add(PeerConnected(
      sessionId: _sessionId ?? '',
      peerId: peerId,
      isLeader: isLeader,
    ));
  }
  
  void _emitDisconnected(String peerId, String reason) {
    _eventController.add(PeerDisconnected(
      sessionId: _sessionId,
      peerId: peerId,
      reason: DisconnectReason.transportLost,
    ));
  }
  
  void _emitMessageReceived(P2pMessage message) {
    _eventController.add(MessageReceived(
      sessionId: _sessionId ?? '',
      fromPeerId: _peerId ?? '',
      message: message,
    ));
  }
  
  void _emitError(String code, String message) {
    _eventController.add(P2pErrorEvent(
      code: P2pErrorCode.internal,
      message: message,
      details: {'code': code},
    ));
  }
  
  P2pState _parseState(String state) {
    switch (state) {
      case 'idle':
        return P2pState.idle;
      case 'discovering':
        return P2pState.discovering;
      case 'hosting':
        return P2pState.hosting;
      case 'connecting':
        return P2pState.connecting;
      case 'connected':
        return P2pState.connected;
      default:
        return P2pState.idle;
    }
  }
}

/// ✅ TOP-LEVEL FUNCTION: Parse BLE message in background isolate
/// Must be top-level for compute() to work
P2pMessage _parseMessageInIsolate(List<int> bytes) {
  final jsonString = utf8.decode(bytes);
  final codec = P2pCodec();
  return codec.decode(jsonString);
}

/// Parçalanmış bir mesajın birleştirme tamponu (bkz. _addChunk).
class _ChunkBuffer {
  final int total;
  final Map<int, List<int>> parts = {};
  final DateTime createdAt = DateTime.now();

  _ChunkBuffer(this.total);
}
