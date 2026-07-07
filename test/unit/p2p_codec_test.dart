import 'package:flutter_test/flutter_test.dart';
import 'package:nomatch/plugins/p2p/p2p_codec.dart';
import 'package:nomatch/plugins/p2p/p2p_messages.dart';

/// P2pCodec + mesaj serileştirme testleri.
///
/// Amaç: encode→decode round-trip sırasında hiçbir alanın kaybolmaması,
/// bilinmeyen/bozuk girdilerin güvenli şekilde hata vermesi ve varsayılan
/// değer mantığının (ör. ErrorMessage.code fallback) doğru çalışması.
void main() {
  final codec = P2pCodec();

  /// Bir mesajı encode edip decode ederek geri döndürür.
  T roundTrip<T extends P2pMessage>(P2pMessage msg) {
    final decoded = codec.decode(codec.encode(msg));
    expect(decoded, isA<T>());
    return decoded as T;
  }

  group('P2pCodec round-trip', () {
    test('SelectionMessage tüm alanları korur', () {
      final out = roundTrip<SelectionMessage>(SelectionMessage(
        sid: 'sess-1',
        choice: 'bottom',
        rid: 7,
        mid: 'm-7',
        madeAtMs: 1234567,
        rev: 3,
        isFinal: false,
      ));
      expect(out.sid, 'sess-1');
      expect(out.choice, 'bottom');
      expect(out.rid, 7);
      expect(out.mid, 'm-7');
      expect(out.madeAtMs, 1234567);
      expect(out.rev, 3);
      expect(out.isFinal, false);
    });

    test('RoundStartMessage asset ve startAtMs alanlarını korur', () {
      final out = roundTrip<RoundStartMessage>(RoundStartMessage(
        sid: 's',
        rid: 2,
        qid: 42,
        deadlineMs: 999,
        leaderId: 'dev-A',
        topAsset: 'top.webp',
        bottomAsset: 'bottom.webp',
        startAtMs: 555,
      ));
      expect(out.rid, 2);
      expect(out.qid, 42);
      expect(out.deadlineMs, 999);
      expect(out.leaderId, 'dev-A');
      expect(out.topAsset, 'top.webp');
      expect(out.bottomAsset, 'bottom.webp');
      expect(out.startAtMs, 555);
    });

    test('RoundStartMessage startAtMs null ise korunur', () {
      final out = roundTrip<RoundStartMessage>(RoundStartMessage(
        sid: 's',
        rid: 1,
        qid: 1,
        deadlineMs: 100,
      ));
      expect(out.startAtMs, isNull);
      // Verilmeyen opsiyonel string alanlar boş stringe düşer.
      expect(out.leaderId, '');
      expect(out.topAsset, '');
    });

    test('GameStartMessage seed/leaderId/startAtMs korunur', () {
      final out = roundTrip<GameStartMessage>(GameStartMessage(
        sid: 's',
        startAtMs: 12,
        seed: 987654,
        leaderId: 'dev-B',
      ));
      expect(out.startAtMs, 12);
      expect(out.seed, 987654);
      expect(out.leaderId, 'dev-B');
    });

    test('GameStartMessage opsiyonel alanlar null kalır', () {
      final out = roundTrip<GameStartMessage>(GameStartMessage(sid: 's'));
      expect(out.startAtMs, isNull);
      expect(out.seed, isNull);
      expect(out.leaderId, isNull);
    });

    test('ShareOfferMessage extra map ve offerId korunur', () {
      final out = roundTrip<ShareOfferMessage>(ShareOfferMessage(
        sid: 's',
        kind: 'share_info',
        value: 'instagram_handle',
        offerId: 'offer-1',
        extra: {'shareKind': 'ShareKind.social', 'n': 5},
      ));
      expect(out.kind, 'share_info');
      expect(out.value, 'instagram_handle');
      expect(out.offerId, 'offer-1');
      expect(out.extra, isNotNull);
      expect(out.extra!['shareKind'], 'ShareKind.social');
      expect(out.extra!['n'], 5);
    });

    test('SensorSnapshotMessage nativeDeviceId korunur', () {
      final out = roundTrip<SensorSnapshotMessage>(SensorSnapshotMessage(
        sid: 's',
        isFlat: true,
        headingDeg: 123.5,
        timestampMs: 42,
        nativeDeviceId: 'uuid-123',
      ));
      expect(out.isFlat, true);
      expect(out.headingDeg, 123.5);
      expect(out.timestampMs, 42);
      expect(out.nativeDeviceId, 'uuid-123');
    });

    test('ShareResponseMessage decision, accepted üzerinden türetilir', () {
      final accepted = roundTrip<ShareResponseMessage>(
          ShareResponseMessage(sid: 's', accepted: true));
      expect(accepted.accepted, true);
      expect(accepted.decision, 'accept');

      final rejected = roundTrip<ShareResponseMessage>(
          ShareResponseMessage(sid: 's', accepted: false));
      expect(rejected.decision, 'reject');
    });

    test('Küçük/pairing mesajları tip olarak korunur', () {
      expect(roundTrip<HelloMessage>(HelloMessage(sid: 's')).sid, 's');
      expect(roundTrip<HeartbeatMessage>(HeartbeatMessage(sid: 's')).sid, 's');
      expect(roundTrip<PairIntentMessage>(PairIntentMessage(sid: 's')).sid, 's');
      expect(roundTrip<PairAckMessage>(PairAckMessage(sid: 's')).sid, 's');
      expect(roundTrip<RetryIntentMessage>(RetryIntentMessage(sid: 's')).sid, 's');
      final rej = roundTrip<PairRejectMessage>(
          PairRejectMessage(sid: 's', reason: 'flat'));
      expect(rej.reason, 'flat');
    });
  });

  group('ErrorMessage.code fallback', () {
    test('code verilmezse error değerine düşer (constructor)', () {
      final e = ErrorMessage(sid: 's', error: 'boom');
      expect(e.code, 'boom');
    });

    test('fromJson code alanı yoksa error kullanılır', () {
      final e = ErrorMessage.fromJson({'sid': 's', 'error': 'net_lost'});
      expect(e.code, 'net_lost');
    });

    test('fromJson code alanı varsa onu kullanır', () {
      final e = ErrorMessage.fromJson(
          {'sid': 's', 'error': 'net_lost', 'code': 'E_NET'});
      expect(e.code, 'E_NET');
    });
  });

  group('P2pCodec hata durumları', () {
    test('bilinmeyen mesaj tipi exception fırlatır', () {
      expect(() => codec.decode('{"t":"wat","sid":"s"}'), throwsException);
    });

    test('bozuk JSON exception fırlatır', () {
      expect(() => codec.decode('{not json'), throwsException);
    });

    test('t alanı olmayan JSON exception fırlatır', () {
      // t → '' → bilinmeyen tip
      expect(() => codec.decode('{"sid":"s"}'), throwsException);
    });
  });
}
