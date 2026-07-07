// ═══════════════════════════════════════════════════════════════════════════════
// PREVIEW GALLERY — Ekranları cihazsız (Chrome) kontrol etmek için giriş noktası
// ═══════════════════════════════════════════════════════════════════════════════
//
// Çalıştırma:  flutter run -d chrome -t lib/preview_gallery.dart
//
// BLE/sensör/native GEREKTİRMEZ. Her ekranı sahte veriyle render eder; asıl
// uygulamayı DEĞİŞTİRMEZ (ayrı main()). TestFlight'a çıkmadan önce renk paleti,
// animasyonlar ve düzeni gözden geçirmek için.

import 'package:flutter/material.dart';

import 'theme/app_background.dart';
import 'theme/game_colors.dart';
import 'theme/design_tokens.dart';
import 'ui/start/start_triangle_button.dart';
import 'ui/radar/radar_rings_painter.dart';
import 'ui/widgets/brand_indicators.dart';
import 'ui/anim/diverge_animation.dart';
import 'features/game/game_screen.dart';
import 'features/game/game_share_screen.dart';
import 'features/game/game_engine.dart';
import 'plugins/p2p/p2p_messages.dart';

void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tap!Match — Önizleme',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: GameColors.purple,
          secondary: GameColors.lime,
          surface: InkPlum.surface,
        ),
        scaffoldBackgroundColor: Colors.transparent,
      ),
      builder: (context, child) =>
          AppBackground(child: child ?? const SizedBox.shrink()),
      home: const _GalleryHome(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sahte transport & engine kurulumu (testlerdekiyle aynı mantık)
// ─────────────────────────────────────────────────────────────────────────────

class _FakeTransport implements GameTransport {
  @override
  Future<void> send(P2pMessage msg) async {}
}

const _kTop = 'assets/questions/13beach.webp';
const _kBottom = 'assets/questions/13cultural.webp';
const _kNow = 1000000;

void _startRound(GameEngine e, int rid) => e.onP2pMessage(RoundStartMessage(
      sid: 'preview',
      rid: rid,
      qid: rid,
      deadlineMs: _kNow + 5000,
      leaderId: 'aaaa',
      topAsset: _kTop,
      bottomAsset: _kBottom,
    ));

void _peerPick(GameEngine e, int rid, String c) => e.onP2pMessage(SelectionMessage(
    sid: 'preview', rid: rid, choice: c, madeAtMs: _kNow, rev: 1, isFinal: true));

/// Bağlı bir follower engine kurar ve ilk "playing" turunu açar.
Future<GameEngine> _buildEngine() async {
  final e = GameEngine(
    transport: _FakeTransport(),
    isLeader: false,
    sessionId: 'preview',
    localDeviceId: 'zzzz',
  );
  await e.onPeerConnected(peerId: 'peer');
  e.onTick(_kNow);
  _startRound(e, 1);
  return e;
}

/// 5 eşleşen turu oynatarak terminalSuccess'e sürer (ekran abone olduktan
/// SONRA çağrılır ki başarı animasyonu snapshot'ını canlı alsın).
void _playToWin(GameEngine e) {
  for (var rid = 1; rid <= 5; rid++) {
    _startRound(e, rid);
    e.onLocalTapTop();
    _peerPick(e, rid, 'top');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Galeri ana ekranı
// ─────────────────────────────────────────────────────────────────────────────

class _GalleryHome extends StatelessWidget {
  const _GalleryHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            const _Title('Tap!Match — Ekran Önizleme'),
            const SizedBox(height: Space.sm),
            const Text(
              'Cihazsız görsel kontrol • BLE/sensör gerekmez',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: Space.xl),

            // Tam ekran önizlemeler
            _Section('Tam ekranlar'),
            _NavTile('🚀 Açılış (splash) → radar',
                () => _open(context, const _SplashPreview())),
            _NavTile('🎮 Oyun tahtası (playing)',
                () => _open(context, const _GamePreview(win: false))),
            _NavTile('🎉 Kazanç animasyonu (win)',
                () => _open(context, const _GamePreview(win: true))),
            _NavTile('💔 Kayıp / eşleşememe animasyonu',
                () => _open(context, const _LossPreview())),
            _NavTile('📤 Paylaşım ekranı (WhatsApp / Instagram)',
                () => _open(context, const _SharePreview())),
            _NavTile('👤 Paylaşım sonucu (rakip bilgisi)',
                () => _open(context, const _ShareResultPreview())),

            const SizedBox(height: Space.xl),

            // Bileşen önizlemeleri (satır içi)
            _Section('Renk paleti'),
            const _PaletteRow(),

            const SizedBox(height: Space.xl),
            _Section('Başlangıç üçgeni (4 durum)'),
            const _TriangleRow(),

            const SizedBox(height: Space.xl),
            _Section('Radar halkaları (tarama)'),
            SizedBox(
              height: 260,
              child: Stack(
                alignment: Alignment.center,
                children: const [
                  RadarRingsWidget(isScanning: true),
                  StartTriangleButton(
                      isScanning: true, triangleState: TriangleState.scanning, onTap: _noop),
                ],
              ),
            ),

            const SizedBox(height: Space.xl),
            _Section('Marka göstergeleri (spinner / progress)'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                PulseLoader(size: 56, color: GameColors.purple),
                PulseLoader(size: 56, color: GameColors.lime),
                ProgressRing(value: 0.35, size: 56, color: GameColors.purple),
                ProgressRing(value: 0.75, size: 56, color: GameColors.retryActive),
              ],
            ),
            const SizedBox(height: Space.xxl),
          ],
        ),
      ),
    );
  }

  static void _noop() {}

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tam ekran önizleme sarmalayıcıları
// ─────────────────────────────────────────────────────────────────────────────

class _GamePreview extends StatefulWidget {
  final bool win;
  const _GamePreview({required this.win});

  @override
  State<_GamePreview> createState() => _GamePreviewState();
}

class _GamePreviewState extends State<_GamePreview> {
  GameEngine? _engine;

  @override
  void initState() {
    super.initState();
    _buildEngine().then((e) {
      if (!mounted) return;
      setState(() => _engine = e);
      if (widget.win) {
        // Ekran abone olduktan SONRA kazanca sür ki başarı animasyonu görünsün.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _playToWin(e);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = _engine;
    return _PreviewScaffold(
      child: e == null
          ? const Center(child: PulseLoader())
          : GameScreen(
              engine: e,
              onOpenShare: () {},
              onReset: () => Navigator.of(context).maybePop(),
            ),
    );
  }
}

class _LossPreview extends StatelessWidget {
  const _LossPreview();

  @override
  Widget build(BuildContext context) {
    return const _PreviewScaffold(child: DivergeAnimation());
  }
}

/// Açılışın (native splash) tarayıcı karşılığı: Ink Plum zemin + ortada
/// şeffaf logo, ~900ms sonra 300ms fade ile radar ekranına geçiş.
/// NOT: Yakın bir taklittir; gerçek native splash yalnızca iOS build'inde görünür.
class _SplashPreview extends StatefulWidget {
  const _SplashPreview();

  @override
  State<_SplashPreview> createState() => _SplashPreviewState();
}

class _SplashPreviewState extends State<_SplashPreview>
    with SingleTickerProviderStateMixin {
  // 1.0 = splash tam görünür, 0.0 = tamamen radar
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _play();
  }

  void _play() {
    _fade.value = 1.0;
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _fade.reverse();
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logoW =
        (MediaQuery.of(context).size.shortestSide * 0.5).clamp(140.0, 260.0);
    return _PreviewScaffold(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Altta: açılış sonrası gelen radar ekranı
          const Positioned.fill(
            child: Stack(
              alignment: Alignment.center,
              children: [
                RadarRingsWidget(isScanning: false),
                StartTriangleButton(
                    isScanning: false,
                    triangleState: TriangleState.idle,
                    onTap: _noop),
              ],
            ),
          ),
          // Üstte: solid Ink Plum splash + ortada logo (fade ile kaybolur)
          FadeTransition(
            opacity: _fade,
            child: Container(
              color: InkPlum.base,
              alignment: Alignment.center,
              child: Image.asset(
                'assets/branding/logo.png',
                width: logoW,
                fit: BoxFit.contain,
              ),
            ),
          ),
          // Tekrar oynat
          Positioned(
            bottom: 32,
            child: TextButton.icon(
              onPressed: _play,
              icon: const Icon(Icons.replay, color: Colors.white54, size: 18),
              label: const Text('tekrar oynat',
                  style: TextStyle(color: Colors.white54)),
            ),
          ),
        ],
      ),
    );
  }

  static void _noop() {}
}

class _SharePreview extends StatefulWidget {
  const _SharePreview();

  @override
  State<_SharePreview> createState() => _SharePreviewState();
}

class _SharePreviewState extends State<_SharePreview> {
  GameEngine? _engine;

  @override
  void initState() {
    super.initState();
    _buildEngine().then((e) {
      if (mounted) setState(() => _engine = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = _engine;
    return _PreviewScaffold(
      child: e == null
          ? const Center(child: PulseLoader())
          : GameShareScreen(
              engine: e,
              onReset: () => Navigator.of(context).maybePop(),
            ),
    );
  }
}

class _ShareResultPreview extends StatefulWidget {
  const _ShareResultPreview();

  @override
  State<_ShareResultPreview> createState() => _ShareResultPreviewState();
}

class _ShareResultPreviewState extends State<_ShareResultPreview> {
  GameEngine? _engine;

  @override
  void initState() {
    super.initState();
    _buildEngine().then((e) {
      if (mounted) setState(() => _engine = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = _engine;
    return _PreviewScaffold(
      child: e == null
          ? const Center(child: PulseLoader())
          : GameShareResultScreen(
              engine: e,
              peerValue: '5551234567',
              peerShareKind: ShareKind.phone,
              onReset: () => Navigator.of(context).maybePop(),
            ),
    );
  }
}

/// Tam ekran önizlemeler için: Ink Plum arka plan + geri butonu.
class _PreviewScaffold extends StatelessWidget {
  final Widget child;
  const _PreviewScaffold({required this.child});

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(child: child),
            Positioned(
              top: MediaQuery.of(context).padding.top + Space.sm,
              left: Space.sm,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Küçük yardımcı widget'lar
// ─────────────────────────────────────────────────────────────────────────────

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700));
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                color: GameColors.lime.withValues(alpha: 0.8),
                fontSize: 12,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700)),
      );
}

class _NavTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NavTile(this.label, this.onTap);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: Material(
          color: InkPlum.surface.withValues(alpha: 0.6),
          borderRadius: Radii.brMd,
          child: InkWell(
            borderRadius: Radii.brMd,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg, vertical: Space.md),
              child: Row(
                children: [
                  Expanded(
                      child: Text(label,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16))),
                  const Icon(Icons.chevron_right, color: Colors.white38),
                ],
              ),
            ),
          ),
        ),
      );
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow();

  @override
  Widget build(BuildContext context) {
    const swatches = <(String, Color)>[
      ('purple', GameColors.purple),
      ('lime', GameColors.lime),
      ('choiceTop', GameColors.choiceTop),
      ('choiceBottom', GameColors.choiceBottom),
      ('success', GameColors.successPrimary),
      ('successGlow', GameColors.successGlow),
      ('failure', GameColors.failurePrimary),
      ('failureAccent', GameColors.failureAccent),
      ('reconnecting', GameColors.reconnecting),
      ('retryActive', GameColors.retryActive),
    ];
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final (name, color) in swatches)
          Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: Radii.brSm,
                  boxShadow: Elevation.e1,
                ),
              ),
              const SizedBox(height: Space.xs),
              SizedBox(
                width: 62,
                child: Text(name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ),
            ],
          ),
      ],
    );
  }
}

class _TriangleRow extends StatelessWidget {
  const _TriangleRow();

  @override
  Widget build(BuildContext context) {
    const states = <(String, TriangleState, bool)>[
      ('idle', TriangleState.idle, false),
      ('scanning', TriangleState.scanning, true),
      ('connected', TriangleState.connected, false),
      ('matched', TriangleState.matched, false),
    ];
    return Wrap(
      spacing: Space.md,
      runSpacing: Space.md,
      children: [
        for (final (name, st, scanning) in states)
          Column(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: StartTriangleButton(
                    isScanning: scanning, triangleState: st, onTap: () {}),
              ),
              Text(name,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
      ],
    );
  }
}
