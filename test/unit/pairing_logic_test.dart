import 'package:flutter_test/flutter_test.dart';
import 'package:nomatch/app/pairing_logic.dart';

/// Heading doğrulama + leader seçim algoritması testleri.
///
/// Bunlar eşleşmenin çekirdeği: yön hesabındaki wraparound hataları veya
/// leader tie durumu gerçek cihazlarda "eşleşmiyor / iki lider" bug'larına yol açar.
void main() {
  group('HeadingValidation.isFacingEachOther (≈180° ±30°)', () {
    test('tam karşılıklı (0° / 180°) → true', () {
      expect(HeadingValidation.isFacingEachOther(0, 180), true);
    });

    test('kaydırılmış ama 180° fark (10° / 190°) → true', () {
      expect(HeadingValidation.isFacingEachOther(10, 190), true);
    });

    test('wraparound (350° / 170° = 180° fark) → true', () {
      expect(HeadingValidation.isFacingEachOther(350, 170), true);
    });

    test('tolerans alt sınırı: 150° fark → true (dahil)', () {
      expect(HeadingValidation.isFacingEachOther(0, 150), true);
    });

    test('tolerans dışında: 149° fark → false', () {
      expect(HeadingValidation.isFacingEachOther(0, 149), false);
    });

    test('tolerans üst sınırı: 210° fark (=150° normalize) → true', () {
      expect(HeadingValidation.isFacingEachOther(0, 210), true);
    });

    test('aynı yön (0° / 0°) → false', () {
      expect(HeadingValidation.isFacingEachOther(0, 0), false);
    });

    test('dik açı (0° / 90°) → false', () {
      expect(HeadingValidation.isFacingEachOther(0, 90), false);
    });

    test('argüman sırası simetriktir', () {
      expect(
        HeadingValidation.isFacingEachOther(190, 10),
        HeadingValidation.isFacingEachOther(10, 190),
      );
    });
  });

  group('HeadingValidation.getAngleDifference', () {
    test('0° / 180° = 180°', () {
      expect(HeadingValidation.getAngleDifference(0, 180), 180);
    });

    test('wraparound: 350° / 10° = 20°', () {
      expect(HeadingValidation.getAngleDifference(350, 10), 20);
    });

    test('her zaman 0..180 aralığında normalize', () {
      expect(HeadingValidation.getAngleDifference(10, 350), 20);
      expect(HeadingValidation.getAngleDifference(0, 270), 90);
    });
  });

  group('LeaderAlgorithm.selectLeader', () {
    test('küçük device ID lider olur', () {
      expect(LeaderAlgorithm.selectLeader('aaa', 'bbb'), true);
      expect(LeaderAlgorithm.selectLeader('bbb', 'aaa'), false);
    });

    test('eşit ID → false (tie: ikisi de lider değil)', () {
      // Not: Bu bir tehlike sinyali — aynı ID iki cihaz için deadlock riski.
      expect(LeaderAlgorithm.selectLeader('same', 'same'), false);
    });

    test('leader seçimi karşılıklı tutarlıdır (tam olarak bir lider)', () {
      const id1 = 'device-77';
      const id2 = 'device-12';
      final oneWay = LeaderAlgorithm.selectLeader(id1, id2);
      final otherWay = LeaderAlgorithm.selectLeader(id2, id1);
      expect(oneWay, isNot(otherWay),
          reason: 'İki farklı cihazdan tam olarak biri lider olmalı');
    });
  });

  group('LeaderAlgorithm.generateSessionId', () {
    test('normal (uzun) ID\'lerle prefix_prefix_timestamp formatı', () {
      final sid = LeaderAlgorithm.generateSessionId(
          'AAAAAAAA1111', 'BBBBBBBB2222');
      expect(sid, startsWith('AAAAAAAA_BBBBBBBB_'));
      // Sonda geçerli bir timestamp olmalı.
      final ts = int.tryParse(sid.split('_').last);
      expect(ts, isNotNull);
      expect(ts! > 0, true);
    });

    test('8 karakterden kısa ID çökmez, olduğu gibi kullanılır (regresyon)', () {
      // Eskiden substring(0, 8) kısa ID'de RangeError fırlatıyordu; artık güvenli.
      final sid = LeaderAlgorithm.generateSessionId('short', 'BBBBBBBB2222');
      expect(sid, startsWith('short_BBBBBBBB_'));
      expect(int.tryParse(sid.split('_').last), isNotNull);
    });

    test('tam 8 karakter ID kesilmeden kullanılır', () {
      final sid = LeaderAlgorithm.generateSessionId('AAAAAAAA', 'BBBBBBBB');
      expect(sid, startsWith('AAAAAAAA_BBBBBBBB_'));
    });
  });
}
