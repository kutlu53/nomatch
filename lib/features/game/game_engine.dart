import '../../plugins/p2p/p2p_messages.dart';
import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'game_state.dart';
import 'models.dart';
import 'question_bank.dart';
import 'lazy_question_provider.dart';

/// ✅ PERFORMANCE: Debug logging control
/// Set to false in production for better performance
const bool _kEngineDebug = false;
const bool _kEngineVerbose = false; // Extra verbose logs (tick, every state change)

void _log(String msg) {
  if (_kEngineDebug) print('ENGINE: $msg');
}

void _logVerbose(String msg) {
  if (_kEngineVerbose) print('ENGINE: $msg');
}

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
  String? _peerActualDeviceId; // ✅ FIX: Peer's actual device ID (from leaderId in messages)
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
  
  // ✅ NEW: Retry intent tracking
  bool _localRetryIntent = false;
  bool _peerRetryIntent = false;
  // ✅ FIX: Duplicate mesaj korumaları (BLE katmanı retry'la gönderdiği için
  // aynı mesaj iki kez teslim edilebilir).
  bool _restartScheduled = false;
  String? _lastRoundStartMid;
  // ✅ FIX: Dispose sonrası çalışan gecikmeli callback'ler kapalı controller'a
  // yazmasın / ölü oturum için BLE mesajı göndermesin.
  bool _disposed = false;
  
  // ✅ FIX: Track if we deferred leadership to peer (for restart conflict resolution)
  bool _deferredToRemoteLeadership = false;
  
  /// ✅ NEW: Check if local player has sent retry intent
  bool get localRetryIntent => _localRetryIntent;
  
  /// ✅ NEW: Check if peer has sent retry intent  
  bool get peerRetryIntent => _peerRetryIntent;
  
  /// ✅ SIMPLIFIED: Effective leader check
  /// Just use the original isLeader flag from pairing, adjusted for any conflicts
  bool get _effectiveLeader {
    return isLeader && !_deferredToRemoteLeadership;
  }

  GameEngine({
    required this.transport,
    required this.isLeader,
    this.externalRoundControl = false,
    required this.sessionId,
    required this.localDeviceId,
    this.questions, // ✅ NEW
  });

  Future<void> onPeerConnected({required String peerId}) async {
    _log(" onPeerConnected called, peerId=$peerId, isLeader=$isLeader, externalRoundControl=$externalRoundControl");
    _peerId = peerId;
    
    // ✅ FIX: Reset ALL game state for new connection
    _finalizedRounds.clear();
    _nextRid = 1;
    _nextQid = 1;
    _localRetryIntent = false;
    _peerRetryIntent = false;
    _peerSimilarity = null;
    _peerDifference = null;
    
    // Reset game state to initial values
    _setState(const GameState.initial().copyWith(
      phase: GamePhase.pairing,
      similarity: 0,
      difference: 0,
      clearCurrentRound: true,
      clearLastErrorCode: true,
    ));
    
    // ✅ Leader: Generate random seed
    if (isLeader) {
      _shuffleSeed = math.Random().nextInt(1000000);
      _log(" 🎲 Generated shuffle seed: $_shuffleSeed");
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
        leaderId: localDeviceId, // ✅ NEW: Send our actual device ID
      );
      _send(msg);
      _log(" 📤 Sent GameStartMessage with seed=$_shuffleSeed, startAtMs=$startAtMs, leaderId=$localDeviceId");
    }
    
    // Note: State already set above with similarity=0, difference=0
    if (isLeader && !externalRoundControl) {
      _log(" ⏰ Deferring first round start (waiting for UI to be ready)");
      // ✅ NEW: Defer first round until UI is ready (animated transition complete)
      // Wait 500ms to let UI transition animations settle, then start
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_disposed) return; // eşleşme bu sırada kapatılmış olabilir
        // ✅ FIX: Check _effectiveLeader in case we deferred during the delay
        if (_peerId != null && _effectiveLeader) {
          _log(" 🚀 NOW calling _maybeStartFirstRound");
          _maybeStartFirstRound();
        } else if (_deferredToRemoteLeadership) {
          _log(" ⏭️ Skipping _maybeStartFirstRound - deferred to remote leadership");
        }
      });
    } else {
      _log(" Skipping _maybeStartFirstRound - isLeader=$isLeader, externalRoundControl=$externalRoundControl");
    }
  }
  
  /// ✅ FIXED: Reshuffle with seed (async version)
  Future<void> _reshuffleWithSeedAsync() async {
    if (_shuffleSeed == null) {
      _log(" ⚠️ No shuffle seed, using default order");
      return;
    }
    
    if (questions is LazyQuestionProvider) {
      try {
        await (questions as LazyQuestionProvider).reshuffleForSession(sessionId, _shuffleSeed!);
        _log(" ✅ Questions reshuffled with seed=$_shuffleSeed");
      } catch (e) {
        _log(" ❌ ERROR reshuffling questions: $e");
      }
    }
  }

  void onPeerDisconnected() {
    _peerId = null;
    _cancelPendingStartTimer();
    _resetToPairing();
  }

  /// ✅ NEW: Restart game with the same peer (for retry after failure)
  Future<void> restartGame() async {
    if (_peerId == null) {
      _log(" ⚠️ Cannot restart - no peer connected");
      return;
    }
    
    // ✅ SIMPLIFIED: Just use the original isLeader flag from pairing
    // Don't use _effectiveLeader - it has complex logic that can cause both devices to think they're leader
    final shouldBeLeader = isLeader && !_deferredToRemoteLeadership;
    
    _log(" 🔄 ═══════════════════════════════════════");
    _log(" 🔄 RESTARTING GAME WITH SAME PEER");
    _log(" 🔄 Keeping established role: shouldBeLeader=$shouldBeLeader");
    _log(" 🔄 (isLeader=$isLeader, _deferredToRemoteLeadership=$_deferredToRemoteLeadership)");
    _log(" 🔄 ═══════════════════════════════════════");
    
    // Reset game state
    _finalizedRounds.clear();
    _cancelPendingStartTimer();
    _nextRid = 1;
    _nextQid = 1;
    _nowMs = 0; // ✅ FIX: Reset time tracking (will be updated by ticker)
    
    // ✅ Reset retry flags (but NOT leadership - already established!)
    _localRetryIntent = false;
    _peerRetryIntent = false;
    
    // ✅ FIX: Reset peer game result from previous game
    _log(" 🔄 Resetting peer game result (was: sim=$_peerSimilarity, diff=$_peerDifference)");
    _peerSimilarity = null;
    _peerDifference = null;
    
    // ✅ NOTE: NOT resetting _deferredToRemoteLeadership - keep established roles!
    
    // Generate new shuffle seed (leader only)
    if (shouldBeLeader) {
      _shuffleSeed = math.Random().nextInt(1000000);
      _log(" 🎲 New shuffle seed: $_shuffleSeed");
    }
    
    // Reshuffle questions
    await _reshuffleWithSeedAsync();
    
    // Reset state to playing
    _setState(const GameState.initial().copyWith(
      phase: GamePhase.pairing,
      similarity: 0,
      difference: 0,
      clearCurrentRound: true,
      clearLastErrorCode: true,
    ));
    
    // ✅ FIX: Only the deterministic leader sends GameStartMessage
    if (shouldBeLeader) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final startAtMs = now + 600;
      final msg = GameStartMessage(
        v: protocolVersion,
        sid: sessionId,
        seed: _shuffleSeed,
        startAtMs: startAtMs,
        leaderId: localDeviceId, // ✅ NEW: Send our actual device ID
      );
      _send(msg);
      _log(" 📤 Sent new GameStartMessage for restart (seed=$_shuffleSeed, leaderId=$localDeviceId)");
      
      // Start first round after delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_disposed) return; // eşleşme bu sırada kapatılmış olabilir
        if (_peerId != null && _effectiveLeader) {
          _log(" 🚀 Starting first round (restart)");
          _maybeStartFirstRound();
        } else {
          _log(" ⚠️ Cannot start round - peerId=$_peerId, _effectiveLeader=$_effectiveLeader");
        }
      });
    } else {
      // ✅ Follower: wait for GameStartMessage from leader
      _log(" 👥 Follower waiting for GameStartMessage from leader (we have larger ID)");
    }
  }

  // ✅ FIX: Fire-and-forget gönderim yardımcısı. transport.send() artık
  // bağlantı kopunca exception fırlatıyor; beklemeden gönderilen mesajlarda
  // bu hatanın unhandled kalmaması için burada yakalanıp loglanır.
  void _send(P2pMessage msg) {
    transport
        .send(msg)
        .catchError((Object e) => _log(' ⚠️ send failed (${msg.runtimeType}): $e'));
  }

  /// ✅ NEW: Send retry intent (called when player presses retry button)
  void sendRetryIntent() {
    if (_peerId == null) {
      _log(" ⚠️ Cannot send retry intent - no peer connected");
      return;
    }
    
    if (_localRetryIntent) {
      _log(" ⚠️ Retry intent already sent");
      return;
    }
    
    _log(" 🔄 ═══════════════════════════════════════");
    _log(" 🔄 SENDING RETRY INTENT");
    _log(" 🔄 ═══════════════════════════════════════");
    
    _localRetryIntent = true;

    // Retry intent mesajını gönder. BLE kopuksa send() exception fırlatabilir;
    // unhandled future'dan kaçınmak için hata sessizce loglanıyor.
    transport.send(RetryIntentMessage(sid: sessionId))
        .catchError((e) => _log('[ENGINE] ⚠️ Retry intent gönderilemedi: $e'));

    // Check if both players want to retry
    _checkBothRetryIntent();
  }
  
  /// ✅ NEW: Handle incoming retry intent from peer
  void _onPeerRetryIntent() {
    // ✅ FIX: Duplicate intent ikinci kez restart planlamasın.
    // (Erken gelen intent kabul edilir: karşı taraf grace farkıyla birkaç
    // saniye önce bitirip retry'a basmış olabilir. Bayat intent'e karşı
    // koruma tur başlangıcında yapılır — yeni tur başlıyorsa önceki oyundan
    // kalan intent geçersizdir.)
    if (_peerRetryIntent) {
      _log(" ⚠️ Duplicate peer retry intent ignored");
      return;
    }

    _log(" 🔄 ═══════════════════════════════════════");
    _log(" 🔄 RECEIVED PEER RETRY INTENT");
    _log(" 🔄 ═══════════════════════════════════════");

    _peerRetryIntent = true;
    
    // Notify UI that peer wants to retry
    _states.add(_state); // Trigger UI update
    
    // Check if both players want to retry
    _checkBothRetryIntent();
  }
  
  /// ✅ NEW: Check if both players want to retry and restart game
  void _checkBothRetryIntent() {
    _log(" 🔍 Checking retry intent - local=$_localRetryIntent, peer=$_peerRetryIntent");
    
    if (_localRetryIntent && _peerRetryIntent) {
      // ✅ FIX: Restart zaten planlandıysa ikinci kez planlama (duplicate
      // mesaj çift restart'a ve çift GameStart gönderimine yol açıyordu).
      if (_restartScheduled) {
        _log(" ⚠️ Restart already scheduled - ignoring");
        return;
      }
      _restartScheduled = true;

      _log(" ✅ ═══════════════════════════════════════");
      _log(" ✅ BOTH PLAYERS WANT TO RETRY - STARTING COUNTDOWN!");
      _log(" ✅ ═══════════════════════════════════════");

      // ✅ NEW: Set restarting phase to show green arrow on both phones
      _setState(_state.copyWith(phase: GamePhase.restarting));

      // ✅ Wait 500ms for the "game starting" animation, then restart
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_disposed) return; // eşleşme bu sırada kapatılmış olabilir
        _restartScheduled = false;
        if (_peerId == null) {
          _log(" ⚠️ Peer disconnected during restart countdown");
          return;
        }

        _log(" 🚀 Countdown complete - restarting game!");

        // Reset retry flags
        _localRetryIntent = false;
        _peerRetryIntent = false;

        // Restart the game
        restartGame();
      });
    }
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
      
      // ✅ SAFETY: Check if game has enough rounds before accepting terminal state
      final totalRounds = (_peerSimilarity ?? 0) + (_peerDifference ?? 0);
      final localTotalRounds = _state.similarity + _state.difference;
      _log("🎮 Peer game result - totalRounds=$totalRounds (peer), localTotalRounds=$localTotalRounds (local)");
      
      if (_peerDifference != null && _peerDifference! >= 5) {
        if (totalRounds < 5) {
          _log("[ENGINE] ⚠️ SUSPICIOUS: Peer claims 5 differences but total rounds=$totalRounds (ignoring)");
          return;
        }
        _log("[ENGINE] 🎮 Peer reached 5 differences - transitioning to terminalFail");
        _setState(_state.copyWith(
          phase: GamePhase.terminalFail,
          difference: _peerDifference!, // Sync with peer's count
          similarity: _peerSimilarity ?? _state.similarity,
        ));
      } else if (_peerSimilarity != null && _peerSimilarity! >= 5) {
        if (totalRounds < 5) {
          _log("[ENGINE] ⚠️ SUSPICIOUS: Peer claims 5 similarities but total rounds=$totalRounds (ignoring)");
          return;
        }
        _log("[ENGINE] 🎮 Peer reached 5 similarities - transitioning to terminalSuccess");
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
    _log(" 📬 Received message: ${msg.runtimeType}");
    
    // ✅ SADE PAIRING: Switch exhaustiveness garantisi - tüm mesaj tipleri için case'ler
    // SensorSnapshotMessage ve PairRejectMessage pairing için kritik (engine'de ignore edilir)
    switch (msg) {
      // Oyun mesajları
      case GameStartMessage():
        _log(" 🎮 Processing GameStartMessage (startAtMs=${msg.startAtMs}, seed=${msg.seed})");
        _onGameStart(msg);
      case RoundStartMessage():
        _log(" 🎯 Processing RoundStartMessage (rid=${msg.rid}, qid=${msg.qid})");
        _onRoundStart(msg);
      case SelectionMessage():
        dev.log("ENGINE: Processing SelectionMessage");
        _onPeerSelection(msg);
      case HeartbeatMessage():
        // No protocol logic in engine (no timeout handling here).
        return;
      case ShareOfferMessage():
        // ✅ NEW: Handle game result and share info messages
        _log("[ENGINE] 📨 ═══════════════════════════════════════");
        _log("[ENGINE] 📨 ShareOfferMessage ALINDı!");
        _log("[ENGINE] 📨 ═══════════════════════════════════════");
        _log("[ENGINE]    - Tür (kind): ${msg.kind}");
        _log("[ENGINE]    - Değer: ${msg.value}");
        _log("[ENGINE]    - Extra: ${msg.extra}");
        
        if (msg.kind == 'game_result') {
          _log("[ENGINE] 🎮 game_result olarak işleniyor...");
          dev.log("ENGINE: Received game_result from peer: ${msg.value}");
          _handlePeerGameResult(msg.value);
        } else if (msg.kind == 'share_info') {
          _log("[ENGINE] 👤 share_info olarak işleniyor...");
          dev.log("ENGINE: Received share_info from peer: ${msg.value}");
          _onPeerShareOffer(msg);
        } else {
          _log("[ENGINE] ⚠️ Bilinmeyen kind: ${msg.kind}");
        }
        return;
      case ShareResponseMessage():
        // Engine does not process share content; upper layer may use this as a hint.
        return;
      case ErrorMessage():
        dev.log("ENGINE: Processing ErrorMessage (code=${msg.code})");
        // ✅ FIX: Önce reset, sonra kodu ayarla. Aksi halde _resetToPairing
        // initial state ile lastErrorCode'u null'a ezip hata kodunu kaybediyordu.
        _resetToPairing();
        _setState(_state.copyWith(lastErrorCode: msg.code));
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
      case RetryIntentMessage():
        // ✅ NEW: Handle retry intent from peer
        _onPeerRetryIntent();
        return;
    }
  }

  // Game start synchronization state
  Timer? _gameStartTimer;

  /// Cancel pending game start timer and clear state
  void _cancelPendingStartTimer() {
    _gameStartTimer?.cancel();
    _gameStartTimer = null;
    // Clear state.pendingGameStartAtMs
    if (_state.pendingGameStartAtMs != null) {
      _setState(_state.copyWith(clearPendingGameStartAtMs: true));
    }
  }

  void _maybeStartFirstRound() {
    // ✅ FIX: Use real current time, not potentially stale _nowMs
    final realNow = DateTime.now().millisecondsSinceEpoch;
    _log(" _maybeStartFirstRound called - phase=${_state.phase}, peerId=$_peerId");
    _log("    _nowMs=$_nowMs, realNow=$realNow");
    _log(" 🎮 INITIAL GAME STATE: similarity=${_state.similarity}, difference=${_state.difference}");
    
    if (_state.phase == GamePhase.playing) {
      _log(" _maybeStartFirstRound skipped - already playing");
      return;
    }
    if (_peerId == null) {
      _log(" _maybeStartFirstRound skipped - peerId is null");
      return;
    }
    
    // ✅ FIX: Update _nowMs to real time if it's 0 or stale
    if (_nowMs == 0 || _nowMs < realNow - 10000) {
      _log(" ⚠️ _nowMs was stale ($_nowMs), updating to realNow ($realNow)");
      _nowMs = realNow;
    }
    
    _log(" _maybeStartFirstRound starting round with now=$_nowMs");
    _startLeaderRound(now: _nowMs);
  }

  void _onGameStart(GameStartMessage msg) {
    _log(" 🎮 _onGameStart called, startAtMs=${msg.startAtMs}, seed=${msg.seed}, leaderId=${msg.leaderId}");
    _log("    isLeader=$isLeader, currentPhase=${_state.phase}");
    
    // ✅ FIX: Store peer's actual device ID for leadership comparison
    if (msg.leaderId != null && msg.leaderId != localDeviceId) {
      _peerActualDeviceId = msg.leaderId;
      _log(" 📥 Stored peer's actual device ID from GameStartMessage: $_peerActualDeviceId");
    }
    
    // ✅ FIX: Accept seed from peer even if we think we're leader (restart conflict resolution)
    // In early game or restart scenario, accept the seed if provided
    final isEarlyGame = _state.phase == GamePhase.pairing || 
                        _state.currentRound == null || 
                        _state.currentRound!.rid <= 1;
    
    if (msg.seed != null) {
      if (!isLeader || isEarlyGame) {
        _shuffleSeed = msg.seed;
        _log(" 📥 Received shuffle seed: $_shuffleSeed (early game or follower)");
        // Reshuffle and then continue with game start after reshuffle completes
        _reshuffleWithSeedAsync().then((_) {
          _log(" ✅ Questions reshuffled, continuing with game start");
          _proceedWithGameStart(msg);
        }).catchError((e) {
          _log(" ❌ Reshuffle failed: $e, continuing anyway");
          _proceedWithGameStart(msg);
        });
        return; // Wait for reshuffle
      } else {
        _log(" ⚠️ Leader ignoring peer seed (late game)");
      }
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
      _logVerbose("[SYNC] recv startAtMs=${msg.startAtMs}, now=$now, delay=$delayMs, leader=$isLeader, peerId=$_peerId");
      dev.log("[SYNC] recv startAtMs=${msg.startAtMs}, now=$now, delay=$delayMs, leader=$isLeader, peerId=$_peerId");
      
      if (delayMs > 0) {
        dev.log("ENGINE: Scheduling game start in ${delayMs}ms (startAtMs=${msg.startAtMs}, now=$now)");
        // Update state to show pending start (for UI ring progress)
        _setState(_state.copyWith(pendingGameStartAtMs: msg.startAtMs));
        _gameStartTimer?.cancel();
        _gameStartTimer = Timer(Duration(milliseconds: delayMs), () {
          final fireNow = DateTime.now().millisecondsSinceEpoch;
          final plannedStartAtMs = msg.startAtMs!;
          final driftMs = fireNow - plannedStartAtMs;
          
          // ✅ [SYNC] log: Timer tetiklenince
          _logVerbose("[SYNC] FIRE now=$fireNow, plannedStartAtMs=$plannedStartAtMs, driftMs=$driftMs");
          dev.log("[SYNC] FIRE now=$fireNow, plannedStartAtMs=$plannedStartAtMs, driftMs=$driftMs");
          
          // ✅ [SYNC] WARNING: driftMs mutlak değeri > 80ms ise
          if (driftMs.abs() > 80) {
            _logVerbose("[SYNC] WARNING drift=${driftMs}ms (planned=$plannedStartAtMs, actual=$fireNow)");
            dev.log("[SYNC] WARNING drift=${driftMs}ms (planned=$plannedStartAtMs, actual=$fireNow)");
          }
          
          dev.log("ENGINE: Game start delay completed, starting first round");
          _setState(_state.copyWith(clearPendingGameStartAtMs: true));
          // ✅ FIX: Only leader starts rounds - follower waits for RoundStartMessage
          if (_effectiveLeader && _peerId != null) {
            dev.log("ENGINE: Starting first round after delay as LEADER (fireNow=$fireNow)");
            _startLeaderRound(now: fireNow);
          } else {
            dev.log("ENGINE: Waiting for RoundStartMessage from leader (we are follower)");
          }
        });
        return; // Delay start, don't start immediately
      } else {
        dev.log("ENGINE: startAtMs is in the past or now, starting immediately");
        _setState(_state.copyWith(clearPendingGameStartAtMs: true));
      }
    }
    
    // No startAtMs or delay already passed: start immediately (LEADER only)
    // ✅ FIX: Use _effectiveLeader to account for deferred leadership
    if (_effectiveLeader && _peerId != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      dev.log("ENGINE: Starting first round immediately (now=$now, _nowMs=$_nowMs)");
      _startLeaderRound(now: now);
    }
  }

  void _startLeaderRound({required int now}) {
    // ✅ FIX: Yeni tur başlıyorsa önceki oyundan kalan (duplicate teslimle
    // geç ulaşmış) retry intent bayattır — birikirse oyun bitince karşının
    // onayı olmadan tek taraflı restart tetikliyordu.
    if (_peerRetryIntent) {
      _log(" 🧹 Stale peer retry intent cleared (new round starting)");
      _peerRetryIntent = false;
    }

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

    _send(
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

  /// ✅ REFACTORED: Leadership conflict resolution helper
  /// Returns true if we should defer to peer, false if we keep leadership, null if no conflict
  bool? _resolveLeadershipConflict(String? peerLeaderId) {
    if (!isLeader || peerLeaderId == localDeviceId) return null; // No conflict
    
    final isEarlyGame = _state.phase == GamePhase.pairing || 
                        _state.currentRound == null || 
                        _state.currentRound!.rid <= 1;
    
    if (!isEarlyGame) {
      _log(" ⚠️ Late game conflict - keeping current leadership");
      return null; // Don't change leadership in late game
    }
    
    // Deterministic: smaller device ID wins
    final theyWin = (peerLeaderId ?? '').compareTo(localDeviceId) < 0;
    _log(" ⚠️ Leader conflict: ${theyWin ? 'deferring to peer' : 'keeping leadership'}");
    return theyWin;
  }

  void _onRoundStart(RoundStartMessage msg) {
    _log(" 📨 RoundStart rid=${msg.rid}, qid=${msg.qid}");

    // ✅ FIX: Aynı mesajın çift teslimi (BLE send retry) turu sıfırlayıp
    // oyuncunun yaptığı seçimi siliyordu. Aynı mid ikinci kez gelirse yok say.
    // (Liderlik devrindeki eşit rid'li FARKLI mesajlar farklı mid taşır,
    // onlar etkilenmez.)
    if (msg.mid.isNotEmpty && msg.mid == _lastRoundStartMid) {
      _log(" ⚠️ Duplicate RoundStart ignored (mid=${msg.mid})");
      return;
    }

    // Store peer's device ID for future comparisons
    if (msg.leaderId != localDeviceId) {
      _peerActualDeviceId = msg.leaderId;
    }
    
    // Resolve any leadership conflict
    final shouldDefer = _resolveLeadershipConflict(msg.leaderId);
    if (shouldDefer == true) {
      _deferredToRemoteLeadership = true;
    } else if (shouldDefer == false) {
      return; // We keep leadership, ignore their round message
    } else if (isLeader && msg.leaderId != localDeviceId) {
      // Late game conflict - ignore
      return;
    }
    
    // Validate message
    if (_peerId == null) return;

    // ✅ FIX: Oyun bittiyse (terminal/share) yeni tur mesajını yok say.
    // Aksi halde skor ayrışmasında cihaz tekrar playing'e döner ve sayaç
    // 5'i aşarak oyunun hiç bitmemesine yol açar.
    if (_state.phase == GamePhase.terminalSuccess ||
        _state.phase == GamePhase.terminalFail ||
        _state.phase == GamePhase.share) {
      _log(" ❌ RoundStart ignored: game already ended (phase=${_state.phase})");
      return;
    }

    final cur = _state.currentRound;
    if (cur != null && msg.rid < cur.rid) return; // Old round

    _log(" 🆕 ROUND ${msg.rid} START (qid=${msg.qid}, score=${_state.similarity}-${_state.difference})");

    // Duplicate tespiti için kabul edilen mesajın mid'ini sakla.
    _lastRoundStartMid = msg.mid.isNotEmpty ? msg.mid : null;

    // ✅ FIX: Yeni tur başlıyorsa önceki oyundan kalan retry intent bayattır.
    if (_peerRetryIntent) {
      _log(" 🧹 Stale peer retry intent cleared (new round starting)");
      _peerRetryIntent = false;
    }

    // ✅ FIX: Deadline'ı liderin saatine göre değil, mesajın bize ulaştığı
    // andan itibaren YEREL saatle hesapla. Offline oyunda cihaz saatleri
    // senkron değildir; saati ileri olan cihazda tüm turlar "süresi dolmuş"
    // görünüyordu ve oyuncunun hiçbir dokunuşu kabul edilmiyordu.
    final localNow = _nowMs != 0 ? _nowMs : DateTime.now().millisecondsSinceEpoch;
    final localDeadlineMs = localNow + roundMs;

    final round = CurrentRound(
      rid: msg.rid,
      qid: msg.qid,
      deadlineMs: localDeadlineMs,
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
    _log('[ENGINE] 🎯 _onLocalTap called: choice=$c, phase=${_state.phase}, rid=${_state.currentRound?.rid}');
    
    if (_state.phase != GamePhase.playing) {
      _log('[ENGINE] ❌ REJECTED: phase != playing');
      return;
    }
    final r = _state.currentRound;
    if (r == null) {
      _log('[ENGINE] ❌ REJECTED: currentRound is null');
      return;
    }
    if (r.localFinal) {
      _log('[ENGINE] ❌ REJECTED: localFinal=true (already selected in round ${r.rid})');
      return;
    }
    if (_nowMs == 0) {
      _log('[ENGINE] ❌ REJECTED: _nowMs is 0');
      return;
    }

    // If already past deadline, ignore taps (deadline finalize will handle none).
    if (_nowMs > r.deadlineMs) {
      _log('[ENGINE] ❌ REJECTED: past deadline');
      return;
    }
    
    _log('[ENGINE] ✅ TAP ACCEPTED: rid=${r.rid}, choice=$c');
    _log('[ENGINE] 📊 Current state BEFORE local tap: localFinal=${r.localFinal}, peerFinal=${r.peerFinal}, peerChoice=${r.peerChoice}');

    final nextRev = r.localRev + 1;
    final rr = r.copyWith(
      localChoice: c,
      localRev: nextRev,
      localFinal: true,
      graceDeadlineMs: r.deadlineMs + graceWindowMs,
    );
    
    _log('[ENGINE] 📊 State AFTER local tap: localFinal=${rr.localFinal}, peerFinal=${rr.peerFinal}, peerChoice=${rr.peerChoice}');
    _setState(_state.copyWith(currentRound: rr));

    _send(
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

    _send(
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
    _log('[ENGINE] 📨 _onPeerSelection: rid=${msg.rid}, choice=${msg.choice}, isFinal=${msg.isFinal}');
    
    if (msg.sid != sessionId) {
      // Transport session ids are device-local; accept selection for current round.
      dev.log("ENGINE: Selection sid mismatch (sessionId=$sessionId, msg.sid=${msg.sid}) - accepting");
    }
    if (_state.phase != GamePhase.playing) {
      _log('[ENGINE] ❌ REJECTED: phase=${_state.phase} (not playing)');
      return;
    }
    final r = _state.currentRound;
    if (r == null) {
      _log('[ENGINE] ❌ REJECTED: currentRound is null');
      return;
    }

    // Out-of-order: old rid is dropped.
    if (msg.rid < r.rid) {
      _log('[ENGINE] ❌ REJECTED: msg.rid=${msg.rid} < current rid=${r.rid}');
      return;
    }
    if (msg.rid > r.rid) {
      _log('[ENGINE] ❌ REJECTED: msg.rid=${msg.rid} > current rid=${r.rid} (unexpected)');
      return;
    }

    // ✅ FIX: madeAtMs karşı cihazın saatiyle damgalıdır ve yerel deadline
    // ile karşılaştırılamaz (saat kayması yanlış red üretir). Geç kalma
    // kontrolü yerel VARIŞ zamanına göre yapılır: grace penceresi hâlâ
    // açıksa seçim kabul edilir; pencere kapandıktan sonra zaten onTick
    // turu peer=none olarak kapatır.
    if (_nowMs != 0 && _nowMs > r.deadlineMs + graceWindowMs) {
      _log('[ENGINE] ❌ REJECTED: arrived after grace window (now=$_nowMs > ${r.deadlineMs + graceWindowMs})');
      return;
    }

    // Same rid: accept only highest rev.
    if (msg.rev < r.peerRev) {
      _log('[ENGINE] ❌ REJECTED: msg.rev=${msg.rev} < peerRev=${r.peerRev}');
      return;
    }

    final c = choiceFromWire(msg.choice);
    if (c == null) {
      _log('[ENGINE] ❌ REJECTED: invalid choice=${msg.choice}');
      return;
    }

    _log('[ENGINE] ✅ PEER SELECTION ACCEPTED: rid=${msg.rid}, choice=$c, isFinal=${msg.isFinal}');
    _log('[ENGINE] 📊 BEFORE: localFinal=${r.localFinal}, peerFinal=${r.peerFinal}');

    final rr = r.copyWith(
      peerChoice: c,
      peerRev: msg.rev,
      peerFinal: msg.isFinal,
    );
    
    _log('[ENGINE] 📊 AFTER: localFinal=${rr.localFinal}, peerFinal=${rr.peerFinal}');
    
    _setState(_state.copyWith(currentRound: rr));
    _finalizeIfComplete(rr);
  }

  void _finalizeIfComplete(CurrentRound r) {
    _log('[ENGINE] 🔍 _finalizeIfComplete: rid=${r.rid}, localFinal=${r.localFinal}, peerFinal=${r.peerFinal}, _nowMs=$_nowMs');
    
    if (_nowMs == 0) {
      _log('[ENGINE] ⏳ SKIPPED: _nowMs=0 (waiting for first tick)');
      dev.log("ENGINE: _finalizeIfComplete skipped - _nowMs=0 (waiting for first tick)");
      return;
    }
    
    final graceDeadline = r.graceDeadlineMs;
    final gracePassed = graceDeadline != null && _nowMs >= graceDeadline;
    final isComplete = r.localFinal && (r.peerFinal || gracePassed);
    
    _log('[ENGINE] 🔍 isComplete check: localFinal=${r.localFinal}, peerFinal=${r.peerFinal}, gracePassed=$gracePassed, graceDeadline=$graceDeadline');
    _log('[ENGINE] 🔍 Result: isComplete=$isComplete');
    
    if (!isComplete) {
      _log('[ENGINE] ⏳ SKIPPED: round not complete yet');
      dev.log("ENGINE: _finalizeIfComplete skipped - round not complete yet (local=${r.localFinal}, peer=${r.peerFinal})");
      return;
    }
    
    // Prevent duplicate counting: if this round was already finalized, skip
    if (_finalizedRounds.contains(r.rid)) {
      _log('[ENGINE] ⏭️ SKIPPED: rid=${r.rid} already finalized');
      dev.log("ENGINE: Round ${r.rid} already finalized, skipping duplicate count");
      return;
    }
    
    _log('[ENGINE] ✅ FINALIZING round ${r.rid}!');
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
    
    // ✅ DEBUG: Her round sonucunu detaylı logla
    _log(" ═══════════════════════════════════════");
    _log(" 📊 ROUND ${r.rid} COMPLETE");
    _log("    Question ID: ${r.qid}");
    _log("    Local choice: $localChoice");
    _log("    Peer choice: $peerChoice");
    _log("    Both chose: $bothChose");
    _log("    Is similar: $isSimilar");
    _log("    Is different: $isDifferent");
    _log("    Score BEFORE: ${_state.similarity}-${_state.difference}");
    _log("    Score AFTER: $nextSimilarity-$nextDifference");
    _log(" ═══════════════════════════════════════");
    
    dev.log(
      "ENGINE: Round complete rid=${r.rid} qid=${r.qid} local=$localChoice peer=$peerChoice similar=$isSimilar "
      "score=$nextSimilarity-$nextDifference",
    );

    var nextPhase = _state.phase;
    final totalRoundsPlayed = nextSimilarity + nextDifference;
    _log(" 📊 Score update - similarity=$nextSimilarity, difference=$nextDifference, totalRounds=$totalRoundsPlayed");
    
    // ✅ FIX: '== 5' yerine '>= 5' — sayaç 5'i atlarsa oyun yine de bitsin.
    if (nextSimilarity >= 5) {
      _log(" 🎉 TERMINAL SUCCESS at round $totalRoundsPlayed");
      nextPhase = GamePhase.terminalSuccess;
    } else if (nextDifference >= 5) {
      _log(" 💔 TERMINAL FAIL at round $totalRoundsPlayed");
      nextPhase = GamePhase.terminalFail;
    } else {
      // Keep both devices in playing between rounds to avoid bouncing to pairing UI.
      nextPhase = GamePhase.playing;
    }

    // ✅ Cancel pending start timer on game end
    if (nextPhase == GamePhase.terminalSuccess || nextPhase == GamePhase.terminalFail) {
      _cancelPendingStartTimer();
      
      // ✅ NEW: Send game result to peer
      // ✅ FIX: Use _effectiveLeader to account for deferred leadership
      if (_effectiveLeader) {
        _send(
          ShareOfferMessage(
            v: protocolVersion,
            sid: sessionId,
            kind: 'game_result',
            value: '{"similarity":$nextSimilarity,"difference":$nextDifference}',
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

    if (nextPhase == GamePhase.playing && _effectiveLeader && !externalRoundControl) {
      _log('[ENGINE] 🚀 Starting next round as effective leader');
      _startLeaderRound(now: _nowMs);
    } else if (nextPhase == GamePhase.playing && !_effectiveLeader) {
      _log('[ENGINE] ⏳ Waiting for peer to start next round (_effectiveLeader=false)');
    }
  }

  void _resetToPairing() {
    _finalizedRounds.clear();
    _cancelPendingStartTimer();
    
    // ✅ FIX: Reset peer game result and retry flags
    _peerSimilarity = null;
    _peerDifference = null;
    _localRetryIntent = false;
    _peerRetryIntent = false;
    _nextRid = 1;
    _nextQid = 1;
    
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
    if (_disposed) return; // kapalı controller'a yazma
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
    _log('[ENGINE] 📤 ═══════════════════════════════════════');
    _log('[ENGINE] 📤 PAYLAŞIM GÖNDERME BAŞLATILDI');
    _log('[ENGINE] 📤 ═══════════════════════════════════════');
    _log('[ENGINE]    - Tür: $kind');
    _log('[ENGINE]    - Değer: $value');
    _log('[ENGINE]    - Session ID: $sessionId');
    _log('[ENGINE]    - Peer ID: $_peerId');
    
    final msg = ShareOfferMessage(
      sid: sessionId,
      kind: 'share_info',
      value: value,
      offerId: _makeMid('share_offer', rid: 0, now: _nowMs),
      extra: {'shareKind': kind.toString()}, // Serialize enum
    );
    
    _log('[ENGINE] 📨 BLE üzerinden gönderiliyor...');
    _send(msg);
    _log('[ENGINE] ✅ Gönderme tamamlandı!');
  }

  /// ✅ NEW: Rakıp bilgi paylaştığında çağrılır
  void _onPeerShareOffer(ShareOfferMessage msg) {
    if (msg.kind != 'share_info' || msg.value.isEmpty) {
      _log('[ENGINE] ⚠️ Geçersiz share offer - kind: ${msg.kind}, value: ${msg.value}');
      return;
    }
    
    _log('[ENGINE] 📥 ═══════════════════════════════════════');
    _log('[ENGINE] 📥 RAKIP PAYLAŞIM ALINDI!');
    _log('[ENGINE] 📥 ═══════════════════════════════════════');
    _log('[ENGINE]    - Değer: ${msg.value}');
    _log('[ENGINE]    - Extra: ${msg.extra}');
    
    // Parse share kind from extra
    final shareKindStr = msg.extra?['shareKind'] as String? ?? '';
    final peerShareKind = shareKindStr.contains('phone') ? 'phone' : 'social';
    _log('[ENGINE]    - Tür (parse): $peerShareKind');
    
    _log('[ENGINE] 🔄 GameState güncelleniyor...');
    _setState(_state.copyWith(
      peerShared: true,
      peerShareValue: msg.value,
      peerShareKind: peerShareKind,
    ));
    _log('[ENGINE] ✅ Durum güncellendi!');
  }

  Future<void> dispose() async {
    _disposed = true;
    _cancelPendingStartTimer();
    await _states.close();
    // ✅ FIX: _snapshots hiç kapatılmıyordu; her eşleşmede yeni engine
    // yaratıldığı için broadcast controller sızıyordu.
    await _snapshots.close();
  }
}

