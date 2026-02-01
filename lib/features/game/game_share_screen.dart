import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../ui/color_palette_manager.dart';
import 'game_engine.dart';
import 'game_state.dart';

/// Game Share Screen - Eski ShareScreen UI'ı ile
/// Kullanıcılar bilgilerini paylaşırlar
/// Her iki oyuncu da paylaştığında GameShareResultScreen açılır
class GameShareScreen extends StatefulWidget {
  final GameEngine engine;
  final VoidCallback onReset;

  const GameShareScreen({
    super.key,
    required this.engine,
    required this.onReset,
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

  @override
  void initState() {
    super.initState();
    print("[SHARE-SCREEN] 📱 ═══════════════════════════════════════");
    print("[SHARE-SCREEN] 📱 Share screen açıldı!");
    print("[SHARE-SCREEN] 📱 ═══════════════════════════════════════");

    // Listen to game state for peer share updates
    _gameStateSubscription = widget.engine.states.listen((state) {
      if (mounted) {
        print("[SHARE-SCREEN] 🔄 DURUM GÜNCELLENDİ:");
        print("[SHARE-SCREEN]    - Benim paylaştığım: $_hasShared");
        print("[SHARE-SCREEN]    - Rakıp paylaştı: ${state.peerShared}");
        print("[SHARE-SCREEN]    - Rakıp değeri: ${state.peerShareValue}");
        print("[SHARE-SCREEN]    - Rakıp türü: ${state.peerShareKind}");

        setState(() {
          _peerHasShared = state.peerShared ?? false;
          _peerValue = state.peerShareValue;
          _peerShareKind = state.peerShareKind;
        });

        // ✅ Her iki oyuncu da paylaştığında ShareResultScreen'e geç
        if (_hasShared && _peerHasShared && _peerValue != null) {
          print("[SHARE-SCREEN] ✅ ═══════════════════════════════════════");
          print("[SHARE-SCREEN] ✅ HER İKİ OYUNCU DA PAYLAŞTI!");
          print("[SHARE-SCREEN] ✅ İşlem: ShareResultScreen'e geçiliyor...");
          print("[SHARE-SCREEN] ✅ ═══════════════════════════════════════");
          _goToShareResultScreen();
        }
      }
    });

    // Initialize with current engine state
    _peerHasShared = widget.engine.state.peerShared ?? false;
    _peerValue = widget.engine.state.peerShareValue;
    _peerShareKind = widget.engine.state.peerShareKind;
    print("[SHARE-SCREEN] 🔍 İlk durum kontrol:");
    print("[SHARE-SCREEN]    - Benim paylaştığım: $_hasShared");
    print("[SHARE-SCREEN]    - Rakıp paylaştı: $_peerHasShared");
    print("[SHARE-SCREEN]    - Rakıp değeri: $_peerValue");

    // Animations
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
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

    // ✅ 30 saniye sonra auto-reset
    _autoResetTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_transitioning && !_peerHasShared) {
        print("[SHARE-SCREEN] ⏱️ 30 saniye geçti, peer paylaşmadı - reset");
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
    print("[SHARE-SCREEN] 📱 Paylaşım türü seçildi: $kind");
    setState(() {
      _selectedShareKind = kind;
      _text.text = "";
    });
    _slideController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  void _onShareSendPressed() {
    if (_text.text.isEmpty) {
      print("[SHARE-SCREEN] ⚠️ Boş bilgi paylaşılamaz");
      return;
    }

    final value = _text.text;
    final kind = _selectedShareKind!;
    print("[SHARE-SCREEN] 📤 GÖNDERME BAŞLATILDI:");
    print("[SHARE-SCREEN]    - Paylaşım türü: $kind");
    print("[SHARE-SCREEN]    - Bilgi: $value");

    // Engine'e paylaş mesajı gönder
    widget.engine.sendShareOffer(
      kind: kind,
      value: value,
    );

    print("[SHARE-SCREEN] ✅ Engine'e gönderildi!");
    print("[SHARE-SCREEN] 🔄 UI güncelleniyor...");

    setState(() {
      _hasShared = true;
      _selectedShareKind = null;
      print("[SHARE-SCREEN] ✅ _hasShared = true (yerel paylaşım tamamlandı)");
    });

    // ✅ Kontrol: Her iki oyuncu da paylaştı mı?
    print("[SHARE-SCREEN] 🔍 Kontrol:");
    print("[SHARE-SCREEN]    - Benim paylaştığım: $_hasShared");
    print("[SHARE-SCREEN]    - Rakıp paylaştı: $_peerHasShared");
    print("[SHARE-SCREEN]    - Rakıp değeri: $_peerValue");
    if (_hasShared && _peerHasShared && _peerValue != null) {
      print("[SHARE-SCREEN] ✅ ÇÖZÜLEBİLİR: Her iki oyuncu da paylaştı!");
      _goToShareResultScreen();
    }

    // Slide controller'ı kapat
    _slideController.reverse();
    _focus.unfocus();
  }

  void _goToShareResultScreen() {
    if (_transitioning) {
      print("[SHARE-SCREEN] ⚠️ Zaten geçiş yapılıyor, tekrar çağrı görmezden gel");
      return;
    }

    print("[SHARE-SCREEN] 🎬 ═══════════════════════════════════════");
    print("[SHARE-SCREEN] 🎬 RESULT SCREEN'E GEÇİŞ BAŞLATILDI");
    print("[SHARE-SCREEN] 🎬 ═══════════════════════════════════════");
    print("[SHARE-SCREEN]    - Rakıp değeri: $_peerValue");
    print("[SHARE-SCREEN]    - Rakıp türü: $_peerShareKind");

    setState(() => _transitioning = true);
    
    print("[SHARE-SCREEN] 🎨 Fade animasyon başlatılıyor...");
    _fadeController.forward().then((_) {
      if (mounted) {
        print("[SHARE-SCREEN] 🎨 Fade animasyon tamamlandı");
        print("[SHARE-SCREEN] 📍 GameShareResultScreen push ediliyor...");
        
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
        
        print("[SHARE-SCREEN] ✅ GameShareResultScreen'e başarıyla geçildi!");
      }
    });
  }

  void _onLongPressStart() {
    print("[SHARE-SCREEN] Long press başladı");
    setState(() => _longPressActive = true);

    _longPressTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      print("[SHARE-SCREEN] 3 saniye tutuldu! Reset yapılıyor...");
      _doReset();
    });
  }

  void _onLongPressEnd() {
    print("[SHARE-SCREEN] Long press bitti");
    _longPressTimer?.cancel();
    setState(() => _longPressActive = false);
  }

  void _doReset() {
    if (_transitioning) {
      print("[SHARE-SCREEN] ⚠️ Zaten geçiş yapılıyor, reset görmezden gel");
      return;
    }

    print("[SHARE-SCREEN] 🔄 ═══════════════════════════════════════");
    print("[SHARE-SCREEN] 🔄 RESET BAŞLATILDI!");
    print("[SHARE-SCREEN] 🔄 ═══════════════════════════════════════");
    print("[SHARE-SCREEN]    - Benim paylaştığım: $_hasShared");
    print("[SHARE-SCREEN]    - Rakıp paylaştı: $_peerHasShared");
    print("[SHARE-SCREEN]    - Aksiyon: Pairing ekranına dönülüyor...");

    setState(() => _transitioning = true);
    _fadeController.forward().then((_) {
      if (mounted) {
        print("[SHARE-SCREEN] ✅ Reset - pairing ekranına dönülüyor");
        widget.onReset();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedShareKind != null;
    final paletteManager = ColorPaletteManager();
    final colors = paletteManager.currentPalette.colors;

    return Scaffold(
      resizeToAvoidBottomInset: true, // ✅ Klavye açılınca içerik yukarı kayar
      body: GestureDetector(
        onLongPressStart: (_) => _onLongPressStart(),
        onLongPressEnd: (_) => _onLongPressEnd(),
        child: Stack(
          children: [
            // ✅ Gradient background (with selected palette & gradient type)
            Container(
              decoration: BoxDecoration(
                gradient: paletteManager.currentGradient,
              ),
            ),

            // ✅ Split-screen layout (eski UI gibi)
            SafeArea(
              child: Column(
                children: [
                  // ✅ ÜSTTE: WhatsApp
                  Expanded(
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
                              duration: const Duration(milliseconds: 300),
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
                                  duration: const Duration(milliseconds: 300),
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
                  ),

                  // ✅ ORTADA: Input + Send (sadece seçilince görün)
                  if (hasSelection && !_hasShared)
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                      ),
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // ✅ Input field
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 16,
                                  ),
                                  child: Row(
                                    children: [
                                      if (_prefix.isNotEmpty)
                                        Text(
                                          _prefix,
                                          style: TextStyle(
                                            color: Colors.black.withValues(alpha: 0.4),
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
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            border: InputBorder.none,
                                            hintText: _placeholder,
                                            hintStyle: TextStyle(
                                              color:
                                                  Colors.black.withValues(alpha: 0.3),
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

                              const SizedBox(height: 24),

                              // ✅ Send button (yazısız arrow)
                              GestureDetector(
                                onTap: _onShareSendPressed,
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Color(0xFF6B4CE6),
                                    size: 32,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // ✅ ALTTA: Instagram
                  Expanded(
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
                              duration: const Duration(milliseconds: 300),
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
                                  duration: const Duration(milliseconds: 300),
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
                  ),
                ],
              ),
            ),

            // ✅ Fade overlay
            if (_transitioning)
              Positioned.fill(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    color: Colors.black,
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
  bool _transitioning = false;

  @override
  void initState() {
    super.initState();
    print("[SHARE-RESULT] 📱 Sonuç ekranı açıldı: ${widget.peerValue}");

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  void _copyToClipboard() {
    print("[SHARE-RESULT] ✅ Kopyalandı: ${widget.peerValue}");
    Clipboard.setData(ClipboardData(text: widget.peerValue));

    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  void _onLongPressStart() {
    print("[SHARE-RESULT] Long press başladı");
    setState(() => _longPressActive = true);

    _longPressTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      print("[SHARE-RESULT] 2 saniye tutuldu - Reset!");
      _doReset();
    });
  }

  void _onLongPressEnd() {
    _longPressTimer?.cancel();
    setState(() => _longPressActive = false);
  }

  void _doReset() {
    if (_transitioning) return;

    setState(() => _transitioning = true);
    _fadeController.forward().then((_) {
      if (mounted) {
        print("[SHARE-RESULT] ✅ Reset - önce bu ekranı kapat, sonra full reset");
        // Önce bu ekranı (GameShareResultScreen) kapat
        Navigator.of(context).pop();
        // Sonra GameShareScreen'i de kapat ve pairing'e dön
        widget.onReset();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final paletteManager = ColorPaletteManager();
    final colors = paletteManager.currentPalette.colors;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onTap: _copyToClipboard,
        onLongPressStart: (_) => _onLongPressStart(),
        onLongPressEnd: (_) => _onLongPressEnd(),
        child: Stack(
          children: [
            // ✅ Gradient background (with selected palette & gradient type)
            Container(
              decoration: BoxDecoration(
                gradient: paletteManager.currentGradient,
              ),
            ),

            // ✅ TAM ORTADA: SADECE BILGI
            SafeArea(
              child: Center(
                child: GestureDetector(
                  onTap: _copyToClipboard,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(_copied ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withOpacity(_copied ? 0.6 : 0.25),
                        width: 2,
                      ),
                    ),
                    child: Text(
                      widget.peerValue,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ✅ LONG PRESS PROGRESS (hidden, sayfada hiçbir yer almaz)
            if (_longPressActive)
              Positioned.fill(
                child: Center(
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: 0.0,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white.withOpacity(0.8),
                      ),
                      strokeWidth: 5,
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

/// Share Kind enum
enum ShareKind { phone, social }
