import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../features/game/game_engine.dart';
import '../features/game/game_state.dart';
import '../features/game/lazy_question_provider.dart';
import '../features/game/question_bank.dart';
import '../features/pairing/flashlight_signal.dart';
import '../features/pairing/pairing_validator.dart' show PeerInfo;
import '../features/pairing/sensor_manager_v2.dart';
import '../models/orientation_vector_sample.dart';
import '../services/robust_face_to_face_detector.dart';
import '../plugins/p2p/p2p_events.dart';
import '../plugins/p2p/p2p_messages.dart';
import '../plugins/p2p_ble/ble_p2p_plugin.dart';
import 'app_phase.dart';

/// Pending share offer
final class PendingShare {
  final ShareKind? kind;
  final String text;

  const PendingShare({required this.kind, required this.text});
  const PendingShare.empty() : this(kind: null, text: '');

  PendingShare copyWith({ShareKind? kind, String? text, bool clearKind = false}) {
    return PendingShare(
      kind: clearKind ? null : (kind ?? this.kind),
      text: text ?? this.text,
    );
  }

  @override
  bool operator ==(Object other) => other is PendingShare && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);
}

/// Incoming share offer
final class IncomingShareOffer {
  final String offerId;
  final String kind; // "phone"|"social"
  final String value;
  final String fromPeerId;

  const IncomingShareOffer({
    required this.offerId,
    required this.kind,
    required this.value,
    required this.fromPeerId,
  });

  @override
  bool operator ==(Object other) {
    return other is IncomingShareOffer &&
        other.offerId == offerId &&
        other.kind == kind &&
        other.value == value &&
        other.fromPeerId == fromPeerId;
  }

  @override
  int get hashCode => Object.hash(offerId, kind, value, fromPeerId);
}

/// UI-facing app state
final class AppViewState {
  final AppPhase phase;
  final GameState game;
  final QuestionPair? currentQuestion;
  final PendingShare pendingShare;
  final IncomingShareOffer? incomingShareOffer;
  final P2pState lastP2pState;
  final String? focusCandidatePeerId;
  final bool focusCandidateLocked;
  final bool pairHandshakeComplete;
  final bool pairingReadySoon;
  final bool stableIsFlat;
  final double? stableHeadingDeg;
  final bool inviteBeaconEnabled;
  final bool inviteBeaconAvailable;
  final bool isConnectingTransition;
  final bool validationFailed; // ✅ NEW: Visual feedback for validation fail
  final bool isReconnecting; // ✅ NEW: Reconnecting state during gameplay
  final GameResultType? gameResultType; // ✅ NEW: Game result (success/failure)
  final bool sentOurShareOffer; // ✅ NEW: Track if we sent our share offer

  const AppViewState({
    required this.phase,
    required this.game,
    required this.currentQuestion,
    required this.pendingShare,
    required this.incomingShareOffer,
    required this.lastP2pState,
    this.focusCandidatePeerId,
    this.focusCandidateLocked = false,
    this.pairHandshakeComplete = false,
    this.pairingReadySoon = false,
    this.stableIsFlat = false,
    this.stableHeadingDeg,
    this.inviteBeaconEnabled = false,
    this.inviteBeaconAvailable = true,
    this.isConnectingTransition = false,
    this.validationFailed = false, // ✅ NEW
    this.isReconnecting = false, // ✅ NEW
    this.gameResultType, // ✅ NEW
    this.sentOurShareOffer = false, // ✅ NEW
  });

  factory AppViewState.initial() => AppViewState(
        phase: AppPhase.splash,
        game: const GameState.initial(),
        currentQuestion: null,
        pendingShare: const PendingShare.empty(),
        incomingShareOffer: null,
        lastP2pState: P2pState.idle,
        focusCandidatePeerId: null,
        focusCandidateLocked: false,
        pairHandshakeComplete: false,
        pairingReadySoon: false,
        stableIsFlat: false,
        stableHeadingDeg: null,
        inviteBeaconEnabled: false,
        inviteBeaconAvailable: true,
        isConnectingTransition: false,
        validationFailed: false, // ✅ NEW
        isReconnecting: false, // ✅ NEW
        gameResultType: null, // ✅ NEW
        sentOurShareOffer: false, // ✅ NEW
      );

  AppViewState copyWith({
    AppPhase? phase,
    GameState? game,
    QuestionPair? currentQuestion,
    bool clearCurrentQuestion = false,
    PendingShare? pendingShare,
    IncomingShareOffer? incomingShareOffer,
    bool clearIncomingShareOffer = false,
    P2pState? lastP2pState,
    String? focusCandidatePeerId,
    bool clearFocusCandidatePeerId = false,
    bool? focusCandidateLocked,
    bool? pairHandshakeComplete,
    bool? pairingReadySoon,
    bool? stableIsFlat,
    double? stableHeadingDeg,
    bool? inviteBeaconEnabled,
    bool? inviteBeaconAvailable,
    bool? isConnectingTransition,
    bool? validationFailed, // ✅ NEW
    bool? isReconnecting, // ✅ NEW
    GameResultType? gameResultType, // ✅ NEW
    bool? sentOurShareOffer, // ✅ NEW
  }) {
    return AppViewState(
      phase: phase ?? this.phase,
      game: game ?? this.game,
      currentQuestion: clearCurrentQuestion ? null : (currentQuestion ?? this.currentQuestion),
      pendingShare: pendingShare ?? this.pendingShare,
      incomingShareOffer: clearIncomingShareOffer ? null : (incomingShareOffer ?? this.incomingShareOffer),
      lastP2pState: lastP2pState ?? this.lastP2pState,
      focusCandidatePeerId: clearFocusCandidatePeerId ? null : (focusCandidatePeerId ?? this.focusCandidatePeerId),
      focusCandidateLocked: focusCandidateLocked ?? this.focusCandidateLocked,
      pairHandshakeComplete: pairHandshakeComplete ?? this.pairHandshakeComplete,
      pairingReadySoon: pairingReadySoon ?? this.pairingReadySoon,
      stableIsFlat: stableIsFlat ?? this.stableIsFlat,
      stableHeadingDeg: stableHeadingDeg ?? this.stableHeadingDeg,
      inviteBeaconEnabled: inviteBeaconEnabled ?? this.inviteBeaconEnabled,
      inviteBeaconAvailable: inviteBeaconAvailable ?? this.inviteBeaconAvailable,
      isConnectingTransition: isConnectingTransition ?? this.isConnectingTransition,
      validationFailed: validationFailed ?? this.validationFailed, // ✅ NEW
      isReconnecting: isReconnecting ?? this.isReconnecting, // ✅ NEW
      gameResultType: gameResultType ?? this.gameResultType, // ✅ NEW
      sentOurShareOffer: sentOurShareOffer ?? this.sentOurShareOffer, // ✅ NEW
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppViewState &&
        other.phase == phase &&
        other.game == game &&
        other.currentQuestion == currentQuestion &&
        other.pendingShare == pendingShare &&
        other.incomingShareOffer == incomingShareOffer &&
        other.lastP2pState == lastP2pState &&
        other.focusCandidatePeerId == focusCandidatePeerId &&
        other.focusCandidateLocked == focusCandidateLocked &&
        other.pairHandshakeComplete == pairHandshakeComplete &&
        other.pairingReadySoon == pairingReadySoon &&
        other.stableIsFlat == stableIsFlat &&
        other.stableHeadingDeg == stableHeadingDeg &&
        other.inviteBeaconEnabled == inviteBeaconEnabled &&
        other.inviteBeaconAvailable == inviteBeaconAvailable &&
        other.isConnectingTransition == isConnectingTransition &&
        other.validationFailed == validationFailed && // ✅ NEW
        other.isReconnecting == isReconnecting && // ✅ NEW
        other.gameResultType == gameResultType && // ✅ NEW
        other.sentOurShareOffer == sentOurShareOffer; // ✅ NEW
  }

  @override
  int get hashCode => Object.hash(
        phase,
        game,
        currentQuestion,
        pendingShare,
        incomingShareOffer,
        lastP2pState,
        focusCandidatePeerId,
        focusCandidateLocked,
        pairHandshakeComplete,
        pairingReadySoon,
        stableIsFlat,
        stableHeadingDeg,
        inviteBeaconEnabled,
        inviteBeaconAvailable,
        isConnectingTransition,
        validationFailed, // ✅ NEW
        isReconnecting, // ✅ NEW
        gameResultType, // ✅ NEW
        sentOurShareOffer, // ✅ NEW
      );
}

/// Main coordinator: manages P2P pairing, validation, and game start
final class AppCoordinator {
  static const int _protocolVersion = 1;
  static const int _roundMs = 5000;

  // Protocol constants
  static const double _flatThreshold = 0.82; // accelZ/g > 0.82 = flat

  final BleP2pPlugin plugin;  // ✅ Changed from NomatchP2pPlugin to BleP2pPlugin
  final QuestionProvider questions;
  final String appInstanceId;

  bool _initialized = false;
  bool _permissionsGranted = false;

  // State streams
  final StreamController<AppViewState> _states = StreamController<AppViewState>.broadcast();
  AppViewState _state = AppViewState.initial();
  AppViewState get state => _state;
  Stream<AppViewState> get states => _states.stream;

  // Peer tracking
  final StreamController<List<PeerInfo>> _peers = StreamController<List<PeerInfo>>.broadcast();
  Stream<List<PeerInfo>> get peers => _peers.stream;
  final List<PeerInfo> _discoveredPeers = [];
  List<PeerInfo> get discoveredPeers => List.unmodifiable(_discoveredPeers);

  // Subscriptions
  StreamSubscription<NomatchP2pEvent>? _p2pSub;
  StreamSubscription<GameState>? _engineSub;
  StreamSubscription<FaceToFaceEvent>? _f2fSub;

  // Sensor management (V2 - Face-to-Face Detection)
  final SensorManagerV2 _sensorManagerV2 = SensorManagerV2();

  // Flashlight management (invite beacon)
  final FlashlightSignal _flashlight = FlashlightSignal();

  // Pairing state
  String? _sessionId;
  String? _connectedPeerId;
  bool _isLeader = false;

  // Game engine
  GameEngine? _engine;
  Timer? _ticker;
  int _nextRid = 1;

  // Validation state (V2)
  bool _f2fValidationComplete = false;

  AppCoordinator({
    required this.plugin,
    required this.questions,
    required this.appInstanceId,
  });

  /// Initialize coordinator
  Future<void> initialize() async {
    if (_initialized) {
      print("[COORD] Already initialized");
      return;
    }
    print("[COORD] ========================================");
    print("[COORD] Initializing");

    // Handle web preview
    if (kIsWeb) {
      print("[COORD] Web mode - no native P2P");
      _setPhase(AppPhase.pairing);
      _initialized = true;
      return;
    }

    // ✅ NEW: Show splash screen first
    _setPhase(AppPhase.splash);
    print("[COORD] Splash screen shown");

    // ✅ Wait for splash to display (2 seconds)
    await Future.delayed(const Duration(seconds: 2));
    print("[COORD] Splash duration completed");

    // Check permissions
    print("[COORD] Checking permissions...");
    final permsOk = await _ensurePermissions();
    if (!permsOk) {
      print("[COORD] Permissions denied - staying on splash");
      _initialized = true;
      return;
    }

    // Initialize plugin
    try {
      print("[COORD] Initializing P2P plugin...");
      await plugin.initialize(appInstanceId: appInstanceId);
      print("[COORD] Plugin initialized");

      // Subscribe to P2P events
      _p2pSub = plugin.events.listen(_onP2pEvent);
      print("[COORD] Subscribed to P2P events");

      // Start pairing
      await _startPairing();
      print("[COORD] Pairing started");
      print("[COORD] ========================================");
      _initialized = true;
    } catch (e, stack) {
      print("[COORD] ❌ Init failed: $e");
      print("[COORD] Stack: $stack");
      _initialized = true;
      return;
    }
  }

  /// Start pairing process
  Future<void> _startPairing() async {
    print("[PAIR] 🚀 STARTING PAIRING PROCESS");
    print("[PAIR] ╔════════════════════════════════════════════╗");
    print("[PAIR] ║    PAIRING INITIALIZATION SEQUENCE         ║");
    print("[PAIR] ╚════════════════════════════════════════════╝");
    _debugLog("🚀 PAIRING STARTED | App instance: $appInstanceId");

    try {
      // Stop any existing activity
      print("[PAIR] 🛑 Stopping any existing P2P activity...");
      await plugin.stop();
      print("[PAIR]   ✅ Plugin stopped");

      // ✅ Reset validation failed flag
      print("[PAIR] 🔄 Resetting validation state");
      _emitIfChanged(_state.copyWith(validationFailed: false));

      // Start sensors (V2 - Face-to-Face Detection)
      if (!kIsWeb) {
        print("[PAIR] 📡 Starting sensor monitoring (V2 - Face-to-Face)...");
        
        // Start SensorManagerV2 for orientation vector streaming
        await _sensorManagerV2.start();
        
        // Listen to face-to-face events
        _f2fSub = _sensorManagerV2.faceToFaceEvents.listen((event) {
          dev.log('[F2F] Event: ${event.isSynced ? '✅' : '❌'} ${event.reason}');
          if (event.isSynced) {
            _f2fValidationComplete = true;
            dev.log('[F2F] ✅ FACE-TO-FACE VALIDATED!');
            
            // ✅ TRIGGER GAME START via validation snapshot handler
            if (_connectedPeerId != null && _sessionId != null) {
              print('[F2F] 📤 Sending validation snapshot to trigger game start...');
              _handleValidationSnapshot(_connectedPeerId!, SensorSnapshotMessage(
                sid: _sessionId!,
                isFlat: true,
                headingDeg: 0,
                timestampMs: DateTime.now().millisecondsSinceEpoch,
              ));
            }
          }
        });
        
        print("[PAIR]   ✅ Sensors started (orientation vector stream @ 20Hz)");
        print("[PAIR]   ℹ️ Tracking: Forward direction vectors + stability");
      } else {
        print("[PAIR] 🌐 Web mode - skipping sensor monitoring");
      }

      // Start hosting and discovery
      final deviceId = _stableDeviceId(appInstanceId);
      print("[PAIR] 🏠 Starting P2P hosting...");
      print("[PAIR]   - Device ID: $deviceId");
      await plugin.startHosting(displayNameHash: deviceId);
      print("[PAIR]   ✅ Hosting started");

      print("[PAIR] 🔍 Starting peer discovery...");
      await plugin.startDiscovery();
      print("[PAIR]   ✅ Discovery started");

      print("[PAIR] ┌────────────────────────────────────────────┐");
      print("[PAIR] │   ✅ PAIRING READY FOR CONNECTIONS!       │");
      print("[PAIR] │   Waiting for peer discovery...            │");
      print("[PAIR] └────────────────────────────────────────────┘");
      _debugLog("✅ PAIRING READY | Hosting and discovery started | Waiting for peer discovery");
      
      _setPhase(AppPhase.pairing);
    } catch (e, stack) {
      print("[PAIR] ❌ PAIRING START FAILED: $e");
      print("[PAIR] Stack trace: $stack");
      _debugLog("❌ PAIRING START FAILED | Error: $e");
      rethrow;
    }
  }


  /// Handle P2P events
  void _onP2pEvent(NomatchP2pEvent e) {
    switch (e) {
      case P2pStateChanged(:final state):
        dev.log("[P2P] State changed: $state");
        _debugLog("P2P STATE: $state | Local SessionID: $_sessionId");
        _emitIfChanged(_state.copyWith(lastP2pState: state));
        return;

      case PeerDiscovered(:final peerId, :final rssi, :final meta):
        _handlePeerDiscovered(peerId, rssi, meta);
        return;

      case PeerConnected(:final sessionId, :final peerId, :final isLeader):
        _handlePeerConnected(sessionId, peerId, isLeader);
        return;

      case PeerDisconnected():
        _handlePeerDisconnected();
        return;

      case MessageReceived(:final fromPeerId, :final message):
        _handleMessage(fromPeerId, message);
        return;

      case P2pErrorEvent(:final code, :final message, :final details):
        print('[P2P] ❌ Error: code=$code, message=$message, details=$details');
        dev.log('[P2P] Error Event: code=$code, message=$message, details=$details');
        return;
    }
  }

  /// Handle peer discovery
  void _handlePeerDiscovered(String peerId, int rssi, Map<String, dynamic>? meta) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existingIdx = _discoveredPeers.indexWhere((p) => p.id == peerId);
    
    print("[PEER] 📡 Peer discovered: $peerId (RSSI: ${rssi}dBm)");
    _debugLog("📡 PEER DISCOVERED | PeerID: $peerId | RSSI: ${rssi}dBm | Meta: $meta | Total peers: ${_discoveredPeers.length + 1}");

    if (existingIdx >= 0) {
      final existing = _discoveredPeers[existingIdx];
      print("[PEER] 🔄 Updating existing peer: $peerId (RSSI: $rssi)");
      _debugLog("🔄 PEER RSSI UPDATE | PeerID: $peerId | Old RSSI: ${existing.rssi}dBm | New RSSI: ${rssi}dBm");
      _discoveredPeers[existingIdx] = PeerInfo(
        id: peerId,
        rssi: rssi.toDouble(),
        isFlat: existing.isFlat,
        heading: existing.heading,
        lastSeenMs: now,
      );
    } else {
      print("[PEER] ✨ New peer added to list: $peerId");
      _debugLog("✨ NEW PEER ADDED | PeerID: $peerId | RSSI: ${rssi}dBm | Total peers now: ${_discoveredPeers.length + 1}");
      _discoveredPeers.add(PeerInfo(
        id: peerId,
        rssi: rssi.toDouble(),
        lastSeenMs: now,
      ));
    }

    // Log all discovered peers
    print("[PEER] 📊 Current peer list (${_discoveredPeers.length} peers):");
    for (int i = 0; i < _discoveredPeers.length; i++) {
      final p = _discoveredPeers[i];
      print("[PEER]   [$i] $p.id - RSSI: ${p.rssi}dBm");
    }

    _emitPeers();

    // Update UI: show peers available
    final hasPeers = _discoveredPeers.isNotEmpty;
    print("[PEER] 🎯 Pairing ready status: $hasPeers (${_discoveredPeers.length} peers available)");
    _emitIfChanged(_state.copyWith(pairingReadySoon: hasPeers));

    // Try to connect to closest peer
    _tryConnectToClosestPeer();
  }

  /// Try connecting to closest peer (by RSSI)
  void _tryConnectToClosestPeer() {
    if (_discoveredPeers.isEmpty) {
      print("[PAIR] ⏭️ No peers discovered yet, skipping connection attempt");
      return;
    }
    
    if (_connectedPeerId != null) {
      print("[PAIR] ⏭️ Already connected to $_connectedPeerId, skipping connection attempt");
      return;
    }

    // Find closest peer by RSSI
    final closest = _discoveredPeers.reduce((a, b) => a.rssi > b.rssi ? a : b);
    print("[PAIR] 🔗 Connecting to closest peer: ${closest.id} (RSSI: ${closest.rssi}dBm)");
    _debugLog("🔗 CONNECTION ATTEMPT | PeerID: ${closest.id} | RSSI: ${closest.rssi}dBm | Peers available: ${_discoveredPeers.length}");

    // Set focus candidate
    print("[PAIR] 🎯 Setting focus candidate: ${closest.id}");
    _emitIfChanged(_state.copyWith(
      focusCandidatePeerId: closest.id,
      focusCandidateLocked: false,
    ));

    // Request connection
    print("[PAIR] 📞 Requesting connection from plugin...");
    plugin.connect(peerId: closest.id);
  }

  /// Handle peer connected
  Future<void> _handlePeerConnected(String sessionId, String peerId, bool isLeader) async {
    print("[CONN] ✅ 🤝 PEER CONNECTED!");
    print("[CONN]   SessionID: $sessionId");
    print("[CONN]   PeerID: $peerId");
    print("[CONN]   Role: ${isLeader ? 'LEADER' : 'FOLLOWER'}");
    _debugLog("🤝 PEER CONNECTED | SessionID: $sessionId | PeerID: $peerId | IsLeader: $isLeader");

    _sessionId = sessionId;
    _connectedPeerId = peerId;
    _isLeader = isLeader;
    
    // Lock focus on connected peer
    print("[PAIR] 🔒 Locking focus on connected peer");
    _emitIfChanged(_state.copyWith(
      focusCandidateLocked: true,
      isConnectingTransition: true,
    ));

    // Face-to-face validation will auto-trigger via SensorManagerV2
    print("[PAIR] ⏳ Waiting for face-to-face validation...");
  }

  /// Handle peer disconnected
  void _handlePeerDisconnected() {
    print("[DISC] 🔌 PEER DISCONNECTED!");
    print("[DISC]   - Was connected to: $_connectedPeerId");
    print("[DISC]   - SessionID was: $_sessionId");
    print("[DISC]   - Was leader: $_isLeader");
    print("[DISC]   - Phase at disconnect: ${_state.phase}");
    _debugLog("🔌 DISCONNECTED | Was connected to: $_connectedPeerId | SessionID was: $_sessionId | Phase: ${_state.phase}");

    // ✅ Clear pairing state
    print("[DISC] 🧹 Clearing pairing state...");
    _sessionId = null;
    _connectedPeerId = null;
    _isLeader = false;
    _f2fValidationComplete = false;
    _f2fSub?.cancel();

    // ✅ NEW: Stop game engine if disconnect during gameplay
    print("[DISC] 🛑 Stopping game engine");
    _disposeEngine();

    print("[DISC] 🔄 Updating UI state");
    _emitIfChanged(_state.copyWith(
      focusCandidateLocked: false,
      pairHandshakeComplete: false,
      isConnectingTransition: false,
      validationFailed: false, // ✅ Reset validation failed flag
    ));

    // ✅ NEW: Stop P2P if in share/gameResult/splash to prevent auto-reconnect
    // Only allow pairing phase to do discovery/hosting
    if (_state.phase == AppPhase.shareResults || _state.phase == AppPhase.gameResult || _state.phase == AppPhase.splash) {
      print("[DISC] ⏸️ In ${_state.phase} phase - stopping P2P to prevent auto-reconnect");
      plugin.stop();
    }

    // ✅ Only restart pairing if in pairing phase
    if (_state.phase == AppPhase.pairing) {
      print("[DISC] 🔄 In PAIRING phase - restarting pairing discovery...");
      _startPairing();
    } else {
      print("[DISC] ⏸️ In ${_state.phase} phase - NOT restarting pairing");
    }
  }

  /// Handle incoming messages
  void _handleMessage(String fromPeerId, P2pMessage message) {
    // ✅ DEBUG: Log all messages with session context
    // ⚠️ NOTE: iOS MultipeerConnectivity can have session ID mismatches - ignore them
    _debugLog("[MSG] Received ${message.t} from $fromPeerId (remote_sid: ${message.sid}, local_sid: $_sessionId, match: ${message.sid == _sessionId})");
    
    switch (message) {
      case SensorSnapshotMessage():
        _handleValidationSnapshot(fromPeerId, message);
        return;

      case PairIntentMessage():
        // ✅ NEW: Handle pair intent messages (peer wants to pair with us)
        print("[PAIR] Received pair intent from $fromPeerId");
        // Typically handled by P2P plugin or pairing validator
        // This can be a no-op if pair negotiation is handled elsewhere
        return;

      case PairAckMessage():
        // ✅ NEW: Handle pair ack messages (peer acknowledged pair intent)
        print("[PAIR] Received pair ack from $fromPeerId");
        // Pair negotiation acknowledged
        return;

      case PairRejectMessage():
        print("[PAIR] ⚠️ Pair rejected: ${message.reason}");
        _disconnectAndRetry();
        return;

      case GameStartMessage():
        _engine?.onP2pMessage(message);
        return;

      case RoundStartMessage():
        _engine?.onP2pMessage(message);
        return;

      case SelectionMessage():
        _engine?.onP2pMessage(message);
        return;

      case HeartbeatMessage():
        _engine?.onP2pMessage(message);
        return;

      case ShareOfferMessage():
        // ✅ STRICT: Both players MUST send their info before moving to results
        _debugLog("📨 SHARE OFFER RECEIVED | From: $fromPeerId | Kind: ${message.kind} | Value: ${message.value}");
        
        // ✅ Store the incoming offer
        _emitIfChanged(_state.copyWith(
          incomingShareOffer: IncomingShareOffer(
            offerId: message.offerId,
            kind: message.kind,
            value: message.value,
            fromPeerId: fromPeerId,
          ),
        ));
        
        // ✅ Check if BOTH have shared
        if (_state.sentOurShareOffer) {
          // We already sent ours, peer just sent theirs → BOTH shared!
          print("[SHARE] 🎉 BOTH SHARED! (offer received + we sent ours) Auto-accepting...");
          Future.delayed(const Duration(milliseconds: 500), () {
            onIncomingShareDecision(accept: true);
          });
        } else {
          // We haven't sent yet, just store the offer
          print("[SHARE] 📨 Incoming offer stored. Waiting for user to send their info...");
        }
        return;

      case ShareResponseMessage():
        // ✅ ENHANCED: Handle peer's response to our share offer
        _handleShareResponse(message);
        return;

      case ErrorMessage():
        _engine?.onP2pMessage(message);
        return;

      case HelloMessage():
        _engine?.onP2pMessage(message);
        return;
    }
  }

  /// ✅ NEW: Handle peer's response to our share offer
  void _handleShareResponse(ShareResponseMessage message) {
    print("[SHARE] 📨 Received response: decision=${message.decision}");
    
    if (message.decision == 'accept') {
      // ✅ Peer accepted our offer
      print("[SHARE] ✅ Peer accepted our share");
      _debugLog("✅ SHARE ACCEPTED | PeerID: $_connectedPeerId");
      
      // ✅ STRICT: Just log the acceptance - don't transition yet!
      // Transition happens in onShareSendPressed() when BOTH conditions met:
      // 1. We sent our offer (onShareSendPressed was called)
      // 2. Peer sent their offer (incomingShareOffer exists)
      print("[SHARE] ⏳ Peer accepted. Transition will happen when we also receive their offer.");
    } else {
      // ✅ Peer rejected - end game
      print("[SHARE] ❌ Peer rejected our share");
      _debugLog("❌ SHARE REJECTED | PeerID: $_connectedPeerId");
      Future.delayed(const Duration(milliseconds: 1000), () {
        _stopAll();
      });
    }
  }


  /// Handle validation snapshot from peer
  void _handleValidationSnapshot(String fromPeerId, SensorSnapshotMessage message) {
    // V2 system: Face-to-face validation happens automatically via SensorManagerV2
    // This handler is kept for protocol compatibility but doesn't process validation
    
    // TODO: Send OrientationVectorSample instead of SensorSnapshotMessage
    // For now, trigger validation immediately when peer sends validation snapshot
    print("[PAIR] 📬 Validation snapshot received from peer");
    
    // Check face-to-face validation status (V2 system)
    if (!_sensorManagerV2.isSynced) {
      print("[PAIR] ⏳ Waiting for face-to-face validation (requires 1.5s of stable sync)...");
      print("[PAIR] ℹ️  isSynced: ${_sensorManagerV2.isSynced}");
      _debugLog("⏳ F2F validation pending | Synced: ${_sensorManagerV2.isSynced}");
      return;
    }

    print("[PAIR] ✅ ✅ ✅ FACE-TO-FACE VALIDATION PASSED! ✅ ✅ ✅");
    print("[PAIR] 🎉 Devices are facing each other correctly!");
    _debugLog("✅ F2F VALIDATION PASSED | Ready to start game | Session: $_sessionId");
    _f2fValidationComplete = true;

    // Update UI - start transition animation
    print("[PAIR] 🎬 Starting transition animation (3.5 seconds)");
    _emitIfChanged(_state.copyWith(
      pairHandshakeComplete: true,
      isConnectingTransition: true,
    ));

    // Schedule game start (3.5 seconds delay: 3s for transition animation + 0.5s buffer)
    // This ensures animation completes before game screen opens
    print("[PAIR] ⏱️ Scheduling game start in 3500ms...");
    Future.delayed(const Duration(milliseconds: 3500), () {
      _startGame();
    });
  }


  /// Reject pairing and disconnect
  void _rejectAndDisconnect(String reason) {
    print("[PAIR] ❌ REJECTING PAIRING - Reason: $reason");
    _debugLog("❌ PAIRING REJECTED | Reason: $reason");

    // ✅ Set validation fail visual feedback
    print("[PAIR] 🎨 Setting visual feedback (red blink animation)");
    _emitIfChanged(_state.copyWith(validationFailed: true));

    final sid = _sessionId ?? appInstanceId;
    final peerId = _connectedPeerId;

    // Send reject message if connected
    if (peerId != null && _sessionId != null) {
      try {
        print("[PAIR] 📤 Sending reject message to $peerId");
        final msg = PairRejectMessage(
          sid: sid,
          reason: reason,
        );
        plugin.send(msg);
        print("[PAIR] ✅ Reject message sent");
      } catch (e) {
        print("[PAIR] ❌ Failed to send reject message: $e");
      }
    }

    _disconnectAndRetry();
  }

  /// Disconnect and retry pairing
  void _disconnectAndRetry() {
    print("[PAIR] 🔄 DISCONNECTING AND RETRYING...");
    print("[PAIR]   - Clearing pairing state");
    _debugLog("🔄 DISCONNECT AND RETRY | Clearing state and restarting discovery");

    _sessionId = null;
    _connectedPeerId = null;
    _f2fValidationComplete = false;
    _f2fSub?.cancel();

    print("[PAIR] 🛑 Stopping P2P plugin");
    plugin.stop();

    print("[PAIR] 🔄 Resetting UI state");
    _emitIfChanged(_state.copyWith(
      focusCandidateLocked: false,
      pairHandshakeComplete: false,
      isConnectingTransition: false,
      validationFailed: false, // ✅ Clear validation failed flag
    ));

    // Restart pairing
    print("[PAIR] 🚀 Restarting pairing discovery...");
    _startPairing();
  }

  /// Start game after validation
  void _startGame() {
    print("[GAME] 🎮 STARTING GAME...");
    _debugLog("🎮 GAME INITIALIZATION STARTED");

    final sessionId = _sessionId;
    final peerId = _connectedPeerId;

    print("[GAME] 📋 Game configuration:");
    print("[GAME]   - Session ID: $sessionId");
    print("[GAME]   - Peer ID: $peerId");
    print("[GAME]   - Role: ${_isLeader ? 'LEADER' : 'FOLLOWER'}");

    if (sessionId == null || peerId == null) {
      print("[GAME] ❌ GAME START FAILED - Missing session or peer!");
      print("[GAME]   - SessionID: $sessionId");
      print("[GAME]   - PeerID: $peerId");
      _debugLog("❌ GAME START FAILED | SessionID: $sessionId | PeerID: $peerId");
      return;
    }

    // Cancel face-to-face validation (no longer needed during game)
    print("[GAME] 🔪 Cancelling face-to-face validation");
    _f2fValidationComplete = true;

    // Stop sensor monitoring (not needed during game)
    print("[GAME] 🛑 Stopping sensor monitoring");
    _sensorManagerV2.stop();
    _f2fSub?.cancel();
    _f2fSub = null;

    // Initialize engine
    print("[GAME] ⚙️ Initializing game engine");
    _startEngine(sessionId: sessionId, peerId: peerId);

    // Set phase to playing
    print("[GAME] 🎬 Setting phase to PLAYING");
    _setPhase(AppPhase.playing);

    // Start ticker
    print("[GAME] ⏱️ Starting game ticker (16ms intervals)");
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _engine?.onTick(now);
    });

    // ✅ NEW: Leader starts first round immediately after game begins
    if (_isLeader) {
      print("[GAME] 👑 LEADER MODE: Will start first round after delay");
      print("[GAME] ⏳ Waiting 100ms before starting first round...");
      Future.delayed(const Duration(milliseconds: 100), () {
        print("[GAME] 👑 Leader starting first round now!");
        _startLeaderNextRound();
      });
    } else {
      print("[GAME] 👥 FOLLOWER MODE: Waiting for first round from leader");
    }

    print("[GAME] ✅ ✅ ✅ GAME SUCCESSFULLY STARTED! ✅ ✅ ✅");
    _debugLog("✅ GAME STARTED | SessionID: $sessionId | PeerID: $peerId | IsLeader: $_isLeader");
  }

  /// Start game engine
  void _startEngine({required String sessionId, required String peerId}) {
    _disposeEngine();

    final engine = GameEngine(
      transport: _CoordinatorTransport(plugin),
      isLeader: _isLeader,
      externalRoundControl: true,
      sessionId: sessionId,
      localDeviceId: _stableDeviceId(appInstanceId),
      questions: questions, // ✅ NEW: Pass question provider for asset embedding
    );

    _engine = engine;
    engine.onPeerConnected(peerId: peerId);

    _engineSub = engine.states.listen(_onEngineState);
  }

  /// Handle engine state changes
  void _onEngineState(GameState gs) {
    print("[COORD] _onEngineState called. Phase: ${gs.phase}");
    
    final phase = switch (gs.phase) {
      GamePhase.playing => AppPhase.playing,
      GamePhase.terminalFail => AppPhase.gameResult, // ✅ NEW: Use gameResult instead
      GamePhase.terminalSuccess => AppPhase.gameResult, // ✅ NEW: Use gameResult instead
      GamePhase.share => AppPhase.share,
      GamePhase.pairing => AppPhase.pairing,
      GamePhase.idle => AppPhase.splash,
    };

    // ✅ NEW: Determine game result type
    final resultType = gs.phase == GamePhase.terminalSuccess
        ? GameResultType.success
        : GameResultType.failure;
    
    if (phase == AppPhase.gameResult) {
      print("[COORD] Game ended! Result type: $resultType 🎬");
    }

    // ✅ NEW: Use embedded assets from currentRound (perfect sync)
    final q = gs.currentRound != null
        ? QuestionPair(
            qid: gs.currentRound!.qid,
            topAsset: gs.currentRound!.topAsset ?? '',
            bottomAsset: gs.currentRound!.bottomAsset ?? '',
          )
        : _questionFor(gs.currentRound?.qid); // Fallback to legacy method
    
    // ✅ NEW: Reset transition animation flags when game starts
    final shouldResetTransition = phase == AppPhase.playing;
    
    _emitIfChanged(
      _state.copyWith(
        phase: phase,
        game: gs,
        currentQuestion: q,
        clearCurrentQuestion: q == null,
        pairHandshakeComplete: !shouldResetTransition ? _state.pairHandshakeComplete : false,
        isConnectingTransition: !shouldResetTransition ? _state.isConnectingTransition : false,
        gameResultType: phase == AppPhase.gameResult ? resultType : null, // ✅ NEW
      ),
    );

    // Start next round if leader
    if (_isLeader && phase == AppPhase.playing && gs.currentRound == null && gs.difference < 5 && gs.similarity < 5) {
      _startLeaderNextRound();
    }
  }

  /// Start next round (leader only)
  void _startLeaderNextRound() {
    final sid = _sessionId;
    if (sid == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final qid = questions.nextQid();
    final rid = _nextRid++;
    final deadline = now + _roundMs;

    // ✅ NEW: Get question and embed assets
    final q = questions.getById(qid);

    final msg = RoundStartMessage(
      v: _protocolVersion,
      sid: sid,
      mid: _shortRandomId(),
      rid: rid,
      qid: qid,
      deadlineMs: deadline,
      leaderId: _stableDeviceId(appInstanceId),
      topAsset: q?.topAsset, // ✅ NEW: Embed asset
      bottomAsset: q?.bottomAsset, // ✅ NEW: Embed asset
    );

    plugin.send(msg);
    _engine?.onP2pMessage(msg);
  }

  /// Get question for qid
  QuestionPair? _questionFor(int? qid) {
    if (qid == null) return null;
    try {
      return questions.getById(qid);
    } catch (_) {
      print("[COORD] Question not found: $qid");
      return null;
    }
  }

  /// Dispose engine
  void _disposeEngine() {
    _ticker?.cancel();
    _ticker = null;
    _engineSub?.cancel();
    _engineSub = null;
    final e = _engine;
    _engine = null;
    if (e != null) {
      // ignore: discarded_futures
      e.dispose();
    }
  }

  /// Update phase
  void _setPhase(AppPhase phase) {
    _emitIfChanged(_state.copyWith(phase: phase));
  }

  /// Emit state if changed
  void _emitIfChanged(AppViewState next) {
    if (next == _state) return;
    _state = next;
    _states.add(next);
  }

  /// Emit peers list
  void _emitPeers() {
    _peers.add(List<PeerInfo>.unmodifiable(_discoveredPeers));
  }

  /// Check and request permissions
  Future<bool> _ensurePermissions() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    print("[PERM] Checking Android permissions...");

    final scan = await Permission.bluetoothScan.request();
    if (!scan.isGranted) return false;

    final connect = await Permission.bluetoothConnect.request();
    if (!connect.isGranted) return false;

    final advertise = await Permission.bluetoothAdvertise.request();
    if (!advertise.isGranted) return false;

    final loc = await Permission.locationWhenInUse.request();
    if (!loc.isGranted) return false;

    print("[PERM] ✅ All permissions granted");
    return true;
  }

  /// Cleanup
  Future<void> dispose() async {
    dev.log("[COORD] Disposing");
    _stopAll();
    // ✅ NEW: Stop flashlight blinking on cleanup
    await _updateFlashlightState(false);
    _flashlight.dispose();
    await _p2pSub?.cancel();
    _p2pSub = null;
    await _f2fSub?.cancel();
    _f2fSub = null;
    _sensorManagerV2.dispose();
    await _states.close();
  }

  /// Stop all activity
  void _stopAll() {
    _disposeEngine();
    _f2fSub?.cancel();
    _f2fSub = null;
    _sensorManagerV2.stop();
    plugin.stop();
  }

  /// UI actions
  void onLocalTapTop() {
    _engine?.onLocalTapTop();
  }

  void onLocalTapBottom() {
    _engine?.onLocalTapBottom();
  }

  void setInviteBeaconEnabled(bool enabled) {
    // ✅ NEW: Control torch/flashlight for invite beacon - yanıp sönsün (pil dostu)
    _emitIfChanged(_state.copyWith(inviteBeaconEnabled: enabled));
    _updateFlashlightState(enabled);
  }

  /// ✅ NEW: Turn flashlight blinking on/off (low power mode)
  Future<void> _updateFlashlightState(bool enabled) async {
    try {
      if (enabled) {
        // Start low-power blinking: 120ms on, 1500ms off (very battery friendly)
        await _flashlight.startLowPowerBlink(onMs: 120, offMs: 1500);
        print("[BEACON] 💡 Flashlight blinking enabled (low power)");
      } else {
        await _flashlight.stopBlinking();
        print("[BEACON] 💡 Flashlight stopped");
      }
    } catch (e) {
      print("[BEACON] ❌ Flashlight error: $e");
    }
  }

  void onShareKindSelected(ShareKind kind) {
    _emitIfChanged(_state.copyWith(pendingShare: _state.pendingShare.copyWith(kind: kind)));
  }

  void onShareTextChanged(String text) {
    _emitIfChanged(_state.copyWith(pendingShare: _state.pendingShare.copyWith(text: text)));
  }

  Future<void> onShareSendPressed() async {
    final sid = _sessionId;
    final peerId = _connectedPeerId;
    final kind = _state.pendingShare.kind;

    if (sid == null || peerId == null || kind == null) {
      print("[SHARE] ❌ Cannot send - sid=$sid, peerId=$peerId, kind=$kind");
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final msg = ShareOfferMessage(
      v: _protocolVersion,
      sid: sid,
      offerId: _shortRandomId(),
      kind: kind == ShareKind.phone ? 'phone' : 'social',
      value: _state.pendingShare.text,
    );

    print("[SHARE] 📤 Sending offer: kind=${msg.kind}, value=${msg.value}");
    await plugin.send(msg);
    print("[SHARE] ✅ Offer sent");
    
    // ✅ Mark that WE sent our offer
    _emitIfChanged(_state.copyWith(
      pendingShare: const PendingShare.empty(),
      sentOurShareOffer: true, // ✅ SET FLAG
    ));

    // ✅ Check if peer ALREADY sent their offer
    if (_state.incomingShareOffer != null) {
      // ✅ Both have shared! Auto-accept
      print("[SHARE] 🎉 BOTH SHARED! (peer already sent) Auto-accepting...");
      Future.delayed(const Duration(milliseconds: 500), () {
        onIncomingShareDecision(accept: true);
      });
    } else {
      // ✅ Peer hasn't sent yet - wait for their offer
      print("[SHARE] ⏳ We sent, waiting for peer (60s timeout)...");
      
      // ✅ TIMEOUT: If peer doesn't share within 60 seconds, reset
      Future.delayed(const Duration(seconds: 60), () {
        if (_state.phase == AppPhase.share && _state.incomingShareOffer == null) {
          print("[SHARE] ❌ Timeout: Peer didn't share. Returning to pairing...");
          resetAndReturnToPairing();
        }
      });
    }
  }

  Future<void> onIncomingShareDecision({required bool accept}) async {
    final sid = _sessionId;
    final offer = _state.incomingShareOffer;
    if (sid == null || offer == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final msg = ShareResponseMessage(
      v: _protocolVersion,
      sid: sid,
      accepted: accept,
      decision: accept ? 'accept' : 'reject',
    );

    print("[SHARE] 📤 Sending response: decision=${msg.decision}");
    await plugin.send(msg);
    
    // ✅ ENHANCED: Handle response
    if (accept) {
      // ✅ Both shared! Move to results
      // This means: I sent my offer + peer sent theirs + I'm accepting theirs
      // = both have shared
      print("[SHARE] 🎉 BOTH SHARED! (response accepted) Moving to results...");
      Future.delayed(const Duration(milliseconds: 500), () {
        _setPhase(AppPhase.shareResults);
      });
    } else {
      // ✅ If rejected, go back to pairing
      print("[SHARE] ❌ Rejecting offer → Returning to pairing");
      Future.delayed(const Duration(milliseconds: 500), () {
        resetAndReturnToPairing();
      });
    }
  }

  /// ✅ NEW: Lifecycle hook for app resume
  void onAppResumed() {
    print("[COORD] App resumed");
    // Resume sensor monitoring if paused
    if (_f2fSub != null && !_f2fSub!.isPaused) {
      _f2fSub?.resume();
    }
  }

  /// ✅ NEW: Lifecycle hook for app pause
  void onAppPaused() {
    print("[COORD] App paused");
    // Pause sensor monitoring
    _f2fSub?.pause();
  }

  /// ✅ NEW: Preload questions asynchronously
  Future<void> preloadQuestions() async {
    try {
      print("[COORD] Preloading questions...");
      _debugLog("📚 Preloading questions from assets");
      
      // If it's a LazyQuestionProvider, load it now
      if (questions is LazyQuestionProvider) {
        final lazy = questions as LazyQuestionProvider;
        await lazy.preload();
        print("[COORD] ✅ Questions preloaded");
        _debugLog("✅ Questions loaded successfully");
      } else {
        print("[COORD] ℹ️ Questions provider doesn't support preloading");
      }
    } catch (e) {
      print("[COORD] ❌ Questions preload error: $e");
      _debugLog("❌ Questions preload failed: $e");
      rethrow;
    }
  }

  /// ✅ NEW: Stop all activities (cleanup) - public wrapper for UI
  void stopAll() {
    _stopAll();
  }

  /// ✅ NEW: Proceed from game result to share screen
  void proceedToShare() {
    print("[COORD] Proceeding to share screen 📱");
    // ✅ Reset share state flags when entering share phase
    _emitIfChanged(_state.copyWith(
      phase: AppPhase.share,
      sentOurShareOffer: false, // ✅ Reset flag
      incomingShareOffer: null, // ✅ Clear any old offer
    ));
  }

  /// ✅ NEW: Reset game and return to pairing
  void resetAndReturnToPairing() {
    print("[COORD] Resetting game and returning to pairing 🔄");
    _stopAll();
    
    // ✅ IMPORTANT: Clear all share state before going to pairing
    _emitIfChanged(_state.copyWith(
      phase: AppPhase.pairing,
      pendingShare: const PendingShare.empty(), // ✅ Clear pending
      incomingShareOffer: null, // ✅ Clear incoming
      sentOurShareOffer: false, // ✅ Reset flag
    ));
    
    _startPairing();
  }

  /// ✅ NEW: Full reset - return to splash screen
  void resetToSplash() {
    print("[COORD] 🔄 FULL RESET → Splash screen");
    _stopAll();
    
    // ✅ Clear EVERYTHING and go to splash
    _emitIfChanged(_state.copyWith(
      phase: AppPhase.splash,
      game: const GameState.initial(),
      currentQuestion: null,
      pendingShare: const PendingShare.empty(),
      incomingShareOffer: null,
      sentOurShareOffer: false,
      gameResultType: null,
      validationFailed: false,
      isReconnecting: false,
      focusCandidatePeerId: null,
      focusCandidateLocked: false,
      pairHandshakeComplete: false,
    ));
    
    print("[COORD] ✅ Reset complete - splash screen displayed");
  }

  /// ✅ Public pairing start for GameResultScreen callback
  Future<void> startPairingAfterReset() async {
    print("[COORD] 📱 Starting pairing after splash...");
    await _startPairing();
  }

  /// ✅ NEW: Debug logging helper - prints to console with prefix
  void _debugLog(String msg) {
    final timestamp = DateTime.now().toString().split('.')[0]; // HH:mm:ss
    final fullMsg = "[$timestamp] 🔍 $msg";
    print(fullMsg);
    dev.log(fullMsg, name: 'NOMATCH_DEBUG');
  }
}

/// Transport for game engine
final class _CoordinatorTransport implements GameTransport {
  final BleP2pPlugin plugin;
  const _CoordinatorTransport(this.plugin);

  @override
  Future<void> send(P2pMessage msg) => plugin.send(msg);
}

/// Generate stable device ID
String _stableDeviceId(String appInstanceId) {
  final b64 = base64UrlEncode(utf8.encode(appInstanceId));
  return b64.length <= 12 ? b64 : b64.substring(0, 12);
}

/// Generate short random ID
String _shortRandomId() {
  final r = math.Random.secure();
  final bytes = List<int>.generate(9, (_) => r.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}
