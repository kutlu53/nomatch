import 'dart:async';

import 'package:flutter/material.dart';

import '../app/pairing_manager.dart';
import '../app/app_state.dart';
import '../app/pairing_logic.dart';
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

class _AppShellState extends State<AppShell> {
  late AppViewState _viewState;

  StreamSubscription? _pairingStateSub;
  StreamSubscription? _flatSub;
  late final SensorManager _sensorManager;

  @override
  void initState() {
    super.initState();
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
    });

    // Start sensors
    _startSensors();
    
    // NOTE: Pairing is now started by user tapping OK button in PairingScreen
    // (was previously auto-started here with retry logic)
  }

  @override
  void dispose() {
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
