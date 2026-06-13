import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// GAME COLOR SYSTEM - Ink Plum Compatible
// ═══════════════════════════════════════════════════════════════════════════════
// 
// Premium dark theme colors that harmonize with Ink Plum base palette.
// Inspired by the Secret Link overlay (purple + lime accent).
//
// Design principles:
// - Muted, sophisticated tones (no harsh bright colors)
// - High contrast against dark background for readability
// - Consistent opacity levels for visual hierarchy
// ═══════════════════════════════════════════════════════════════════════════════

class GameColors {
  GameColors._();

  // ─────────────────────────────────────────────────────────────────────────────
  // PRIMARY ACCENTS (from Secret Link)
  // ─────────────────────────────────────────────────────────────────────────────
  
  /// Primary purple - main brand accent
  static const Color purple = Color(0xFF7B5CFF);
  
  /// Secondary lime - complementary accent
  static const Color lime = Color(0xFFB4F000);
  
  // ─────────────────────────────────────────────────────────────────────────────
  // CHOICE INDICATORS (Top/Bottom selection)
  // ─────────────────────────────────────────────────────────────────────────────
  
  /// Top choice - cool cyan-violet
  static const Color choiceTop = Color(0xFF6E8EFF);
  
  /// Bottom choice - warm coral-peach
  static const Color choiceBottom = Color(0xFFFF8C6E);
  
  /// No selection made - neutral ghost
  static const Color choiceNone = Color(0xFF4A4458);
  
  /// Default/unselected state
  static const Color choiceDefault = Color(0xFF2A2438);
  
  // ─────────────────────────────────────────────────────────────────────────────
  // RESULT STATES (Match outcomes)
  // ─────────────────────────────────────────────────────────────────────────────
  
  /// Match - harmonious teal-mint
  static const Color match = Color(0xFF4ECDC4);
  
  /// Mismatch - soft rose-coral
  static const Color mismatch = Color(0xFFFF6B6B);
  
  /// Local player didn't select - muted amber
  static const Color localTimeout = Color(0xFFFFBE5C);
  
  /// Peer didn't select - soft sky blue
  static const Color peerTimeout = Color(0xFF5CB8FF);
  
  /// Both didn't select - neutral lavender
  static const Color bothTimeout = Color(0xFF8B7FB8);
  
  // ─────────────────────────────────────────────────────────────────────────────
  // TERMINAL ANIMATIONS (Success/Failure)
  // ─────────────────────────────────────────────────────────────────────────────
  
  /// Success primary - rich emerald
  static const Color successPrimary = Color(0xFF2ECC71);
  
  /// Success accent - teal harmony
  static const Color successAccent = Color(0xFF26A69A);
  
  /// Success glow - bright mint (for effects)
  static const Color successGlow = Color(0xFF69F0AE);
  
  /// Failure primary - deep crimson
  static const Color failurePrimary = Color(0xFFE74C3C);
  
  /// Failure accent - burnt orange
  static const Color failureAccent = Color(0xFFD35400);
  
  /// Failure glow - soft coral (for effects)
  static const Color failureGlow = Color(0xFFFF7675);
  
  // ─────────────────────────────────────────────────────────────────────────────
  // UI ELEMENTS
  // ─────────────────────────────────────────────────────────────────────────────
  
  /// Button/interactive elements - soft white
  static const Color interactiveLight = Color(0xFFF5F5F5);
  
  /// Pressed state overlay
  static const Color pressedOverlay = Color(0x33FFFFFF);
  
  /// Border highlight
  static const Color borderLight = Color(0x4DFFFFFF);
  
  /// Border subtle
  static const Color borderSubtle = Color(0x1AFFFFFF);
  
  /// Reconnecting indicator - warm orange
  static const Color reconnecting = Color(0xFFFF9F43);
  
  /// Retry button active - confirm green
  static const Color retryActive = Color(0xFF00E676);
  
  // ─────────────────────────────────────────────────────────────────────────────
  // OPACITY PRESETS
  // ─────────────────────────────────────────────────────────────────────────────
  
  /// High emphasis (primary content)
  static const double opacityHigh = 0.95;
  
  /// Medium emphasis (secondary content)
  static const double opacityMedium = 0.70;
  
  /// Low emphasis (tertiary/disabled)
  static const double opacityLow = 0.40;
  
  /// Subtle (hints, borders)
  static const double opacitySubtle = 0.20;
  
  /// Overlay background
  static const double opacityOverlay = 0.85;
}
