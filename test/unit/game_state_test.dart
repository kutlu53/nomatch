import 'package:flutter_test/flutter_test.dart';
import 'package:nomatch/features/game/game_state.dart';

/// GameState / CurrentRound değişmez (immutable) veri mantığı.
///
/// Odak: copyWith'in clear-flag semantiği ve tur tamamlanma (isComplete)
/// mantığı — engine bunlara güveniyor.
void main() {
  CurrentRound round({
    bool localFinal = false,
    bool peerFinal = false,
    int? graceDeadlineMs,
    int deadlineMs = 5000,
  }) {
    return CurrentRound(
      rid: 1,
      qid: 1,
      deadlineMs: deadlineMs,
      localChoice: null,
      peerChoice: null,
      localFinal: localFinal,
      peerFinal: peerFinal,
      localRev: 0,
      peerRev: 0,
      graceDeadlineMs: graceDeadlineMs,
    );
  }

  group('CurrentRound.isComplete', () {
    test('local ve peer final → complete', () {
      expect(round(localFinal: true, peerFinal: true).isComplete(0), true);
    });

    test('local final ama peer değil, grace geçmemiş → incomplete', () {
      final r = round(localFinal: true, peerFinal: false, graceDeadlineMs: 8000);
      expect(r.isComplete(5000), false);
    });

    test('local final, grace geçmiş → complete (peer none sayılır)', () {
      final r = round(localFinal: true, peerFinal: false, graceDeadlineMs: 8000);
      expect(r.isComplete(8000), true);
    });

    test('local final değilse asla complete olmaz (grace geçse bile)', () {
      final r = round(localFinal: false, peerFinal: true, graceDeadlineMs: 1);
      expect(r.isComplete(999999), false);
    });

    test('isGracePassed: grace null iken false', () {
      expect(round(localFinal: true).isGracePassed(999999), false);
    });

    test('isGracePassed: tam sınırda (now == grace) true', () {
      expect(round(graceDeadlineMs: 8000).isGracePassed(8000), true);
    });
  });

  group('GameState.copyWith clear flag semantiği', () {
    test('clearCurrentRound tur bilgisini siler', () {
      final s = const GameState.initial()
          .copyWith(phase: GamePhase.playing, currentRound: round());
      expect(s.currentRound, isNotNull);
      final cleared = s.copyWith(clearCurrentRound: true);
      expect(cleared.currentRound, isNull);
    });

    test('clearCurrentRound olmadan currentRound korunur', () {
      final s = const GameState.initial().copyWith(currentRound: round());
      final next = s.copyWith(similarity: 3);
      expect(next.currentRound, isNotNull);
      expect(next.similarity, 3);
    });

    test('clearLastErrorCode hatayı temizler', () {
      final s = const GameState.initial().copyWith(lastErrorCode: 'E1');
      expect(s.lastErrorCode, 'E1');
      expect(s.copyWith(clearLastErrorCode: true).lastErrorCode, isNull);
    });

    test('clearPendingGameStartAtMs bekleyen başlangıcı temizler', () {
      final s = const GameState.initial().copyWith(pendingGameStartAtMs: 123);
      expect(s.pendingGameStartAtMs, 123);
      expect(s.copyWith(clearPendingGameStartAtMs: true).pendingGameStartAtMs,
          isNull);
    });

    test('isTerminal yalnızca terminal fazlarında true', () {
      expect(const GameState.initial().copyWith(phase: GamePhase.playing).isTerminal,
          false);
      expect(
          const GameState.initial()
              .copyWith(phase: GamePhase.terminalSuccess)
              .isTerminal,
          true);
      expect(
          const GameState.initial()
              .copyWith(phase: GamePhase.terminalFail)
              .isTerminal,
          true);
    });
  });

  group('Değer eşitliği (state stream deduplication için kritik)', () {
    test('aynı içerikli GameState eşittir', () {
      final a = const GameState.initial().copyWith(
          phase: GamePhase.playing, similarity: 2, difference: 1);
      final b = const GameState.initial().copyWith(
          phase: GamePhase.playing, similarity: 2, difference: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('farklı skor → eşit değil', () {
      final a = const GameState.initial().copyWith(similarity: 2);
      final b = const GameState.initial().copyWith(similarity: 3);
      expect(a, isNot(b));
    });

    test('aynı içerikli CurrentRound eşittir', () {
      expect(round(localFinal: true), round(localFinal: true));
      expect(round(localFinal: true).hashCode, round(localFinal: true).hashCode);
    });

    test('farklı localFinal → CurrentRound eşit değil', () {
      expect(round(localFinal: true), isNot(round(localFinal: false)));
    });
  });
}
