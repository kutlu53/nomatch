import 'package:flutter/material.dart';

import 'app_background.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DESIGN TOKENS — Tek kaynak: boşluk, yarıçap, hareket ve elevation
// ═══════════════════════════════════════════════════════════════════════════════
//
// Amaç: ekranlara serpiştirilmiş "magic number"ları merkezileştirip tutarlı
// bir ritim kurmak. Yeni UI kodu bu token'ları kullanmalı; eski kod kademeli
// olarak buraya taşınabilir.

/// 4pt tabanlı boşluk ölçeği.
class Space {
  Space._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Köşe yarıçapı token'ları — değerler uygulamanın gerçek kullanımına hizalı
/// (page dot=4, kart/input=24, büyük board=32), böylece adopte etmek görünümü
/// değiştirmez; yalnızca 30/32 gibi yakın değerleri tek noktaya toplar.
class Radii {
  Radii._();
  static const double xs = 4;
  static const double sm = 12;
  static const double md = 24;
  static const double lg = 32;
  static const double pill = 999;

  static const BorderRadius brXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
}

/// Hareket süreleri — değerler uygulamanın gerçek ritmiyle hizalı
/// (baskın geçiş = 300ms, ikincil = 400ms, nabız/döngü = 800ms).
/// NOT: Çok fazlı koreografi süreleri (success 3000, radar 1600 vb.) kasıtlı
/// olarak token DIŞINDA tutulur; onlar sanatsal zamanlamadır, geçiş değil.
class Motion {
  Motion._();
  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration base = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration xslow = Duration(milliseconds: 800);

  /// Standart giriş/çıkış eğrisi (Material "standard" muadili).
  static const Curve standard = Curves.easeInOutCubic;

  /// Ekrana giren öğeler için yavaşlayan eğri.
  static const Curve decelerate = Curves.easeOutCubic;

  /// Ekrandan çıkan öğeler için hızlanan eğri.
  static const Curve accelerate = Curves.easeInCubic;
}

/// Elevation modeli — Ink Plum tabanına uygun 3 kademeli gölge seti.
/// Ad-hoc BoxShadow'lar yerine e1/e2/e3 kullanılmalı.
class Elevation {
  Elevation._();

  /// Hafif ayrım (basılı/aktif küçük öğeler).
  static List<BoxShadow> get e1 => [
        BoxShadow(
          color: InkPlum.edge.withValues(alpha: 0.40),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// Standart kart yükseltisi.
  static List<BoxShadow> get e2 => [
        BoxShadow(
          color: InkPlum.edge.withValues(alpha: 0.55),
          blurRadius: 20,
          offset: const Offset(0, 8),
          spreadRadius: 1,
        ),
      ];

  /// Öne çıkan/etkileşimli yüzey.
  static List<BoxShadow> get e3 => [
        BoxShadow(
          color: InkPlum.edge.withValues(alpha: 0.65),
          blurRadius: 28,
          offset: const Offset(0, 12),
          spreadRadius: 2,
        ),
      ];

  /// Bir aksan rengiyle vurgu halesi (basılı seçim vb.).
  static List<BoxShadow> glow(Color color, {double alpha = 0.4, double blur = 20}) => [
        BoxShadow(
          color: color.withValues(alpha: alpha),
          blurRadius: blur,
          spreadRadius: 2,
        ),
      ];
}
