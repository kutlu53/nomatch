import 'dart:async';
import 'package:torch_light/torch_light.dart';
import 'dart:developer' as dev;

/// Telefon flaş ışığını kontrol eden ve sinyalizasyon için
/// kullanılan yönetici sınıf.
class FlashlightSignal {
  Timer? _blinkTimer;
  bool _isBlinking = false;
  bool _currentState = false;

  /// Flaş desteklenmiyor mu?
  bool _notSupported = false;

  bool get isBlinking => _isBlinking;

  /// Flaş ışığını yanıp söndürmeyi başlatır (düşük pil tüketimi için 1 sn aralık)
  Future<void> startBlinking() async {
    if (_isBlinking) return;

    try {
      // Check if torch is available
      final hasFlash = await TorchLight.isTorchAvailable();
      if (!hasFlash) {
        _notSupported = true;
        dev.log("FLASHLIGHT: Torch not available on this device");
        return;
      }

      _isBlinking = true;
      dev.log("FLASHLIGHT: Starting blink");

      // 1 saniyede bir yanıp sönme (pil dostu)
      _blinkTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
        try {
          if (_currentState) {
            await TorchLight.disableTorch();
            _currentState = false;
          } else {
            await TorchLight.enableTorch();
            _currentState = true;
          }
        } catch (e) {
          dev.log("FLASHLIGHT: Blink error: $e");
        }
      });
    } catch (e) {
      dev.log("FLASHLIGHT: Start error: $e");
      _notSupported = true;
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
    final hasFlash = await ensureAvailable();
    if (!hasFlash) return;

    _isBlinking = true;
    await _setTorchState(true);
    _scheduleNextBlink(isOn: true, onMs: onMs, offMs: offMs);
  }

  /// Flaş ışığını durdurur ve kapatır
  Future<void> stopBlinking() async {
    if (!_isBlinking) return;

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

  void _scheduleNextBlink({required bool isOn, required int onMs, required int offMs}) {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(Duration(milliseconds: isOn ? onMs : offMs), () async {
      if (!_isBlinking) return;
      await _setTorchState(!isOn);
      _scheduleNextBlink(isOn: !isOn, onMs: onMs, offMs: offMs);
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
