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
  // Marka moruyla ilişkili serin/sıcak bir çift — birbirinden net ayrışır.
  // ─────────────────────────────────────────────────────────────────────────────

  /// Top choice - cool periwinkle (mor ailesinden)
  static const Color choiceTop = Color(0xFF7E93FF);

  /// Bottom choice - warm rose (mor-magenta ucuna doğru)
  static const Color choiceBottom = Color(0xFFFF8FA6);

  /// No selection made - neutral ghost
  static const Color choiceNone = Color(0xFF4A4458);

  /// Default/unselected state
  static const Color choiceDefault = Color(0xFF2A2438);

  // ─────────────────────────────────────────────────────────────────────────────
  // RESULT STATES (Match outcomes)
  // Semantikler marka ailesinden türetildi: olumlu=lime, olumsuz=magenta-kızıl.
  // ─────────────────────────────────────────────────────────────────────────────

  /// Match - lime ailesinden olumlu
  static const Color match = Color(0xFF93D845);

  /// Mismatch - marka moruyla ilişkili gül-kızıl
  static const Color mismatch = Color(0xFFE24A6A);

  /// Local player didn't select - muted amber
  static const Color localTimeout = Color(0xFFE0A94A);

  /// Peer didn't select - periwinkle (choiceTop ile hizalı)
  static const Color peerTimeout = Color(0xFF7E93FF);

  /// Both didn't select - neutral lavender (mor ailesi)
  static const Color bothTimeout = Color(0xFF8B7FB8);

  // ─────────────────────────────────────────────────────────────────────────────
  // TERMINAL ANIMATIONS (Success/Failure)
  // Başarı lime ailesinden, başarısızlık mor-magenta ailesinden türetildi;
  // artık Flat-UI emerald/crimson yerine markayla uyumlu.
  // ─────────────────────────────────────────────────────────────────────────────

  /// Success primary - brand green
  static const Color successPrimary = Color(0xFF93D845);

  /// Success accent - deeper leaf
  static const Color successAccent = Color(0xFF6FB33A);

  /// Success glow - bright lime (for effects)
  static const Color successGlow = Color(0xFFC4F94E);

  /// Failure primary - rose-red (mor undertone)
  static const Color failurePrimary = Color(0xFFE24A6A);

  /// Failure accent - magenta-plum (markaya bağlar)
  static const Color failureAccent = Color(0xFFA83A7A);

  /// Failure glow - soft rose (for effects)
  static const Color failureGlow = Color(0xFFFF6E90);
  
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
  
  /// Reconnecting indicator - warm amber (kasıtlı olarak nötr/uyarı tonu)
  static const Color reconnecting = Color(0xFFFFB454);

  /// Retry button active - lime ailesinden onay
  static const Color retryActive = Color(0xFFA6E84D);
  
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
