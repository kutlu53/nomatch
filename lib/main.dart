import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'dart:developer' as dev;

import 'core/debug_config.dart';
import 'app/pairing_manager.dart';
import 'app/app_state.dart';
import 'app/pairing_logic.dart';
import 'features/game/lazy_question_provider.dart';
import 'plugins/p2p_ble/ble_p2p_plugin.dart';
import 'plugins/p2p/p2p_events.dart';
import 'plugins/p2p/p2p_messages.dart';
import 'services/notification_service.dart';
import 'theme/app_background.dart'; // ✅ Ink Plum background
import 'ui/app_shell.dart';

Future<void> main() async {
  // ✅ Preserve native splash until we manually remove it
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  debugPrint('[INIT] 🚀 Logo göründü - initialization başlıyor...');
  
  // ✅ Minimum splash süresi (logo en az bu kadar görünsün)
  final splashTimer = Future.delayed(const Duration(milliseconds: 800));

  // Lock orientation to portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Get unique device ID (using UUID from flutter_blue_plus)
  String appInstanceId = 'nomatch-device'; // fallback
  try {
    final platform = MethodChannel('com.nomatch/ble_advertising');
    appInstanceId = await platform.invokeMethod('getDeviceId') ?? 'nomatch-device';
  } catch (e) {
    dev.log('[INIT] ⚠️ Could not get device UUID, using fallback');
  }

  // BLE plugin
  final plugin = kIsWeb ? _MockBlePlugin() : BleP2pPlugin();

  // Questions provider
  final questions = LazyQuestionProvider();

  // ✅ Initialize notification service
  final notificationService = NotificationService();

  // ✅ Initialize BLE + preload questions + notifications (paralel splash timer ile)
  final initFuture = Future.wait([
    plugin.initialize(appInstanceId: appInstanceId),
    questions.preload(),
    notificationService.initialize(),
  ]);

  // Pairing manager
  final pairingManager = PairingManager(
    blePlugin: plugin,
    deviceId: appInstanceId,
    questions: questions,
  );

  // ✅ Her iki işlem de bitene kadar bekle
  await Future.wait([splashTimer, initFuture]);
  
  debugPrint('[INIT] ✅ Init tamamlandı - app başlatılıyor');

  runApp(MyApp(
    pairingManager: pairingManager,
    blePlugin: plugin,
    questions: questions,
    appInstanceId: appInstanceId,
    alreadyInitialized: true, // ✅ Init zaten yapıldı
  ));
}

class _MockBlePlugin extends BleP2pPlugin {
  @override
  Stream<NomatchP2pEvent> get events => Stream.empty();

  @override
  Future<void> initialize({required String appInstanceId}) async {}

  @override
  Future<void> startHosting({required String displayNameHash, String? sessionConfigJson}) async {}

  @override
  Future<void> startDiscovery() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> connect({required String peerId}) async {}

  @override
  Future<void> send(P2pMessage message, {int maxRetries = 3}) async {}

  @override
  Future<void> dispose() async {}
}

class MyApp extends StatefulWidget {
  final PairingManager pairingManager;
  final BleP2pPlugin blePlugin;
  final LazyQuestionProvider questions;
  final String appInstanceId;
  final bool alreadyInitialized;

  const MyApp({
    required this.pairingManager,
    required this.blePlugin,
    required this.questions,
    required this.appInstanceId,
    this.alreadyInitialized = false,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _ready = false;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // ✅ Fade-in animasyonu (splash → radar geçişi)
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    
    _init();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.pairingManager.dispose();
    widget.blePlugin.dispose();
    super.dispose();
  }

  // ✅ Track app background/foreground for silent notifications
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    final isBackground = state == AppLifecycleState.paused ||
                         state == AppLifecycleState.inactive ||
                         state == AppLifecycleState.hidden;
    
    widget.pairingManager.isInBackground = isBackground;
    dev.log('[LIFECYCLE] App state: $state → isBackground=$isBackground');
    
    // Cancel notifications when app comes to foreground
    if (!isBackground) {
      NotificationService().cancelAll();
    }
  }

  Future<void> _init() async {
    // ✅ Init zaten main()'de yapıldı - sadece splash'ı kaldır ve fade başlat
    print('[INIT] ✅ App widget ready - removing splash');
    
    if (mounted) {
      setState(() => _ready = true);
      
      // ✅ Native splash'ı kaldır ve fade-in başlat
      FlutterNativeSplash.remove();
      _fadeController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      // ✅ Ink Plum background wraps entire app
      builder: (context, child) => AppBackground(
        child: child ?? const SizedBox.shrink(),
      ),
      home: _ready 
        ? FadeTransition(
            opacity: _fadeAnimation,
            child: AppShell(
              pairingManager: widget.pairingManager,
              blePlugin: widget.blePlugin,
              questions: widget.questions,
            ),
          )
        : const SizedBox.shrink(), // Native splash görünürken boş
    );
  }
}
