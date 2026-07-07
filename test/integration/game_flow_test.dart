import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomatch/features/game/game_engine.dart';
import 'package:nomatch/features/game/game_state.dart';
import 'package:nomatch/plugins/p2p/p2p_messages.dart';

import '../support/fakes.dart';

/// Entegrasyon: birden çok turu zincirleyerek tam oyun akışlarını ve
/// leader/follower koordinasyonunu test eder. Amaç, tekil turlarda görünmeyen
/// birikimli/durum-geçişli bug'ları yakalamak.
void main() {
  const int t0 = 2000000;
  const String sid = 'sess';

  // ───────────────────────── FOLLOWER yardımcıları ─────────────────────────
  Future<GameEngine> bootFollower(FakeTransport tr) async {
    final e = GameEngine(
      transport: tr,
      isLeader: false,
      sessionId: sid,
      localDeviceId: 'zzzz-local',
    );
    await e.onPeerConnected(peerId: 'peer-1');
    e.onTick(t0);
    return e;
  }

  void followerStartRound(GameEngine e, int rid) {
    e.onP2pMessage(RoundStartMessage(
      sid: sid,
      rid: rid,
      qid: rid,
      deadlineMs: t0 + 5000,
      leaderId: 'aaaa-peer',
      topAsset: 'top$rid',
      bottomAsset: 'bot$rid',
    ));
  }

  void followerPlayRound(GameEngine e, int rid,
      {required String local, required String peer}) {
    followerStartRound(e, rid);
    if (local == 'top') {
      e.onLocalTapTop();
    } else if (local == 'bottom') {
      e.onLocalTapBottom();
    }
    if (peer != 'none') {
      e.onP2pMessage(SelectionMessage(
        sid: sid, rid: rid, choice: peer, madeAtMs: t0, rev: 1, isFinal: true));
    } else {
      // Peer sessiz: grace penceresini geçir ki tur kapansın.
      // (Sonraki turlar için saati geri almamak adına aynı tick'i kullanırız.)
      e.onTick(t0 + 8000);
      e.onTick(t0); // saati geri sabit değere çek (deadline t0+5000 sabit)
    }
  }

  // ───────────────────────── LEADER yardımcıları ─────────────────────────
  /// Leader engine kurar ve ilk turun başlamasını bekler (boot 500ms timer).
  Future<GameEngine> bootLeader(FakeTransport tr) async {
    final e = GameEngine(
      transport: tr,
      isLeader: true,
      sessionId: sid,
      localDeviceId: 'aaaa-local', // küçük ID → lider
      questions: SeqQuestions([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
    );
    await e.onPeerConnected(peerId: 'peer-1');
    await pumpUntil(() => e.state.currentRound != null,
        reason: 'leader ilk turu başlatmadı');
    return e;
  }

  /// Leader tarafında bir turu, iki oyuncu da eşleşecek şekilde oynatır.
  /// Deadline'ı okuyup pencere içinde kalır; finalize sonrası leader
  /// SENKRON olarak sonraki turu başlatır.
  void leaderPlayMatchRound(GameEngine e) {
    final r = e.state.currentRound!;
    final now = r.deadlineMs - 1000;
    e.onTick(now);
    e.onLocalTapTop();
    e.onP2pMessage(SelectionMessage(
      sid: sid, rid: r.rid, choice: 'top', madeAtMs: now, rev: 1, isFinal: true));
  }

  void leaderPlayMismatchRound(GameEngine e) {
    final r = e.state.currentRound!;
    final now = r.deadlineMs - 1000;
    e.onTick(now);
    e.onLocalTapTop();
    e.onP2pMessage(SelectionMessage(
      sid: sid, rid: r.rid, choice: 'bottom', madeAtMs: now, rev: 1, isFinal: true));
  }

  group('Tam oyun — FOLLOWER perspektifi', () {
    test('5 benzerlik → terminalSuccess', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      for (var rid = 1; rid <= 5; rid++) {
        followerPlayRound(e, rid, local: 'top', peer: 'top');
      }
      expect(e.state.similarity, 5);
      expect(e.state.phase, GamePhase.terminalSuccess);
    });

    test('5 farklılık → terminalFail', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      for (var rid = 1; rid <= 5; rid++) {
        followerPlayRound(e, rid, local: 'top', peer: 'bottom');
      }
      expect(e.state.difference, 5);
      expect(e.state.phase, GamePhase.terminalFail);
    });

    test('karışık skor 4-4 sonra 5. benzerlik kazandırır', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      // 4 benzerlik, 4 farklılık serpiştir.
      final pattern = [
        ['top', 'top'], // sim 1
        ['top', 'bottom'], // diff 1
        ['top', 'top'], // sim 2
        ['top', 'bottom'], // diff 2
        ['top', 'top'], // sim 3
        ['top', 'bottom'], // diff 3
        ['top', 'top'], // sim 4
        ['top', 'bottom'], // diff 4
      ];
      var rid = 1;
      for (final p in pattern) {
        followerPlayRound(e, rid++, local: p[0], peer: p[1]);
      }
      expect(e.state.similarity, 4);
      expect(e.state.difference, 4);
      expect(e.state.phase, GamePhase.playing, reason: 'henüz terminal değil');

      // 5. benzerlik oyunu bitirmeli (4 diff'e rağmen).
      followerPlayRound(e, rid++, local: 'top', peer: 'top');
      expect(e.state.similarity, 5);
      expect(e.state.phase, GamePhase.terminalSuccess);
    });

    test('sessiz peer içeren tam kayıp senaryosu (hepsi none)', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      for (var rid = 1; rid <= 5; rid++) {
        // local seçer ama peer hep sessiz → her tur farklılık.
        followerPlayRound(e, rid, local: 'top', peer: 'none');
      }
      expect(e.state.difference, 5);
      expect(e.state.phase, GamePhase.terminalFail);
    });
  });

  group('Tam oyun — LEADER perspektifi (otomatik tur ilerletme)', () {
    test('5 eşleşen tur → terminalSuccess + game_result gönderilir', () async {
      final tr = FakeTransport();
      final e = await bootLeader(tr);

      var guard = 0;
      while (!e.state.isTerminal && guard++ < 20) {
        leaderPlayMatchRound(e);
      }

      expect(e.state.phase, GamePhase.terminalSuccess);
      expect(e.state.similarity, 5);

      // Leader her turu round_start ile başlatır (tam 5 tur).
      expect(tr.countOfType<RoundStartMessage>(), 5);

      // Terminal'de leader peer'a game_result yollar.
      final results =
          tr.ofType<ShareOfferMessage>().where((m) => m.kind == 'game_result');
      expect(results.length, 1);
      final payload = jsonDecode(results.first.value) as Map<String, dynamic>;
      expect(payload['similarity'], 5);
    });

    test('5 farklı tur → terminalFail + game_result difference=5', () async {
      final tr = FakeTransport();
      final e = await bootLeader(tr);

      var guard = 0;
      while (!e.state.isTerminal && guard++ < 20) {
        leaderPlayMismatchRound(e);
      }

      expect(e.state.phase, GamePhase.terminalFail);
      expect(e.state.difference, 5);

      final results =
          tr.ofType<ShareOfferMessage>().where((m) => m.kind == 'game_result');
      expect(results.length, 1);
      final payload = jsonDecode(results.first.value) as Map<String, dynamic>;
      expect(payload['difference'], 5);
    });

    test('leader her turda benzersiz qid içeren round_start yollar', () async {
      final tr = FakeTransport();
      final e = await bootLeader(tr);
      var guard = 0;
      while (!e.state.isTerminal && guard++ < 20) {
        leaderPlayMatchRound(e);
      }
      final qids = tr.ofType<RoundStartMessage>().map((m) => m.qid).toList();
      expect(qids.length, 5);
      expect(qids.toSet().length, 5, reason: 'qid\'ler tekrar etmemeli');
    });
  });

  group('Leadership çakışma çözümü', () {
    // externalRoundControl: leader boot timer\'ını kapatarak deterministik test.
    GameEngine leaderNoAutoStart(FakeTransport tr, String localId) {
      return GameEngine(
        transport: tr,
        isLeader: true,
        externalRoundControl: true,
        sessionId: sid,
        localDeviceId: localId,
        questions: SeqQuestions([1, 2, 3]),
      );
    }

    test('daha küçük ID\'li peer round_start yollarsa leader devreder', () async {
      final tr = FakeTransport();
      final e = leaderNoAutoStart(tr, 'mmmm-local'); // orta ID
      await e.onPeerConnected(peerId: 'peer');
      e.onTick(t0);
      // Peer daha küçük ID ('aaaa') ile tur başlatır → biz devretmeliyiz.
      e.onP2pMessage(RoundStartMessage(
        sid: sid, rid: 1, qid: 1, deadlineMs: t0 + 5000,
        leaderId: 'aaaa-peer', topAsset: 't', bottomAsset: 'b'));
      expect(e.state.phase, GamePhase.playing,
          reason: 'küçük ID\'li peer\'a devredip turu kabul etmeli');
      expect(e.state.currentRound?.rid, 1);
    });

    test('daha büyük ID\'li peer round_start yollarsa leader yok sayar', () async {
      final tr = FakeTransport();
      final e = leaderNoAutoStart(tr, 'aaaa-local'); // en küçük ID → lider biz
      await e.onPeerConnected(peerId: 'peer');
      e.onTick(t0);
      // Peer daha büyük ID ('zzzz') ile tur başlatır → yok sayılmalı.
      e.onP2pMessage(RoundStartMessage(
        sid: sid, rid: 1, qid: 1, deadlineMs: t0 + 5000,
        leaderId: 'zzzz-peer', topAsset: 't', bottomAsset: 'b'));
      expect(e.state.currentRound, isNull,
          reason: 'liderliği koruyup turu yok saymalı');
    });
  });

  group('Peer game_result senkronizasyonu (follower)', () {
    test('geçerli 5-benzerlik sonucu terminalSuccess yapar', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      e.onP2pMessage(ShareOfferMessage(
        sid: sid,
        kind: 'game_result',
        value: '{"similarity":5,"difference":0}',
      ));
      expect(e.state.phase, GamePhase.terminalSuccess);
      expect(e.state.similarity, 5);
    });

    test('geçerli 5-farklılık sonucu terminalFail yapar', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      e.onP2pMessage(ShareOfferMessage(
        sid: sid,
        kind: 'game_result',
        value: '{"similarity":0,"difference":5}',
      ));
      expect(e.state.phase, GamePhase.terminalFail);
    });

    test('şüpheli sonuç (toplam tur < 5) yok sayılır', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      // difference=5 ama toplam=4 → tutarsız, kabul edilmemeli.
      e.onP2pMessage(ShareOfferMessage(
        sid: sid,
        kind: 'game_result',
        value: '{"similarity":-1,"difference":5}',
      ));
      expect(e.state.isTerminal, false);
    });

    test('bozuk JSON game_result çökmez, state değişmez', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      final before = e.state.phase;
      e.onP2pMessage(
          ShareOfferMessage(sid: sid, kind: 'game_result', value: '{bad'));
      expect(e.state.phase, before);
    });
  });

  group('Retry el sıkışması (yeniden oynama)', () {
    test('her iki taraf da retry isterse restarting fazına geçer', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      // Önce kaybettir.
      for (var rid = 1; rid <= 5; rid++) {
        followerPlayRound(e, rid, local: 'top', peer: 'bottom');
      }
      expect(e.state.phase, GamePhase.terminalFail);

      // Yerel retry gönder.
      e.sendRetryIntent();
      expect(tr.countOfType<RetryIntentMessage>(), 1);
      expect(e.localRetryIntent, true);
      expect(e.state.phase, GamePhase.terminalFail,
          reason: 'peer henüz istemedi');

      // Peer retry gelir → restarting fazı (yeşil ok animasyonu).
      e.onP2pMessage(RetryIntentMessage(sid: sid));
      expect(e.peerRetryIntent, true);
      expect(e.state.phase, GamePhase.restarting);

      // 500ms sonra oyun yeniden başlar (follower → pairing bekler).
      await pumpUntil(() => e.state.phase == GamePhase.pairing,
          reason: 'restart tamamlanmadı');
      expect(e.state.similarity, 0);
      expect(e.state.difference, 0);
      expect(e.localRetryIntent, false);
      expect(e.peerRetryIntent, false);
    });

    test('aynı retry iki kez gönderilmez (idempotent)', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      e.sendRetryIntent();
      e.sendRetryIntent();
      expect(tr.countOfType<RetryIntentMessage>(), 1);
    });

    test('BLE kopukken retry gönderimi exception yaymaz', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      tr.throwOnSend = true;
      // catchError ile yutulmalı; test senkron olarak patlamamalı.
      expect(() => e.sendRetryIntent(), returnsNormally);
    });
  });

  group('Zincir: oyna → kaybet → retry → yeni oyunda tekrar oyna', () {
    test('yeniden başlatma sonrası skor sıfırdan sayılır', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);

      // 1. oyun: kayıp.
      for (var rid = 1; rid <= 5; rid++) {
        followerPlayRound(e, rid, local: 'top', peer: 'bottom');
      }
      expect(e.state.phase, GamePhase.terminalFail);

      // Her iki taraf retry → restart.
      e.sendRetryIntent();
      e.onP2pMessage(RetryIntentMessage(sid: sid));
      await pumpUntil(() => e.state.phase == GamePhase.pairing);

      // 2. oyun: yeni turlar (rid tekrar 1\'den). Saati tazele.
      e.onTick(t0);
      followerPlayRound(e, 1, local: 'top', peer: 'top');
      expect(e.state.similarity, 1,
          reason: 'yeni oyun temiz skorla başlamalı');
      expect(e.state.difference, 0);
    });
  });
}
