import 'dart:async';
import 'package:flutter/material.dart';
import '../app/app_coordinator.dart';
import 'widgets/soft_miss_view.dart';

class TerminalFailScreen extends StatelessWidget {
  final AppCoordinator coordinator;
  const TerminalFailScreen({super.key, required this.coordinator});

  @override
  Widget build(BuildContext context) {
    print("[TERMINAL_FAIL_SCREEN] Building! 🎬");
    return SoftMissView(
      onComplete: () {
        // Animation is complete, transition to terminal state
        coordinator.stopAll();
      },
    );
  }
}
