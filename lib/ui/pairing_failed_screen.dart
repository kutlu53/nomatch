import 'package:flutter/material.dart';
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

    // 4 saniye animasyon → hardReset → radar ekranı idle durumda açılır.
    // Kullanıcı üçgene dokunarak taramayı başlatır; otomatik başlatma yok.
    Future.delayed(const Duration(milliseconds: 4000), () async {
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
