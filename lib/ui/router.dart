import 'package:flutter/material.dart';
import 'dart:developer' as dev;

import '../app/pairing_manager.dart';
import '../app/app_state.dart';
import '../app/pairing_logic.dart';
import '../features/game/game_screen.dart';
import '../features/game/game_share_screen.dart';
import '../features/game/game_state.dart';
import 'pairing_failed_screen.dart';
import 'pairing_screen.dart';

/// Router: maps PairingState -> screen widgets
/// 
/// Responsibility: ONLY screen selection based on state.
/// Animation logic is handled by individual screen widgets.
class AppRouter extends StatelessWidget {
  final PairingManager pairingManager;
  final AppViewState viewState;

  const AppRouter({
    super.key,
    required this.pairingManager,
    required this.viewState,
  });

  @override
  Widget build(BuildContext context) {
    final state = viewState.pairingState;
    dev.log('AppRouter: state=$state');

    return switch (state) {
      // Pairing states -> PairingScreen
      PairingState.idle ||
      PairingState.hostingReady ||
      PairingState.peerSearching ||
      PairingState.preConnected ||
      PairingState.headingValidating ||
      PairingState.connected => 
        PairingScreen(pairingManager: pairingManager, state: viewState),
      
      // Game states -> GameScreen
      PairingState.game || 
      PairingState.gameReady || 
      PairingState.playing => 
        _buildGameScreen(context),
      
      // Failed state -> PairingFailedScreen
      PairingState.failed => 
        PairingFailedScreen(pairingManager: pairingManager),
    };
  }
  
  Widget _buildGameScreen(BuildContext context) {
    return GameScreen(
      engine: pairingManager.gameEngine!,
      connectionStatus: pairingManager.connectionStatus,
      onOpenShare: () => _handleOpenShare(context),
      onReset: () => _handleReset(),
    );
  }
  
  void _handleOpenShare(BuildContext context) {
    final phase = pairingManager.gameEngine?.state.phase;
    
    if (phase != GamePhase.terminalSuccess) {
      dev.log('[ROUTER] onOpenShare ignored - phase=$phase');
      return;
    }
    
    pairingManager.setShareScreenActive(true);
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameShareScreen(
          engine: pairingManager.gameEngine!,
          connectionStatus: pairingManager.connectionStatus,
          onReset: () async {
            pairingManager.setShareScreenActive(false);
            await pairingManager.hardReset();
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
  
  Future<void> _handleReset() async {
    dev.log('[ROUTER] terminalFail - hard reset');
    await pairingManager.hardReset();
  }
}
