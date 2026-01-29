import '../../plugins/p2p/p2p_messages.dart';
import 'dart:async';
import 'dart:developer' as dev;

import 'game_state.dart';
import 'models.dart';
import 'question_bank.dart'; // ✅ FIX: Import QuestionProvider and QuestionPair from question_bank

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
  static const int graceWindowMs = 800;
  static const String noSelectionChoice = 'none';

  final GameTransport transport;
  final bool isLeader;
  final bool externalRoundControl;
  final String sessionId;
  final String localDeviceId;
  final QuestionProvider? questions; // ✅ NEW: For question asset embedding

  String? _peerId;
  int _nowMs = 0;

  GameState _state = const GameState.initial();
  final StreamController<GameState> _states = StreamController<GameState>.broadcast();
  final StreamController<RoundSnapshot> _snapshots = StreamController<RoundSnapshot>.broadcast();

  Stream<GameState> get states => _states.stream;
  Stream<RoundSnapshot> get snapshots => _snapshots.stream;
  GameState get state => _state;

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

  void onPeerConnected({required String peerId}) {
    _peerId = peerId;
    _finalizedRounds.clear(); // Clear finalized rounds for new game
    _setState(_state.copyWith(phase: GamePhase.pairing, clearLastErrorCode: true));
    if (isLeader && !externalRoundControl) {
      _maybeStartFirstRound();
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
    if (_state.phase == GamePhase.terminalSuccess) {
      _setState(_state.copyWith(phase: GamePhase.share));
      return;
    }

    final r = _state.currentRound;
    if (_state.phase != GamePhase.playing || r == null) return;

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
    if (_state.phase == GamePhase.playing) return;
    if (_peerId == null) return;
    if (_nowMs == 0) return; // needs external tick for determinism
    _startLeaderRound(now: _nowMs);
  }

  void _onGameStart(GameStartMessage msg) {
    dev.log("ENGINE: _onGameStart called, startAtMs=${msg.startAtMs}");
    
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
          if (_peerId != null && _nowMs > 0) {
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
    
    // No startAtMs or delay already passed: start immediately
    if (_peerId != null && _nowMs > 0) {
      _startLeaderRound(now: _nowMs);
    }
  }

  void _startLeaderRound({required int now}) {
    final rid = _nextRid++;
    final qid = _nextQid++;
    final deadlineMs = now + roundMs;
    final startAtMs = now + 600; // Schedule start 600ms from now

    // ✅ NEW: Get question assets for embedding
    final q = questions?.getById(qid);

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
    if (_state.phase != GamePhase.playing) return;
    final r = _state.currentRound;
    if (r == null) return;
    if (r.localFinal) return;
    if (_nowMs == 0) return;

    // If already past deadline, ignore taps (deadline finalize will handle none).
    if (_nowMs > r.deadlineMs) return;

    final nextRev = r.localRev + 1;
    final rr = r.copyWith(
      localChoice: c,
      localRev: nextRev,
      localFinal: true,
      graceDeadlineMs: r.deadlineMs + graceWindowMs,
    );
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
    if (msg.sid != sessionId) {
      // Transport session ids are device-local; accept selection for current round.
      dev.log("ENGINE: Selection sid mismatch (sessionId=$sessionId, msg.sid=${msg.sid}) - accepting");
    }
    if (_state.phase != GamePhase.playing) return;
    final r = _state.currentRound;
    if (r == null) return;

    // Out-of-order: old rid is dropped.
    if (msg.rid < r.rid) return;
    if (msg.rid > r.rid) {
      // Newer rid arrived unexpectedly: ignore (follower should wait for round_start).
      return;
    }

    // Deadline validity.
    if (msg.madeAtMs > r.deadlineMs) return;

    // Same rid: accept only highest rev.
    if (msg.rev < r.peerRev) return;

    final c = choiceFromWire(msg.choice);
    if (c == null) return;

    final rr = r.copyWith(
      peerChoice: c,
      peerRev: msg.rev,
      peerFinal: msg.isFinal,
    );
    _setState(_state.copyWith(currentRound: rr));
    _finalizeIfComplete(rr);
  }

  void _finalizeIfComplete(CurrentRound r) {
    if (_nowMs == 0) return;
    if (!r.isComplete(_nowMs)) return;
    
    // Prevent duplicate counting: if this round was already finalized, skip
    if (_finalizedRounds.contains(r.rid)) {
      dev.log("ENGINE: Round ${r.rid} already finalized, skipping duplicate count");
      return;
    }
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
    
    // Emit snapshot for UI
    if (_peerId != null && next.currentRound != null) {
      final r = next.currentRound!;
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
        phase: next.phase,
        terminal: null, // GameState doesn't track terminal directly
      );
      _snapshots.add(snap);
    }
  }

  String _makeMid(String kind, {required int rid, required int now}) {
    // Deterministic, allocation-light: caller provides now.
    return '$localDeviceId:$kind:$rid:$now';
  }

  Future<void> dispose() async {
    _cancelPendingStartTimer();
    await _states.close();
  }
}

