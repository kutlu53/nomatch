import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer' as dev;

import '../app/pairing_manager.dart';
import '../app/app_state.dart';
import '../app/pairing_logic.dart';
import '../features/pairing/flashlight_signal.dart';
import '../services/notification_service.dart';
import '../theme/game_colors.dart';
import 'start/start_triangle_button.dart';
import 'widgets/radar_pairing_view.dart';
import 'widgets/public_pairing_view.dart';

/// Extended UI state including game transition
enum ScreenState { idle, scanning, matched, transitioning, game }

/// Pairing mode types
enum PairingMode { radar, publicTransport }

/// PairingScreen - handles the scanning/matching UI with animations
/// Supports two modes: radar (default) and public transport (swipeable)
class PairingScreen extends StatefulWidget {
  final PairingManager pairingManager;
  final AppViewState state;

  const PairingScreen({
    super.key,
    required this.pairingManager,
    required this.state,
  });

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> with TickerProviderStateMixin {
  bool _torchEnabled = false;
  ScreenState _screenState = ScreenState.idle;
  final FlashlightSignal _flashlight = FlashlightSignal();
  
  // Page controller for swipe between modes
  late final PageController _pageController;
  int _currentPage = 0;
  
  // Discovery-only mode (public transport)
  StreamSubscription<List<DiscoveredPeer>>? _discoveredPeersSub;
  StreamSubscription<bool>? _pendingRequestsSub;
  StreamSubscription<NomatchNotificationType>? _notifTapSub;
  StreamSubscription<void>? _headingRetrySub;
  List<DiscoveredPeer> _discoveredPeers = [];
  bool _isPublicModeScanning = false;
  bool _hasPendingPublicRequest = false;

  // Mod geçişi seri hale getirme: hızlı swipe'larda üst üste binen
  // async operasyonları önlemek için debounce + versiyon sayacı.
  Timer? _modeSwitchDebounce;
  int _modeSwitchVersion = 0;
  // ✅ BLE start/stop operasyonlarını sıraya koyar — bir önceki operasyon
  // (örn. startDiscoveryOnly) bitmeden bir sonraki (örn. stop) başlamaz.
  // Aksi halde geç tamamlanan eski operasyon, yeni operasyonun BLE
  // durumunu üzerine yazabilir (bkz. _switchToPublicMode/_switchToRadarMode).
  Future<void> _modeSwitchOperation = Future.value();
  
  // Match animation controller (400ms fade out)
  late final AnimationController _matchController;
  
  // Game transition controller (200ms)
  late final AnimationController _gameTransitionController;
  
  // Match sequence animations
  late final Animation<double> _triangleScaleAnim;
  late final Animation<double> _triangleOpacityAnim;
  late final Animation<double> _radarOpacityAnim;
  late final Animation<double> _radarScaleAnim;
  late final Animation<double> _transitionFadeAnim;

  // ✅ Heading doğrulaması retry uyarısı: kısa kırmızımsı pulse (400ms)
  late final AnimationController _headingAlertController;
  late final Animation<double> _headingAlertAnimation;

  @override
  void initState() {
    super.initState();

    // ✅ Oyun/hata sonrası ekran yeniden oluşturulduğunda, kullanıcı public
    // transport modundaysa o sayfada kal — radar sayfasına geri atma.
    final startOnPublicPage = widget.pairingManager.lastSessionWasPublic;
    _currentPage = startOnPublicPage ? 1 : 0;
    _pageController = PageController(initialPage: _currentPage);
    _pageController.addListener(_onPageScroll);
    
    // Subscribe to discovered peers for public transport mode
    _discoveredPeersSub = widget.pairingManager.discoveredPeers.listen((peers) {
      if (mounted) {
        setState(() => _discoveredPeers = peers);
      }
    });
    
    // Subscribe to pending public requests (for indicator animation)
    _pendingRequestsSub = widget.pairingManager.hasPendingPublicRequest.listen((hasPending) {
      if (mounted) {
        setState(() => _hasPendingPublicRequest = hasPending);
      }
    });
    
    // Check initial state
    _hasPendingPublicRequest = widget.pairingManager.currentHasPendingRequest;

    // Bildirime tap edildiğinde public moda geç
    _notifTapSub = NotificationService().onTap.listen((type) {
      if (!mounted) return;
      if (type == NomatchNotificationType.pairRequest && _currentPage != 1) {
        _pageController.animateToPage(
          1,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
    
    _matchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    
    _gameTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600), // Extended from 200ms for smoother transition
    );
    
    // Triangle fade out
    _triangleScaleAnim = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _matchController, curve: Curves.easeOut),
    );
    _triangleOpacityAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _matchController, curve: Curves.easeOut),
    );
    
    // Radar dissolve
    _radarOpacityAnim = Tween<double>(begin: 0.10, end: 0.0).animate(
      CurvedAnimation(parent: _matchController, curve: Curves.easeIn),
    );
    _radarScaleAnim = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _matchController, curve: Curves.easeOut),
    );
    
    // Game transition
    _transitionFadeAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _gameTransitionController, curve: Curves.easeIn),
    );

    // ✅ Heading retry uyarı pulse'ı: hızlı yanıp sönen kırmızımsı halka
    _headingAlertController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _headingAlertAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 70,
      ),
    ]).animate(_headingAlertController);

    // Heading doğrulaması başarısız olup retry edildiğinde kısa pulse göster
    _headingRetrySub = widget.pairingManager.headingRetryEvents.listen((_) {
      if (mounted) _headingAlertController.forward(from: 0.0);
    });

    // Public sayfasıyla başlıyorsak BLE discovery'yi de hemen başlat
    // (normal swipe akışında bunu _onPageChanged/_switchToPublicMode yapar).
    if (startOnPublicPage) {
      _isPublicModeScanning = true;
      _screenState = ScreenState.scanning;
      widget.pairingManager.setPublicMode(true);
      widget.pairingManager.startDiscoveryOnly();
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _matchController.dispose();
    _gameTransitionController.dispose();
    _headingAlertController.dispose();
    _flashlight.dispose();
    _modeSwitchDebounce?.cancel();
    _discoveredPeersSub?.cancel();
    _pendingRequestsSub?.cancel();
    _notifTapSub?.cancel();
    _headingRetrySub?.cancel();
    super.dispose();
  }
  
  /// Handle page scroll to start/stop discovery mode
  void _onPageScroll() {
    // Don't change mode during match/transition
    if (_screenState == ScreenState.matched || 
        _screenState == ScreenState.transitioning) return;
  }
  
  /// Handle page change - 150ms debounce ile hızlı swipe'larda
  /// üst üste binen async BLE operasyonlarını önler.
  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
      if (page == 0) {
        _discoveredPeers = [];
        _isPublicModeScanning = false;
      }
    });

    // setPublicMode'u debounce beklemeden HEMEN çağır.
    // false: _discoveryOnlyMode anında kapanır → handlePeerDiscovered artık stream'e
    //        ekleme yapmaz; peer map ve stream de temizlenir; _state idle'a çekilir.
    //        Bu sayede 150ms debounce penceresi boyunca nokta ve istem dışı
    //        bağlantı girişimi olmaz.
    widget.pairingManager.setPublicMode(page == 1);

    if (_screenState == ScreenState.matched ||
        _screenState == ScreenState.transitioning) return;

    _modeSwitchDebounce?.cancel();
    _modeSwitchVersion++;
    final version = _modeSwitchVersion;

    _modeSwitchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted || _modeSwitchVersion != version) return;
      if (page == 1) {
        _switchToPublicMode(version);
      } else {
        _switchToRadarMode(version);
      }
    });
  }

  /// Switch to public transport mode - auto-start BLE discovery
  Future<void> _switchToPublicMode(int version) async {
    _isPublicModeScanning = true;
    // setPublicMode(true) zaten _onPageChanged'da çağrıldı
    setState(() => _screenState = ScreenState.scanning);
    // Önceki mod geçişi (örn. stop()) tamamlanmadan BLE'yi başlatma —
    // aksi halde geç tamamlanan eski operasyon yeni BLE durumunu ezebilir.
    final previous = _modeSwitchOperation;
    _modeSwitchOperation = previous.then((_) async {
      if (!mounted || _modeSwitchVersion != version) return;
      dev.log('[MODE] Switching to Public mode - auto-starting BLE');
      await widget.pairingManager.startDiscoveryOnly();
    });
    await _modeSwitchOperation;
  }

  /// Switch to radar mode - stop BLE
  Future<void> _switchToRadarMode(int version) async {
    // setPublicMode(false) zaten _onPageChanged'da çağrıldı
    setState(() {
      _screenState = ScreenState.idle;
      _discoveredPeers = [];
    });
    // Önceki mod geçişi (örn. startDiscoveryOnly) tamamlanmadan stop() çağırma —
    // aksi halde geç tamamlanan eski operasyon BLE'yi yeniden başlatabilir.
    final previous = _modeSwitchOperation;
    _modeSwitchOperation = previous.then((_) async {
      if (!mounted || _modeSwitchVersion != version) return;
      dev.log('[MODE] Switching to Radar mode - stopping BLE');
      await widget.pairingManager.stop();
    });
    await _modeSwitchOperation;
  }
  
  /// Trigger the match animation sequence
  void _triggerMatchAnimation() {
    dev.log('[MATCH] Triggering match animation');
    setState(() => _screenState = ScreenState.matched);
    
    // ✅ Haptic feedback on match
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 100), () => HapticFeedback.mediumImpact());
    
    // Start preparing game in background
    widget.pairingManager.prepareGame();
    
    // Wait for checkmark to show, then fade out
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && _screenState == ScreenState.matched) {
        _matchController.forward(from: 0.0).then((_) {
          if (mounted) _triggerGameTransition();
        });
      }
    });
  }
  
  /// Trigger the transition to game screen
  void _triggerGameTransition() {
    dev.log('[TRANSITION] Starting game transition');
    setState(() => _screenState = ScreenState.transitioning);
    
    _gameTransitionController.forward(from: 0.0).then((_) {
      if (mounted) widget.pairingManager.showGame();
    });
  }
  
  @override
  void didUpdateWidget(PairingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    final newPairingState = widget.state.pairingState;
    final oldPairingState = oldWidget.state.pairingState;
    
    // Sync scanning state
    if (newPairingState == PairingState.peerSearching || 
        newPairingState == PairingState.hostingReady ||
        newPairingState == PairingState.preConnected ||
        newPairingState == PairingState.headingValidating) {
      if (_screenState == ScreenState.idle) {
        setState(() => _screenState = ScreenState.scanning);
      }
    }
    
    // Detect match: preConnected/headingValidating -> connected
    if (newPairingState == PairingState.connected && 
        oldPairingState != PairingState.connected) {
      _triggerMatchAnimation();
    }
    
    // Reset on idle
    if (newPairingState == PairingState.idle && 
        oldPairingState != PairingState.idle) {
      _matchController.reset();
      _gameTransitionController.reset();
      setState(() => _screenState = ScreenState.idle);
    }
  }

  /// Handle start/stop scanning tap
  Future<void> _handleStartTap(bool isPhoneFlat) async {
    if (_screenState == ScreenState.matched || 
        _screenState == ScreenState.transitioning ||
        _screenState == ScreenState.game) return;
    
    if (_screenState == ScreenState.scanning) {
      setState(() => _screenState = ScreenState.idle);
      await widget.pairingManager.stop();
      return;
    }
    
    setState(() => _screenState = ScreenState.scanning);
    
    const maxRetries = 20;
    int retries = 0;
    bool success = false;
    
    while (retries < maxRetries && !success && _screenState == ScreenState.scanning) {
      // ✅ FIX: Read isPhoneFlat dynamically from widget state, not captured parameter
      final currentIsFlat = widget.state.isPhoneFlat;
      final result = await widget.pairingManager.start(isPhoneFlat: currentIsFlat);
      if (result.success) {
        success = true;
        break;
      }
      retries++;
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // ✅ 20 deneme de başarısız oldu (ör. telefon hiç düz konmadı veya BLE
    // başlatılamadı): ekran "scanning" durumunda asılı kalmasın, başlangıç
    // üçgenine geri dön. stop() olası yarım kalmış state/BLE'yi de temizler.
    if (!success && mounted && _screenState == ScreenState.scanning) {
      await widget.pairingManager.stop();
      if (mounted) {
        setState(() => _screenState = ScreenState.idle);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final pairingState = state.pairingState;
    
    final isScanning = _screenState == ScreenState.scanning;
    final isMatched = _screenState == ScreenState.matched;
    final isTransitioning = _screenState == ScreenState.transitioning;
    final isGame = _screenState == ScreenState.game;
    final showScanContent = _screenState != ScreenState.game;

    // Disable page swiping during match/transition
    final canSwipe = _screenState == ScreenState.idle || _screenState == ScreenState.scanning;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageView(
        controller: _pageController,
        physics: canSwipe 
            ? const BouncingScrollPhysics() 
            : const NeverScrollableScrollPhysics(),
        onPageChanged: _onPageChanged,
        children: [
          // Page 1: Radar mode (default)
          _buildRadarPage(
            state: state,
            pairingState: pairingState,
            isScanning: isScanning,
            isMatched: isMatched,
            isTransitioning: isTransitioning,
            isGame: isGame,
            showScanContent: showScanContent,
          ),
          
          // Page 2: Public transport mode
          _buildPublicTransportPage(
            isScanning: isScanning,
            isPhoneFlat: state.isPhoneFlat,
          ),
        ],
      ),
    );
  }
  
/// Build the radar pairing page (default mode)
  Widget _buildRadarPage({
    required AppViewState state,
    required PairingState pairingState,
    required bool isScanning,
    required bool isMatched,
    required bool isTransitioning,
    required bool isGame,
    required bool showScanContent,
  }) {
    return AnimatedBuilder(
      animation: Listenable.merge([_matchController, _gameTransitionController, _headingAlertController]),
      builder: (context, child) {
        final triangleScale = isMatched ? _triangleScaleAnim.value : 1.0;
        final triangleOpacity = isMatched ? _triangleOpacityAnim.value : 1.0;
        final radarOpacity = isMatched ? _radarOpacityAnim.value : null;
        final radarScale = isMatched ? _radarScaleAnim.value : 1.0;
        final transitionOpacity = isTransitioning ? _transitionFadeAnim.value : 1.0;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Layer 1: Radar
            if (showScanContent)
              Positioned.fill(
                child: ClipRect(
                  child: Transform.scale(
                    scale: radarScale,
                    child: Opacity(
                      opacity: isTransitioning ? transitionOpacity : 1.0,
                      child: RadarPairingView(
                        focusCandidatePeerId: widget.pairingManager.peerId,
                        focusCandidateLocked: pairingState == PairingState.preConnected,
                        pairHandshakeComplete: pairingState == PairingState.connected,
                        isConnectingTransition: pairingState == PairingState.preConnected,
                        isScanning: isScanning,
                        collapseProgress: 0.0,
                        freezeOpacity: radarOpacity,
                        alertOpacity: _headingAlertAnimation.value,
                      ),
                    ),
                  ),
                ),
              ),

            // Layer 2: Triangle button
            if (!isTransitioning && !isGame && triangleOpacity > 0)
              _buildTriangleButton(
                pairingState: pairingState,
                isScanning: isScanning,
                isMatched: isMatched,
                triangleScale: triangleScale,
                triangleOpacity: triangleOpacity,
                isPhoneFlat: state.isPhoneFlat,
              ),

            // Flashlight toggle (only on radar page)
            if (_screenState == ScreenState.idle || _screenState == ScreenState.scanning)
              _buildFlashlightToggle(state.isPhoneFlat),
            
            // Page indicator
            if (_screenState == ScreenState.idle || _screenState == ScreenState.scanning)
              _buildPageIndicator(currentPage: _currentPage),
          ],
        );
      },
    );
  }
  
  /// Build the public transport pairing page (metro/bus mode)
  Widget _buildPublicTransportPage({
    required bool isScanning,
    required bool isPhoneFlat,
  }) {
    return Stack(
      children: [
        PublicPairingView(
          isScanning: _isPublicModeScanning,
          // onTap removed - BLE auto-starts in public mode
          discoveredPeers: _discoveredPeers,
          onPeerTap: _handlePeerTap,
        ),
        
        // Page indicator at bottom
        _buildPageIndicator(currentPage: _currentPage),
      ],
    );
  }
  
  /// Handle tap on a discovered peer dot
  void _handlePeerTap(String peerId) {
    dev.log('[PUBLIC] Peer tapped: $peerId');
    widget.pairingManager.tapPublicPeer(peerId);
  }
  
  /// Page indicator dots at the bottom
  Widget _buildPageIndicator({required int currentPage}) {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPageDot(isActive: currentPage == 0, hasNotification: false),
            const SizedBox(width: 8),
            // Public mode dot - blinks purple when there's a pending request
            _hasPendingPublicRequest && currentPage == 0
                ? _PulsingPageDot(isActive: currentPage == 1)
                : _buildPageDot(isActive: currentPage == 1, hasNotification: false),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPageDot({required bool isActive, required bool hasNotification}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isActive ? 20 : 8,
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: const Color(0xFFEDEBFF).withOpacity(isActive ? 0.6 : 0.25),
      ),
    );
  }
  
  Widget _buildTriangleButton({
    required PairingState pairingState,
    required bool isScanning,
    required bool isMatched,
    required double triangleScale,
    required double triangleOpacity,
    required bool isPhoneFlat,
  }) {
    final triangleState = switch (pairingState) {
      PairingState.connected => TriangleState.matched,
      PairingState.preConnected || PairingState.headingValidating => TriangleState.connected,
      _ when isScanning => TriangleState.scanning,
      _ => TriangleState.idle,
    };
    
    return Center(
      child: Transform.scale(
        scale: triangleScale,
        child: Opacity(
          opacity: triangleOpacity,
          child: StartTriangleButton(
            isScanning: isScanning && !isMatched,
            triangleState: isMatched ? TriangleState.matched : triangleState,
            onTap: isMatched ? () {} : () => _handleStartTap(isPhoneFlat),
          ),
        ),
      ),
    );
  }
  
  Widget _buildFlashlightToggle(bool isPhoneFlat) {
    return Positioned(
      top: 50,
      right: 20,
      child: GestureDetector(
        onTap: isPhoneFlat
          ? () async {
              setState(() => _torchEnabled = !_torchEnabled);
              if (_torchEnabled) {
                await _flashlight.startBlinking();
              } else {
                await _flashlight.stopBlinking();
              }
            }
          : null,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
            border: Border.all(
              color: const Color(0xFFF5F5F5).withValues(alpha: isPhoneFlat ? 0.8 : 0.3),
              width: 2,
            ),
          ),
          child: Icon(
            _torchEnabled ? Icons.toggle_on : Icons.toggle_off,
            color: isPhoneFlat
                ? (_torchEnabled 
                    ? const Color(0xFFF5F5F5)
                    : const Color(0xFFF5F5F5).withValues(alpha: 0.5))
                : const Color(0xFFF5F5F5).withValues(alpha: 0.2),
            size: 28,
          ),
        ),
      ),
    );
  }
}

/// Pulsing page dot that blinks in purple to indicate a pending request
class _PulsingPageDot extends StatefulWidget {
  final bool isActive;

  const _PulsingPageDot({required this.isActive});

  @override
  State<_PulsingPageDot> createState() => _PulsingPageDotState();
}

class _PulsingPageDotState extends State<_PulsingPageDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    
    _opacityAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: widget.isActive ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: GameColors.purple.withOpacity(_opacityAnimation.value),
              boxShadow: [
                BoxShadow(
                  color: GameColors.purple.withOpacity(0.4 * _opacityAnimation.value),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
