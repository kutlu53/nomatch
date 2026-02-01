import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../features/game/game_engine.dart';
import '../features/game/game_state.dart';
import '../features/game/question_bank.dart';
import '../features/game/lazy_question_provider.dart';
import '../features/pairing/pairing_validator.dart' show PeerInfo;
import '../features/pairing/sensor_manager.dart';
import '../plugins/p2p/p2p_events.dart';
import '../plugins/p2p/p2p_messages.dart';
import '../plugins/p2p/p2p_plugin.dart';
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
        other.isReconnecting == isReconnecting; // ✅ NEW
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
      );
}

/// Main coordinator: manages P2P pairing, validation, and game start
final class AppCoordinator {
  static const int _protocolVersion = 1;
  static const int _roundMs = 5000;

  // Protocol constants
  static const double _flatThreshold = 0.82; // accelZ/g > 0.82 = flat
  static const double _headingTolerance = 25.0; // 25° tolerance for opposite heading

  final NomatchP2pPlugin plugin;
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
  StreamSubscription<SensorData>? _sensorSub;

  // Sensor management
  final SensorManager _sensorManager = SensorManager();
  SensorData _currentSensorData = SensorData.initial();

  // Pairing state
  String? _sessionId;
  String? _connectedPeerId;
  bool _isLeader = false;

  // Game engine
  GameEngine? _engine;
  Timer? _ticker;
  int _nextRid = 1;

  // Validation state
  bool? _remoteIsFlat;
  double? _remoteHeadingDeg;
  int? _remoteSensorTimestampMs;
  bool _validationComplete = false;
  Timer? _validationTimer;

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

    // Check permissions
    print("[COORD] Checking permissions...");
    final permsOk = await _ensurePermissions();
    if (!permsOk) {
      print("[COORD] Permissions denied - showing splash");
      _setPhase(AppPhase.splash);
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
    print("[PAIR] Starting pairing...");

    try {
      // Stop any existing activity
      await plugin.stop();

      // Start sensors
      if (!kIsWeb) {
        _sensorManager.start();
        _sensorSub = _sensorManager.sensorStream.listen(_onSensorData);
        print("[PAIR] Sensors started");
      }

      // Start hosting and discovery
      await plugin.startHosting(displayNameHash: _stableDeviceId(appInstanceId), sessionConfigJson: '{}');
      await plugin.startDiscovery(sessionConfigJson: '{}');

      print("[PAIR] Hosting + discovery started");
      _setPhase(AppPhase.pairing);
    } catch (e) {
      print("[PAIR] ❌ Failed: $e");
      rethrow;
    }
  }

  /// Handle sensor data updates
  void _onSensorData(SensorData data) {
    _currentSensorData = data;
    // Update UI state with sensor data
    _emitIfChanged(_state.copyWith(
      stableIsFlat: data.isFlat,
      stableHeadingDeg: data.heading,
    ));
  }

  /// Handle P2P events
  void _onP2pEvent(NomatchP2pEvent e) {
    switch (e) {
      case P2pStateChanged(:final state):
        dev.log("[P2P] State changed: $state");
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

      case P2pErrorEvent(:final code):
        print('[P2P] Error: $code');
        return;
    }
  }

  /// Handle peer discovery
  void _handlePeerDiscovered(String peerId, int rssi, Map<String, dynamic>? meta) {
    print("[PEER] Discovered: $peerId rssi=$rssi");

    final now = DateTime.now().millisecondsSinceEpoch;
    final existingIdx = _discoveredPeers.indexWhere((p) => p.id == peerId);

    if (existingIdx >= 0) {
      final existing = _discoveredPeers[existingIdx];
      _discoveredPeers[existingIdx] = PeerInfo(
        id: peerId,
        rssi: rssi.toDouble(),
        isFlat: existing.isFlat,
        heading: existing.heading,
        lastSeenMs: now,
      );
    } else {
      _discoveredPeers.add(PeerInfo(
        id: peerId,
        rssi: rssi.toDouble(),
        lastSeenMs: now,
      ));
    }

    _emitPeers();

    // Update UI: show peers available
    final hasPeers = _discoveredPeers.isNotEmpty;
    _emitIfChanged(_state.copyWith(pairingReadySoon: hasPeers));

    // Try to connect to closest peer
    _tryConnectToClosestPeer();
  }

  /// Try connecting to closest peer (by RSSI)
  void _tryConnectToClosestPeer() {
    if (_discoveredPeers.isEmpty || _connectedPeerId != null) return;

    // Find closest peer by RSSI
    final closest = _discoveredPeers.reduce((a, b) => a.rssi > b.rssi ? a : b);
    print("[PAIR] Connecting to closest peer: ${closest.id} rssi=${closest.rssi}");

    // Set focus candidate
    _emitIfChanged(_state.copyWith(
      focusCandidatePeerId: closest.id,
      focusCandidateLocked: false,
    ));

    // Request connection
    plugin.connect(peerId: closest.id);
  }

  /// Handle peer connected
  Future<void> _handlePeerConnected(String sessionId, String peerId, bool isLeader) async {
    print("[CONN] ✅ Connected to $peerId (leader=$isLeader)");

    _sessionId = sessionId;
    _connectedPeerId = peerId;
    _isLeader = isLeader;

    // Lock focus on connected peer
    _emitIfChanged(_state.copyWith(
      focusCandidateLocked: true,
      isConnectingTransition: true,
    ));

    // Send sensor snapshot for validation
    _sendValidationSnapshot(peerId);

    // Wait for remote snapshot (timeout: 3s)
    _validationTimer = Timer(const Duration(seconds: 3), () {
      if (!_validationComplete) {
        print("[PAIR] ❌ Validation timeout");
        _disconnectAndRetry();
      }
    });
  }

  /// Handle peer disconnected
  void _handlePeerDisconnected() {
    print("[DISC] 🔌 Disconnected");

    _sessionId = null;
    _connectedPeerId = null;
    _isLeader = false;
    _validationComplete = false;
    _remoteIsFlat = null;
    _remoteHeadingDeg = null;
    _validationTimer?.cancel();

    _emitIfChanged(_state.copyWith(
      focusCandidateLocked: false,
      pairHandshakeComplete: false,
      isConnectingTransition: false,
    ));

    // Restart pairing
    _startPairing();
  }

  /// Handle incoming messages
  void _handleMessage(String fromPeerId, P2pMessage message) {
    switch (message) {
      case SensorSnapshotMessage():
        _handleValidationSnapshot(fromPeerId, message);
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
        _emitIfChanged(_state.copyWith(
          incomingShareOffer: IncomingShareOffer(
            offerId: message.offerId,
            kind: message.kind,
            value: message.value,
            fromPeerId: fromPeerId,
          ),
        ));
        return;

      case ShareResponseMessage():
        _engine?.onP2pMessage(message);
        return;

      case ErrorMessage():
        _engine?.onP2pMessage(message);
        return;

      case HelloMessage():
        _engine?.onP2pMessage(message);
        return;
    }
  }

  /// Send validation snapshot (sensor data)
  void _sendValidationSnapshot(String peerId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final sid = _sessionId ?? appInstanceId;

    final msg = SensorSnapshotMessage(
      v: _protocolVersion,
      sid: sid,
      isFlat: _currentSensorData.isFlat,
      headingDeg: _currentSensorData.heading,
      timestampMs: now,
      mid: _shortRandomId(),
    );

    print("[PAIR] Sending validation snapshot: flat=${msg.isFlat} heading=${msg.headingDeg?.toStringAsFixed(1) ?? 'null'}");
    plugin.send(msg);
  }

  /// Handle validation snapshot from peer
  void _handleValidationSnapshot(String fromPeerId, SensorSnapshotMessage message) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ageMs = now - message.timestampMs;

    print("[PAIR] Received validation snapshot from $fromPeerId: flat=${message.isFlat} heading=${message.headingDeg?.toStringAsFixed(1) ?? 'null'} age=${ageMs}ms");

    _remoteIsFlat = message.isFlat;
    _remoteHeadingDeg = message.headingDeg;
    _remoteSensorTimestampMs = message.timestampMs;

    // Validate conditions
    if (!_validatePairingConditions()) {
      print("[PAIR] ❌ Validation FAILED");
      _rejectAndDisconnect('validation_failed');
      return;
    }

    print("[PAIR] ✅ Validation PASSED");
    _validationComplete = true;
    _validationTimer?.cancel();

    // Update UI
    _emitIfChanged(_state.copyWith(
      pairHandshakeComplete: true,
      isConnectingTransition: true,
    ));

    // Schedule game start
    Future.delayed(const Duration(milliseconds: 900), () {
      _startGame();
    });
  }

  /// Validate pairing conditions:
  /// 1. Both devices flat (isFlat = true)
  /// 2. Heading: Either BOTH available OR both null (no mixed state)
  /// 3. If both heading available: difference ~180° (within tolerance)
  bool _validatePairingConditions() {
    // ✅ Condition 1: Both must be flat
    final localFlat = _currentSensorData.isFlat;
    final remoteFlat = _remoteIsFlat ?? false;

    if (!localFlat || !remoteFlat) {
      print("[PAIR] FAIL: flat check (local=$localFlat remote=$remoteFlat)");
      return false;
    }

    print("[PAIR] PASS: flat check ✓");

    // ✅ Condition 2: Heading validation (REQUIRE BOTH or NONE)
    final localHeading = _getStableHeading();
    final remoteHeading = _remoteHeadingDeg;

    // ✅ Check for mismatch: one has heading, other doesn't
    if ((localHeading != null) != (remoteHeading != null)) {
      print("[PAIR] FAIL: heading data mismatch (local=$localHeading, remote=$remoteHeading)");
      return false;
    }

    // ✅ Both have heading: validate 180° opposite
    if (localHeading != null && remoteHeading != null) {
      final diff = _oppositeDiffDeg(localHeading, remoteHeading);
      const tolerance = _headingTolerance;

      if (diff > tolerance) {
        print("[PAIR] FAIL: heading mismatch (diff=$diff° > $tolerance°)");
        return false;
      }

      print("[PAIR] PASS: heading check (diff=$diff°) ✓");
    } else {
      // ✅ Both null: Skip heading (flat detection sufficient)
      print("[PAIR] PASS: heading check skipped (both devices have no heading data)");
    }

    return true;
  }

  /// ✅ NEW: Get stable heading with variance filtering
  /// Returns null if heading is too unstable (jitter)
  double? _getStableHeading() {
    final heading = _currentSensorData.heading;
    if (heading == null) return null;

    // Calculate recent variance from last 5 samples
    final recentSamples = _sensorHistory.length >= 3
        ? _sensorHistory
            .skip(math.max(0, _sensorHistory.length - 5))
            .map((s) => s.heading)
            .whereType<double>()
            .toList()
        : <double>[];

    if (recentSamples.length < 3) {
      // Not enough samples yet, trust single value
      return heading;
    }

    // Calculate mean
    final mean = recentSamples.reduce((a, b) => a + b) / recentSamples.length;

    // Calculate variance
    var sumSquaredDiff = 0.0;
    for (final h in recentSamples) {
      final diff = h - mean;
      sumSquaredDiff += diff * diff;
    }
    final variance = sumSquaredDiff / recentSamples.length;

    // Only return heading if stable (variance < 50°²)
    if (variance > 50.0) {
      print("[PAIR] Heading unstable (variance=$variance), returning null");
      return null;
    }

    return heading;
  }

  /// Calculate opposite angle difference (0-180°)
  double _oppositeDiffDeg(double heading1, double heading2) {
    double diff = ((heading1 - heading2).abs() - 180).abs();
    if (diff > 180) diff = 360 - diff;
    return diff;
  }

  /// Reject pairing and disconnect
  void _rejectAndDisconnect(String reason) {
    print("[PAIR] Rejecting: $reason");

    // ✅ Set validation fail visual feedback
    _emitIfChanged(_state.copyWith(validationFailed: true));

    final sid = _sessionId ?? appInstanceId;
    final peerId = _connectedPeerId;

    // Send reject message if connected
    if (peerId != null && _sessionId != null) {
      try {
        final msg = PairRejectMessage(
          v: _protocolVersion,
          sid: sid,
          ts: DateTime.now().millisecondsSinceEpoch,
          mid: _shortRandomId(),
          reason: reason,
        );
        plugin.send(msg);
      } catch (e) {
        print("[PAIR] Failed to send reject: $e");
      }
    }

    _disconnectAndRetry();
  }

  /// Disconnect and retry pairing
  void _disconnectAndRetry() {
    print("[PAIR] Disconnecting and retrying...");

    _sessionId = null;
    _connectedPeerId = null;
    _validationComplete = false;
    _remoteIsFlat = null;
    _remoteHeadingDeg = null;
    _validationTimer?.cancel();

    plugin.stop();

    _emitIfChanged(_state.copyWith(
      focusCandidateLocked: false,
      pairHandshakeComplete: false,
      isConnectingTransition: false,
    ));

    // Restart pairing
    _startPairing();
  }

  /// Start game after validation
  void _startGame() {
    print("[GAME] Starting game...");

    final sessionId = _sessionId;
    final peerId = _connectedPeerId;

    if (sessionId == null || peerId == null) {
      print("[GAME] ❌ Missing session or peer");
      return;
    }

    // Initialize engine
    _startEngine(sessionId: sessionId, peerId: peerId);

    // Set phase to playing
    _setPhase(AppPhase.playing);

    // Start ticker
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _engine?.onTick(now);
    });

    print("[GAME] ✅ Game started");
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
    final phase = switch (gs.phase) {
      GamePhase.playing => AppPhase.playing,
      GamePhase.terminalFail => AppPhase.terminalFail,
      GamePhase.terminalSuccess => AppPhase.terminalSuccess,
      GamePhase.share => AppPhase.share,
      GamePhase.pairing => AppPhase.pairing,
      GamePhase.idle => AppPhase.splash,
    };

    // ✅ NEW: Use embedded assets from currentRound (perfect sync)
    final q = gs.currentRound != null
        ? QuestionPair(
            topAsset: gs.currentRound!.topAsset ?? '',
            bottomAsset: gs.currentRound!.bottomAsset ?? '',
          )
        : _questionFor(gs.currentRound?.qid); // Fallback to legacy method
    
    _emitIfChanged(
      _state.copyWith(
        phase: phase,
        game: gs,
        currentQuestion: q,
        clearCurrentQuestion: q == null,
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

    final msg = RoundStartMessage(
      v: _protocolVersion,
      sid: sid,
      ts: now,
      mid: _shortRandomId(),
      rid: rid,
      qid: qid,
      deadlineMs: deadline,
      leaderId: _stableDeviceId(appInstanceId),
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
    await _p2pSub?.cancel();
    _p2pSub = null;
    await _sensorSub?.cancel();
    _sensorSub = null;
    _sensorManager.dispose();
    await _states.close();
  }

  /// Stop all activity
  void _stopAll() {
    _disposeEngine();
    _validationTimer?.cancel();
    _sensorSub?.cancel();
    _sensorSub = null;
    _sensorManager.stop();
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
    // Placeholder - invite beacon functionality can be added later
    _emitIfChanged(_state.copyWith(inviteBeaconEnabled: enabled));
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

    if (sid == null || peerId == null || kind == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final msg = ShareOfferMessage(
      v: _protocolVersion,
      sid: sid,
      ts: now,
      mid: _shortRandomId(),
      offerId: _shortRandomId(),
      kind: kind == ShareKind.phone ? 'phone' : 'social',
      value: _state.pendingShare.text,
    );

    await plugin.send(msg);
    _emitIfChanged(_state.copyWith(pendingShare: const PendingShare.empty()));
  }

  Future<void> onIncomingShareDecision({required bool accept}) async {
    final sid = _sessionId;
    final offer = _state.incomingShareOffer;
    if (sid == null || offer == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final msg = ShareResponseMessage(
      v: _protocolVersion,
      sid: sid,
      ts: now,
      mid: _shortRandomId(),
      offerId: offer.offerId,
      decision: accept ? 'accept' : 'reject',
    );

    await plugin.send(msg);
    _stopAll();
  }
}

/// Transport for game engine
final class _CoordinatorTransport implements GameTransport {
  final NomatchP2pPlugin plugin;
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
