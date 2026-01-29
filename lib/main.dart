import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer' as dev;

import 'app/app_coordinator.dart';
import 'features/game/lazy_question_provider.dart';
import 'plugins/p2p_ble/ble_p2p_plugin.dart';  // ✅ Changed to BLE plugin
import 'plugins/p2p/p2p_events.dart';
import 'plugins/p2p/p2p_messages.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock orientation to portrait only (no landscape, no upside-down)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Placeholder, stable per dev build. Replace with a persistent id later.
  const String appInstanceId = 'dev-instance';

  // Web'de BLE çalışmaz, mock plugin kullan
  final plugin = kIsWeb ? _MockBlePlugin() : BleP2pPlugin();  // ✅ Changed to BleP2pPlugin
  
  // Questions'ı lazy loading için provider oluştur
  final questions = LazyQuestionProvider();

  final coordinator = AppCoordinator(
    plugin: plugin,
    questions: questions,
    appInstanceId: appInstanceId,
  );

  // Run a quick splash while initializing.
  runApp(_StartupApp(coordinator: coordinator, isWeb: kIsWeb));
}


// Mock plugin for web preview
class _MockBlePlugin extends BleP2pPlugin {  // ✅ Changed to BleP2pPlugin
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

class _StartupApp extends StatefulWidget {
  final AppCoordinator coordinator;
  final bool isWeb;
  const _StartupApp({required this.coordinator, required this.isWeb});

  @override
  State<_StartupApp> createState() => _StartupAppState();
}

class _StartupAppState extends State<_StartupApp> with WidgetsBindingObserver {
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
    // Dispose coordinator and cleanup BLE resources
    widget.coordinator.dispose();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        widget.coordinator.onAppResumed();
        break;
      case AppLifecycleState.paused:
        widget.coordinator.onAppPaused();
        break;
      default:
        break;
    }
  }

  Future<void> _init() async {
    // Initialize coordinator and questions in parallel
    dev.log("STARTUP: begin");
    
    // Start both tasks in parallel
    final coordinatorInit = widget.coordinator.initialize();
    final questionsPreload = widget.coordinator.preloadQuestions();
    
    dev.log("STARTUP: initializing coordinator and preloading questions (parallel)");
    try {
      await Future.wait([coordinatorInit, questionsPreload]);
      dev.log("STARTUP: coordinator init and questions preload done");
    } catch (e) {
      dev.log("STARTUP: init error: $e");
    }
    
    if (mounted) setState(() => _ready = true);
    dev.log("STARTUP: ready=true");
  }

  @override
  Widget build(BuildContext context) {
    // Native splash stays until ready, then show AppShell directly
    if (!_ready) {
      return const MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.shrink(), // Empty, native splash is visible
        ),
        debugShowCheckedModeBanner: false,
      );
    }
    
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
      ),
      home: AppShell(coordinator: widget.coordinator),
    );
  }
}

