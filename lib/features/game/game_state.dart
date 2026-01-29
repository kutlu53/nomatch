enum GamePhase { idle, pairing, playing, terminalFail, terminalSuccess, share }

enum Choice { top, bottom, none }

Choice? choiceFromWire(String? v) {
  return switch (v) {
    'top' => Choice.top,
    'bottom' => Choice.bottom,
    'none' => Choice.none,
    _ => null,
  };
}

String choiceToWire(Choice c) {
  return switch (c) {
    Choice.top => 'top',
    Choice.bottom => 'bottom',
    Choice.none => 'none',
  };
}

final class CurrentRound {
  final int rid;
  final int qid;
  final int deadlineMs;

  final Choice? localChoice;
  final Choice? peerChoice;

  final bool localFinal;
  final bool peerFinal;

  final int localRev;
  final int peerRev;

  /// Optional grace window end. If set and now >= graceDeadlineMs, peer is treated as none.
  final int? graceDeadlineMs;
  
  /// ✅ NEW: Question assets (embedded by leader, used by both)
  final String? topAsset;
  final String? bottomAsset;

  const CurrentRound({
    required this.rid,
    required this.qid,
    required this.deadlineMs,
    required this.localChoice,
    required this.peerChoice,
    required this.localFinal,
    required this.peerFinal,
    required this.localRev,
    required this.peerRev,
    required this.graceDeadlineMs,
    this.topAsset, // ✅ NEW
    this.bottomAsset, // ✅ NEW
  });

  bool isGracePassed(int nowEpochMs) {
    final g = graceDeadlineMs;
    return g != null && nowEpochMs >= g;
  }

  /// Complete if local final AND (peer final OR grace passed).
  bool isComplete(int nowEpochMs) => localFinal && (peerFinal || isGracePassed(nowEpochMs));

  CurrentRound copyWith({
    int? rid,
    int? qid,
    int? deadlineMs,
    Choice? localChoice,
    Choice? peerChoice,
    bool? localFinal,
    bool? peerFinal,
    int? localRev,
    int? peerRev,
    int? graceDeadlineMs,
    bool clearGraceDeadlineMs = false,
    String? topAsset, // ✅ NEW
    String? bottomAsset, // ✅ NEW
  }) {
    return CurrentRound(
      rid: rid ?? this.rid,
      qid: qid ?? this.qid,
      deadlineMs: deadlineMs ?? this.deadlineMs,
      localChoice: localChoice ?? this.localChoice,
      peerChoice: peerChoice ?? this.peerChoice,
      localFinal: localFinal ?? this.localFinal,
      peerFinal: peerFinal ?? this.peerFinal,
      localRev: localRev ?? this.localRev,
      peerRev: peerRev ?? this.peerRev,
      graceDeadlineMs: clearGraceDeadlineMs ? null : (graceDeadlineMs ?? this.graceDeadlineMs),
      topAsset: topAsset ?? this.topAsset, // ✅ NEW
      bottomAsset: bottomAsset ?? this.bottomAsset, // ✅ NEW
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CurrentRound &&
        other.rid == rid &&
        other.qid == qid &&
        other.deadlineMs == deadlineMs &&
        other.localChoice == localChoice &&
        other.peerChoice == peerChoice &&
        other.localFinal == localFinal &&
        other.peerFinal == peerFinal &&
        other.localRev == localRev &&
        other.peerRev == peerRev &&
        other.graceDeadlineMs == graceDeadlineMs &&
        other.topAsset == topAsset && // ✅ NEW
        other.bottomAsset == bottomAsset; // ✅ NEW
  }

  @override
  int get hashCode => Object.hash(
        rid,
        qid,
        deadlineMs,
        localChoice,
        peerChoice,
        localFinal,
        peerFinal,
        localRev,
        peerRev,
        graceDeadlineMs,
        topAsset, // ✅ NEW
        bottomAsset, // ✅ NEW
      );
}

final class GameState {
  final GamePhase phase;
  final int similarity;
  final int difference;
  final CurrentRound? currentRound;
  final Object? lastErrorCode;
  
  /// Optional: scheduled game start time (epoch ms) for synchronization
  final int? pendingGameStartAtMs;

  const GameState({
    required this.phase,
    required this.similarity,
    required this.difference,
    required this.currentRound,
    required this.lastErrorCode,
    this.pendingGameStartAtMs,
  });

  const GameState.initial()
      : phase = GamePhase.idle,
        similarity = 0,
        difference = 0,
        currentRound = null,
        lastErrorCode = null,
        pendingGameStartAtMs = null;

  bool get isTerminal => phase == GamePhase.terminalFail || phase == GamePhase.terminalSuccess;

  GameState copyWith({
    GamePhase? phase,
    int? similarity,
    int? difference,
    CurrentRound? currentRound,
    bool clearCurrentRound = false,
    Object? lastErrorCode,
    bool clearLastErrorCode = false,
    int? pendingGameStartAtMs,
    bool clearPendingGameStartAtMs = false,
  }) {
    return GameState(
      phase: phase ?? this.phase,
      similarity: similarity ?? this.similarity,
      difference: difference ?? this.difference,
      currentRound: clearCurrentRound ? null : (currentRound ?? this.currentRound),
      lastErrorCode: clearLastErrorCode ? null : (lastErrorCode ?? this.lastErrorCode),
      pendingGameStartAtMs: clearPendingGameStartAtMs ? null : (pendingGameStartAtMs ?? this.pendingGameStartAtMs),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GameState &&
        other.phase == phase &&
        other.similarity == similarity &&
        other.difference == difference &&
        other.currentRound == currentRound &&
        other.lastErrorCode == lastErrorCode &&
        other.pendingGameStartAtMs == pendingGameStartAtMs;
  }

  @override
  int get hashCode => Object.hash(phase, similarity, difference, currentRound, lastErrorCode, pendingGameStartAtMs);
}

