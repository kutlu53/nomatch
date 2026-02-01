import '../../plugins/p2p/p2p_messages.dart';
import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'game_state.dart';
import 'models.dart';
import 'question_bank.dart'; // ✅ FIX: Import QuestionProvider and QuestionPair from question_bank
import 'lazy_question_provider.dart';

abstract class GameTransport {
  Future<void> send(P2pMessage msg);
}

/// Deterministic, UI-free game engine.
///
/// - Uses epoch ms (ts/deadlineMs).
/// - Does not import plugin; only depends on [GameTransport].
/// - Emits immutable [GameState] only when it changes.
final class GameEngine {
  static const int protocolVersion = 1;
  static const int roundMs = 5000;
  static const int graceWindowMs = 3000; // ✅ Increased from 800ms to handle BLE delays
  static const String noSelectionChoice = 'none';

  final GameTransport transport;
  final bool isLeader;
  final bool externalRoundControl;
  final String sessionId;
  final String localDeviceId;
  final QuestionProvider? questions; // ✅ NEW: For question asset embedding

  String? _peerId;
  int _nowMs = 0;
  int? _shuffleSeed; // ✅ NEW: Seed for question shuffling

  GameState _state = const GameState.initial();
  final StreamController<GameState> _states = StreamController<GameState>.broadcast();
  final StreamController<RoundSnapshot> _snapshots = StreamController<RoundSnapshot>.broadcast();

  Stream<GameState> get states => _states.stream;
  Stream<RoundSnapshot> get snapshots => _snapshots.stream;
  GameState get state => _state;
  
  /// ✅ NEW: Check if game is over (terminal state reached)
  bool get isGameTerminal => _state.phase == GamePhase.terminalSuccess || _state.phase == GamePhase.terminalFail;

  // Leader-only bookkeeping.
  int _nextRid = 1;
  int _nextQid = 1;
  
  // Track finalized rounds to prevent duplicate counting
  final Set<int> _finalizedRounds = {};

  GameEngine({
    required this.transport,
    required this.isLeader,
    this.externalRoundControl = false,
    required this.sessionId,
    required this.localDeviceId,
    this.questions, // ✅ NEW
  });

  Future<void> onPeerConnected({required String peerId}) async {
    print("ENGINE: onPeerConnected called, peerId=$peerId, isLeader=$isLeader, externalRoundControl=$externalRoundControl");
    _peerId = peerId;
    _finalizedRounds.clear(); // Clear finalized rounds for new game
    
    // ✅ Leader: Generate random seed
    if (isLeader) {
      _shuffleSeed = math.Random().nextInt(1000000);
      print("ENGINE: 🎲 Generated shuffle seed: $_shuffleSeed");
    }
    
    // ✅ FIXED: Reshuffle questions with seed FIRST and AWAIT completion
    await _reshuffleWithSeedAsync();
    
    // ✅ FIXED: Send GameStartMessage AFTER reshuffle (both leader and follower ready)
    if (isLeader) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final startAtMs = now + 600; // Start 600ms from now for synchronization
      final msg = GameStartMessage(
        v: protocolVersion,
        sid: sessionId,
        seed: _shuffleSeed,
        startAtMs: startAtMs, // ✅ NEW: Schedule synchronized start
      );
      transport.send(msg);
      print("ENGINE: 📤 Sent GameStartMessage with seed=$_shuffleSeed, startAtMs=$startAtMs");
    }
    
    _setState(_state.copyWith(phase: GamePhase.pairing, clearLastErrorCode: true));
    if (isLeader && !externalRoundControl) {
      print("ENGINE: ⏰ Deferring first round start (waiting for UI to be ready)");
      // ✅ NEW: Defer first round until UI is ready (animated transition complete)
      // Wait 500ms to let UI transition animations settle, then start
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_peerId != null) {
          print("ENGINE: 🚀 NOW calling _maybeStartFirstRound");
          _maybeStartFirstRound();
        }
      });
    } else {
      print("ENGINE: Skipping _maybeStartFirstRound - isLeader=$isLeader, externalRoundControl=$externalRoundControl");
    }
  }
  
  /// ✅ FIXED: Reshuffle with seed (async version)
  Future<void> _reshuffleWithSeedAsync() async {
    if (_shuffleSeed == null) {
      print("ENGINE: ⚠️ No shuffle seed, using default order");
      return;
    }
    
    if (questions is LazyQuestionProvider) {
      try {
        await (questions as LazyQuestionProvider).reshuffleForSession(sessionId, _shuffleSeed!);
        print("ENGINE: ✅ Questions reshuffled with seed=$_shuffleSeed");
      } catch (e) {
        print("ENGINE: ❌ ERROR reshuffling questions: $e");
      }
    }
  }

  void onPeerDisconnected() {
    _peerId = null;
    _cancelPendingStartTimer();
    _resetToPairing();
  }

  void onTick(int nowEpochMs) {
    _nowMs = nowEpochMs;

    // TerminalSuccess is a transient marker; next tick moves to Share.
    // ✅ Don't auto-transition to share - let UI handle animation then call onOpenShare
    // Terminal states will be converted to share after animation completes
    if (_state.phase == GamePhase.terminalSuccess || _state.phase == GamePhase.terminalFail) {
      return;
    }

    final r = _state.currentRound;
    if (_state.phase != GamePhase.playing) {
      dev.log("ENGINE: onTick skipped - phase=${_state.phase}, not playing");
      return;
    }
    if (r == null) {
      dev.log("ENGINE: onTick skipped - no currentRound");
      return;
    }

    // Deadline: local must finalize and send none if not tapped.
    if (!r.localFinal && nowEpochMs >= r.deadlineMs) {
      _finalizeLocalNoneAtDeadline(r);
      return;
    }

    // Grace: if local finalized and peer not final, start grace and/or finalize peer none.
    if (r.localFinal && !r.peerFinal) {
      final withGrace = r.graceDeadlineMs == null ? r.copyWith(graceDeadlineMs: r.deadlineMs + graceWindowMs) : r;
      if (withGrace != r) _setState(_state.copyWith(currentRound: withGrace));

      if (withGrace.isGracePassed(nowEpochMs)) {
        final rr = withGrace.copyWith(peerChoice: Choice.none, peerFinal: true);
        _setState(_state.copyWith(currentRound: rr));
        _finalizeIfComplete(rr);
      }
    }

    // Leader auto-advances after complete; follower waits for round_start.
    if (r.isComplete(nowEpochMs)) {
      _finalizeIfComplete(r);
    }
  }

  void onLocalTapTop() => _onLocalTap(Choice.top);
  void onLocalTapBottom() => _onLocalTap(Choice.bottom);
  
  /// Public API: select(choice) for UI interaction
  void select(String choice) {
    if (choice == 'top') {
      _onLocalTap(Choice.top);
    } else if (choice == 'bottom') {
      _onLocalTap(Choice.bottom);
    }
  }

  // ✅ NEW: Store peer game result
  int? _peerSimilarity;
  int? _peerDifference;
  
  int? get peerSimilarity => _peerSimilarity;
  int? get peerDifference => _peerDifference;
  
  void _handlePeerGameResult(String jsonValue) {
    try {
      final json = jsonDecode(jsonValue) as Map<String, dynamic>;
      _peerSimilarity = json['similarity'] as int?;
      _peerDifference = json['difference'] as int?;
      dev.log("ENGINE: Peer result stored - similarity=$_peerSimilarity, difference=$_peerDifference");
      
      // ✅ FIX: When peer sends game_result, game is OVER - transition to terminal state
      // The peer has already determined the game outcome, so we must match it
      if (_peerDifference != null && _peerDifference! >= 5) {
        print("[ENGINE] 🎮 Peer reached 5 differences - transitioning to terminalFail");
        _setState(_state.copyWith(
          phase: GamePhase.terminalFail,
          difference: _peerDifference!, // Sync with peer's count
          similarity: _peerSimilarity ?? _state.similarity,
        ));
      } else if (_peerSimilarity != null && _peerSimilarity! >= 5) {
        print("[ENGINE] 🎮 Peer reached 5 similarities - transitioning to terminalSuccess");
        _setState(_state.copyWith(
          phase: GamePhase.terminalSuccess,
          similarity: _peerSimilarity!, // Sync with peer's count
          difference: _peerDifference ?? _state.difference,
        ));
      }
    } catch (e) {
      dev.log("ENGINE: ❌ Error parsing peer game result: $e");
    }
  }

  void onP2pMessage(P2pMessage msg) {
    dev.log("ENGINE: Received message: ${msg.runtimeType}");
    
    // ✅ SADE PAIRING: Switch exhaustiveness garantisi - tüm mesaj tipleri için case'ler
    // SensorSnapshotMessage ve PairRejectMessage pairing için kritik (engine'de ignore edilir)
    switch (msg) {
      // Oyun mesajları
      case GameStartMessage():
        dev.log("ENGINE: Processing GameStartMessage (startAtMs=${msg.startAtMs})");
        _onGameStart(msg);
      case RoundStartMessage():
        dev.log("ENGINE: Processing RoundStartMessage (rid=${msg.rid}, qid=${msg.qid})");
        _onRoundStart(msg);
      case SelectionMessage():
        dev.log("ENGINE: Processing SelectionMessage");
        _onPeerSelection(msg);
      case HeartbeatMessage():
        // No protocol logic in engine (no timeout handling here).
        return;
      case ShareOfferMessage():
        // ✅ NEW: Handle game result and share info messages
        print("[ENGINE] 📨 ═══════════════════════════════════════");
        print("[ENGINE] 📨 ShareOfferMessage ALINDı!");
        print("[ENGINE] 📨 ═══════════════════════════════════════");
        print("[ENGINE]    - Tür (kind): ${msg.kind}");
        print("[ENGINE]    - Değer: ${msg.value}");
        print("[ENGINE]    - Extra: ${msg.extra}");
        
        if (msg.kind == 'game_result') {
          print("[ENGINE] 🎮 game_result olarak işleniyor...");
          dev.log("ENGINE: Received game_result from peer: ${msg.value}");
          _handlePeerGameResult(msg.value);
        } else if (msg.kind == 'share_info') {
          print("[ENGINE] 👤 share_info olarak işleniyor...");
          dev.log("ENGINE: Received share_info from peer: ${msg.value}");
          _onPeerShareOffer(msg);
        } else {
          print("[ENGINE] ⚠️ Bilinmeyen kind: ${msg.kind}");
        }
        return;
      case ShareResponseMessage():
        // Engine does not process share content; upper layer may use this as a hint.
        return;
      case ErrorMessage():
        dev.log("ENGINE: Processing ErrorMessage (code=${msg.code})");
        _setState(_state.copyWith(lastErrorCode: msg.code));
        _resetToPairing();
      case HelloMessage():
        return;
      
      // ✅ Pairing için kritik mesajlar (engine'de ignore edilir)
      case SensorSnapshotMessage():
        // Sensor snapshot is for pairing validation, not game logic
        return;
      case PairRejectMessage():
        // Pair reject is handled at pairing layer, not game engine
        return;
      case PairIntentMessage():
        // Pair intent is for pairing negotiation, not game engine
        return;
      case PairAckMessage():
        // Pair ack is for pairing negotiation, not game engine
        return;
    }
  }

  // Game start synchronization state
  Timer? _gameStartTimer;
  int? _pendingGameStartAtMs;

  /// Cancel pending game start timer and clear state
  void _cancelPendingStartTimer() {
    _gameStartTimer?.cancel();
    _gameStartTimer = null;
    _pendingGameStartAtMs = null;
    // Clear state.pendingGameStartAtMs
    if (_state.pendingGameStartAtMs != null) {
      _setState(_state.copyWith(clearPendingGameStartAtMs: true));
    }
  }

  void _maybeStartFirstRound() {
    print("ENGINE: _maybeStartFirstRound called - phase=${_state.phase}, peerId=$_peerId, nowMs=$_nowMs");
    if (_state.phase == GamePhase.playing) {
      print("ENGINE: _maybeStartFirstRound skipped - already playing");
      return;
    }
    if (_peerId == null) {
      print("ENGINE: _maybeStartFirstRound skipped - peerId is null");
      return;
    }
    print("ENGINE: _maybeStartFirstRound starting round");
    _startLeaderRound(now: _nowMs);
  }

  void _onGameStart(GameStartMessage msg) {
    dev.log("ENGINE: _onGameStart called, startAtMs=${msg.startAtMs}");
    
    // ✅ FIXED: Peer receives seed from leader and reshuffles BEFORE starting game
    if (msg.seed != null && !isLeader) {
      _shuffleSeed = msg.seed;
      print("ENGINE: 📥 Received shuffle seed from leader: $_shuffleSeed");
      // Reshuffle and then continue with game start after reshuffle completes
      _reshuffleWithSeedAsync().then((_) {
        print("ENGINE: ✅ Peer questions reshuffled, continuing with game start");
        _proceedWithGameStart(msg);
      }).catchError((e) {
        print("ENGINE: ❌ Reshuffle failed: $e, continuing anyway");
        _proceedWithGameStart(msg);
      });
      return; // Wait for reshuffle
    }
    
    // Leader or no seed: proceed immediately
    _proceedWithGameStart(msg);
  }
  
  /// ✅ NEW: Continue game start after reshuffle (if needed)
  void _proceedWithGameStart(GameStartMessage msg) {
    
    if (msg.startAtMs != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final delayMs = (msg.startAtMs! - now).clamp(0, double.infinity).toInt();
      
      // ✅ [SYNC] log: GameStart alınınca
      print("[SYNC] recv startAtMs=${msg.startAtMs}, now=$now, delay=$delayMs, leader=$isLeader, peerId=$_peerId");
      dev.log("[SYNC] recv startAtMs=${msg.startAtMs}, now=$now, delay=$delayMs, leader=$isLeader, peerId=$_peerId");
      
      if (delayMs > 0) {
        dev.log("ENGINE: Scheduling game start in ${delayMs}ms (startAtMs=${msg.startAtMs}, now=$now)");
        _pendingGameStartAtMs = msg.startAtMs;
        // Update state to show pending start (for UI ring progress)
        _setState(_state.copyWith(pendingGameStartAtMs: msg.startAtMs));
        _gameStartTimer?.cancel();
        _gameStartTimer = Timer(Duration(milliseconds: delayMs), () {
          final fireNow = DateTime.now().millisecondsSinceEpoch;
          final plannedStartAtMs = msg.startAtMs!;
          final driftMs = fireNow - plannedStartAtMs;
          
          // ✅ [SYNC] log: Timer tetiklenince
          print("[SYNC] FIRE now=$fireNow, plannedStartAtMs=$plannedStartAtMs, driftMs=$driftMs");
          dev.log("[SYNC] FIRE now=$fireNow, plannedStartAtMs=$plannedStartAtMs, driftMs=$driftMs");
          
          // ✅ [SYNC] WARNING: driftMs mutlak değeri > 80ms ise
          if (driftMs.abs() > 80) {
            print("[SYNC] WARNING drift=${driftMs}ms (planned=$plannedStartAtMs, actual=$fireNow)");
            dev.log("[SYNC] WARNING drift=${driftMs}ms (planned=$plannedStartAtMs, actual=$fireNow)");
          }
          
          dev.log("ENGINE: Game start delay completed, starting first round");
          _pendingGameStartAtMs = null;
          _setState(_state.copyWith(clearPendingGameStartAtMs: true));
          if (_peerId != null) {
            dev.log("ENGINE: Starting first round after delay (fireNow=$fireNow)");
            _startLeaderRound(now: fireNow);
          }
        });
        return; // Delay start, don't start immediately
      } else {
        dev.log("ENGINE: startAtMs is in the past or now, starting immediately");
        _pendingGameStartAtMs = null;
        _setState(_state.copyWith(clearPendingGameStartAtMs: true));
      }
    }
    
    // No startAtMs or delay already passed: start immediately (LEADER only)
    if (isLeader && _peerId != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      dev.log("ENGINE: Starting first round immediately (now=$now, _nowMs=$_nowMs)");
      _startLeaderRound(now: now);
    }
  }

  void _startLeaderRound({required int now}) {
    final rid = _nextRid++;
    // ✅ RANDOM QID: Each round picks a random question
    final qid = questions?.nextQid() ?? _nextQid++;
    final deadlineMs = now + roundMs;
    final startAtMs = now + 600; // Schedule start 600ms from now

    // ✅ NEW: Get question assets for embedding
    final q = questions?.getById(qid);
    dev.log("ENGINE: _startLeaderRound qid=$qid, questions=${questions != null ? "LOADED" : "NULL"}, q=${q != null ? "FOUND" : "NULL"}, top=${q?.topAsset}, bottom=${q?.bottomAsset}");

    final round = CurrentRound(
      rid: rid,
      qid: qid,
      deadlineMs: deadlineMs,
      localChoice: null,
      peerChoice: null,
      localFinal: false,
      peerFinal: false,
      localRev: 0,
      peerRev: 0,
      graceDeadlineMs: null,
      topAsset: q?.topAsset, // ✅ NEW: Embed question asset
      bottomAsset: q?.bottomAsset, // ✅ NEW: Embed question asset
    );

    _setState(_state.copyWith(phase: GamePhase.playing, currentRound: round));

    transport.send(
      RoundStartMessage(
        v: protocolVersion,
        sid: sessionId,
        mid: _makeMid('round_start', rid: rid, now: now),
        rid: rid,
        qid: qid,
        deadlineMs: deadlineMs,
        leaderId: localDeviceId,
        startAtMs: startAtMs,
        topAsset: q?.topAsset, // ✅ NEW: Embed question asset
        bottomAsset: q?.bottomAsset, // ✅ NEW: Embed question asset
      ),
    );
  }

  void _onRoundStart(RoundStartMessage msg) {
    dev.log("ENGINE: _onRoundStart called");
    dev.log("ENGINE: isLeader=$isLeader, msg.sid=${msg.sid}, sessionId=$sessionId");
    
    if (isLeader && msg.leaderId != localDeviceId) {
      dev.log("ENGINE: Leader ignoring RoundStartMessage from another leaderId=${msg.leaderId}");
      return;
    }
    if (isLeader) {
      dev.log("ENGINE: Leader processing local RoundStartMessage");
    }
    
    if (msg.sid != sessionId) {
      if (isLeader) {
        dev.log("ENGINE: Session ID mismatch, ignoring");
        return;
      }
      dev.log("ENGINE: Session ID mismatch, accepting for follower");
    }
    
    if (_peerId == null) {
      dev.log("ENGINE: No peer connected, ignoring");
      return;
    }

    final cur = _state.currentRound;
    if (cur != null && msg.rid < cur.rid) {
      dev.log("ENGINE: Old rid (${msg.rid} < ${cur.rid}), ignoring");
      return; // drop old rid
    }

    dev.log("ENGINE: Creating new round: rid=${msg.rid}, qid=${msg.qid}, deadline=${msg.deadlineMs}");
    
    // ✅ NEW: Log embedded assets
    dev.log("ENGINE: Question assets - top=${msg.topAsset}, bottom=${msg.bottomAsset}");

    final round = CurrentRound(
      rid: msg.rid,
      qid: msg.qid,
      deadlineMs: msg.deadlineMs,
      localChoice: null,
      peerChoice: null,
      localFinal: false,
      peerFinal: false,
      localRev: 0,
      peerRev: 0,
      graceDeadlineMs: null,
      topAsset: msg.topAsset, // ✅ NEW: Use embedded assets
      bottomAsset: msg.bottomAsset, // ✅ NEW: Use embedded assets
    );

    dev.log("ENGINE: Setting state to PLAYING with new round");
    _setState(_state.copyWith(phase: GamePhase.playing, currentRound: round, clearLastErrorCode: true));
    dev.log("ENGINE: Round started successfully");
  }

  void _onLocalTap(Choice c) {
    print('[ENGINE] 🎯 _onLocalTap called: choice=$c, phase=${_state.phase}, rid=${_state.currentRound?.rid}');
    
    if (_state.phase != GamePhase.playing) {
      print('[ENGINE] ❌ REJECTED: phase != playing');
      return;
    }
    final r = _state.currentRound;
    if (r == null) {
      print('[ENGINE] ❌ REJECTED: currentRound is null');
      return;
    }
    if (r.localFinal) {
      print('[ENGINE] ❌ REJECTED: localFinal=true (already selected in round ${r.rid})');
      return;
    }
    if (_nowMs == 0) {
      print('[ENGINE] ❌ REJECTED: _nowMs is 0');
      return;
    }

    // If already past deadline, ignore taps (deadline finalize will handle none).
    if (_nowMs > r.deadlineMs) {
      print('[ENGINE] ❌ REJECTED: past deadline');
      return;
    }
    
    print('[ENGINE] ✅ TAP ACCEPTED: rid=${r.rid}, choice=$c');
    print('[ENGINE] 📊 Current state BEFORE local tap: localFinal=${r.localFinal}, peerFinal=${r.peerFinal}, peerChoice=${r.peerChoice}');

    final nextRev = r.localRev + 1;
    final rr = r.copyWith(
      localChoice: c,
      localRev: nextRev,
      localFinal: true,
      graceDeadlineMs: r.deadlineMs + graceWindowMs,
    );
    
    print('[ENGINE] 📊 State AFTER local tap: localFinal=${rr.localFinal}, peerFinal=${rr.peerFinal}, peerChoice=${rr.peerChoice}');
    _setState(_state.copyWith(currentRound: rr));

    transport.send(
      SelectionMessage(
        v: protocolVersion,
        sid: sessionId,
        mid: _makeMid('selection', rid: r.rid, now: _nowMs),
        rid: r.rid,
        choice: choiceToWire(c),
        madeAtMs: _nowMs,
        rev: nextRev,
        isFinal: true,
      ),
    );

    _finalizeIfComplete(rr);
  }

  void _finalizeLocalNoneAtDeadline(CurrentRound r) {
    final nextRev = r.localRev + 1;
    final rr = r.copyWith(
      localChoice: Choice.none,
      localRev: nextRev,
      localFinal: true,
      graceDeadlineMs: r.deadlineMs + graceWindowMs,
    );
    _setState(_state.copyWith(currentRound: rr));

    transport.send(
      SelectionMessage(
        v: protocolVersion,
        sid: sessionId,
        mid: _makeMid('selection_none', rid: r.rid, now: _nowMs),
        rid: r.rid,
        choice: 'none',
        madeAtMs: r.deadlineMs,
        rev: nextRev,
        isFinal: true,
      ),
    );
  }

  void _onPeerSelection(SelectionMessage msg) {
    print('[ENGINE] 📨 _onPeerSelection: rid=${msg.rid}, choice=${msg.choice}, isFinal=${msg.isFinal}');
    
    if (msg.sid != sessionId) {
      // Transport session ids are device-local; accept selection for current round.
      dev.log("ENGINE: Selection sid mismatch (sessionId=$sessionId, msg.sid=${msg.sid}) - accepting");
    }
    if (_state.phase != GamePhase.playing) {
      print('[ENGINE] ❌ REJECTED: phase=${_state.phase} (not playing)');
      return;
    }
    final r = _state.currentRound;
    if (r == null) {
      print('[ENGINE] ❌ REJECTED: currentRound is null');
      return;
    }

    // Out-of-order: old rid is dropped.
    if (msg.rid < r.rid) {
      print('[ENGINE] ❌ REJECTED: msg.rid=${msg.rid} < current rid=${r.rid}');
      return;
    }
    if (msg.rid > r.rid) {
      print('[ENGINE] ❌ REJECTED: msg.rid=${msg.rid} > current rid=${r.rid} (unexpected)');
      return;
    }

    // Deadline validity.
    if (msg.madeAtMs > r.deadlineMs) {
      print('[ENGINE] ❌ REJECTED: madeAtMs=${msg.madeAtMs} > deadline=${r.deadlineMs}');
      return;
    }

    // Same rid: accept only highest rev.
    if (msg.rev < r.peerRev) {
      print('[ENGINE] ❌ REJECTED: msg.rev=${msg.rev} < peerRev=${r.peerRev}');
      return;
    }

    final c = choiceFromWire(msg.choice);
    if (c == null) {
      print('[ENGINE] ❌ REJECTED: invalid choice=${msg.choice}');
      return;
    }

    print('[ENGINE] ✅ PEER SELECTION ACCEPTED: rid=${msg.rid}, choice=$c, isFinal=${msg.isFinal}');
    print('[ENGINE] 📊 BEFORE: localFinal=${r.localFinal}, peerFinal=${r.peerFinal}');

    final rr = r.copyWith(
      peerChoice: c,
      peerRev: msg.rev,
      peerFinal: msg.isFinal,
    );
    
    print('[ENGINE] 📊 AFTER: localFinal=${rr.localFinal}, peerFinal=${rr.peerFinal}');
    
    _setState(_state.copyWith(currentRound: rr));
    _finalizeIfComplete(rr);
  }

  void _finalizeIfComplete(CurrentRound r) {
    print('[ENGINE] 🔍 _finalizeIfComplete: rid=${r.rid}, localFinal=${r.localFinal}, peerFinal=${r.peerFinal}, _nowMs=$_nowMs');
    
    if (_nowMs == 0) {
      print('[ENGINE] ⏳ SKIPPED: _nowMs=0 (waiting for first tick)');
      dev.log("ENGINE: _finalizeIfComplete skipped - _nowMs=0 (waiting for first tick)");
      return;
    }
    
    final graceDeadline = r.graceDeadlineMs;
    final gracePassed = graceDeadline != null && _nowMs >= graceDeadline;
    final isComplete = r.localFinal && (r.peerFinal || gracePassed);
    
    print('[ENGINE] 🔍 isComplete check: localFinal=${r.localFinal}, peerFinal=${r.peerFinal}, gracePassed=$gracePassed, graceDeadline=$graceDeadline');
    print('[ENGINE] 🔍 Result: isComplete=$isComplete');
    
    if (!isComplete) {
      print('[ENGINE] ⏳ SKIPPED: round not complete yet');
      dev.log("ENGINE: _finalizeIfComplete skipped - round not complete yet (local=${r.localFinal}, peer=${r.peerFinal})");
      return;
    }
    
    // Prevent duplicate counting: if this round was already finalized, skip
    if (_finalizedRounds.contains(r.rid)) {
      print('[ENGINE] ⏭️ SKIPPED: rid=${r.rid} already finalized');
      dev.log("ENGINE: Round ${r.rid} already finalized, skipping duplicate count");
      return;
    }
    
    print('[ENGINE] ✅ FINALIZING round ${r.rid}!');
    _finalizedRounds.add(r.rid);

    final peerChoice = r.peerFinal ? (r.peerChoice ?? Choice.none) : Choice.none;
    final localChoice = r.localChoice ?? Choice.none;

    // Count similarity only if BOTH players made the SAME choice
    final bool bothChose = localChoice != Choice.none && peerChoice != Choice.none;
    final bool isSimilar = bothChose && localChoice == peerChoice;
    
    // Count difference if:
    // - Both chose but different choices, OR
    // - One or both didn't choose (noSelection counts as difference)
    final bool isDifferent = !isSimilar; // Different choices OR noSelection
    
    final nextSimilarity = _state.similarity + (isSimilar ? 1 : 0);
    final nextDifference = _state.difference + (isDifferent ? 1 : 0);
    dev.log(
      "ENGINE: Round complete rid=${r.rid} qid=${r.qid} local=$localChoice peer=$peerChoice similar=$isSimilar "
      "score=${nextSimilarity}-${nextDifference}",
    );

    var nextPhase = _state.phase;
    if (nextSimilarity == 5) {
      nextPhase = GamePhase.terminalSuccess;
    } else if (nextDifference == 5) {
      nextPhase = GamePhase.terminalFail;
    } else {
      // Keep both devices in playing between rounds to avoid bouncing to pairing UI.
      nextPhase = GamePhase.playing;
    }

    // ✅ Cancel pending start timer on game end
    if (nextPhase == GamePhase.terminalSuccess || nextPhase == GamePhase.terminalFail) {
      _cancelPendingStartTimer();
      
      // ✅ NEW: Send game result to peer
      if (isLeader) {
        transport.send(
          ShareOfferMessage(
            v: protocolVersion,
            sid: sessionId,
            kind: 'game_result',
            value: '{\"similarity\":$nextSimilarity,\"difference\":$nextDifference}',
          ),
        );
      }
    }

    _setState(
      _state.copyWith(
        phase: nextPhase,
        similarity: nextSimilarity,
        difference: nextDifference,
        clearCurrentRound: true,
      ),
    );

    if (nextPhase == GamePhase.playing && isLeader && !externalRoundControl) {
      _startLeaderRound(now: _nowMs);
    }
  }

  void _resetToPairing() {
    _finalizedRounds.clear();
    _cancelPendingStartTimer();
    _setState(
      const GameState.initial().copyWith(
        phase: GamePhase.pairing,
        similarity: 0,
        difference: 0,
        clearCurrentRound: true,
      ),
    );
  }

  void _setState(GameState next) {
    if (next == _state) return;
    _state = next;
    _states.add(next);
    
    // Emit snapshot for UI - even for terminal states to ensure animation triggers
    if (_peerId != null) {
      final r = next.currentRound;
      if (r != null) {
        final snap = RoundSnapshot(
          sessionId: sessionId,
          peerId: _peerId!,
          isLeader: isLeader,
          roundNumber: r.rid,
          startedAtMs: 0, // CurrentRound doesn't track started time
          deadlineMs: r.deadlineMs,
          localChoice: r.localChoice != null ? choiceToWire(r.localChoice!) : null,
          localRevision: r.localRev,
          localFinal: r.localFinal,
          peerChoice: r.peerChoice != null ? choiceToWire(r.peerChoice!) : null,
          peerRevision: r.peerRev,
          peerFinal: r.peerFinal,
          phase: next.phase, // ✅ IMPORTANT: Use new phase for snapshot
          terminal: null, // GameState doesn't track terminal directly
          topAsset: r.topAsset, // ✅ NEW: Pass asset
          bottomAsset: r.bottomAsset, // ✅ NEW: Pass asset
        );
        dev.log("ENGINE: Emitting snapshot - rid=${r.rid}, phase=${next.phase}");
        _snapshots.add(snap);
      } else if (next.isTerminal) {
        // ✅ NEW: Emit snapshot even without currentRound for terminal states
        // This ensures UI gets notified of phase change to terminalSuccess/terminalFail/share
        dev.log("ENGINE: Emitting terminal state snapshot - phase=${next.phase}");
        // Create a minimal snapshot for terminal state
        // Use the last known round number if available, otherwise use 0
        final lastRid = _nextRid - 1; // Last round that was played
        final snap = RoundSnapshot(
          sessionId: sessionId,
          peerId: _peerId!,
          isLeader: isLeader,
          roundNumber: lastRid,
          startedAtMs: 0,
          deadlineMs: 0,
          localChoice: null,
          localRevision: 0,
          localFinal: false,
          peerChoice: null,
          peerRevision: 0,
          peerFinal: false,
          phase: next.phase,
          terminal: null,
          topAsset: null,
          bottomAsset: null,
        );
        _snapshots.add(snap);
      }
    }
  }

  String _makeMid(String kind, {required int rid, required int now}) {
    // Deterministic, allocation-light: caller provides now.
    return '$localDeviceId:$kind:$rid:$now';
  }

  /// ✅ NEW: Send share offer (bilgi paylaşma)
  void sendShareOffer({required Object kind, required String value}) {
    print('[ENGINE] 📤 ═══════════════════════════════════════');
    print('[ENGINE] 📤 PAYLAŞIM GÖNDERME BAŞLATILDI');
    print('[ENGINE] 📤 ═══════════════════════════════════════');
    print('[ENGINE]    - Tür: $kind');
    print('[ENGINE]    - Değer: $value');
    print('[ENGINE]    - Session ID: $sessionId');
    print('[ENGINE]    - Peer ID: $_peerId');
    
    final msg = ShareOfferMessage(
      sid: sessionId,
      kind: 'share_info',
      value: value,
      offerId: _makeMid('share_offer', rid: 0, now: _nowMs),
      extra: {'shareKind': kind.toString()}, // Serialize enum
    );
    
    print('[ENGINE] 📨 BLE üzerinden gönderiliyor...');
    transport.send(msg);
    print('[ENGINE] ✅ Gönderme tamamlandı!');
  }

  /// ✅ NEW: Rakıp bilgi paylaştığında çağrılır
  void _onPeerShareOffer(ShareOfferMessage msg) {
    if (msg.kind != 'share_info' || msg.value.isEmpty) {
      print('[ENGINE] ⚠️ Geçersiz share offer - kind: ${msg.kind}, value: ${msg.value}');
      return;
    }
    
    print('[ENGINE] 📥 ═══════════════════════════════════════');
    print('[ENGINE] 📥 RAKIP PAYLAŞIM ALINDI!');
    print('[ENGINE] 📥 ═══════════════════════════════════════');
    print('[ENGINE]    - Değer: ${msg.value}');
    print('[ENGINE]    - Extra: ${msg.extra}');
    
    // Parse share kind from extra
    final shareKindStr = msg.extra?['shareKind'] as String? ?? '';
    final peerShareKind = shareKindStr.contains('phone') ? 'phone' : 'social';
    print('[ENGINE]    - Tür (parse): $peerShareKind');
    
    print('[ENGINE] 🔄 GameState güncelleniyor...');
    _setState(_state.copyWith(
      peerShared: true,
      peerShareValue: msg.value,
      peerShareKind: peerShareKind,
    ));
    print('[ENGINE] ✅ Durum güncellendi!');
  }

  Future<void> dispose() async {
    _cancelPendingStartTimer();
    await _states.close();
  }
}

