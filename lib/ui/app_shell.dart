import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../app/app_coordinator.dart';
import '../app/app_phase.dart';
import 'router.dart';

class AppShell extends StatefulWidget {
  final AppCoordinator coordinator;

  const AppShell({super.key, required this.coordinator});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppViewState _view = widget.coordinator.state;
  StreamSubscription<AppViewState>? _sub;
  int? _lastPrecachedQid;
  AppPhase? _lastLoggedPhase;

  @override
  void initState() {
    super.initState();
    _sub = widget.coordinator.states.listen((s) {
      if (!mounted) return;

      if (_lastLoggedPhase != s.phase) {
        _lastLoggedPhase = s.phase;
        dev.log('AppShell: phase_change -> ${s.phase}');
      }

      if (s.phase == AppPhase.playing && s.currentQuestion != null) {
        final qid = s.currentQuestion!.qid;
        if (_lastPrecachedQid != qid) {
          _lastPrecachedQid = qid;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              await precacheImage(AssetImage(s.currentQuestion!.topAsset), context);
              await precacheImage(AssetImage(s.currentQuestion!.bottomAsset), context);
            } catch (_) {}
          });
        }
      }

      setState(() => _view = s);
    });
    dev.log('AppShell:init state=${widget.coordinator.state.phase}');
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    dev.log('AppShell: build, phase=${_view.phase}');
    
    return AppRouter(
      coordinator: widget.coordinator,
      viewState: _view,
    );
  }
}

