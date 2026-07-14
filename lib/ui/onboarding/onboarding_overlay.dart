import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../theme/app_background.dart';

/// İlk açılış onboarding'i — iki sessiz vinyet videoyu sırayla oynatır
/// (radar → public). Herhangi bir dokunuş atlar; uygulamanın "yazı yok"
/// kuralına uygun olarak atlama düğmesi/metni yoktur.
///
/// Gösterim koşulu ve "bir kez" bayrağı [AppShell] tarafından yönetilir;
/// bu widget yalnızca oynatma + bitiş/atlama bildiriminden sorumludur.
class OnboardingOverlay extends StatefulWidget {
  /// Video bittiğinde veya kullanıcı atladığında çağrılır.
  final VoidCallback onFinished;

  const OnboardingOverlay({super.key, required this.onFinished});

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay>
    with SingleTickerProviderStateMixin {
  static const _videoAssets = [
    'assets/onboarding/radar_mode.mp4',
    'assets/onboarding/public_mode.mp4',
  ];

  final List<VideoPlayerController> _controllers = [];
  int _current = 0;
  bool _finishing = false;

  // Overlay giriş/çıkış solması
  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _initVideos();
  }

  Future<void> _initVideos() async {
    // İki video da baştan yüklenir (toplam ~6.6MB) — geçişte bekleme olmaz.
    for (final asset in _videoAssets) {
      final c = VideoPlayerController.asset(asset);
      _controllers.add(c);
    }

    try {
      await Future.wait(_controllers.map((c) async {
        await c.initialize();
        await c.setVolume(0); // Uygulama sessiz — video da sessiz
      }));
    } catch (e) {
      // Video yüklenemezse onboarding sessizce atlanır; kullanıcıyı
      // siyah ekranda bekletmek en kötü senaryo olurdu.
      debugPrint('[ONBOARDING] Video init hatası, atlanıyor: $e');
      _finish();
      return;
    }

    if (!mounted) return;

    _controllers[0].addListener(_onVideoProgress);
    setState(() {}); // İlk kare hazır
    _fadeController.forward();
    _controllers[0].play();
  }

  void _onVideoProgress() {
    final c = _controllers[_current];
    final v = c.value;
    if (!v.isInitialized) return;
    // Video sonuna geldi mi? (isCompleted bazı sürümlerde güvenilir değil)
    if (v.position >= v.duration && !v.isPlaying) {
      _advance();
    }
  }

  void _advance() {
    _controllers[_current].removeListener(_onVideoProgress);
    if (_current + 1 >= _controllers.length) {
      _finish();
      return;
    }
    setState(() => _current++);
    _controllers[_current].addListener(_onVideoProgress);
    _controllers[_current].play();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    for (final c in _controllers) {
      c.removeListener(_onVideoProgress);
      unawaited(c.pause());
    }
    if (mounted && _fadeController.value > 0) {
      await _fadeController.reverse();
    }
    widget.onFinished();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controllers.length > _videoAssets.length - 1 &&
        _controllers.every((c) => c.value.isInitialized);

    return FadeTransition(
      opacity: CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
      // Dokunuş her yerde atlar; opaque zemin alttaki ekranı hem gizler
      // hem de dokunuşların ona sızmasını engeller.
      child: GestureDetector(
        onTap: _finish,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: InkPlum.base,
          alignment: Alignment.center,
          child: !ready
              ? const SizedBox.shrink()
              // Videolar 9:16; contain ile Ink Plum zemin üzerinde
              // letterbox olur — zemin rengi videoyla akraba, dikiş görünmez.
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: AspectRatio(
                    key: ValueKey(_current),
                    aspectRatio: _controllers[_current].value.aspectRatio,
                    child: VideoPlayer(_controllers[_current]),
                  ),
                ),
        ),
      ),
    );
  }
}
