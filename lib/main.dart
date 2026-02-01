import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer' as dev;

import 'app/pairing_manager.dart';
import 'app/app_state.dart';
import 'app/pairing_logic.dart';
import 'features/game/lazy_question_provider.dart';
import 'plugins/p2p_ble/ble_p2p_plugin.dart';
import 'plugins/p2p/p2p_events.dart';
import 'plugins/p2p/p2p_messages.dart';
import 'ui/app_shell.dart';
import 'ui/color_palette_manager.dart'; // ✅ Gradient/palette için

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // Pairing manager
  final pairingManager = PairingManager(
    blePlugin: plugin,
    deviceId: appInstanceId,
    questions: questions,
  );

  runApp(MyApp(
    pairingManager: pairingManager,
    blePlugin: plugin,
    questions: questions,
    appInstanceId: appInstanceId,
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
  Future<void> send(P2pMessage message) async {}

  @override
  Future<void> dispose() async {}
}

class MyApp extends StatefulWidget {
  final PairingManager pairingManager;
  final BleP2pPlugin blePlugin;
  final LazyQuestionProvider questions;
  final String appInstanceId;

  const MyApp({
    required this.pairingManager,
    required this.blePlugin,
    required this.questions,
    required this.appInstanceId,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.pairingManager.dispose();
    widget.blePlugin.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      print('[INIT] 🚀 Initializing app...');
      
      // ✅ Minimum 3 saniye splash göster
      final splashTimer = Future.delayed(const Duration(seconds: 3));
      
      // Paralel olarak initialization yap
      await Future.wait([
        splashTimer,
        _initializeApp(),
      ]);
      
      print('[INIT] ✅ App ready (after 3s splash)');
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      print('[INIT] ❌ Init error: $e');
      dev.log('Init error: $e');
    }
  }
  
  Future<void> _initializeApp() async {
    await widget.blePlugin.initialize(appInstanceId: widget.appInstanceId);
    await widget.questions.preload();
    await ColorPaletteManager().loadPalette(); // ✅ Kaydedilmiş gradient/palette yükle
  }

  @override
  Widget build(BuildContext context) {
    // ✅ SPLASH: Full screen logo only (no gradient, no text)
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SizedBox.expand(
            child: Image.asset(
              'assets/branding/logo_full_screen.webp',
              fit: BoxFit.cover, // Tam ekran kaplasın
              errorBuilder: (context, error, stackTrace) {
                // Fallback to PNG
                return Image.asset(
                  'assets/branding/logo_full_screen.png',
                  fit: BoxFit.cover,
                );
              },
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: AppShell(
        pairingManager: widget.pairingManager,
        blePlugin: widget.blePlugin,
        questions: widget.questions,
      ),
    );
  }
}
