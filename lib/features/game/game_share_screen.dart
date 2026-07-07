import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/game_colors.dart';
import '../../theme/app_background.dart';
import '../../theme/design_tokens.dart';
import '../../ui/widgets/brand_indicators.dart';
import 'game_engine.dart';
import 'game_state.dart';

/// ✅ PERFORMANCE: Debug logging control
const bool _kShareScreenDebug = false;
void _ssLog(String msg) {
  if (_kShareScreenDebug) print(msg);
}

/// Game Share Screen - Eski ShareScreen UI'ı ile
/// Kullanıcılar bilgilerini paylaşırlar
/// Her iki oyuncu da paylaştığında GameShareResultScreen açılır
class GameShareScreen extends StatefulWidget {
  final GameEngine engine;
  final VoidCallback onReset;
  final Stream<bool>? connectionStatus; // ✅ BLE connection status stream

  const GameShareScreen({
    super.key,
    required this.engine,
    required this.onReset,
    this.connectionStatus,
  });

  @override
  State<GameShareScreen> createState() => _GameShareScreenState();
}

class _GameShareScreenState extends State<GameShareScreen>
    with TickerProviderStateMixin {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;
  bool _whatsappPressed = false;
  bool _instagramPressed = false;
  ShareKind? _selectedShareKind;
  bool _hasShared = false;

  // Peer info
  bool _peerHasShared = false;
  String? _peerValue;
  Object? _peerShareKind;

  late StreamSubscription<GameState> _gameStateSubscription;

  bool _longPressActive = false;
  Timer? _longPressTimer;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _transitioning = false;

  Timer? _autoResetTimer;

  // Peer bekleniyor göstergesi
  late AnimationController _waitingPulseController;

  // ✅ Connection status tracking
  StreamSubscription<bool>? _connectionSub;
  bool _isReconnecting = false;
  late AnimationController _reconnectPulseController;

  @override
  void initState() {
    super.initState();
    _ssLog("[SHARE-SCREEN] 📱 ═══════════════════════════════════════");
    _ssLog("[SHARE-SCREEN] 📱 Share screen açıldı!");
    _ssLog("[SHARE-SCREEN] 📱 ═══════════════════════════════════════");

    // Listen to game state for peer share updates
    _gameStateSubscription = widget.engine.states.listen((state) {
      if (mounted) {
        _ssLog("[SHARE-SCREEN] 🔄 DURUM GÜNCELLENDİ:");
        _ssLog("[SHARE-SCREEN]    - Benim paylaştığım: $_hasShared");
        _ssLog("[SHARE-SCREEN]    - Rakıp paylaştı: ${state.peerShared}");
        _ssLog("[SHARE-SCREEN]    - Rakıp değeri: ${state.peerShareValue}");
        _ssLog("[SHARE-SCREEN]    - Rakıp türü: ${state.peerShareKind}");

        setState(() {
          _peerHasShared = state.peerShared ?? false;
          _peerValue = state.peerShareValue;
          _peerShareKind = state.peerShareKind;
        });

        // ✅ Her iki oyuncu da paylaştığında ShareResultScreen'e geç
        if (_hasShared && _peerHasShared && _peerValue != null) {
          _ssLog("[SHARE-SCREEN] ✅ ═══════════════════════════════════════");
          _ssLog("[SHARE-SCREEN] ✅ HER İKİ OYUNCU DA PAYLAŞTI!");
          _ssLog("[SHARE-SCREEN] ✅ İşlem: ShareResultScreen'e geçiliyor...");
          _ssLog("[SHARE-SCREEN] ✅ ═══════════════════════════════════════");
          _goToShareResultScreen();
        }
      }
    });

    // Initialize with current engine state
    _peerHasShared = widget.engine.state.peerShared ?? false;
    _peerValue = widget.engine.state.peerShareValue;
    _peerShareKind = widget.engine.state.peerShareKind;
    _ssLog("[SHARE-SCREEN] 🔍 İlk durum kontrol:");
    _ssLog("[SHARE-SCREEN]    - Benim paylaştığım: $_hasShared");
    _ssLog("[SHARE-SCREEN]    - Rakıp paylaştı: $_peerHasShared");
    _ssLog("[SHARE-SCREEN]    - Rakıp değeri: $_peerValue");

    // Animations
    _slideController = AnimationController(
      vsync: this,
      duration: Motion.slow,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOutCubic),
    );

    // ✅ Reconnect pulse animation
    _reconnectPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // Peer bekleniyor pulse (local gönderdi, peer henüz göndermedi)
    _waitingPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // ✅ Listen to connection status
    _connectionSub = widget.connectionStatus?.listen((isConnected) {
      if (mounted) {
        setState(() => _isReconnecting = !isConnected);
        _ssLog('[SHARE-SCREEN] 📡 Connection status: ${isConnected ? "✅ Connected" : "⚠️ Reconnecting..."}');
      }
    });

    // 30 saniye içinde peer paylaşmazsa sıfırla.
    // Local paylaşınca timer yeniden başlatılır (bkz. _onShareSendPressed).
    _autoResetTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_transitioning && !_peerHasShared) {
        _ssLog("[SHARE-SCREEN] ⏱️ 30 saniye geçti, peer paylaşmadı - reset");
        _doReset();
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _slideController.dispose();
    _gameStateSubscription.cancel();
    _connectionSub?.cancel();
    _reconnectPulseController.dispose();
    _waitingPulseController.dispose();
    _longPressTimer?.cancel();
    _fadeController.dispose();
    _autoResetTimer?.cancel();
    super.dispose();
  }

  String get _placeholder {
    if (_selectedShareKind == ShareKind.phone) {
      return '555 123 4567';
    } else {
      return 'kullaniciadi';
    }
  }

  String get _prefix {
    if (_selectedShareKind == ShareKind.social) {
      return 'instagram.com/';
    }
    return '';
  }

  void _onShareKindSelected(ShareKind kind) {
    _ssLog("[SHARE-SCREEN] 📱 Paylaşım türü seçildi: $kind");
    // Aynı platforma tekrar dokunmak formu kapatır.
    if (_selectedShareKind == kind) {
      _dismissForm();
      return;
    }
    setState(() {
      _selectedShareKind = kind;
      _text.text = "";
    });
    _slideController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  void _dismissForm() {
    setState(() => _selectedShareKind = null);
    _slideController.reverse();
    _focus.unfocus();
  }

  void _onShareSendPressed() {
    if (_text.text.isEmpty) {
      _ssLog("[SHARE-SCREEN] ⚠️ Boş bilgi paylaşılamaz");
      // Boş gönderme girişimine dokunsal geri bildirim ver.
      HapticFeedback.mediumImpact();
      return;
    }

    final value = _text.text;
    final kind = _selectedShareKind!;
    _ssLog("[SHARE-SCREEN] 📤 GÖNDERME BAŞLATILDI:");
    _ssLog("[SHARE-SCREEN]    - Paylaşım türü: $kind");
    _ssLog("[SHARE-SCREEN]    - Bilgi: $value");

    // Engine'e paylaş mesajı gönder
    widget.engine.sendShareOffer(
      kind: kind,
      value: value,
    );

    _ssLog("[SHARE-SCREEN] ✅ Engine'e gönderildi!");
    _ssLog("[SHARE-SCREEN] 🔄 UI güncelleniyor...");

    setState(() {
      _hasShared = true;
      _selectedShareKind = null;
      _ssLog("[SHARE-SCREEN] ✅ _hasShared = true (yerel paylaşım tamamlandı)");
    });

    // Local gönderdi: eski timer'ı iptal et, peer için 30s daha ver.
    // Önceki timer ekran açılışından itibaren sayıyordu; local gönderdikten
    // sonra peer'in da bilgisini yazması için taze süre tanımak gerekir.
    _autoResetTimer?.cancel();
    _autoResetTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_transitioning && !_peerHasShared) {
        _ssLog("[SHARE-SCREEN] ⏱️ Local sonrası 30s doldu, peer paylaşmadı - reset");
        _doReset();
      }
    });

    // ✅ Kontrol: Her iki oyuncu da paylaştı mı?
    _ssLog("[SHARE-SCREEN] 🔍 Kontrol:");
    _ssLog("[SHARE-SCREEN]    - Benim paylaştığım: $_hasShared");
    _ssLog("[SHARE-SCREEN]    - Rakıp paylaştı: $_peerHasShared");
    _ssLog("[SHARE-SCREEN]    - Rakıp değeri: $_peerValue");
    if (_hasShared && _peerHasShared && _peerValue != null) {
      _ssLog("[SHARE-SCREEN] ✅ ÇÖZÜLEBİLİR: Her iki oyuncu da paylaştı!");
      _goToShareResultScreen();
    }

    // Slide controller'ı kapat
    _slideController.reverse();
    _focus.unfocus();
  }

  void _goToShareResultScreen() {
    if (_transitioning) {
      _ssLog("[SHARE-SCREEN] ⚠️ Zaten geçiş yapılıyor, tekrar çağrı görmezden gel");
      return;
    }

    _ssLog("[SHARE-SCREEN] 🎬 ═══════════════════════════════════════");
    _ssLog("[SHARE-SCREEN] 🎬 RESULT SCREEN'E GEÇİŞ BAŞLATILDI");
    _ssLog("[SHARE-SCREEN] 🎬 ═══════════════════════════════════════");
    _ssLog("[SHARE-SCREEN]    - Rakıp değeri: $_peerValue");
    _ssLog("[SHARE-SCREEN]    - Rakıp türü: $_peerShareKind");

    setState(() => _transitioning = true);
    
    _ssLog("[SHARE-SCREEN] 🎨 Fade animasyon başlatılıyor...");
    _fadeController.forward().then((_) {
      if (mounted) {
        _ssLog("[SHARE-SCREEN] 🎨 Fade animasyon tamamlandı");
        _ssLog("[SHARE-SCREEN] 📍 GameShareResultScreen push ediliyor...");
        
        // ShareResultScreen'e push et
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => GameShareResultScreen(
              engine: widget.engine,
              peerValue: _peerValue!,
              peerShareKind: (_peerShareKind.toString().contains('phone')
                  ? ShareKind.phone
                  : ShareKind.social),
              onReset: widget.onReset,
            ),
          ),
        );
        
        _ssLog("[SHARE-SCREEN] ✅ GameShareResultScreen'e başarıyla geçildi!");
      }
    });
  }

  void _onLongPressStart() {
    _ssLog("[SHARE-SCREEN] Long press başladı");
    setState(() => _longPressActive = true);

    _longPressTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _ssLog("[SHARE-SCREEN] 3 saniye tutuldu! Reset yapılıyor...");
      _doReset();
    });
  }

  void _onLongPressEnd() {
    _ssLog("[SHARE-SCREEN] Long press bitti");
    _longPressTimer?.cancel();
    setState(() => _longPressActive = false);
  }

  void _doReset() {
    if (_transitioning) {
      _ssLog("[SHARE-SCREEN] ⚠️ Zaten geçiş yapılıyor, reset görmezden gel");
      return;
    }

    _ssLog("[SHARE-SCREEN] 🔄 ═══════════════════════════════════════");
    _ssLog("[SHARE-SCREEN] 🔄 RESET BAŞLATILDI!");
    _ssLog("[SHARE-SCREEN] 🔄 ═══════════════════════════════════════");
    _ssLog("[SHARE-SCREEN]    - Benim paylaştığım: $_hasShared");
    _ssLog("[SHARE-SCREEN]    - Rakıp paylaştı: $_peerHasShared");
    _ssLog("[SHARE-SCREEN]    - Aksiyon: Pairing ekranına dönülüyor...");

    setState(() => _transitioning = true);
    _fadeController.forward().then((_) {
      if (mounted) {
        _ssLog("[SHARE-SCREEN] ✅ Reset - pairing ekranına dönülüyor");
        widget.onReset();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedShareKind != null;

    return Scaffold(
      backgroundColor: Colors.transparent, // ✅ Ink Plum background shows through
      resizeToAvoidBottomInset: true, // ✅ Klavye açılınca içerik yukarı kayar
      body: GestureDetector(
        onLongPressStart: (_) => _onLongPressStart(),
        onLongPressEnd: (_) => _onLongPressEnd(),
        child: Stack(
          children: [
            // ✅ Split-screen layout (eski UI gibi)
            SafeArea(
              child: Column(
                children: [
                  // ✅ ÜSTTE: WhatsApp
                  Expanded(
                    child: AnimatedOpacity(
                      opacity: _hasShared ? 0.3 : 1.0,
                      duration: Motion.slow,
                      child: GestureDetector(
                      onTapDown: (_) {
                        HapticFeedback.lightImpact();
                        setState(() => _whatsappPressed = true);
                      },
                      onTapUp: (_) {
                        setState(() => _whatsappPressed = false);
                        if (!_hasShared) {
                          _onShareKindSelected(ShareKind.phone);
                        }
                      },
                      onTapCancel: () {
                        setState(() => _whatsappPressed = false);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(
                            alpha: _selectedShareKind == ShareKind.phone ? 0.1 : 0.0,
                          ),
                        ),
                        child: Center(
                          child: AnimatedScale(
                            scale: (_whatsappPressed ||
                                    _selectedShareKind == ShareKind.phone)
                                ? 0.92
                                : 1.0,
                            duration: const Duration(milliseconds: 100),
                            child: AnimatedContainer(
                              duration: Motion.base,
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _selectedShareKind == ShareKind.phone
                                    ? const Color(0xFF25D366)
                                    : const Color(0xFF25D366).withValues(alpha: 0.3),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF25D366).withValues(
                                      alpha: _selectedShareKind == ShareKind.phone
                                          ? 0.5
                                          : 0.2,
                                    ),
                                    blurRadius: _selectedShareKind == ShareKind.phone
                                        ? 24
                                        : 12,
                                    offset: Offset(
                                      0,
                                      _selectedShareKind == ShareKind.phone ? 8 : 4,
                                    ),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: AnimatedScale(
                                  scale: _selectedShareKind == ShareKind.phone
                                      ? 1.15
                                      : 1.0,
                                  duration: Motion.base,
                                  child: SvgPicture.asset(
                                    'assets/branding/whatsapp-icon.svg',
                                    width: 70,
                                    height: 70,
                                    colorFilter: const ColorFilter.mode(
                                      Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ), // AnimatedOpacity
                  ),

                  // Peer bekleniyor göstergesi: local gönderdi, peer henüz göndermedi
                  if (_hasShared && !_peerHasShared && !hasSelection)
                    AnimatedBuilder(
                      animation: _waitingPulseController,
                      builder: (context, _) => SizedBox(
                        height: 24,
                        child: Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: GameColors.lime.withValues(alpha: 
                                0.35 + _waitingPulseController.value * 0.65,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: GameColors.lime.withValues(alpha: 
                                    0.2 + _waitingPulseController.value * 0.4,
                                  ),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // ✅ ORTADA: Input + Send (sadece seçilince görün)
                  if (hasSelection && !_hasShared)
                    GestureDetector(
                      // Aşağı swipe → formu kapat
                      onVerticalDragEnd: (details) {
                        if ((details.primaryVelocity ?? 0) > 150) _dismissForm();
                      },
                      child: Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: InkPlum.surface.withValues(alpha: 0.8),
                      ),
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // ✅ Input field
                              Container(
                                decoration: BoxDecoration(
                                  color: GameColors.interactiveLight.withValues(alpha: 0.95),
                                  borderRadius: Radii.brMd,
                                  boxShadow: Elevation.e2,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Space.lg,
                                    vertical: Space.md,
                                  ),
                                  child: Row(
                                    children: [
                                      if (_prefix.isNotEmpty)
                                        Text(
                                          _prefix,
                                          style: TextStyle(
                                            color: InkPlum.base.withValues(alpha: 0.5),
                                            fontSize: 18,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      Expanded(
                                        child: TextField(
                                          controller: _text,
                                          focusNode: _focus,
                                          maxLines: 1,
                                          keyboardType:
                                              _selectedShareKind == ShareKind.phone
                                                  ? TextInputType.phone
                                                  : TextInputType.text,
                                          style: TextStyle(
                                            color: InkPlum.base,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            border: InputBorder.none,
                                            hintText: _placeholder,
                                            hintStyle: TextStyle(
                                              color: InkPlum.base.withValues(alpha: 0.35),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.deny(
                                              RegExp(r'[\n\r]'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: Space.lg),

                              // ✅ Send button (yazısız arrow)
                              GestureDetector(
                                onTap: _onShareSendPressed,
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: GameColors.interactiveLight,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: GameColors.purple.withValues(alpha: 0.3),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: const CustomPaint(
                                    size: Size(32, 32),
                                    painter: _SendArrowPainter(
                                        color: GameColors.purple),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ), // GestureDetector (swipe-down dismiss)

                  // ✅ ALTTA: Instagram
                  Expanded(
                    child: AnimatedOpacity(
                      opacity: _hasShared ? 0.3 : 1.0,
                      duration: Motion.slow,
                      child: GestureDetector(
                      onTapDown: (_) {
                        HapticFeedback.lightImpact();
                        setState(() => _instagramPressed = true);
                      },
                      onTapUp: (_) {
                        setState(() => _instagramPressed = false);
                        if (!_hasShared) {
                          _onShareKindSelected(ShareKind.social); // ✅ Instagram yazma alanı aç
                        }
                      },
                      onTapCancel: () {
                        setState(() => _instagramPressed = false);
                      },
                      child: Container(
                        color: Colors.transparent,
                        child: Center(
                          child: AnimatedScale(
                            scale: (_instagramPressed ||
                                    _selectedShareKind == ShareKind.social)
                                ? 0.92
                                : 1.0,
                            duration: const Duration(milliseconds: 100),
                            child: AnimatedContainer(
                              duration: Motion.base,
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _selectedShareKind == ShareKind.social
                                    ? const Color(0xFFE4405F)
                                    : const Color(0xFFE4405F).withValues(alpha: 0.3),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFE4405F).withValues(
                                      alpha: _selectedShareKind == ShareKind.social
                                          ? 0.5
                                          : 0.2,
                                    ),
                                    blurRadius: _selectedShareKind == ShareKind.social
                                        ? 24
                                        : 12,
                                    offset: Offset(
                                      0,
                                      _selectedShareKind == ShareKind.social ? 8 : 4,
                                    ),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: AnimatedScale(
                                  scale: _selectedShareKind == ShareKind.social
                                      ? 1.15
                                      : 1.0,
                                  duration: Motion.base,
                                  child: SvgPicture.asset(
                                    'assets/branding/instagram-icon.svg',
                                    width: 70,
                                    height: 70,
                                    colorFilter: const ColorFilter.mode(
                                      Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ), // AnimatedOpacity
                  ),
                ],
              ),
            ),

            // ✅ RECONNECT INDICATOR (yazısız - sadece yanıp sönen turuncu border)
            if (_isReconnecting)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _reconnectPulseController,
                    builder: (context, child) {
                      final pulse = _reconnectPulseController.value;
                      return Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: GameColors.reconnecting.withValues(alpha: 0.3 + (pulse * 0.5)),
                            width: 4 + (pulse * 2),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

            // ✅ Fade overlay
            if (_transitioning)
              Positioned.fill(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    color: InkPlum.base,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ✅ ShareResultScreen - Rakıp bilgisini göster (eski ShareResultsScreen gibi)
class GameShareResultScreen extends StatefulWidget {
  final GameEngine engine;
  final String peerValue;
  final ShareKind peerShareKind;
  final VoidCallback onReset;

  const GameShareResultScreen({
    super.key,
    required this.engine,
    required this.peerValue,
    required this.peerShareKind,
    required this.onReset,
  });

  @override
  State<GameShareResultScreen> createState() => _GameShareResultScreenState();
}

class _GameShareResultScreenState extends State<GameShareResultScreen>
    with TickerProviderStateMixin {
  bool _copied = false;
  bool _longPressActive = false;
  Timer? _longPressTimer;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _progressController;
  bool _transitioning = false;

  @override
  void initState() {
    super.initState();
    _ssLog("[SHARE-RESULT] 📱 Sonuç ekranı açıldı: ${widget.peerValue}");

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOutCubic),
    );

    // Uzun basma ilerlemesi için — 2 saniyede 0.0 → 1.0
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _fadeController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _copyToClipboard() {
    _ssLog("[SHARE-RESULT] ✅ Kopyalandı: ${widget.peerValue}");
    Clipboard.setData(ClipboardData(text: widget.peerValue));

    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  /// WhatsApp veya Instagram linkini aç
  Future<void> _openLink() async {
    HapticFeedback.lightImpact();
    
    Uri uri;
    
    if (widget.peerShareKind == ShareKind.phone) {
      // WhatsApp linki - numarayı temizle (sadece rakamlar)
      final cleanNumber = widget.peerValue.replaceAll(RegExp(r'[^\d+]'), '');
      // Türkiye için +90 ekle (eğer yoksa)
      final formattedNumber = cleanNumber.startsWith('+') 
          ? cleanNumber 
          : '+90$cleanNumber';
      uri = Uri.parse('https://wa.me/$formattedNumber');
      _ssLog("[SHARE-RESULT] 📱 WhatsApp açılıyor: $uri");
    } else {
      // Instagram linki - @ işareti varsa kaldır
      final username = widget.peerValue.replaceAll('@', '').trim();
      uri = Uri.parse('https://instagram.com/$username');
      _ssLog("[SHARE-RESULT] 📸 Instagram açılıyor: $uri");
    }

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Link açılamazsa kopyala
        _copyToClipboard();
        _ssLog("[SHARE-RESULT] ⚠️ Link açılamadı, panoya kopyalandı");
      }
    } catch (e) {
      _ssLog("[SHARE-RESULT] ❌ Hata: $e");
      _copyToClipboard();
    }
  }

  void _onLongPressStart() {
    _ssLog("[SHARE-RESULT] Long press başladı");
    _progressController.forward();
    setState(() => _longPressActive = true);

    _longPressTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      _ssLog("[SHARE-RESULT] 2 saniye tutuldu - Reset!");
      _doReset();
    });
  }

  void _onLongPressEnd() {
    _longPressTimer?.cancel();
    _progressController.reset();
    setState(() => _longPressActive = false);
  }

  void _doReset() {
    if (_transitioning) return;

    setState(() => _transitioning = true);
    _fadeController.forward().then((_) {
      if (mounted) {
        _ssLog("[SHARE-RESULT] ✅ Reset - önce bu ekranı kapat, sonra full reset");
        // Önce bu ekranı (GameShareResultScreen) kapat
        Navigator.of(context).pop();
        // Sonra GameShareScreen'i de kapat ve pairing'e dön
        widget.onReset();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // ✅ Ink Plum background shows through
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        // ✅ Stack'in boş alanları da hit-test'e dahil olsun: uzun basış
        // sadece ortadaki bilgi kutusunda değil, ekranın her yerinde çalışsın.
        behavior: HitTestBehavior.opaque,
        onTap: _copyToClipboard,
        onLongPressStart: (_) => _onLongPressStart(),
        onLongPressEnd: (_) => _onLongPressEnd(),
        child: Stack(
          children: [
            // ✅ TAM ORTADA: İKON + BİLGİ (tıklanınca link açılır)
            SafeArea(
              child: Center(
                child: GestureDetector(
                  onTap: _openLink,
                  onDoubleTap: _copyToClipboard, // Çift tıkla kopyala
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.lg),
                    decoration: BoxDecoration(
                      color: InkPlum.surface.withValues(alpha: _copied ? 0.9 : 0.6),
                      borderRadius: Radii.brMd,
                      border: Border.all(
                        color: _copied ? GameColors.lime.withValues(alpha: 0.6) : GameColors.borderSubtle,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ✅ İkon (WhatsApp veya Instagram)
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.peerShareKind == ShareKind.phone
                                ? const Color(0xFF25D366) // WhatsApp yeşili
                                : const Color(0xFFE4405F), // Instagram pembe
                            boxShadow: [
                              BoxShadow(
                                color: (widget.peerShareKind == ShareKind.phone
                                        ? const Color(0xFF25D366)
                                        : const Color(0xFFE4405F))
                                    .withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              widget.peerShareKind == ShareKind.phone
                                  ? 'assets/branding/whatsapp-icon.svg'
                                  : 'assets/branding/instagram-icon.svg',
                              width: 40,
                              height: 40,
                              colorFilter: const ColorFilter.mode(
                                Colors.white,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: Space.lg),
                        
                        // ✅ Bilgi (telefon veya kullanıcı adı)
                        Text(
                          widget.peerValue,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: GameColors.interactiveLight,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Uzun basma ilerlemesi
            if (_longPressActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, _) => ProgressRing(
                        value: _progressController.value,
                        size: 80,
                        color: GameColors.purple,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Gönder butonu için markaya uygun ok — Material ikon yerine.
class _SendArrowPainter extends CustomPainter {
  final Color color;
  const _SendArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cy = h / 2;

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Gövde çizgisi
    canvas.drawLine(Offset(w * 0.20, cy), Offset(w * 0.78, cy), line);
    // Ok ucu (chevron)
    final head = Path()
      ..moveTo(w * 0.58, cy - h * 0.16)
      ..lineTo(w * 0.78, cy)
      ..lineTo(w * 0.58, cy + h * 0.16);
    canvas.drawPath(head, line);
  }

  @override
  bool shouldRepaint(covariant _SendArrowPainter old) => old.color != color;
}

/// Share Kind enum
enum ShareKind { phone, social }
