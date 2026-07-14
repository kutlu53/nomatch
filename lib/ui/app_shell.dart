import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/pairing_manager.dart';
import '../app/pairing_logic.dart';
import '../app/app_state.dart';
import '../features/game/lazy_question_provider.dart';
import '../plugins/p2p_ble/ble_p2p_plugin.dart';
import '../services/sensor_manager.dart';
import 'router.dart';

class AppShell extends StatefulWidget {
  final PairingManager pairingManager;
  final BleP2pPlugin blePlugin;
  final LazyQuestionProvider questions;

  const AppShell({
    super.key,
    required this.pairingManager,
    required this.blePlugin,
    required this.questions,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late AppViewState _viewState;

  StreamSubscription? _pairingStateSub;
  StreamSubscription? _flatSub;
  late final SensorManager _sensorManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialize sensor manager
    _sensorManager = SensorManager();

    // Initialize with current state from manager
    _viewState = AppViewState(
      pairingState: widget.pairingManager.state,
      isPhoneFlat: _sensorManager.isFlat,
    );

    // Listen to flat status changes
    _flatSub = _sensorManager.flatUpdates.listen((isFlat) {
      if (!mounted) return;
      setState(() {
        _viewState = _viewState.copyWith(isPhoneFlat: isFlat);
      });
    });

    // Listen to pairing state changes
    _pairingStateSub = widget.pairingManager.stateUpdates.listen((newState) {
      if (!mounted) return;
      setState(() {
        _viewState = _viewState.copyWith(pairingState: newState);
      });
      _syncWakelock(newState);
    });

    // ✅ Mevcut duruma göre wakelock'u ayarla (ör. hot restart sonrası)
    _syncWakelock(widget.pairingManager.state);

    // Start sensors
    _startSensors();
    
    // NOTE: Pairing is now started by user tapping OK button in PairingScreen
    // (was previously auto-started here with retry logic)
  }

  // ✅ FIX: Eşleştirme/oyun sırasında ekran kararmasın. Telefonlar masada
  // dokunulmadan durduğu için iOS otomatik kilidi oturumu öldürüyordu;
  // wakelock_plus pubspec'te ekliydi ama hiç kullanılmıyordu.
  void _syncWakelock(PairingState state) {
    final active = state != PairingState.idle && state != PairingState.failed;
    // Hata (ör. simülatörde desteklenmeme) oyunu etkilemesin diye yutulur.
    unawaited(WakelockPlus.toggle(enable: active).catchError((_) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Arka planda wakelock tutmanın anlamı yok; öne dönünce duruma göre aç.
    if (state == AppLifecycleState.resumed) {
      _syncWakelock(widget.pairingManager.state);
    } else if (state == AppLifecycleState.paused) {
      unawaited(WakelockPlus.disable().catchError((_) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(WakelockPlus.disable().catchError((_) {}));

    // ✅ Cancel stream subscriptions
    _pairingStateSub?.cancel();
    _flatSub?.cancel();
    
    // ✅ Dispose sensor manager (async - but fire and forget is ok in dispose)
    unawaited(_sensorManager.dispose());
    
    // ✅ Dispose pairing manager
    unawaited(widget.pairingManager.dispose());
    
    super.dispose();
  }

  Future<void> _startSensors() async {
    await _sensorManager.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppRouter(
        pairingManager: widget.pairingManager,
        viewState: _viewState,
      ),
    );
  }
}
