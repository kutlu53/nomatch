import 'package:flutter_test/flutter_test.dart';
import 'package:nomatch/features/game/game_engine.dart';
import 'package:nomatch/features/game/game_state.dart';
import 'package:nomatch/plugins/p2p/p2p_messages.dart';

import '../support/fakes.dart';

/// GameEngine çekirdek mantığı — FOLLOWER tarafından sürülür.
///
/// Follower yolu zamanlayıcı kullanmaz (leader'ın 500ms boot gecikmesi yok),
/// bu yüzden skorlama/deadline/grace mantığını tamamen deterministik test eder.
/// Skorlama kodu (_finalizeIfComplete) leader/follower için aynıdır.
void main() {
  const int t0 = 1000000; // sabit mantıksal "şimdi" (epoch ms)
  const String sid = 'sess';

  /// Follower engine kurar, peer'a bağlar ve saati t0'a ayarlar.
  Future<GameEngine> bootFollower(FakeTransport tr) async {
    final e = GameEngine(
      transport: tr,
      isLeader: false,
      sessionId: sid,
      localDeviceId: 'zzzz-local', // büyük ID → kesinlikle follower
    );
    await e.onPeerConnected(peerId: 'peer-1');
    e.onTick(t0); // _nowMs > 0 olmalı, yoksa tap/finalize reddedilir
    return e;
  }

  /// Leader'dan gelen tur başlangıcını simüle eder (deadline = t0 + 5000).
  void startRound(GameEngine e, int rid) {
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

  /// Peer'ın seçimini simüle eder.
  void peerSelect(GameEngine e, int rid, String choice, {int? at}) {
    e.onP2pMessage(SelectionMessage(
      sid: sid,
      rid: rid,
      choice: choice,
      madeAtMs: at ?? t0,
      rev: 1,
      isFinal: true,
    ));
  }

  group('Tek tur skorlama', () {
    test('her iki oyuncu aynı seçim → benzerlik +1', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      startRound(e, 1);
      e.onLocalTapTop();
      peerSelect(e, 1, 'top');
      expect(e.state.similarity, 1);
      expect(e.state.difference, 0);
    });

    test('farklı seçim → farklılık +1', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      startRound(e, 1);
      e.onLocalTapTop();
      peerSelect(e, 1, 'bottom');
      expect(e.state.similarity, 0);
      expect(e.state.difference, 1);
    });

    test('local seçti, peer seçmedi (grace doldu) → farklılık', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      startRound(e, 1);
      e.onLocalTapTop(); // grace = deadline + 3000 = t0+8000
      // Peer hiç yanıt vermez; grace penceresini geçir.
      e.onTick(t0 + 8000);
      expect(e.state.difference, 1);
      expect(e.state.similarity, 0);
    });

    test('kimse seçmedi (deadline + grace) → farklılık', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      startRound(e, 1);
      // Deadline'da local none olarak finalize edilir.
      e.onTick(t0 + 5000);
      expect(e.state.difference, 0, reason: 'peer henüz final değil');
      // Grace geçince peer de none → tur farklılık olarak kapanır.
      e.onTick(t0 + 8000);
      expect(e.state.difference, 1);
    });

    test('bottom/bottom da benzerliktir (top\'a özel değil)', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      startRound(e, 1);
      e.onLocalTapBottom();
      peerSelect(e, 1, 'bottom');
      expect(e.state.similarity, 1);
    });
  });

  group('Tap doğrulama kuralları', () {
    test('playing değilken tap yok sayılır (state değişmez)', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      // Henüz tur başlamadı (phase pairing).
      e.onLocalTapTop();
      expect(e.state.currentRound, isNull);
      expect(tr.ofType<SelectionMessage>(), isEmpty);
    });

    test('deadline geçince tap reddedilir', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      startRound(e, 1);
      e.onTick(t0 + 6000); // deadline (t0+5000) geçti → local none finalize
      final sentBefore = tr.countOfType<SelectionMessage>();
      e.onLocalTapTop(); // artık kabul edilmemeli
      expect(tr.countOfType<SelectionMessage>(), sentBefore);
    });

    test('aynı turda ikinci tap yok sayılır', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      startRound(e, 1);
      e.onLocalTapTop();
      e.onLocalTapBottom(); // ilk seçim kesindir
      final sels = tr.ofType<SelectionMessage>();
      expect(sels.length, 1);
      expect(sels.first.choice, 'top');
    });

    test('select() public API top/bottom yönlendirir', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      startRound(e, 1);
      e.select('bottom');
      peerSelect(e, 1, 'bottom');
      expect(e.state.similarity, 1);
    });
  });

  group('Peer seçim mesajı doğrulama', () {
    test('eski tur (rid < current) yok sayılır', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      startRound(e, 2); // current rid = 2
      e.onLocalTapTop();
      peerSelect(e, 1, 'top'); // eski rid=1 → drop
      // Peer final olmadı; grace de geçmedi → tur kapanmaz.
      expect(e.state.similarity, 0);
      expect(e.state.difference, 0);
    });

    test('grace kapandıktan sonra gelen peer seçimi sonucu değiştirmez', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      startRound(e, 1);
      e.onLocalTapTop();
      // Grace penceresi (deadline+3000) kapanır → tur farklılıkla kapanır.
      e.onTick(t0 + 8000);
      expect(e.state.difference, 1);
      // Sonradan ulaşan seçim artık kapanmış turu etkileyemez.
      peerSelect(e, 1, 'top', at: t0 + 4000);
      expect(e.state.similarity, 0, reason: 'kapanan tur yeniden skorlanmamalı');
      expect(e.state.difference, 1);
    });

    test('madeAtMs geç görünse bile grace içinde ULAŞAN seçim kabul edilir (saat kayması)', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      startRound(e, 1);
      e.onLocalTapTop();
      // Karşı cihazın saati ileri: madeAtMs deadline'dan çok sonra görünür.
      // Yerel varış zamanı grace içinde olduğundan seçim sayılmalı.
      peerSelect(e, 1, 'top', at: t0 + 5000 + 200);
      expect(e.state.similarity, 1);
    });

    test('liderin deadline damgası saati kaymış olsa bile tur oynanabilir', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      // Liderin saati bizden ÇOK geride: mesajdaki deadline yerel saate göre
      // çoktan geçmiş görünüyor. Deadline yerel varış anından hesaplandığı
      // için tap yine de kabul edilmeli.
      e.onP2pMessage(RoundStartMessage(
        sid: sid,
        rid: 1,
        qid: 1,
        deadlineMs: t0 - 100000, // kaymış lider saati
        leaderId: 'aaaa-peer',
        topAsset: 'top1',
        bottomAsset: 'bot1',
      ));
      e.onLocalTapTop();
      final sels = tr.ofType<SelectionMessage>();
      expect(sels.length, 1, reason: 'yerel deadline kullanılmalı, tap reddedilmemeli');
    });
  });

  group('Duplicate mesaj korumaları', () {
    test('aynı mid ile tekrarlanan RoundStart seçimi silmez', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      final msg = RoundStartMessage(
        sid: sid,
        rid: 1,
        qid: 1,
        deadlineMs: t0 + 5000,
        mid: 'round_start-1-abc',
        leaderId: 'aaaa-peer',
        topAsset: 'top1',
        bottomAsset: 'bot1',
      );
      e.onP2pMessage(msg);
      e.onLocalTapTop();
      // BLE send-retry duplicate teslimi: tur sıfırlanmamalı.
      e.onP2pMessage(msg);
      peerSelect(e, 1, 'top');
      expect(e.state.similarity, 1, reason: 'seçim duplicate ile silinmemeli');
    });

    test('oyun içinde gelen bayat retry intent sonraki turda temizlenir', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      startRound(e, 1);
      // Önceki oyundan kalmış (geç teslim) bayat intent oyun ortasında gelir.
      e.onP2pMessage(RetryIntentMessage(sid: sid));
      // Oyunu 5 farklılıkla bitir; aradaki tur başlangıçları intent'i temizler.
      for (var rid = 1; rid <= 5; rid++) {
        if (rid > 1) startRound(e, rid);
        e.onLocalTapTop();
        peerSelect(e, rid, 'bottom');
      }
      expect(e.state.phase, GamePhase.terminalFail);
      // Yerel retry ister; karşıdan GÜNCEL onay yokken restart olmamalı.
      e.sendRetryIntent();
      expect(e.state.phase, GamePhase.terminalFail,
          reason: 'bayat intent tek taraflı restart tetiklememeli');
    });
  });

  group('Bağlantı yaşam döngüsü', () {
    test('onPeerDisconnected pairing\'e sıfırlar ve skoru siler', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      startRound(e, 1);
      e.onLocalTapTop();
      peerSelect(e, 1, 'top');
      expect(e.state.similarity, 1);

      e.onPeerDisconnected();
      expect(e.state.phase, GamePhase.pairing);
      expect(e.state.similarity, 0);
      expect(e.state.difference, 0);
      expect(e.state.currentRound, isNull);
    });

    test('ErrorMessage oyunu pairing\'e sıfırlar', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      startRound(e, 1);
      e.onLocalTapTop();
      peerSelect(e, 1, 'top');
      e.onP2pMessage(ErrorMessage(sid: sid, error: 'boom'));
      expect(e.state.phase, GamePhase.pairing);
      expect(e.state.similarity, 0);
    });

    test('ErrorMessage sonrası hata kodu korunur (regresyon)', () async {
      // Eskiden _resetToPairing lastErrorCode'u null'a eziyordu.
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      e.onP2pMessage(ErrorMessage(sid: sid, error: 'net_lost', code: 'E_NET'));
      expect(e.state.phase, GamePhase.pairing);
      expect(e.state.lastErrorCode, 'E_NET');
    });
  });

  group('Paylaşım (share_info)', () {
    test('peer share_info → state.peerShared + değer + tür (phone)', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      e.onP2pMessage(ShareOfferMessage(
        sid: sid,
        kind: 'share_info',
        value: '5551234567',
        extra: {'shareKind': 'ShareKind.phone'},
      ));
      expect(e.state.peerShared, true);
      expect(e.state.peerShareValue, '5551234567');
      expect(e.state.peerShareKind, 'phone');
    });

    test('peer share_info sosyal tür → social', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      e.onP2pMessage(ShareOfferMessage(
        sid: sid,
        kind: 'share_info',
        value: 'my_handle',
        extra: {'shareKind': 'ShareKind.social'},
      ));
      expect(e.state.peerShareKind, 'social');
    });

    test('boş değerli share_info yok sayılır', () async {
      final tr = FakeTransport();
      final e = await bootFollower(tr);
      e.onP2pMessage(ShareOfferMessage(sid: sid, kind: 'share_info', value: ''));
      expect(e.state.peerShared, isNot(true));
    });
  });
}
