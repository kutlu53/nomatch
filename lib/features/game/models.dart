import 'game_state.dart';

/// Exactly 5 terminal outcomes (requested).
enum RoundTerminal {
  match,
  mismatch,
  localNoSelection,
  peerNoSelection,
  bothNoSelection,
}

final class RoundSnapshot {
  final String sessionId;
  final String peerId;
  final bool isLeader;

  final int roundNumber;
  final int startedAtMs;
  final int deadlineMs; // playing deadline (5s)

  final String? localChoice; // null until chosen
  final int localRevision;
  final bool localFinal;

  final String? peerChoice; // null until received/finalized
  final int peerRevision;
  final bool peerFinal;

  final GamePhase phase;
  final RoundTerminal? terminal; // only in Result
  
  final String? topAsset; // ✅ NEW: Question asset for top
  final String? bottomAsset; // ✅ NEW: Question asset for bottom

  const RoundSnapshot({
    required this.sessionId,
    required this.peerId,
    required this.isLeader,
    required this.roundNumber,
    required this.startedAtMs,
    required this.deadlineMs,
    required this.localChoice,
    required this.localRevision,
    required this.localFinal,
    required this.peerChoice,
    required this.peerRevision,
    required this.peerFinal,
    required this.phase,
    required this.terminal,
    this.topAsset, // ✅ NEW
    this.bottomAsset, // ✅ NEW
  });
}

