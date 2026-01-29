import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  
  /// Gradient oluştur
  LinearGradient get gradient {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
      stops: const [0.0, 0.3, 0.7, 1.0],
    );
  }
}

/// Renk paleti yöneticisi - Singleton
class ColorPaletteManager {
  static final ColorPaletteManager _instance = ColorPaletteManager._internal();
  factory ColorPaletteManager() => _instance;
  ColorPaletteManager._internal();
  
  static const String _storageKey = 'selected_color_palette';
  ColorPalette _currentPalette = ColorPalette.midnightMischief;
  
  /// Mevcut paleti al
  ColorPalette get currentPalette => _currentPalette;
  
  /// Paleti değiştir ve kaydet
  Future<void> setPalette(ColorPalette palette) async {
    _currentPalette = palette;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_storageKey, palette.index);
  }
  
  /// Kaydedilmiş paleti yükle
  Future<void> loadPalette() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_storageKey);
    if (index != null && index >= 0 && index < ColorPalette.values.length) {
      _currentPalette = ColorPalette.values[index];
    }
  }
}
