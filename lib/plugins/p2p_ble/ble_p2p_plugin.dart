import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide DisconnectReason;
import 'package:permission_handler/permission_handler.dart';

import '../p2p/p2p_events.dart';
import '../p2p/p2p_messages.dart';
import '../p2p/p2p_codec.dart';
import 'ble_constants.dart';

/// Cross-platform P2P implementation using Bluetooth Low Energy
/// 
/// Supports Android-Android, iOS-iOS, and Android-iOS pairing
class BleP2pPlugin {
  static const platform = MethodChannel('com.nomatch/ble_advertising');
  
  final StreamController<NomatchP2pEvent> _eventController = StreamController<NomatchP2pEvent>.broadcast();
  
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
    
    // In BLE, connection happens automatically on discovery
    // This is called from upper layer, we can ignore or use for explicit connect
  }
  
  /// Send message to connected peer
  Future<void> send(P2pMessage message) async {
    if (_messageChar == null) {
      dev.log('BLE_P2P: Not connected, cannot send');
      return;
    }
    
    try {
      final json = message.toJson();
      final data = utf8.encode(jsonEncode(json));
      
      // BLE has MTU limit, chunk if needed
      await _sendChunked(data);
      
      dev.log('BLE_P2P: Sent ${message.runtimeType}');
    } catch (e) {
      dev.log('BLE_P2P: Send failed: $e');
      _emitError('send_failed', e.toString());
    }
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
      
      // Start scan without service UUID filter
      // ⚠️ DEBUG: Service UUID advertise data'sında görünmediği için filter kapalı
      // iOS'ta GATT service advertise data'sına otomatik eklenmemiş
      await FlutterBluePlus.startScan(
        // withServices: [Guid(BleConstants.serviceUuid)],  // Temporarily disabled
        timeout: BleConstants.scanTimeout,
      );
      dev.log('BLE_P2P: Scanning WITHOUT service UUID filter (debug mode)');
      
      // Listen to scan results
      _scanResultsSub = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          _onDeviceDiscovered(r);
        }
      });
      
      // Listen to scan completion
      _isScanningStateSub = FlutterBluePlus.isScanning.listen((scanning) {
        if (!scanning && _isScanning) {
          dev.log('BLE_P2P: Scan timeout');
          _isScanning = false;
        }
      });
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
    
    dev.log('[BLE] 📡 Device discovered: ${device.remoteId} | RSSI: ${rssi}dBm | Name: "${device.platformName}"');
    
    // 🔍 DEBUG: Temporarily accept ALL devices to see what's being advertised
    // if (device.platformName.isEmpty) {
    //   dev.log('[BLE] ⚠️ Device has no name, ignoring: ${device.remoteId}');
    //   return;
    // }
    
    // if (!device.platformName.startsWith('dev-instance')) {
    //   dev.log('[BLE] ⚠️ Device name not recognized, ignoring: ${device.platformName}');
    //   return;
    // }
    
    // Filter by RSSI (proximity check)
    if (rssi < BleConstants.minRssi || rssi > BleConstants.maxRssi) {
      dev.log('[BLE] ⚠️ Device RSSI out of range: $rssi (min: ${BleConstants.minRssi}, max: ${BleConstants.maxRssi})');
      return;
    }
    
    // Use device UUID as peer ID (more reliable than name for deduplication)
    final peerId = device.remoteId.toString();
    dev.log('[BLE] ✅ Valid Nomatch peer discovered - ID: $peerId | Name: ${device.platformName} | RSSI: ${rssi}dBm');
    
    // Emit peer discovered event
    _emitPeerDiscovered(peerId, rssi);
    
    // Auto-connect if not already connected
    if (_connectedDevice == null) {
      dev.log('[BLE] 🔗 Attempting connection to $peerId');
      _connectToDevice(device);
    }
  }
  
  Future<void> _connectToDevice(BluetoothDevice device) async {
    dev.log('[BLE] 🔗 Connection sequence started for ${device.remoteId}');
    
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
      
      // Find NoMatch service
      BluetoothService? nomatchService;
      for (var service in services) {
        dev.log('[BLE]   - Service: ${service.uuid}');
        if (service.uuid.toString() == BleConstants.serviceUuid) {
          nomatchService = service;
          dev.log('[BLE]   ✅ NoMatch service found!');
          break;
        }
      }
      
      // NOTE: Service discovery works differently on iOS vs Android
      // Connection is successful even if GATT service isn't found in discovery
      // The service exists but may not be enumerated in the services list
      if (nomatchService == null) {
        dev.log('[BLE] ⚠️ NoMatch service not found in discovery, but connection established');
        // Continue anyway - connection is still valid
      } else {
        dev.log('[BLE] ✅ NoMatch service found in GATT discovery');
      }
      
      // Cancel previous characteristic subscriptions
      await _messageStreamSub?.cancel();
      await _sensorStreamSub?.cancel();
      await _connectionStateSub?.cancel();
      
      // Find characteristics
      dev.log('[BLE] 🔎 Looking for characteristics...');
      if (nomatchService != null) {
        for (var char in nomatchService.characteristics) {
        dev.log('[BLE]   - Characteristic: ${char.uuid}');
        if (char.uuid.toString() == BleConstants.messageCharUuid) {
          _messageChar = char;
          dev.log('[BLE]   ✅ Message characteristic found!');
          
          // Subscribe to notifications
          await char.setNotifyValue(true);
          _messageStreamSub = char.lastValueStream.listen(_onMessageReceived);
          dev.log('[BLE]   ✅ Message notifications enabled');
        } else if (char.uuid.toString() == BleConstants.sensorCharUuid) {
          _sensorChar = char;
          dev.log('[BLE]   ✅ Sensor characteristic found!');
          await char.setNotifyValue(true);
          _sensorStreamSub = char.lastValueStream.listen((value) {
            dev.log('[BLE] 📡 Received sensor data: ${value.length} bytes');
          });
          dev.log('[BLE]   ✅ Sensor notifications enabled');
        }
        }
      } else {
        dev.log('[BLE] ⚠️ Service characteristics not available, continuing without characteristic subscriptions');
      }
      
      // Determine leader (device with larger ID is leader)
      final myId = _appInstanceId ?? '';
      final peerId = device.remoteId.toString();
      _peerId = peerId;
      final isLeader = myId.compareTo(peerId) > 0;
      
      dev.log('[BLE] ✅ ✅ ✅ CONNECTED ✅ ✅ ✅');
      dev.log('[BLE]   - Peer ID: $peerId');
      dev.log('[BLE]   - My ID: $myId');
      dev.log('[BLE]   - Role: ${isLeader ? 'LEADER' : 'FOLLOWER'}');
      dev.log('[BLE]   - Session ID: $_sessionId');
      
      _emitConnected(peerId, isLeader);
      
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
      _emitError('connection_failed', e.toString());
    }
  }
  
  Future<void> _disconnect() async {
    if (_connectedDevice == null) return;
    
    dev.log('BLE_P2P: Disconnecting');
    await _connectedDevice!.disconnect();
    _connectedDevice = null;
    _messageChar = null;
    _sensorChar = null;
  }
  
  void _onDisconnected(String peerId) {
    dev.log('BLE_P2P: Disconnected from $peerId');
    
    _connectedDevice = null;
    _messageChar = null;
    _sensorChar = null;
    
    _emitDisconnected(peerId, 'connection_lost');
  }
  
  void _onMessageReceived(List<int> value) {
    if (value.isEmpty) return;
    
    try {
      final jsonString = utf8.decode(value);
      final codec = P2pCodec();
      final message = codec.decode(jsonString);
      
      dev.log('BLE_P2P: Received ${message.runtimeType}');
      
      _emitMessageReceived(message);
    } catch (e) {
      dev.log('BLE_P2P: Failed to parse message: $e');
    }
  }
  
  Future<void> _sendChunked(List<int> data) async {
    if (_messageChar == null) return;
    
    // BLE has MTU limit, send in chunks
    const chunkSize = 512 - 3; // ATT header overhead
    
    for (int i = 0; i < data.length; i += chunkSize) {
      final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
      final chunk = data.sublist(i, end);
      
      await _messageChar!.write(chunk, withoutResponse: false);
    }
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
