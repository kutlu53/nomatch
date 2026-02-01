import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gradient tipleri
enum GradientType {
  linear,
  radial,
  sweep,
  vertical,
  horizontal,
  corner,
}

/// Renk paletleri - Uygulama genelinde kullanılır
enum ColorPalette {
  midnightMischief,
  tropicalParadise,
  sunsetFlirt,
  cherryBlossom,
  forestTwilight,
  lavenderDream,
  cosmicConnection,
  bubblegumRebel,
}

extension ColorPaletteExtension on ColorPalette {
  /// Palet emoji'si (yazı yok, sadece emoji)
  String get emoji {
    switch (this) {
      case ColorPalette.midnightMischief: return '🌙';
      case ColorPalette.tropicalParadise: return '🌴';
      case ColorPalette.sunsetFlirt: return '🌅';
      case ColorPalette.cherryBlossom: return '🌸';
      case ColorPalette.forestTwilight: return '🌲';
      case ColorPalette.lavenderDream: return '🦋';
      case ColorPalette.cosmicConnection: return '🚀';
      case ColorPalette.bubblegumRebel: return '💗';
    }
  }
  
  /// Palet renkleri
  List<Color> get colors {
    switch (this) {
      case ColorPalette.midnightMischief:
        return [
          const Color(0xFF1a1a2e),
          const Color(0xFF16213e),
          const Color(0xFF0f3460),
          const Color(0xFFe94560),
        ];
      case ColorPalette.tropicalParadise:
        return [
          const Color(0xFF004e64),
          const Color(0xFF00a5cf),
          const Color(0xFF25a18e),
          const Color(0xFFffdd00),
        ];
      case ColorPalette.sunsetFlirt:
        return [
          const Color(0xFF2d1b69),
          const Color(0xFF11468f),
          const Color(0xFFf77f00),
          const Color(0xFFfcbf49),
        ];
      case ColorPalette.cherryBlossom:
        return [
          const Color(0xFF6a4c93),
          const Color(0xFFa44a8e),
          const Color(0xFFeb5e95),
          const Color(0xFFffcce1),
        ];
      case ColorPalette.forestTwilight:
        return [
          const Color(0xFF081c15),
          const Color(0xFF1b4332),
          const Color(0xFF40916c),
          const Color(0xFF52b788),
        ];
      case ColorPalette.lavenderDream:
        return [
          const Color(0xFF3d1c59),
          const Color(0xFF7c3aed),
          const Color(0xFFa78bfa),
          const Color(0xFFfde68a),
        ];
      case ColorPalette.cosmicConnection:
        return [
          const Color(0xFF0d1b2a),
          const Color(0xFF1b263b),
          const Color(0xFF415a77),
          const Color(0xFFe0e1dd),
        ];
      case ColorPalette.bubblegumRebel:
        return [
          const Color(0xFF2b2d42),
          const Color(0xFF8d99ae),
          const Color(0xFFffc2d1),
          const Color(0xFFff006e),
        ];
    }
  }
  
  /// Linear Gradient (diagonal) - yumuşak geçiş
  LinearGradient get gradientLinear {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    );
  }

  /// Radial Gradient (circular - center'dan dış taraf)
  RadialGradient get gradientRadial {
    return RadialGradient(
      center: Alignment.center,
      radius: 1.5,
      colors: colors,
    );
  }

  /// Sweep Gradient (döner/spiral)
  SweepGradient get gradientSweep {
    return SweepGradient(
      center: Alignment.center,
      colors: colors,
      startAngle: 0.0,
      endAngle: 3.14 * 2, // Full circle
    );
  }

  /// Vertical Linear Gradient (yukarıdan aşağıya)
  LinearGradient get gradientVertical {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
    );
  }

  /// Horizontal Linear Gradient (soldan sağa)
  LinearGradient get gradientHorizontal {
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: colors,
    );
  }

  /// Corner-to-corner (bottom-right to top-left)
  LinearGradient get gradientCorner {
    return LinearGradient(
      begin: Alignment.bottomRight,
      end: Alignment.topLeft,
      colors: colors,
    );
  }

  /// Default gradient (for backward compatibility)
  LinearGradient get gradient => gradientLinear;
}

/// Renk paleti yöneticisi - Singleton
class ColorPaletteManager {
  static final ColorPaletteManager _instance = ColorPaletteManager._internal();
  factory ColorPaletteManager() => _instance;
  ColorPaletteManager._internal();
  
  static const String _storageKey = 'selected_color_palette';
  static const String _gradientKey = 'selected_gradient_type';
  
  ColorPalette _currentPalette = ColorPalette.midnightMischief;
  GradientType _currentGradientType = GradientType.linear;
  
  /// Mevcut paleti al
  ColorPalette get currentPalette => _currentPalette;
  
  /// Mevcut gradient tipini al
  GradientType get currentGradientType => _currentGradientType;
  
  /// Mevcut gradient'i oluştur (yumuşak geçişler için stops yok)
  Gradient get currentGradient {
    final colors = _currentPalette.colors;
    // stops kaldırıldı - Flutter otomatik eşit dağıtır = daha yumuşak geçiş
    
    return switch (_currentGradientType) {
      GradientType.linear => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ),
      GradientType.radial => RadialGradient(
        center: Alignment.center,
        radius: 1.5,
        colors: colors,
      ),
      GradientType.sweep => SweepGradient(
        center: Alignment.center,
        colors: colors,
        startAngle: 0.0,
        endAngle: math.pi * 2,
      ),
      GradientType.vertical => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ),
      GradientType.horizontal => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: colors,
      ),
      GradientType.corner => LinearGradient(
        begin: Alignment.bottomRight,
        end: Alignment.topLeft,
        colors: colors,
      ),
    };
  }
  
  /// Paleti değiştir (kaydetme yok - sadece session için)
  void setPalette(ColorPalette palette) {
    _currentPalette = palette;
  }
  
  /// Gradient tipini değiştir (kaydetme yok - sadece session için)
  void setGradientType(GradientType type) {
    _currentGradientType = type;
  }
  
  /// Paleti ve gradient tipini birlikte set et
  void setTheme(ColorPalette palette, GradientType gradientType) {
    _currentPalette = palette;
    _currentGradientType = gradientType;
  }
  
  /// Kaydedilmiş paleti yükle
  Future<void> loadPalette() async {
    final prefs = await SharedPreferences.getInstance();
    final paletteIndex = prefs.getInt(_storageKey);
    if (paletteIndex != null && paletteIndex >= 0 && paletteIndex < ColorPalette.values.length) {
      _currentPalette = ColorPalette.values[paletteIndex];
    }
    final gradientIndex = prefs.getInt(_gradientKey);
    if (gradientIndex != null && gradientIndex >= 0 && gradientIndex < GradientType.values.length) {
      _currentGradientType = GradientType.values[gradientIndex];
    }
  }
  
  /// Paleti ve gradient tipini kaydet
  Future<void> saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_storageKey, _currentPalette.index);
    await prefs.setInt(_gradientKey, _currentGradientType.index);
  }
}
