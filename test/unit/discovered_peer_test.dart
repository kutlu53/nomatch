import 'package:flutter_test/flutter_test.dart';
import 'package:nomatch/app/pairing_manager.dart';

/// DiscoveredPeer.normalizedDistance — public transport modunda dot'un
/// merkeze uzaklığını sinyal gücünden hesaplar. Clamp sınırlarındaki
/// hatalar dot'ların ekran dışına taşmasına yol açabilir.
void main() {
  DiscoveredPeer peer(int rssi) => DiscoveredPeer(
        id: 'p',
        rssi: rssi,
        lastSeen: DateTime(2020),
      );

  group('normalizedDistance (0.0=uzak, 1.0=yakın)', () {
    test('en yakın sınır (-40 dBm) → 1.0', () {
      expect(peer(-40).normalizedDistance, 1.0);
    });

    test('en uzak sınır (-90 dBm) → 0.0', () {
      expect(peer(-90).normalizedDistance, 0.0);
    });

    test('orta nokta (-65 dBm) → 0.5', () {
      expect(peer(-65).normalizedDistance, closeTo(0.5, 1e-9));
    });

    test('çok zayıf sinyal (-100 dBm) alt sınıra clamp → 0.0', () {
      expect(peer(-100).normalizedDistance, 0.0);
    });

    test('çok güçlü sinyal (-20 dBm) üst sınıra clamp → 1.0', () {
      expect(peer(-20).normalizedDistance, 1.0);
    });

    test('sonuç her zaman 0.0..1.0 aralığında', () {
      for (final rssi in [-200, -95, -70, -50, -30, 0, 50]) {
        final v = peer(rssi).normalizedDistance;
        expect(v >= 0.0 && v <= 1.0, true, reason: 'rssi=$rssi → $v');
      }
    });
  });

  group('DiscoveredPeer.copyWith', () {
    test('state güncellenir, id sabit kalır', () {
      final p = peer(-50);
      final updated = p.copyWith(state: PublicPeerState.matched);
      expect(updated.id, 'p');
      expect(updated.state, PublicPeerState.matched);
      expect(updated.rssi, -50);
    });
  });
}
