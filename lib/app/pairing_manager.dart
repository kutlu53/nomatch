import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'pairing_logic.dart';
import 'heading_validator.dart';
import '../plugins/p2p_ble/ble_p2p_plugin.dart';
import '../plugins/p2p_ble/ble_constants.dart';
import '../plugins/p2p/p2p_events.dart';
import '../plugins/p2p/p2p_messages.dart';
import '../features/game/game_engine.dart';
import '../features/game/game_state.dart';
import '../features/game/lazy_question_provider.dart';

/// Peer information for radar display
final class PeerInfo {
  final String id;
  final int rssi;
  final double? heading;
  final bool isConnecting;
  final bool isConnected;
  
  const PeerInfo({
    required this.id,
    required this.rssi,
    this.heading,
    this.isConnecting = false,
    this.isConnected = false,
  });
}

/// Main pairing coordinator
class PairingManager {
  final BleP2pPlugin blePlugin;
  final String deviceId; // Unique device ID
  final LazyQuestionProvider questions;
  
  late HeadingValidator headingValidator;
  
  PairingState _state = PairingState.idle;
  PairingState get state => _state;
  
  // Current pairing attempt
  String? _peerId;
  String? _sessionId;
  String? _peerNativeDeviceId; // ✅ NEW: Peer's native device UUID
  bool _isLeader = false;
  double? _peerHeading;
  double? _ourHeading;

  // Streams
  final _stateController = StreamController<PairingState>.broadcast();
  Stream<PairingState> get stateUpdates => _stateController.stream;
  
  // Game engine
  GameEngine? _gameEngine;
  GameEngine? get gameEngine => _gameEngine;
  final _gameStateController = StreamController<GameState>.broadcast();
  Stream<GameState> get gameStateUpdates => _gameStateController.stream;
  
  Timer? _gameTicker;
  bool _shareScreenPushed = false; // ✅ NEW: Prevent duplicate share screen pushes

  // Timers
  Timer? _headingValidationTimer;
  Timer? _connectionTimeout;
  
  // BLE event subscription
  StreamSubscription? _bleEventsSub;
  StreamSubscription? _gameEngineSubscription;
  StreamSubscription? _headingSubscription; // ✅ NEW: Track heading subscription

  PairingManager({
    required this.blePlugin,
    required this.deviceId,
    required this.questions,
  }) {
    headingValidator = HeadingValidator();
    _listenToBleEvents();
  }
  
  /// Listen to BLE plugin events
  void _listenToBleEvents() {
    _bleEventsSub = blePlugin.events.listen((event) {
      print('[TEST-CONN] 📡 BLE event: ${event.runtimeType}');
      
      if (event is PeerDiscovered) {
        print('[TEST-CONN] 📡 Peer discovered: ${event.peerId}, rssi=${event.rssi}');
        handlePeerDiscovered(event.peerId, event.rssi);
      } else if (event is PeerConnected) {
        print('[TEST-CONN] ✅ PeerConnected event received: ${event.peerId}');
        handlePeerConnected(event.sessionId, event.peerId, event.isLeader);
      } else if (event is PeerDisconnected) {
        print('[TEST-CONN] 🔌 PeerDisconnected: ${event.peerId}');
        handlePeerDisconnected();
      } else if (event is MessageReceived) {
        print('[TEST-CONN] 📨 Message received: ${event.message.runtimeType}');
        _handleMessageReceived(event.message);
      }
    });
  }

  // Nomatch-specific UUIDs
  static const String NOMATCH_SERVICE_UUID = '550e8400-e29b-41d4-a716-446655440000';
  static const String NOMATCH_CHAR_TX_RX = '550e8400-e29b-41d4-a716-446655440001';
  static const String NOMATCH_CHAR_CONTROL = '550e8400-e29b-41d4-a716-446655440002';

  /// Start pairing process
  Future<PairingResult> start({
    required bool isPhoneFlat,
  }) async {
    print('[TEST-CONN] 🚀 Starting pairing (isFlat: $isPhoneFlat)');
    
    // Allow pairing only if phone is roughly flat (with tolerance)
    if (!isPhoneFlat) {
      print('[PAIR] ⚠️ Phone not flat enough, waiting...');
      return PairingResult(
        success: false,
        errorReason: 'phone_not_flat',
      );
    }

    try {
      // Reset state from previous attempts
      _reset();
      
      // 1. Start heading validator
      await headingValidator.start();
      _setState(PairingState.hostingReady);

      // 2. Start BLE hosting and discovery with Nomatch-specific UUID
      print('[PAIR] 📡 Starting BLE hosting with Nomatch UUID...');
      await blePlugin.startHosting(displayNameHash: deviceId);
      
      // iOS'ta explicit advertising başlat (native method channel üzerinden)
      print('[PAIR] 📡 Triggering iOS BLE advertising...');
      try {
        const bleChannel = MethodChannel('com.nomatch/ble_advertising');
        await bleChannel.invokeMethod('startAdvertising', {
          'serviceUuid': BleConstants.nomatchServiceUUID,
          'deviceName': 'nomatch-device',
        });
        print('[PAIR] ✅ iOS advertising initiated');
      } catch (e) {
        print('[PAIR] ⚠️ iOS advertising trigger failed: $e');
      }
      
      await blePlugin.startDiscovery();
      print('[PAIR] ✅ Hosting started, waiting for peers...');

      _setState(PairingState.peerSearching);
      
      return PairingResult(success: true);
    } catch (e, st) {
      print('[PAIR] ❌ Start failed: $e');
      print('[PAIR] ❌ Stack trace: $st');
      print('[TEST-CONN] ❌ Exception: ${e.runtimeType}');
      return PairingResult(
        success: false,
        errorReason: 'start_failed: $e',
      );
    }
  }

  /// Handle peer discovered (BLE)
  void handlePeerDiscovered(String peerId, int rssi) {
    print('[TEST-CONN] 📡 Peer discovered: peerId=$peerId, rssi=$rssi');
    print('[PEER] 📡 Peer discovered: $peerId (RSSI: $rssi dBm)');
    
    // Ignore self (don't connect to own device)
    if (peerId == deviceId) {
      print('[PEER] ⚠️ Ignoring self-advertisement, skipping');
      return;
    }
    
    // Only connect if signal is strong enough (RSSI > -80 dBm)
    if (rssi < -80) {
      print('[PEER] ⚠️ Signal too weak, skipping');
      return;
    }

    // Only connect to FIRST peer discovered (ignore others)
    if (_peerId != null) {
      print('[PEER] ⚠️ Already connecting to $_peerId, ignoring new peer: $peerId');
      return;
    }

    // Try to connect to first peer
    _peerId = peerId;
    print('[PAIR] 🔗 Connecting to peer: $peerId');
    blePlugin.connect(peerId: peerId);

    // Start connection timeout (10 seconds)
    _connectionTimeout?.cancel();
    _connectionTimeout = Timer(const Duration(seconds: 10), () {
      print('[PAIR] ⏱️ Connection timeout');
      _reset();
    });
  }

  /// Handle peer connected (BLE)
  void handlePeerConnected(String sessionId, String peerId, bool isLeader) {
    print('[TEST-CONN] ✅ CONNECTED to $peerId (role=${isLeader ? 'LEADER' : 'FOLLOWER'})');
    
    // Ignore if peer doesn't match what we discovered
    // (this prevents connecting to wrong devices)
    if (_peerId != null && _peerId != peerId) {
      print('[CONN] ⚠️ Ignoring mismatched peer connection. Expected: $_peerId, Got: $peerId');
      return;
    }
    
    // Ignore duplicate connections (idempotency)
    if (_sessionId == sessionId && _peerId == peerId && _state == PairingState.preConnected) {
      print('[CONN] ⚠️ Ignoring duplicate peer connection event');
      return;
    }
    
    print('[CONN] ✅ PEER CONNECTED!');
    print('[CONN]   Session: $sessionId');
    print('[CONN]   Peer: $peerId');
    print('[CONN]   Role: ${isLeader ? 'LEADER' : 'FOLLOWER'}');

    // ✅ Cancel connection timeout since peer connected successfully
    _connectionTimeout?.cancel();
    _connectionTimeout = null;

    _sessionId = sessionId;
    _peerId = peerId;
    _isLeader = isLeader;
    _setState(PairingState.preConnected);

    // Start heading validation
    _startHeadingValidation();
  }

  // ✅ Throttle heading messages to avoid BLE overload
  DateTime? _lastHeadingSentTime;
  static const _headingSendInterval = Duration(milliseconds: 500); // Send max 2x per second
  
  /// Start heading validation phase
  void _startHeadingValidation() {
    print('[CONN] 🧭 Starting heading validation (3 seconds)');
    _setState(PairingState.headingValidating);

    // ✅ NEW: Cancel existing heading subscription if any
    _headingSubscription?.cancel();
    _lastHeadingSentTime = null; // Reset throttle
    
    // Listen to heading updates and send them via P2P (throttled)
    _headingSubscription = headingValidator.headingUpdates.listen((heading) {
      _updateOurHeading(heading);
      
      // Send heading to peer via P2P message (throttled to avoid BLE overload)
      if (_peerId != null && _sessionId != null) {
        final now = DateTime.now();
        if (_lastHeadingSentTime == null || 
            now.difference(_lastHeadingSentTime!) >= _headingSendInterval) {
          _lastHeadingSentTime = now;
          _sendHeadingMessage(heading);
        }
      }
    });

    _headingValidationTimer?.cancel();
    print('[CONN] ⏱️ Setting 3-second timer for heading validation');
    _headingValidationTimer = Timer(const Duration(seconds: 3), () {
      print('[CONN] ⏰ Heading validation timer fired!');
      _completeHeadingValidation();
    });
    print('[CONN] ⏱️ Timer set');
  }
  
  /// Send heading via P2P message
  Future<void> _sendHeadingMessage(double heading) async {
    try {
      if (_sessionId == null) {
        print('[CONN] ⚠️ No session ID yet, skipping send');
        return;
      }
      
      final message = SensorSnapshotMessage(
        sid: _sessionId!,
        isFlat: true, // Assume flat during pairing
        headingDeg: heading,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        mid: null,
        nativeDeviceId: deviceId, // ✅ NEW: Send our native device ID
      );
      
      print('[CONN] 📤 Sending heading ${heading.toStringAsFixed(1)}° to peer');
      await blePlugin.send(message);
      print('[CONN] ✅ Heading sent successfully');
    } catch (e) {
      print('[CONN] ❌ Failed to send heading: $e');
    }
  }

  /// Receive peer heading (from P2P message)
  void receivePeerHeading(double heading) {
    // print('[HEADING] 📨 Received peer heading: ${heading.toStringAsFixed(1)}°');
    _peerHeading = heading;
  }
  
  /// Update our heading
  void _updateOurHeading(double heading) {
    _ourHeading = heading;
    // print('[HEADING] 🧭 Our heading: ${heading.toStringAsFixed(1)}°');
  }

  // ✅ NEW: Retry counter for heading validation
  int _headingValidationRetries = 0;
  static const int _maxHeadingRetries = 3;
  
  /// Complete heading validation
  Future<void> _completeHeadingValidation() async {
    print('[CONN] ✓ Heading validation period complete');
    
    print('[CONN] 📊 DEBUG: ourHeading=$_ourHeading, peerHeading=$_peerHeading');
    
    // Check if heading data received from peer
    if (_ourHeading == null || _peerHeading == null) {
      print('[CONN] ❌ Heading validation failed (missing data)');
      print('[CONN]   └─ Our heading: ${_ourHeading?.toStringAsFixed(1) ?? "null"}°');
      print('[CONN]   └─ Peer heading: ${_peerHeading?.toStringAsFixed(1) ?? "null"}°');
      await _retryOrFailHeadingValidation('heading_missing');
      return;
    }

    // Check if facing each other
    final facing = HeadingValidation.isFacingEachOther(
      _ourHeading!,
      _peerHeading!,
    );
    final diff = HeadingValidation.getAngleDifference(
      _ourHeading!,
      _peerHeading!,
    );

    print('[CONN] 📐 Heading difference: ${diff.toStringAsFixed(1)}° (need 150°-210° for face-to-face)');
    if (facing) {
      print('[CONN] ✅ Face-to-face validation: PASSED');
    } else {
      print('[CONN] ❌ Face-to-face validation: FAILED (diff=${diff.toStringAsFixed(1)}°, need ~180°)');
    }

    if (!facing) {
      await _retryOrFailHeadingValidation('not_facing');
      return;
    }
    
    // ✅ Success: Stop heading subscription and reset retry counter
    _headingSubscription?.cancel();
    _headingSubscription = null;
    _headingValidationRetries = 0;
    print('[CONN] 🛑 Heading subscription stopped');

    // ✅ NEW: Determine leader using native device IDs (if available)
    if (_peerNativeDeviceId != null) {
      _isLeader = LeaderAlgorithm.selectLeader(deviceId, _peerNativeDeviceId!);
      print('[CONN] 👑 Leader elected: ${_isLeader ? 'THIS DEVICE' : 'PEER DEVICE'} (using native UUIDs)');
    } else {
      // Fallback to BLE IDs if peer native ID not yet received
      _isLeader = LeaderAlgorithm.selectLeader(deviceId, _peerId!);
      print('[CONN] 👑 Leader elected: ${_isLeader ? 'THIS DEVICE' : 'PEER DEVICE'} (fallback to BLE IDs)');
    }

    _setState(PairingState.connected);
    print('[CONN] ✅✅✅ PAIRING SUCCESS ✅✅✅');
  }

  /// ✅ NEW: Retry heading validation or fail after max retries
  Future<void> _retryOrFailHeadingValidation(String reason) async {
    _headingValidationRetries++;
    print('[CONN] ⚠️ Heading validation attempt $_headingValidationRetries/$_maxHeadingRetries failed: $reason');
    
    if (_headingValidationRetries >= _maxHeadingRetries) {
      print('[CONN] ❌ Max heading validation retries reached, failing pairing');
      _headingSubscription?.cancel();
      _headingSubscription = null;
      _headingValidationRetries = 0;
      await _failPairing(reason);
      return;
    }
    
    // ✅ Retry: Clear heading data and restart validation (keep connection!)
    print('[CONN] 🔄 Retrying heading validation (attempt ${_headingValidationRetries + 1})...');
    _ourHeading = null;
    _peerHeading = null;
    
    // Restart heading validation timer (keep subscription active)
    _headingValidationTimer?.cancel();
    _headingValidationTimer = Timer(const Duration(seconds: 3), () {
      print('[CONN] ⏰ Heading validation retry timer fired!');
      _completeHeadingValidation();
    });
  }

  /// Handle peer disconnected
  void handlePeerDisconnected() {
    print('[DISC] 🔌 Peer disconnected');
    _reset();
  }

  // ✅ Track if game is already prepared
  bool _gamePreparationDone = false;
  
  /// Prepare game - called IMMEDIATELY when pairing succeeds (during animation)
  /// This initializes the engine and preloads questions in the background
  Future<void> prepareGame() async {
    if (_gamePreparationDone) {
      print('[GAME] ⚠️ Game already prepared, skipping');
      return;
    }
    
    print('[GAME] 🎮 Preparing game (background)...');
    print('[GAME] 🎮 _sessionId=$_sessionId, _peerId=$_peerId');
    
    // Cancel any pending timeouts
    _connectionTimeout?.cancel();
    _connectionTimeout = null;
    // Stop heading validation
    _headingValidationTimer?.cancel();
    // Stop compass
    await headingValidator.stop();
    
    // Initialize game engine (heavy work - done during animation)
    if (_sessionId != null && _peerId != null) {
      await _initializeGameEngine(
        sessionId: _sessionId!,
        peerId: _peerId!,
      );
      _gamePreparationDone = true;
      print('[GAME] ✅ Game preparation complete (background)');
    } else {
      print('[GAME] ❌ Cannot prepare game: _sessionId or _peerId is null!');
    }
  }
  
  /// Show game - called when animation completes
  /// This starts the ticker and transitions to game screen
  Future<void> showGame() async {
    print('[GAME] 🎮 Showing game...');
    
    // If not prepared yet, prepare now (fallback)
    if (!_gamePreparationDone) {
      print('[GAME] ⚠️ Game not prepared, preparing now...');
      await prepareGame();
    }
    
    // Start game ticker (30 FPS - optimized to reduce main thread load)
    if (_gameEngine != null) {
      print('[GAME] 🎮 Starting ticker (30 FPS)...');
      int tickCount = 0;
      _gameTicker = Timer.periodic(const Duration(milliseconds: 33), (_) {
        tickCount++;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (tickCount <= 5 || tickCount % 30 == 0) {
          dev.log('[GAME-TICK] tick #$tickCount, now=$now');
        }
        _gameEngine?.onTick(now);
        
        // ✅ Stop ticker when game is terminal
        if (_gameEngine?.isGameTerminal ?? false) {
          print('[GAME] 🎮 Game terminal detected - stopping ticker');
          _gameTicker?.cancel();
          _gameTicker = null;
        }
      });
      print('[GAME] 🎮 Ticker started!');
    }
    
    // Transition to game phase
    _setState(PairingState.game);
    print('[GAME] ✅ Game phase started');
  }
  
  /// Start game - legacy method for backwards compatibility
  Future<void> startGame() async {
    await prepareGame();
    await showGame();
  }
  
  /// Initialize game engine
  Future<void> _initializeGameEngine({
    required String sessionId,
    required String peerId,
  }) async {
    print('[GAME] 🎮 Initializing game engine...');
    print('[GAME] 🎮 Questions provider: ${questions != null ? "LOADED" : "NULL"}');
    
    // ✅ NEW: Preload questions before starting game
    if (questions != null) {
      print('[GAME] 📚 Preloading questions...');
      await questions!.preload();
      print('[GAME] ✅ Questions preloaded');
    }
    
    // Dispose old engine if exists
    _gameEngineSubscription?.cancel();
    _gameEngineSubscription = null;
    _gameEngine = null;
    
    // Create transport for P2P messages
    final transport = _PairingManagerTransport(blePlugin);
    
    // Create engine
    _gameEngine = GameEngine(
      transport: transport,
      isLeader: _isLeader,
      externalRoundControl: false, // ✅ FIX: Allow engine to start rounds automatically
      sessionId: sessionId,
      localDeviceId: deviceId,
      questions: questions,
    );
    
    // ✅ FIXED: Connect peer (await reshuffle completion)
    await _gameEngine!.onPeerConnected(peerId: peerId);
    
    // Subscribe to game state updates
    _gameEngineSubscription = _gameEngine!.states.listen((gameState) {
      _gameStateController.add(gameState);
      print('[GAME] 🎮 Game state: ${gameState.phase}');
    });
    
    print('[GAME] ✅ Game engine initialized');
  }

  /// Fail pairing
  Future<void> _failPairing(String reason) async {
    print('[PAIR] ❌ Pairing failed: $reason');
    _setState(PairingState.failed);
    await Future.delayed(const Duration(milliseconds: 500));
    _reset();
    _setState(PairingState.peerSearching);
  }

  /// Stop pairing (pause, not permanent cleanup)
  Future<void> stop() async {
    print('[PAIR] 🛑 Stopping pairing');
    await headingValidator.stop();
    await blePlugin.stop();
    _disposeGameEngine(); // ✅ Dispose game engine to clear all state
    _reset();
    _setState(PairingState.idle);
  }

  /// Dispose game engine completely
  void _disposeGameEngine() {
    _gameEngineSubscription?.cancel();
    _gameEngineSubscription = null;
    _gameEngine = null;
    print('[PAIR] 🎮 Game engine disposed');
  }
  
  /// Reset state
  void _reset() {
    _headingValidationTimer?.cancel();
    _connectionTimeout?.cancel();
    _gameTicker?.cancel();
    _gameTicker = null;
    _headingSubscription?.cancel(); // ✅ NEW: Cancel heading subscription
    _peerId = null;
    _sessionId = null;
    _peerNativeDeviceId = null; // ✅ NEW: Reset peer native device ID
    _ourHeading = null;
    _peerHeading = null;
    _isLeader = false;
    _shareScreenPushed = false; // ✅ FIX: Reset share screen flag for next game
    _gamePreparationDone = false; // ✅ FIX: Reset game preparation flag for next game
    _headingValidationRetries = 0; // ✅ FIX: Reset heading validation retries
    print('[PAIR] 🔄 State reset complete');
  }
  
  /// Handle top card tap
  void onLocalTapTop() {
    _gameEngine?.onLocalTapTop();
  }
  
  /// Handle bottom card tap
  void onLocalTapBottom() {
    _gameEngine?.onLocalTapBottom();
  }
  
  /// Handle P2P messages for game
  void _handleGameMessage(P2pMessage message) {
    _gameEngine?.onP2pMessage(message);
  }

  /// Update state and notify
  void _setState(PairingState state) {
    _state = state;
    _stateController.add(state);
    print('[STATE] State changed to: $state');
    dev.log('[PAIR] State: $state');
  }

  /// Handle received P2P message
  void _handleMessageReceived(P2pMessage message) {
    if (message is SensorSnapshotMessage) {
      print('[CONN] 📨 P2P message received: heading=${message.headingDeg.toStringAsFixed(1)}°');
      if (message.nativeDeviceId != null) {
        _peerNativeDeviceId = message.nativeDeviceId; // ✅ NEW: Store peer's native device ID
        print('[CONN] 📱 Peer native device ID: $_peerNativeDeviceId');
      }
      receivePeerHeading(message.headingDeg);
    } else if (_state == PairingState.game) {
      // Route game messages to engine
      _handleGameMessage(message);
    }
  }

  /// Get pairing result
  PairingResult getResult() {
    if (_state != PairingState.connected) {
      return PairingResult(success: false, errorReason: 'not_connected');
    }

    return PairingResult(
      success: true,
      peerId: _peerId,
      sessionId: _sessionId,
      isLeader: _isLeader,
    );
  }

  /// Cleanup
  Future<void> dispose() async {
    print('[PAIR] 🛑 Cleaning up pairing manager');
    _headingValidationTimer?.cancel();
    _connectionTimeout?.cancel();
    _gameTicker?.cancel();
    _gameEngineSubscription?.cancel();
    _bleEventsSub?.cancel();
    await headingValidator.dispose();
    await _stateController.close();
    await _gameStateController.close();
  }
}

/// Transport implementation for game engine
class _PairingManagerTransport implements GameTransport {
  final BleP2pPlugin plugin;

  _PairingManagerTransport(this.plugin);

  @override
  Future<void> send(P2pMessage msg) => plugin.send(msg);
}
