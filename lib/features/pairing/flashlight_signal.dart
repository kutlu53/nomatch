import 'dart:async';
import 'package:torch_light/torch_light.dart';
import 'dart:developer' as dev;

/// Telefon flaş ışığını kontrol eden ve sinyalizasyon için
/// kullanılan yönetici sınıf.
class FlashlightSignal {
  Timer? _blinkTimer;
  bool _isBlinking = false;
  bool _currentState = false;

  // ✅ FIX: Her start/stop isteği nesli artırır; eski isteğin gecikmiş
  // async devamları (isTorchAvailable/enableTorch await'leri) nesil
  // değiştiyse vazgeçer. Eskiden hızlı aç-kapa yarışında stopBlinking()
  // no-op kalıyor ve fener sonsuza kadar yanıp sönmeye devam ediyordu.
  int _generation = 0;

  /// Flaş desteklenmiyor mu?
  bool _notSupported = false;

  bool get isBlinking => _isBlinking;

  /// Flaş ışığını yanıp söndürmeyi başlatır (düşük pil tüketimi için 1 sn aralık)
  Future<void> startBlinking() async {
    if (_isBlinking) return;

    // İstenen durum await'lerden ÖNCE işaretlenir ki bu sırada gelen
    // stopBlinking() no-op kalmasın.
    _isBlinking = true;
    final gen = ++_generation;

    try {
      // Check if torch is available
      final hasFlash = await TorchLight.isTorchAvailable();
      if (gen != _generation) return; // bu sırada stop/yeni start geldi
      if (!hasFlash) {
        _notSupported = true;
        _isBlinking = false;
        dev.log("FLASHLIGHT: Torch not available on this device");
        return;
      }

      dev.log("FLASHLIGHT: Starting blink");

      // 1 saniyede bir yanıp sönme (pil dostu)
      _blinkTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
        if (gen != _generation) return;
        try {
          if (_currentState) {
            await TorchLight.disableTorch();
            _currentState = false;
          } else {
            await TorchLight.enableTorch();
            if (gen != _generation) {
              // enableTorch beklerken stop geldi; feneri açık bırakma.
              await TorchLight.disableTorch();
              return;
            }
            _currentState = true;
          }
        } catch (e) {
          dev.log("FLASHLIGHT: Blink error: $e");
        }
      });
    } catch (e) {
      dev.log("FLASHLIGHT: Start error: $e");
      if (gen == _generation) {
        _notSupported = true;
        _isBlinking = false;
      }
    }
  }

  Future<bool> ensureAvailable() async {
    if (_notSupported) return false;
    try {
      final hasFlash = await TorchLight.isTorchAvailable();
      if (!hasFlash) {
        _notSupported = true;
      }
      return hasFlash;
    } catch (e) {
      dev.log("FLASHLIGHT: Availability error: $e");
      _notSupported = true;
      return false;
    }
  }

  Future<void> startLowPowerBlink({int onMs = 120, int offMs = 1500}) async {
    if (_isBlinking) return;
    _isBlinking = true; // await'ten önce işaretle (stop yarışı)
    final gen = ++_generation;
    final hasFlash = await ensureAvailable();
    if (gen != _generation) return;
    if (!hasFlash) {
      _isBlinking = false;
      return;
    }

    await _setTorchState(true);
    if (gen != _generation) {
      await _setTorchState(false); // stop yarışı: açık bırakma
      return;
    }
    _scheduleNextBlink(gen: gen, isOn: true, onMs: onMs, offMs: offMs);
  }

  /// Flaş ışığını durdurur ve kapatır
  Future<void> stopBlinking() async {
    // ✅ FIX: '_isBlinking değilse çık' kontrolü kaldırıldı — start hazırlığı
    // (availability await'i) sırasında gelen kapatma da işlemeli. Kapatma
    // her durumda güvenlidir.
    _generation++;
    _isBlinking = false;
    _blinkTimer?.cancel();
    _blinkTimer = null;

    try {
      await TorchLight.disableTorch();
      _currentState = false;
      dev.log("FLASHLIGHT: Stopped");
    } catch (e) {
      dev.log("FLASHLIGHT: Stop error: $e");
    }
  }

  /// Temizlik
  void dispose() {
    stopBlinking();
  }

  void _scheduleNextBlink({required int gen, required bool isOn, required int onMs, required int offMs}) {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(Duration(milliseconds: isOn ? onMs : offMs), () async {
      if (gen != _generation || !_isBlinking) return;
      await _setTorchState(!isOn);
      if (gen != _generation) {
        await _setTorchState(false); // stop yarışı: açık bırakma
        return;
      }
      _scheduleNextBlink(gen: gen, isOn: !isOn, onMs: onMs, offMs: offMs);
    });
  }

  Future<void> _setTorchState(bool enable) async {
    try {
      if (enable) {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }
      _currentState = enable;
    } catch (e) {
      dev.log("FLASHLIGHT: Toggle error: $e");
    }
  }
}
