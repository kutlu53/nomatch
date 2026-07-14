import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/pairing_manager.dart';
import '../theme/app_background.dart';
import 'anim/diverge_animation.dart';

/// Eşleşme başarısızlık ekranı — soyut "ayrılma" animasyonu.
/// Görsel iş [DivergeAnimation] içinde; bu ekran yalnızca arka planı ve
/// animasyon sonrası otomatik reset'i yönetir.
class PairingFailedScreen extends StatefulWidget {
  final PairingManager pairingManager;

  const PairingFailedScreen({
    super.key,
    required this.pairingManager,
  });

  @override
  State<PairingFailedScreen> createState() => _PairingFailedScreenState();
}

class _PairingFailedScreenState extends State<PairingFailedScreen> {
  @override
  void initState() {
    super.initState();

    // ✅ UI: Başarısızlık anına dokunsal geri bildirim — girişte orta darbe,
    // bağın koptuğu anda (animasyonun 0.7'si ≈ 2450ms) hafif bir tık.
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 2450), () {
      if (mounted) HapticFeedback.lightImpact();
    });

    // ✅ UI: 4000ms → 3600ms — animasyon 3.5sn'de bitiyor; kullanıcıyı boş
    // ekranda yarım saniye bekletme. Router'daki çapraz solma dönüşü yumuşatır.
    Future.delayed(const Duration(milliseconds: 3600), () async {
      if (!mounted) return;
      await widget.pairingManager.hardReset();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: InkPlum.base,
      body: Stack(
        children: [
          // Ink Plum radial arka plan
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  InkPlum.surface.withValues(alpha: 0.3),
                  InkPlum.base,
                  InkPlum.edge,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          // Soyut ayrılma animasyonu
          const DivergeAnimation(),
        ],
      ),
    );
  }
}
