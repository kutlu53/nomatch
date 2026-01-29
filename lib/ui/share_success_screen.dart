import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/app_coordinator.dart';

/// Başarılı paylaşım ekranı - karşı tarafın bilgisini gösterir
/// - Animasyonlu başarı gösterimi
/// - Kopyalanabilir bilgi
/// - FAB ile home butonu
class ShareSuccessScreen extends StatefulWidget {
  final AppCoordinator coordinator;
  final IncomingShareOffer? offer;

  const ShareSuccessScreen({
    super.key,
    required this.coordinator,
    required this.offer,
  });

  @override
  State<ShareSuccessScreen> createState() => _ShareSuccessScreenState();
}

class _ShareSuccessScreenState extends State<ShareSuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _checkAnimation;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Check animasyonu (0-400ms)
    _checkAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.elasticOut),
    );

    // Slide animasyonu (300-800ms)
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 0.8, curve: Curves.easeOutCubic),
    ));

    // Fade animasyonu (300-800ms)
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 0.8, curve: Curves.easeIn),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _copyToClipboard() {
    if (widget.offer != null) {
      Clipboard.setData(ClipboardData(text: widget.offer!.value));
      HapticFeedback.mediumImpact();
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Z kuşağı gradient (oyun ekranı ile aynı)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF6B4CE6), // Mor
                  Color(0xFFE94B8B), // Pembe
                  Color(0xFFFF8C42), // Turuncu
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // Karşı tarafın bilgisi (ortada)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Başarı simgesi (yeşil check) - Animasyonlu
                ScaleTransition(
                  scale: _checkAnimation,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981), // Modern yeşil
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withOpacity(0.4),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 60,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // ✅ ENHANCED: Minimalist info card
                SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15), // More subtle
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3), // Lighter border
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 25,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ✅ ENHANCED: Type indicator (phone/instagram)
                          if (widget.offer != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                widget.offer!.kind == 'phone' ? '📱 Telefon' : '📷 Instagram',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          const SizedBox(height: 20),
                          // ✅ ENHANCED: Data display (cleaner)
                          if (widget.offer != null)
                            Text(
                              widget.offer!.value,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          const SizedBox(height: 16),
                          // ✅ ENHANCED: Copy button (more prominent)
                          if (widget.offer != null)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _copyToClipboard,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _copied ? 'Kopyalandı' : 'Kopyala',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      // ✅ ENHANCED: FAB - Home butonu (modern, circular)
      floatingActionButton: ScaleTransition(
        scale: _fadeAnimation,
        child: FloatingActionButton(
          onPressed: () {
            HapticFeedback.mediumImpact();
            widget.coordinator.stopAll();
          },
          backgroundColor: Colors.white.withOpacity(0.95),
          elevation: 8,
          child: const Icon(
            Icons.home_rounded,
            color: Color(0xFF10B981),
            size: 28,
          ),
        ),
      ),
    );
  }
}
