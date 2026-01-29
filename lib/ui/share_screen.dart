import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app/app_coordinator.dart';
import '../app/app_phase.dart';
import 'color_palette_manager.dart';

/// Minimalist paylaşım ekranı - YAZISIZ
/// - İki ikon: WhatsApp ve Instagram
/// - Tıklanan ikona göre input açılır
/// - Gönder butonu yazısız (sadece ok ikonu)
class ShareScreen extends StatefulWidget {
  final AppViewState state;
  final AppCoordinator coordinator;

  const ShareScreen({
    super.key,
    required this.state,
    required this.coordinator,
  });

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> with TickerProviderStateMixin {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;
  bool _whatsappPressed = false;
  bool _instagramPressed = false;

  @override
  void initState() {
    super.initState();
    _text.text = widget.state.pendingShare.text;
    
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
  }

  @override
  void didUpdateWidget(covariant ShareScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.state.pendingShare.text;
    if (_text.text != next) {
      _text.value = _text.value.copyWith(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
    
    // Kind seçildiğinde input alanını göster
    if (oldWidget.state.pendingShare.kind == null && 
        widget.state.pendingShare.kind != null) {
      _slideController.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _slideController.dispose();
    super.dispose();
  }

  String get _placeholder {
    if (widget.state.pendingShare.kind == ShareKind.phone) {
      return '555 123 4567';
    } else {
      return 'kullaniciadi';
    }
  }

  String get _prefix {
    if (widget.state.pendingShare.kind == ShareKind.social) {
      return 'instagram.com/';
    }
    return '';
  }


  @override
  Widget build(BuildContext context) {
    final hasSelection = widget.state.pendingShare.kind != null;
    final paletteManager = ColorPaletteManager();

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Gradient background
          Container(
            decoration: BoxDecoration(
              gradient: paletteManager.currentPalette.gradient,
            ),
          ),
          
          // Split-screen layout
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
                      widget.coordinator.onShareKindSelected(ShareKind.phone);
                    },
                    onTapCancel: () {
                      setState(() => _whatsappPressed = false);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(
                          widget.state.pendingShare.kind == ShareKind.phone ? 0.1 : 0.0
                        ),
                      ),
                      child: Center(
                        child: AnimatedScale(
                          scale: (_whatsappPressed || widget.state.pendingShare.kind == ShareKind.phone) ? 0.92 : 1.0,
                          duration: const Duration(milliseconds: 100),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.state.pendingShare.kind == ShareKind.phone
                                  ? const Color(0xFF25D366)
                                  : const Color(0xFF25D366).withOpacity(0.3),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF25D366).withOpacity(
                                    widget.state.pendingShare.kind == ShareKind.phone ? 0.5 : 0.2
                                  ),
                                  blurRadius: widget.state.pendingShare.kind == ShareKind.phone ? 24 : 12,
                                  offset: Offset(0, widget.state.pendingShare.kind == ShareKind.phone ? 8 : 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: AnimatedScale(
                                scale: widget.state.pendingShare.kind == ShareKind.phone ? 1.15 : 1.0,
                                duration: const Duration(milliseconds: 300),
                                child: SvgPicture.asset(
                                  'assets/branding/whatsapp-icon.svg',
                                  width: 70,
                                  height: 70,
                                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                
                // ✅ ORTADA: Input + Gönder (sadece seçilince görün)
                if (hasSelection)
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                    ),
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Input field
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
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
                                    // Prefix (Instagram için)
                                    if (_prefix.isNotEmpty)
                                      Text(
                                        _prefix,
                                        style: TextStyle(
                                          color: Colors.black.withOpacity(0.4),
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    // TextField
                                    Expanded(
                                      child: TextField(
                                        controller: _text,
                                        focusNode: _focus,
                                        maxLines: 1,
                                        keyboardType: widget.state.pendingShare.kind == ShareKind.phone
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
                                            color: Colors.black.withOpacity(0.3),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        onChanged: widget.coordinator.onShareTextChanged,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 24),
                            
                            // Gönder butonu (yazısız, sadece ok)
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                widget.coordinator.onShareSendPressed();
                                // ✅ NEW: If peer already shared, auto-accept their offer
                                // DELAY 500ms to ensure pendingShare is cleared first
                                if (widget.state.incomingShareOffer != null) {
                                  print("[SHARE] Peer offer received. Auto-accepting after 500ms delay...");
                                  Future.delayed(const Duration(milliseconds: 500), () {
                                    widget.coordinator.onIncomingShareDecision(accept: true);
                                  });
                                }
                              },
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
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
                      widget.coordinator.onShareKindSelected(ShareKind.social);
                    },
                    onTapCancel: () {
                      setState(() => _instagramPressed = false);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(
                          widget.state.pendingShare.kind == ShareKind.social ? 0.1 : 0.0
                        ),
                      ),
                      child: Center(
                        child: AnimatedScale(
                          scale: (_instagramPressed || widget.state.pendingShare.kind == ShareKind.social) ? 0.92 : 1.0,
                          duration: const Duration(milliseconds: 100),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.state.pendingShare.kind == ShareKind.social
                                  ? const Color(0xFFE4405F)
                                  : const Color(0xFFE4405F).withOpacity(0.3),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE4405F).withOpacity(
                                    widget.state.pendingShare.kind == ShareKind.social ? 0.5 : 0.2
                                  ),
                                  blurRadius: widget.state.pendingShare.kind == ShareKind.social ? 24 : 12,
                                  offset: Offset(0, widget.state.pendingShare.kind == ShareKind.social ? 8 : 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: AnimatedScale(
                                scale: widget.state.pendingShare.kind == ShareKind.social ? 1.15 : 1.0,
                                duration: const Duration(milliseconds: 300),
                                child: SvgPicture.asset(
                                  'assets/branding/instagram-icon.svg',
                                  width: 70,
                                  height: 70,
                                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
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
        ],
      ),
    );
  }
}

/// ✅ Modern Icon Button - Şık ve sade tasarım
class _ModernIconButton extends StatelessWidget {
  final Widget icon;
  final bool isPressed;
  final bool isSelected;
  final Color backgroundColor;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onTapCancel;

  const _ModernIconButton({
    required this.icon,
    required this.isPressed,
    required this.isSelected,
    required this.backgroundColor,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTapUp(),
      onTapCancel: onTapCancel,
      child: AnimatedScale(
        scale: isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected 
                ? backgroundColor 
                : backgroundColor.withOpacity(0.3),
            boxShadow: [
              BoxShadow(
                color: backgroundColor.withOpacity(isSelected ? 0.5 : 0.2),
                blurRadius: isSelected ? 24 : 12,
                offset: Offset(0, isSelected ? 8 : 4),
              ),
            ],
          ),
          child: Center(
            child: AnimatedScale(
              scale: isSelected ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
}

/// ✅ WhatsApp Logo - Basit ve anlaşılır
/// ✅ Eski custom painter'lar kaldırıldı - SVG logolar kullanılıyor
/// ✅ Kaldırıldı - Modern button kullanıyoruz artık
