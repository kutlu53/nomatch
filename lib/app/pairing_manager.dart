import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/services.dart';

import 'pairing_logic.dart';
import 'heading_validator.dart';
import '../core/debug_config.dart';
import '../plugins/p2p_ble/ble_p2p_plugin.dart';
import '../plugins/p2p_ble/ble_constants.dart';
import '../plugins/p2p/p2p_events.dart';
import '../plugins/p2p/p2p_messages.dart';
import '../features/game/game_engine.dart';
import '../features/game/game_state.dart';
import '../features/game/lazy_question_provider.dart';
import '../services/notification_service.dart';

/// Peer state in public transport mode
enum PublicPeerState {
  idle,       // Just discovered, no interaction
  requesting, // We sent a request to this peer
  requested,  // This peer sent us a request  
  matched,    // Both sides agreed to pair
}

/// Discovered peer for public transport mode (discovery-only)
final class DiscoveredPeer {
  final String id;
  final int rssi;
  final DateTime lastSeen;
  final PublicPeerState state;
  
  const DiscoveredPeer({
    required this.id,
    required this.rssi,
    required this.lastSeen,
    this.state = PublicPeerState.idle,
  });
  
  /// Create a copy with updated state
  DiscoveredPeer copyWith({
    int? rssi,
    DateTime? lastSeen,
    PublicPeerState? state,
  }) {
    return DiscoveredPeer(
      id: id,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
      state: state ?? this.state,
    );
  }
  
  /// Normalize RSSI to 0.0-1.0 range (closer = higher value)
  /// RSSI typically ranges from -30 (very close) to -100 (far)
  double get normalizedDistance {
    const minRssi = -90.0; // Far
    const maxRssi = -40.0; // Close
    final clamped = rssi.clamp(minRssi.toInt(), maxRssi.toInt()).toDouble();
    return (clamped - minRssi) / (maxRssi - minRssi);
  }
}

/// Main pairing coordinator
class PairingManager {
  final BleP2pPlugin blePlugin;
  final String deviceId; // Unique device ID
  final LazyQuestionProvider questions;
  
  late HeadingValidator headingValidator;
  
  PairingState _state = PairingState.idle;
  PairingState get state => _state;

  // Current pairing attempt
  String? _peerId;
  String? get peerId => _peerId;
  String? _sessionId;
  String? _peerNativeDeviceId; // ✅ NEW: Peer's native device UUID
  bool _isLeader = false;
  double? _peerHeading;
  double? _ourHeading;

  // Streams
  final _stateController = StreamController<PairingState>.broadcast();
  Stream<PairingState> get stateUpdates => _stateController.stream;
  
  // Game engine
  GameEngine? _gameEngine;
  GameEngine? get gameEngine => _gameEngine;
  final _gameStateController = StreamController<GameState>.broadcast();
  Stream<GameState> get gameStateUpdates => _gameStateController.stream;
  
  // ✅ REFACTORED: Centralized timer management
  final _timers = _TimerPool();
  static const _kTimerGameTicker = 'game_ticker';
  static const _kTimerHeadingValidation = 'heading_validation';
  static const _kTimerConnectionTimeout = 'connection_timeout';
  static const _kTimerKeepAlive = 'keep_alive';
  static const _kTimerReconnect = 'reconnect';
  static const _kTimerGameReconnect = 'game_reconnect';
  
  // ✅ Connection retry tracking
  int _connectionAttempts = 0;
  static const int _maxConnectionAttempts = 3;
  String? _lastFailedPeerId;
  
  // BLE event subscription
  StreamSubscription? _bleEventsSub;
  StreamSubscription? _gameEngineSubscription;
  StreamSubscription? _headingSubscription;
  
  // ✅ Share screen flag
  bool _isShareScreenActive = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _keepAliveInterval = Duration(seconds: 3);
  static const Duration _reconnectDelay = Duration(seconds: 2);
  
  /// Stream for connection status updates (for UI)
  final _connectionStatusController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStatus => _connectionStatusController.stream;
  bool _isConnected = true;
  bool get isConnected => _isConnected;

  /// ✅ Heading doğrulaması başarısız olup retry edildiğinde emit edilir
  /// (UI'da kısa bir uyarı pulse'ı göstermek için).
  final _headingRetryController = StreamController<void>.broadcast();
  Stream<void> get headingRetryEvents => _headingRetryController.stream;
  
  // Discovery-only mode (public transport mode)
  bool _discoveryOnlyMode = false;
  // ✅ PairingScreen oyun/hata sonrası yeniden oluşturulduğunda hangi
  // sayfada (radar/public) başlayacağını belirlemek için son aktif modu sakla.
  bool _lastActiveModeWasPublic = false;
  bool get lastSessionWasPublic => _lastActiveModeWasPublic;
  final Map<String, DiscoveredPeer> _discoveredPeers = {};
  final _discoveredPeersController = StreamController<List<DiscoveredPeer>>.broadcast();
  Stream<List<DiscoveredPeer>> get discoveredPeers => _discoveredPeersController.stream;
  
  // ✅ Background notification support
  bool isInBackground = false;
  final NotificationService _notificationService = NotificationService();
  
  /// Trigger a silent notification if app is in background
  void _notifyIfBackground(NomatchNotificationType type) {
    if (isInBackground) {
      pairingLog('[NOTIF] 📳 App in background — sending $type notification');
      _notificationService.notify(type);
    }
  }
  List<DiscoveredPeer> get currentDiscoveredPeers => _discoveredPeers.values.toList();
  
  // Pending public mode requests (from other users in public mode)
  final Set<String> _pendingPublicRequests = {};
  final _pendingRequestsController = StreamController<bool>.broadcast();
  Stream<bool> get hasPendingPublicRequest => _pendingRequestsController.stream;
  bool get currentHasPendingRequest => _pendingPublicRequests.isNotEmpty;
  
  void setShareScreenActive(bool active) {
    _isShareScreenActive = active;
    pairingLog('[PAIR] 📱 Share screen active: $active');
    
    if (active) {
      // ✅ Start keep-alive mechanism for share screen
      _startKeepAlive();
    } else {
      // ✅ Stop keep-alive when leaving share screen
      _stopKeepAlive();
    }
  }
  
  /// Start keep-alive heartbeat for share screen
  void _startKeepAlive() {
    _stopKeepAlive();
    _reconnectAttempts = 0;
    _isConnected = true;
    
    // perfLog('[KEEP-ALIVE] 💓 Starting keep-alive for share screen');
    
    _timers.schedulePeriodic(_kTimerKeepAlive, _keepAliveInterval, (_) async {
      if (!_isShareScreenActive) {
        _stopKeepAlive();
        return;
      }
      
      try {
        final msg = HeartbeatMessage(sid: _sessionId ?? '');
        await blePlugin.send(msg);
        
        if (!_isConnected) {
          // perfLog('[KEEP-ALIVE] ✅ Connection restored!');
          _isConnected = true;
          _connectionStatusController.add(true);
          _reconnectAttempts = 0;
        }
      } catch (e) {
        // perfLog('[KEEP-ALIVE] ❌ Heartbeat failed: $e');
        if (_isConnected) {
          _isConnected = false;
          _connectionStatusController.add(false);
        }
        _attemptReconnect();
      }
    });
  }
  
  /// Stop keep-alive mechanism
  void _stopKeepAlive() {
    _timers.cancel(_kTimerKeepAlive);
    _timers.cancel(_kTimerReconnect);
    // perfLog('[KEEP-ALIVE] 🛑 Keep-alive stopped');
  }
  
  /// Attempt to reconnect when connection is lost
  void _attemptReconnect() {
    if (!_isShareScreenActive) return;
    if (_timers.isActive(_kTimerReconnect)) return; // Already reconnecting
    
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      pairingLog('[RECONNECT] ❌ Max reconnect attempts reached ($_maxReconnectAttempts)');
      return;
    }
    
    _reconnectAttempts++;
    pairingLog('[RECONNECT] 🔄 Attempting reconnect ($_reconnectAttempts/$_maxReconnectAttempts)...');
    
    _timers.schedule(_kTimerReconnect, _reconnectDelay, () async {
      if (!_isShareScreenActive) return;
      
      try {
        if (_peerId != null) {
          pairingLog('[RECONNECT] 🔗 Reconnecting to peer: $_peerId');
          await blePlugin.connect(peerId: _peerId!);
          await Future.delayed(const Duration(milliseconds: 500));
          
          final msg = HeartbeatMessage(sid: _sessionId ?? '');
          await blePlugin.send(msg);
          
          pairingLog('[RECONNECT] ✅ Reconnect successful!');
          _isConnected = true;
          _connectionStatusController.add(true);
          _reconnectAttempts = 0;
        }
      } catch (e) {
        pairingLog('[RECONNECT] ❌ Reconnect attempt failed: $e');
      }
    });
  }

  PairingManager({
    required this.blePlugin,
    required this.deviceId,
    required this.questions,
  }) {
    headingValidator = HeadingValidator();
    // BLE plugin'in auto-connect'ini devre dışı bırak.
    // Tüm bağlantı kararları PairingManager'ın deterministik mantığına bırakılır
    // (küçük device ID bağlantıyı başlatır). Bu, her iki cihazın aynı anda
    // bağlanmaya çalışmasından kaynaklanan race condition'ı önler.
    blePlugin.setAutoConnect(false);
    _listenToBleEvents();
  }
  
  /// Listen to BLE plugin events
  void _listenToBleEvents() {
    _bleEventsSub = blePlugin.events.listen((event) {
      // perfLog('[TEST-CONN] 📡 BLE event: ${event.runtimeType}');
      
      if (event is PeerDiscovered) {
        // perfLog('[TEST-CONN] 📡 Peer discovered: ${event.peerId}, rssi=${event.rssi}');
        handlePeerDiscovered(event.peerId, event.rssi);
      } else if (event is PeerConnected) {
        // perfLog('[TEST-CONN] ✅ PeerConnected event received: ${event.peerId}');
        handlePeerConnected(event.sessionId, event.peerId, event.isLeader);
      } else if (event is PeerDisconnected) {
        // perfLog('[TEST-CONN] 🔌 PeerDisconnected: ${event.peerId}');
        handlePeerDisconnected();
      } else if (event is MessageReceived) {
        // perfLog('[TEST-CONN] 📨 Message received: ${event.message.runtimeType}');
        _handleMessageReceived(event.message, event.fromPeerId);
      } else if (event is P2pErrorEvent) {
        _handleBleError(event);
      }
    });
  }

  // ✅ FIX: Ölümcül BLE hataları (bluetooth kapalı, desteklenmiyor, izin yok,
  // tarama başlatılamadı) daha önce hiç dinlenmiyordu — kullanıcı hiçbir uyarı
  // görmeden sonsuz tarama animasyonu izliyordu. Aktif eşleşme sırasında bu
  // hatalar artık başarısız ekranına düşürür (4s sonra otomatik idle'a döner).
  static const Set<String> _fatalBleErrorCodes = {
    'bluetooth_off',
    'ble_not_supported',
    'permissions_denied',
    'scan_failed',
  };

  void _handleBleError(P2pErrorEvent event) {
    final code = event.details['code'] as String? ?? 'unknown';
    if (!_fatalBleErrorCodes.contains(code)) {
      pairingLog('[BLE-ERR] ⚠️ Non-fatal BLE error: $code (${event.message})');
      return;
    }
    // Zaten başarısızken tekrar tetiklemenin anlamı yok.
    if (_state == PairingState.failed) return;
    // bluetooth_off adapter dinleyicisinden HER AN gelebilir; kullanıcı boşta
    // başlangıç ekranındayken başarısız ekranı basma. Diğer fatal kodlar
    // yalnızca tarama başlatma denemesi sırasında üretilir — event asenkron
    // ulaştığı için state o an hâlâ idle görünebilir, yine de işlenmeli.
    if (code == 'bluetooth_off' && _state == PairingState.idle) {
      pairingLog('[BLE-ERR] ℹ️ bluetooth_off ignored (idle)');
      return;
    }
    pairingLog('[BLE-ERR] ❌ Fatal BLE error during pairing: $code (${event.message})');
    unawaited(_failPairing(code));
  }

  // Nomatch-specific UUIDs
  static const String NOMATCH_SERVICE_UUID = '550e8400-e29b-41d4-a716-446655440000';
  static const String NOMATCH_CHAR_TX_RX = '550e8400-e29b-41d4-a716-446655440001';
  static const String NOMATCH_CHAR_CONTROL = '550e8400-e29b-41d4-a716-446655440002';

  /// Start discovery-only mode (public transport mode)
  /// Only scans and advertises, does NOT connect or pair
  Future<PairingResult> startDiscoveryOnly() async {
    pairingLog('[DISCOVERY] 🔍 Starting discovery-only mode (public transport)');

    // Önceki BLE operasyonu bitmeden tekrar çağrılırsa temiz başlangıç için
    // önce durdur (hızlı radar↔public geçişlerinde çakışmayı önler).
    await blePlugin.stop();

    try {
      // ✅ FIX: Save pending request peers BEFORE reset
      // When switching from radar→public, _handlePendingPublicRequest() may have
      // already added peers with PublicPeerState.requested that we need to preserve
      final savedPendingPeers = <String, DiscoveredPeer>{};
      final savedPendingRequests = Set<String>.from(_pendingPublicRequests);
      final savedPeerNativeDeviceId = _peerNativeDeviceId;
      for (final entry in _discoveredPeers.entries) {
        if (entry.value.state == PublicPeerState.requested) {
          savedPendingPeers[entry.key] = entry.value.copyWith(
            lastSeen: DateTime.now(), // Refresh timestamp so cleanup won't remove
          );
        }
      }
      if (savedPendingPeers.isNotEmpty) {
        pairingLog('[DISCOVERY] 💾 Preserving ${savedPendingPeers.length} pending request peer(s)');
      }
      
      // Reset state
      _reset();
      _discoveryOnlyMode = true;
      _discoveredPeers.clear();
      
      // ✅ FIX: Restore pending request peers AFTER reset
      if (savedPendingPeers.isNotEmpty) {
        _discoveredPeers.addAll(savedPendingPeers);
        _pendingPublicRequests.addAll(savedPendingRequests);
        _peerNativeDeviceId = savedPeerNativeDeviceId; // Restore for leader election
        _discoveredPeersController.add(_discoveredPeers.values.toList());
        _pendingRequestsController.add(_pendingPublicRequests.isNotEmpty);
        
        // Re-schedule auto-expire timers for restored pending requests
        for (final peerId in savedPendingRequests) {
          _timers.schedule('pending_request_$peerId', const Duration(seconds: 30), () {
            _pendingPublicRequests.remove(peerId);
            _pendingRequestsController.add(_pendingPublicRequests.isNotEmpty);
            final peer = _discoveredPeers[peerId];
            if (peer != null && peer.state == PublicPeerState.requested) {
              _discoveredPeers[peerId] = peer.copyWith(state: PublicPeerState.idle);
              _discoveredPeersController.add(_discoveredPeers.values.toList());
            }
          });
        }
        
        pairingLog('[DISCOVERY] ✅ Restored ${savedPendingPeers.length} pending request peer(s) (peerNativeId: $savedPeerNativeDeviceId)');
      }
      
      // Start BLE hosting (advertising)
      pairingLog('[DISCOVERY] 📡 Starting BLE advertising...');
      await blePlugin.startHosting(displayNameHash: deviceId);
      
      // Start BLE discovery (scanning)
      await blePlugin.startDiscovery();
      pairingLog('[DISCOVERY] ✅ Discovery-only mode active');
      
      // Start peer cleanup timer (remove stale peers after 5 seconds)
      _timers.schedulePeriodic('discovery_cleanup', const Duration(seconds: 2), (_) {
        _cleanupStalePeers();
      });
      
      // Mod geçişi sırasında setPublicMode(false) çağrıldıysa state'i kirletme.
      // Aksi hâlde radar sayfasında peerSearching → didUpdateWidget → üçgen mor.
      if (_discoveryOnlyMode) {
        _setState(PairingState.peerSearching);
      }
      return PairingResult(success: true);
    } catch (e) {
      pairingLog('[DISCOVERY] ❌ Failed to start: $e');
      _discoveryOnlyMode = false;
      return PairingResult(success: false, errorReason: 'discovery_failed: $e');
    }
  }
  
  /// Stop discovery-only mode
  Future<void> stopDiscoveryOnly() async {
    pairingLog('[DISCOVERY] 🛑 Stopping discovery-only mode');
    _discoveryOnlyMode = false;
    _discoveredPeers.clear();
    _discoveredPeersController.add([]);
    _timers.cancel('discovery_cleanup');
    _timers.cancel('public_pair_timeout');
    await blePlugin.stop();
    _setState(PairingState.idle);
  }
  
  /// Set public mode flag without stopping/starting BLE
  /// Used when swiping between pages - BLE continues running
  void setPublicMode(bool isPublic) {
    pairingLog('[MODE] Setting public mode: $isPublic (BLE unchanged)');
    _discoveryOnlyMode = isPublic;
    _lastActiveModeWasPublic = isPublic;

    if (isPublic) {
      // Public moda geçiş: cleanup timer'ı başlat
      if (!_timers.isActive('discovery_cleanup')) {
        _timers.schedulePeriodic('discovery_cleanup', const Duration(seconds: 2), (_) {
          _cleanupStalePeers();
        });
      }
      _discoveredPeersController.add(_discoveredPeers.values.toList());
    } else {
      // Radar moduna geçiş:
      // 1. Bağlantı state'ini temizle — _peerId kalırsa handlePeerDiscovered guard'ı
      //    radar bağlantısını bloklar ancak peerSearching state'i hâlâ aktif olduğundan
      //    debounce penceresi içinde istem dışı bağlantı başlatılabilir.
      // 2. State'i idle'a çek — handlePeerDiscovered'daki idle guard artık tüm
      //    BLE event'lerini yoksayar; üçgeye basılmadan bağlantı olmaz.
      if (_state == PairingState.peerSearching || _state == PairingState.preConnected) {
        _peerId = null;
        _sessionId = null;
        _peerNativeDeviceId = null;
        _timers.cancel(_kTimerConnectionTimeout);
        _timers.cancel('public_pair_timeout');
        _setState(PairingState.idle);
        pairingLog('[MODE] Radar moduna geçiş: state idle, bağlantı state temizlendi');
      }
      // Peer listesini ve stream'i hemen temizle.
      // Debounce penceresi (150ms) boyunca _discoveryOnlyMode=false olduğundan
      // handlePeerDiscovered artık stream'e ekleme yapmaz. Ancak mevcut peer
      // listesi hâlâ stream subscription'ında görünebilir — temizliyoruz.
      _discoveredPeers.clear();
      _timers.cancel('discovery_cleanup');
      _discoveredPeersController.add([]);
    }
  }
  
  /// Handle tap on a discovered peer in public mode.
  /// - idle      → isteği gönder
  /// - requesting → isteği iptal et (re-tap)
  /// - requested  → kabul et
  /// - matched    → yoksay
  Future<void> tapPublicPeer(String peerId) async {
    if (!_discoveryOnlyMode) return;

    final peer = _discoveredPeers[peerId];
    if (peer == null) {
      pairingLog('[PUBLIC] ⚠️ Peer not found: $peerId');
      return;
    }

    if (peer.state == PublicPeerState.matched) return;

    // Re-tap requesting = iptal
    if (peer.state == PublicPeerState.requesting) {
      pairingLog('[PUBLIC] ❌ Cancelling pair request to $peerId');
      await _cancelPublicPairRequest(peerId);
      return;
    }

    // Requested = kabul et
    if (peer.state == PublicPeerState.requested) {
      pairingLog('[PUBLIC] ✅ Accepting request from $peerId');
      await _acceptPublicPairRequest(peerId);
      return;
    }

    // ✅ FIX: Aynı anda tek aktif istek. BLE'de tek bağlantı olduğundan,
    // bir istek beklerken ikinci bir dota dokunulursa connect() no-op kalıyor
    // ve PairIntent MEVCUT link üzerinden İLK kişiye gidiyordu; ikinci dot
    // ise sahte "istek gönderildi" durumunda takılı kalıyordu. Yeni istek
    // için önce mevcut isteği iptal etmek gerekir (aynı dota yeniden dokun).
    final hasActiveRequest =
        _discoveredPeers.values.any((p) => p.state == PublicPeerState.requesting);
    if (hasActiveRequest) {
      pairingLog('[PUBLIC] ⚠️ Request to $peerId blocked - another request is active');
      return;
    }

    pairingLog('[PUBLIC] 📤 Sending pair request to $peerId');
    _discoveredPeers[peerId] = peer.copyWith(state: PublicPeerState.requesting);
    _discoveredPeersController.add(_discoveredPeers.values.toList());

    try {
      // Public modda isteği başlatan taraf her zaman bağlantıyı kurar.
      // deviceId (native UUID) ile peerId (BLE peripheral UUID) farklı namespace'ler
      // olduğu için karşılaştırma güvenilir değil; her zaman connect() çağrılmalı.
      // Eş zamanlı tap durumunda plugin içindeki _connectedDevice != null kontrolü
      // ikinci bağlantı girişimini zaten reddeder.
      await blePlugin.connect(peerId: peerId);
      await Future.delayed(const Duration(milliseconds: 500));

      await blePlugin.send(PairIntentMessage(sid: deviceId));
      pairingLog('[PUBLIC] ✅ Pair request sent to $peerId');

      // 15 saniyelik timeout — sürerse reject gönder
      _timers.schedule('public_pair_timeout', const Duration(seconds: 15), () {
        pairingLog('[PUBLIC] ⏱️ Pair request timeout for $peerId');
        final p = _discoveredPeers[peerId];
        if (p != null && p.state == PublicPeerState.requesting) {
          _discoveredPeers[peerId] = p.copyWith(state: PublicPeerState.idle);
          _discoveredPeersController.add(_discoveredPeers.values.toList());
          // Senkron try/catch async hatayı yakalayamaz; catchError kullan.
          blePlugin
              .send(PairRejectMessage(sid: deviceId, reason: 'timeout'))
              .catchError((_) {});
        }
      });
    } catch (e) {
      pairingLog('[PUBLIC] ❌ Failed to send pair request: $e');
      _discoveredPeers[peerId] = peer.copyWith(state: PublicPeerState.idle);
      _discoveredPeersController.add(_discoveredPeers.values.toList());
    }
  }

  /// İstek gönderilmiş bir peer'a yeniden tap → isteği iptal et
  Future<void> _cancelPublicPairRequest(String peerId) async {
    _timers.cancel('public_pair_timeout');
    final peer = _discoveredPeers[peerId];
    if (peer != null) {
      _discoveredPeers[peerId] = peer.copyWith(state: PublicPeerState.idle);
      _discoveredPeersController.add(_discoveredPeers.values.toList());
    }
    try {
      await blePlugin.send(PairRejectMessage(sid: deviceId, reason: 'cancelled'));
      pairingLog('[PUBLIC] ✅ Cancel sent to $peerId');
    } catch (e) {
      pairingLog('[PUBLIC] ⚠️ Cancel send failed (ignored): $e');
    }
  }
  
  /// Handle pending public request when in radar mode
  /// This notifies the UI to show the blinking indicator
  /// [nativeDeviceId] is the sender's native device ID (from PairIntentMessage.sid)
  /// [blePeerId] is the sender's BLE-level device ID (from MessageReceived event)
  ///   — may be empty when we're the peripheral (iOS doesn't expose central's ID)
  void _handlePendingPublicRequest(String nativeDeviceId, String blePeerId) {
    // ✅ Use BLE ID if available, otherwise fall back to native device ID
    // On the peripheral side, _peerId is null → blePeerId is '' → use nativeDeviceId
    // On the central side, blePeerId is the real BLE UUID → use it directly
    final peerKey = blePeerId.isNotEmpty ? blePeerId : nativeDeviceId;
    
    pairingLog('[PUBLIC] 📥 Received public request while in RADAR mode');
    pairingLog('[PUBLIC]   native ID: $nativeDeviceId, BLE ID: $blePeerId, key: $peerKey');
    
    // ✅ Notify if app is in background (purple vibration)
    _notifyIfBackground(NomatchNotificationType.pairRequest);
    
    // ✅ Store native device ID for leader election
    _peerNativeDeviceId = nativeDeviceId;
    
    _pendingPublicRequests.add(peerKey);
    _pendingRequestsController.add(true);
    
    // Also add to discovered peers so they show up when user switches to public mode
    if (!_discoveredPeers.containsKey(peerKey)) {
      _discoveredPeers[peerKey] = DiscoveredPeer(
        id: peerKey,
        rssi: -60, // Default RSSI
        lastSeen: DateTime.now(),
        state: PublicPeerState.requested,
      );
    } else {
      final peer = _discoveredPeers[peerKey]!;
      _discoveredPeers[peerKey] = peer.copyWith(
        state: PublicPeerState.requested,
        lastSeen: DateTime.now(),
      );
    }
    _discoveredPeersController.add(_discoveredPeers.values.toList());
    
    // Auto-expire pending request after 30 seconds
    _timers.schedule('pending_request_$peerKey', const Duration(seconds: 30), () {
      _pendingPublicRequests.remove(peerKey);
      _pendingRequestsController.add(_pendingPublicRequests.isNotEmpty);
      
      // Also update peer state
      final peer = _discoveredPeers[peerKey];
      if (peer != null && peer.state == PublicPeerState.requested) {
        _discoveredPeers[peerKey] = peer.copyWith(state: PublicPeerState.idle);
        _discoveredPeersController.add(_discoveredPeers.values.toList());
      }
    });
  }

  /// Merge phantom pending-request entries when BLE discovers the real device.
  /// Phantom entries are stored with native device ID (not BLE ID) because the
  /// peripheral side can't determine the central's BLE ID.
  void _mergePhantomPendingRequest(String bleDeviceId) {
    // Find pending request entries whose key doesn't match this BLE ID
    // and isn't a known BLE discovery ID (i.e., stored with native device ID)
    String? phantomKey;
    for (final key in _pendingPublicRequests) {
      if (key != bleDeviceId && _discoveredPeers.containsKey(key)) {
        final peer = _discoveredPeers[key]!;
        if (peer.state == PublicPeerState.requested) {
          phantomKey = key;
          break;
        }
      }
    }
    
    if (phantomKey == null) return;
    
    pairingLog('[DISCOVERY] 🔄 Merging phantom pending request: $phantomKey → $bleDeviceId');
    
    // Transfer the requested state to the BLE-discovered peer
    _discoveredPeers[bleDeviceId] = _discoveredPeers[bleDeviceId]!.copyWith(
      state: PublicPeerState.requested,
    );
    
    // Remove the phantom entry
    _discoveredPeers.remove(phantomKey);
    
    // Update pending requests set: replace phantom key with BLE ID
    _pendingPublicRequests.remove(phantomKey);
    _pendingPublicRequests.add(bleDeviceId);
    
    // Move the auto-expire timer to the new key
    _timers.cancel('pending_request_$phantomKey');
    _timers.cancel('public_request_expire_$phantomKey');
    _timers.schedule('pending_request_$bleDeviceId', const Duration(seconds: 30), () {
      _pendingPublicRequests.remove(bleDeviceId);
      _pendingRequestsController.add(_pendingPublicRequests.isNotEmpty);
      final peer = _discoveredPeers[bleDeviceId];
      if (peer != null && peer.state == PublicPeerState.requested) {
        _discoveredPeers[bleDeviceId] = peer.copyWith(state: PublicPeerState.idle);
        _discoveredPeersController.add(_discoveredPeers.values.toList());
      }
    });
  }

  /// Handle receiving a pair request in public mode
  /// [nativeDeviceId] is the sender's native device ID (from PairIntentMessage.sid)
  /// [blePeerId] is the sender's BLE-level device ID (from MessageReceived event, may be empty)
  void _handlePublicPairRequest(String nativeDeviceId, String blePeerId) {
    if (!_discoveryOnlyMode) return;

    pairingLog('[PUBLIC] 📥 Received pair request — native: $nativeDeviceId, ble: $blePeerId');

    // Store native device ID for leader election
    _peerNativeDeviceId = nativeDeviceId;

    // ✅ Notify if app is in background (purple vibration)
    _notifyIfBackground(NomatchNotificationType.pairRequest);

    // Lookup priority:
    // 1. BLE peer ID from event (most reliable — same key as discovery)
    // 2. _peerId set by handlePeerConnected when they connected to us
    // 3. Native device ID (only matches if native ID == BLE ID, rare)
    // 4. Phantom fallback: create entry with native ID, merge when BLE discovery arrives
    String matchedPeerId = blePeerId.isNotEmpty ? blePeerId : (_peerId ?? nativeDeviceId);
    var peer = _discoveredPeers[matchedPeerId];

    if (peer == null && matchedPeerId != nativeDeviceId) {
      // Last resort: native ID key (e.g. radar→public switch preserved it)
      peer = _discoveredPeers[nativeDeviceId];
      if (peer != null) matchedPeerId = nativeDeviceId;
    }

    // Peripheral tarafında blePeerId boştur (iOS central UUID'yi expose etmez).
    // Bu durumda nativeDeviceId ile BLE keşif UUID'si farklı olur → phantom oluşur.
    // Eğer _discoveredPeers'da tam olarak bir idle peer varsa, o peer bu gönderendir.
    if (peer == null && blePeerId.isEmpty) {
      final idleEntries = _discoveredPeers.entries
          .where((e) => e.value.state == PublicPeerState.idle)
          .toList();
      if (idleEntries.length == 1) {
        matchedPeerId = idleEntries.first.key;
        peer = idleEntries.first.value;
        pairingLog('[PUBLIC] 🔄 Peripheral: matched request to single idle peer $matchedPeerId');
      }
    }

    if (peer == null) {
      pairingLog('[PUBLIC] 🔍 No peer entry found — creating phantom with key=$matchedPeerId');
    }

    // Mutual match: biz de istek göndermişsek karşılıklı eşleşme
    if (peer != null && peer.state == PublicPeerState.requesting) {
      pairingLog('[PUBLIC] 🎉 Mutual match with $matchedPeerId!');
      _completePublicPairing(matchedPeerId);
      return;
    }

    // Peer'ı requested olarak işaretle
    if (peer != null) {
      _discoveredPeers[matchedPeerId] = peer.copyWith(state: PublicPeerState.requested);
    } else {
      _discoveredPeers[matchedPeerId] = DiscoveredPeer(
        id: matchedPeerId,
        rssi: -60,
        lastSeen: DateTime.now(),
        state: PublicPeerState.requested,
      );
      // ✅ Phantom kaydı _pendingPublicRequests'e de ekle ki BLE taraması
      // gerçek peer'ı (BLE ID) bulduğunda _mergePhantomPendingRequest()
      // bu phantom'u tanıyıp gerçek dot ile birleştirebilsin.
      _pendingPublicRequests.add(matchedPeerId);
      _pendingRequestsController.add(_pendingPublicRequests.isNotEmpty);
    }
    _discoveredPeersController.add(_discoveredPeers.values.toList());

    // Responder timeout: requester ile simetrik (15s)
    // Requester süreyi aşarsa PairRejectMessage gönderir — bu timer güvencedir.
    _timers.schedule('public_request_expire_$matchedPeerId', const Duration(seconds: 15), () {
      final p = _discoveredPeers[matchedPeerId];
      if (p != null && p.state == PublicPeerState.requested) {
        pairingLog('[PUBLIC] ⏱️ Request from $matchedPeerId expired');
        _discoveredPeers[matchedPeerId] = p.copyWith(state: PublicPeerState.idle);
        _discoveredPeersController.add(_discoveredPeers.values.toList());
      }
    });
  }

  /// Karşı taraftan PairRejectMessage alındığında çağrılır
  void _handlePublicPairReject(String blePeerId) {
    pairingLog('[PUBLIC] ❌ Pair reject received from $blePeerId');

    // ✅ FIX: Ret yalnızca reddeden peer'ın isteğini temizlemeli. Eskiden
    // TÜM requesting/requested peer'lar idle'a dönüyordu — kalabalık ortamda
    // bir yabancının reddi, başka birine giden bekleyen isteği de siliyordu.
    String? target;
    if (_discoveredPeers.containsKey(blePeerId)) {
      target = blePeerId;
    } else {
      // Reject bağlı link üzerinden gelir; key eşleşmezse (namespace farkı)
      // aktif istekli peer'a düş — tek-aktif-istek kuralı sayesinde tekildir.
      for (final e in _discoveredPeers.entries) {
        if (e.value.state == PublicPeerState.requesting ||
            e.value.state == PublicPeerState.requested) {
          target = e.key;
          break;
        }
      }
    }
    if (target == null) return;

    final p = _discoveredPeers[target]!;
    if (p.state != PublicPeerState.requesting &&
        p.state != PublicPeerState.requested) {
      return;
    }
    _timers.cancel('public_request_expire_$target');
    if (p.state == PublicPeerState.requesting) {
      _timers.cancel('public_pair_timeout');
    }
    _discoveredPeers[target] = p.copyWith(state: PublicPeerState.idle);
    pairingLog('[PUBLIC] 🔄 Peer $target reset to idle (reject)');
    _discoveredPeersController.add(_discoveredPeers.values.toList());
  }
  
  /// Accept a pair request from a peer
  Future<void> _acceptPublicPairRequest(String peerId) async {
    pairingLog('[PUBLIC] 📤 Accepting pair from $peerId');

    // ✅ Reverse connection (connect()+discoverServices()) bazen 500ms'den
    // uzun sürebiliyor; tek denemede _messageChar hâlâ null kalırsa send()
    // sessizce başarısız oluyor ve dokunuş "algılanmamış" gibi görünüyordu.
    // Birkaç kez deneyerek bu zamanlama farkını tolere ediyoruz.
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      // İstek bu sırada karşı taraf tarafından iptal edilmiş olabilir.
      if (_discoveredPeers[peerId]?.state != PublicPeerState.requested) {
        pairingLog('[PUBLIC] ⚠️ Accept aborted - $peerId no longer requested');
        return;
      }

      try {
        // Bu cihaz PairIntent'i bağlantıyı başlatmadan (peripheral rolünde)
        // aldıysa _messageChar henüz null'dur — PeerConnected event'i sadece
        // bağlantıyı başlatan central'a gelir. Reverse connection: biz de
        // central olarak bağlanalım (zaten bağlıysak connect() no-op).
        await blePlugin.connect(peerId: peerId);
        await Future.delayed(const Duration(milliseconds: 500));

        final msg = PairAckMessage(sid: deviceId);
        await blePlugin.send(msg);
        _completePublicPairing(peerId);
        return;
      } catch (e) {
        pairingLog('[PUBLIC] ❌ Accept attempt $attempt/$maxAttempts failed: $e');
        if (attempt < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    pairingLog('[PUBLIC] ❌ Failed to accept pair from $peerId after $maxAttempts attempts');

    // ✅ FIX: Eskiden burada yalnızca log vardı: dot 'requested' durumunda
    // takılı kalıyor, kullanıcı kabulünün başarısız olduğunu göremiyor,
    // karşı taraf da 15 sn boşuna bekliyordu. Durumu temizle ve karşıya
    // (bağlantı kurulabildiyse) ret bildir.
    _timers.cancel('pending_request_$peerId');
    _timers.cancel('public_request_expire_$peerId');
    _pendingPublicRequests.remove(peerId);
    _pendingRequestsController.add(_pendingPublicRequests.isNotEmpty);

    final failedPeer = _discoveredPeers[peerId];
    if (failedPeer != null && failedPeer.state == PublicPeerState.requested) {
      _discoveredPeers[peerId] = failedPeer.copyWith(state: PublicPeerState.idle);
      _discoveredPeersController.add(_discoveredPeers.values.toList());
    }

    // Best-effort: karşı taraf beklemesin. Bağlantı yoksa sessizce düşer
    // (requester kendi 15 sn timeout'uyla zaten temizlenir).
    blePlugin
        .send(PairRejectMessage(sid: deviceId, reason: 'accept_failed'))
        .catchError((_) {});
  }
  
  /// Handle receiving a pair accept in public mode
  void _handlePublicPairAccept(String fromPeerId) {
    if (!_discoveryOnlyMode) return;
    
    pairingLog('[PUBLIC] 📥 Received pair accept from $fromPeerId');
    
    // ✅ FIX: Store peer's native device ID from PairAckMessage.sid
    // This is critical for deterministic leader election in public mode
    _peerNativeDeviceId = fromPeerId;
    pairingLog('[PUBLIC] 📱 Stored peer native device ID: $_peerNativeDeviceId');
    
    // First try exact match
    var peer = _discoveredPeers[fromPeerId];
    String? matchedPeerId = fromPeerId;
    
    // If no exact match, find any peer in "requesting" state
    // (The accept message uses native device ID, but we track by BLE ID)
    if (peer == null || peer.state != PublicPeerState.requesting) {
      pairingLog('[PUBLIC] 🔍 No exact match, searching for requesting peer...');
      for (final entry in _discoveredPeers.entries) {
        if (entry.value.state == PublicPeerState.requesting) {
          peer = entry.value;
          matchedPeerId = entry.key;
          pairingLog('[PUBLIC] ✅ Found requesting peer: $matchedPeerId');
          break;
        }
      }
    }
    
    if (peer != null && peer.state == PublicPeerState.requesting && matchedPeerId != null) {
      _completePublicPairing(matchedPeerId);
    } else {
      pairingLog('[PUBLIC] ⚠️ No matching peer in requesting state');
    }
  }
  
  /// İki native device ID'den deterministik session ID üretir.
  /// Her iki cihaz da aynı ID çiftini sıralayarak aynı değeri hesaplar.
  String _deterministicSessionId(String a, String b) {
    final sorted = [a, b]..sort();
    final prefix0 = sorted[0].length >= 8 ? sorted[0].substring(0, 8) : sorted[0];
    final prefix1 = sorted[1].length >= 8 ? sorted[1].substring(0, 8) : sorted[1];
    return '${prefix0}_$prefix1';
  }

  /// Complete public mode pairing - skip heading validation, go directly to game
  void _completePublicPairing(String peerId) {
    pairingLog('[PUBLIC] 🎉 Pairing complete with $peerId - starting game!');
    _timers.cancel('public_pair_timeout');
    
    // Update peer state to matched
    final peer = _discoveredPeers[peerId];
    if (peer != null) {
      _discoveredPeers[peerId] = peer.copyWith(state: PublicPeerState.matched);
      _discoveredPeersController.add(_discoveredPeers.values.toList());
    }
    
    // Store peer ID and generate deterministic session ID.
    // Her iki cihaz da aynı native ID çiftini sıralayarak aynı session ID'yi üretir.
    _peerId = peerId;
    final otherId = _peerNativeDeviceId ?? peerId;
    _sessionId = _deterministicSessionId(deviceId, otherId);
    
    // Exit discovery mode after short delay (show green state)
    Future.delayed(const Duration(milliseconds: 300), () async {
      // ✅ FIX: Bu 300ms içinde hardReset()/mod değişimi olduysa alanlar
      // sıfırlanmıştır; devam edilirse _peerId! null hatası verir veya
      // sıfırlama sonrası sahte 'connected' state'i yayınlanırdı.
      if (_peerId != peerId) {
        pairingLog('[PUBLIC] ⚠️ Pairing completion aborted - state reset during delay');
        return;
      }
      _discoveryOnlyMode = false;
      _timers.cancel('discovery_cleanup');
      
      // ✅ PUBLIC MODE: Skip heading validation - elect leader and connect directly
      pairingLog('[PUBLIC] 📱 Public mode - skipping heading validation');
      
      // Elect leader based on device IDs
      if (_peerNativeDeviceId != null) {
        _isLeader = LeaderAlgorithm.selectLeader(deviceId, _peerNativeDeviceId!);
        pairingLog('[PUBLIC] 👑 Leader elected: ${_isLeader ? 'THIS DEVICE' : 'PEER DEVICE'} (native UUIDs)');
      } else {
        // ✅ FIX: deviceId (native) ile _peerId (BLE peripheral UUID) farklı
        // namespace'ler — karşılaştırma iki cihazda ilişkisiz sonuç verir ve
        // ikisi de follower kalırsa oyun HİÇ başlamaz (deadlock, timeout yok).
        // Bunun yerine iki taraf da lider olur: GameEngine'in çakışma çözümü
        // (RoundStart.leaderId, native↔native) fazla lideri deterministik
        // olarak devre dışı bırakır. Çift follower'ın kurtarıcısı yoktur.
        _isLeader = true;
        pairingLog('[PUBLIC] 👑 Peer native ID yok - lider varsayılıyor (çakışma çözümü devreder)');
      }
      
      // Go directly to connected state - UI will trigger game transition
      _setState(PairingState.connected);
      pairingLog('[PUBLIC] ✅✅✅ PUBLIC PAIRING SUCCESS ✅✅✅');
      
      // ✅ Notify if app is in background (lime vibration)
      _notifyIfBackground(NomatchNotificationType.radarMatch);
    });
  }
  
  /// Cleanup stale peers (not seen in last 30 seconds)
  /// BUT keep peers that are in active pairing state or connected
  void _cleanupStalePeers() {
    // If we have an active session in discovery mode, don't clean up at all
    // This prevents dots from disappearing while connected
    if (_discoveryOnlyMode && _sessionId != null) {
      return;
    }
    
    final now = DateTime.now();
    // idle peer'lar için 8s — metro/otobüs gibi hızlı değişen ortamlarda güncel kalır.
    // requested/requesting/matched peer'lar bu fonksiyona girmiyor (aşağıda guard var).
    const staleThreshold = Duration(seconds: 8);
    
    _discoveredPeers.removeWhere((id, peer) {
      // Don't remove peers in active pairing states
      if (peer.state != PublicPeerState.idle) {
        return false;
      }
      
      // Don't remove the peer we're connected to
      if (_peerId != null && id == _peerId) {
        return false;
      }
      
      final isStale = now.difference(peer.lastSeen) > staleThreshold;
      if (isStale) {
        pairingLog('[DISCOVERY] 🗑️ Removing stale peer: $id (last seen ${now.difference(peer.lastSeen).inSeconds}s ago)');
      }
      return isStale;
    });
    
    _discoveredPeersController.add(_discoveredPeers.values.toList());
  }

  /// Start pairing process
  Future<PairingResult> start({
    required bool isPhoneFlat,
  }) async {
    // perfLog('[TEST-CONN] 🚀 Starting pairing (isFlat: $isPhoneFlat)');
    
    // Allow pairing only if phone is roughly flat (with tolerance)
    if (!isPhoneFlat) {
      pairingLog('[PAIR] ⚠️ Phone not flat enough, waiting...');
      return PairingResult(
        success: false,
        errorReason: 'phone_not_flat',
      );
    }

    try {
      // Önceki BLE operasyonu (hosting/scan) hâlâ aktifse temiz başlangıç için
      // önce durdur — aksi halde startHosting()/startDiscovery() "already
      // advertising/scanning" guard'larına takılıp no-op olur.
      await blePlugin.stop();

      // Reset state from previous attempts
      _reset();

      // 1. Start heading validator
      await headingValidator.start();
      _setState(PairingState.hostingReady);

      // 2. Start BLE hosting and discovery with Nomatch-specific UUID
      pairingLog('[PAIR] 📡 Starting BLE hosting with Nomatch UUID...');
      await blePlugin.startHosting(displayNameHash: deviceId);
      
      // iOS'ta explicit advertising başlat (native method channel üzerinden)
      pairingLog('[PAIR] 📡 Triggering iOS BLE advertising...');
      try {
        const bleChannel = MethodChannel('com.nomatch/ble_advertising');
        await bleChannel.invokeMethod('startAdvertising', {
          'serviceUuid': BleConstants.nomatchServiceUUID,
          'deviceName': 'nomatch-device',
        });
        pairingLog('[PAIR] ✅ iOS advertising initiated');
      } catch (e) {
        pairingLog('[PAIR] ⚠️ iOS advertising trigger failed: $e');
      }
      
      await blePlugin.startDiscovery();
      pairingLog('[PAIR] ✅ Hosting started, waiting for peers...');

      _setState(PairingState.peerSearching);
      
      return PairingResult(success: true);
    } catch (e, st) {
      pairingLog('[PAIR] ❌ Start failed: $e');
      pairingLog('[PAIR] ❌ Stack trace: $st');
      // perfLog('[TEST-CONN] ❌ Exception: ${e.runtimeType}');
      return PairingResult(
        success: false,
        errorReason: 'start_failed: $e',
      );
    }
  }

  /// Handle peer discovered (BLE)
  void handlePeerDiscovered(String peerId, int rssi) {
    // perfLog('[TEST-CONN] 📡 Peer discovered: peerId=$peerId, rssi=$rssi');
    pairingLog('[PEER] 📡 Peer discovered: $peerId (RSSI: $rssi dBm)');
    
    // Ignore self (don't connect to own device)
    if (peerId == deviceId) {
      pairingLog('[PEER] ⚠️ Ignoring self-advertisement, skipping');
      return;
    }
    
    // Zaten bağlı/oyunda veya idle ise yoksay.
    // idle: kullanıcı üçgene basmadı; bağlantı başlatılmamalı.
    // Bu guard ayrıca public→radar geçiş penceresinde (BLE henüz durmamiş)
    // istemeden yapılan bağlantı girişimlerini de engeller.
    if (_state == PairingState.idle ||
        _state == PairingState.preConnected ||
        _state == PairingState.headingValidating ||
        _state == PairingState.connected ||
        _state == PairingState.failed ||
        _state == PairingState.game ||
        _state == PairingState.gameReady ||
        _state == PairingState.playing) {
      pairingLog('[PEER] ⚠️ Ignoring peer discovery in state: $_state');
      return;
    }
    
    // Peer'ları sadece public (discovery-only) modda takip et ve UI'a bildir.
    // Radar modunda BLE scan kısa süre devam edebilir; bu sırada gelen
    // discovery event'leri radar ekranında nokta oluşturmamalı.
    if (_discoveryOnlyMode) {
      final existingPeer = _discoveredPeers[peerId];
      if (existingPeer != null) {
        _discoveredPeers[peerId] = existingPeer.copyWith(
          rssi: rssi,
          lastSeen: DateTime.now(),
        );
      } else {
        _discoveredPeers[peerId] = DiscoveredPeer(
          id: peerId,
          rssi: rssi,
          lastSeen: DateTime.now(),
        );
        _mergePhantomPendingRequest(peerId);
      }
      _discoveredPeersController.add(_discoveredPeers.values.toList());
      pairingLog('[DISCOVERY] 📍 Tracking peer: $peerId (RSSI: $rssi)');
      return; // Public modda bağlantı başlatılmaz
    }
    
    // Bağlantı için alt sınır -95 dBm: radar modu uzak masalar arası eşleşme
    // için tasarlandı, menzil geniş tutulur. -95 altı gürültü tabanına çok
    // yakın — bağlantı denemesi büyük olasılıkla 10 sn'lik timeout'u yakıp
    // daha yakın bir peer'ın keşfini bloke eder, o yüzden elenir.
    if (rssi < -95) {
      pairingLog('[PEER] ⚠️ Signal too weak (RSSI: $rssi < -95), skipping');
      return;
    }

    // Only connect to FIRST peer discovered (ignore others)
    if (_peerId != null) {
      pairingLog('[PEER] ⚠️ Already connecting to $_peerId, ignoring new peer: $peerId');
      return;
    }
    
    // ✅ Check if we've exceeded max attempts for this peer
    if (_lastFailedPeerId == peerId && _connectionAttempts >= _maxConnectionAttempts) {
      pairingLog('[PAIR] ❌ Max connection attempts ($_maxConnectionAttempts) reached for peer: $peerId');
      pairingLog('[PAIR]    Waiting 5 seconds before allowing retry...');
      // Wait 5 seconds before allowing another attempt
      Future.delayed(const Duration(seconds: 5), () {
        _connectionAttempts = 0;
        _lastFailedPeerId = null;
        pairingLog('[PAIR] 🔄 Connection attempts reset - ready to retry');
      });
      return;
    }

    // Her iki cihaz da peer keşfedince direkt bağlantı başlatır.
    // "Küçük ID bağlanır" mantığı deviceId (native UUID) ile peerId (BLE UUID)
    // farklı namespace'leri karşılaştırdığından deadlock yaratıyordu:
    // her iki cihaz da "büyük ID'yim, bekleyeyim" diyerek hiç bağlanmıyordu.
    // BleP2pPlugin içindeki _connectedDevice / _isConnecting guard'ları
    // eş zamanlı bağlantı girişimlerini zaten yönetir.
    _peerId = peerId;
    _connectionAttempts++;
    pairingLog('[PAIR] 🔗 Bağlantı başlatılıyor (deneme $_connectionAttempts/$_maxConnectionAttempts)');
    pairingLog('[PAIR]    Bizim ID: $deviceId');
    pairingLog('[PAIR]    Peer ID: $peerId');
    blePlugin.connect(peerId: peerId);

    // Bağlantı timeout (10 saniye)
    _timers.schedule(_kTimerConnectionTimeout, const Duration(seconds: 10), () {
      pairingLog('[PAIR] ⏱️ Bağlantı timeout (deneme $_connectionAttempts/$_maxConnectionAttempts)');
      _lastFailedPeerId = peerId;
      _reset();
    });
  }

  /// Handle peer connected (BLE)
  void handlePeerConnected(String sessionId, String peerId, bool isLeader) {
    // perfLog('[TEST-CONN] ✅ CONNECTED to $peerId (role=${isLeader ? 'LEADER' : 'FOLLOWER'})');
    
    // ✅ In discovery-only (public) mode, ignore normal connection flow
    // Public mode has its own pairing mechanism via PairIntent/PairAck messages
    if (_discoveryOnlyMode) {
      pairingLog('[CONN] 📱 Discovery mode active - ignoring normal connection flow');
      pairingLog('[CONN]   └─ Will wait for public pairing messages instead');
      // Store session and peer info for message sending and cleanup protection
      _sessionId = sessionId;
      _peerId = peerId; // ✅ Store peer ID to protect from cleanup
      
      // Keep the connected peer fresh in discovered peers list
      final existingPeer = _discoveredPeers[peerId];
      if (existingPeer != null) {
        _discoveredPeers[peerId] = existingPeer.copyWith(lastSeen: DateTime.now());
        _discoveredPeersController.add(_discoveredPeers.values.toList());
      }
      return;
    }
    
    // ✅ "Hayalet" bağlantı: connection timeout sonrası _reset() ile _peerId
    // temizlendi, ama BLE katmanındaki connect() (20s) daha sonra tamamlandı.
    // PairingManager artık bu peer'ı beklemiyor — bağlantıyı reddet, BLE'yi
    // temizle ve taramaya devam et.
    if (_peerId == null) {
      pairingLog('[CONN] ⚠️ Ghost connection rejected (peerId=$peerId) — muhtemelen timeout sonrası geldi');
      blePlugin.disconnect();
      if (_state == PairingState.peerSearching) {
        blePlugin.startDiscovery();
      }
      return;
    }

    // Ignore if peer doesn't match what we discovered
    // (this prevents connecting to wrong devices)
    if (_peerId != null && _peerId != peerId) {
      pairingLog('[CONN] ⚠️ Ignoring mismatched peer connection. Expected: $_peerId, Got: $peerId');
      // Bu da geç gelen bir "hayalet" bağlantı — BLE katmanında kurulmuş
      // durumda kalırsa _connectedDevice dolu kalır ve beklenen peer'a
      // bağlanmayı kalıcı olarak engeller (deadlock). Temizle ve taramaya devam et.
      blePlugin.disconnect();
      if (_state == PairingState.peerSearching) {
        blePlugin.startDiscovery();
      }
      return;
    }
    
    // Ignore duplicate connections (idempotency)
    if (_sessionId == sessionId && _peerId == peerId && _state == PairingState.preConnected) {
      pairingLog('[CONN] ⚠️ Ignoring duplicate peer connection event');
      return;
    }
    
    pairingLog('[CONN] ✅ PEER CONNECTED!');
    pairingLog('[CONN]   Session: $sessionId');
    pairingLog('[CONN]   Peer: $peerId');
    pairingLog('[CONN]   Role: ${isLeader ? 'LEADER' : 'FOLLOWER'}');

    // ✅ Cancel connection timeout since peer connected successfully
    _timers.cancel(_kTimerConnectionTimeout);
    
    // ✅ Reset connection attempt tracking on success
    _connectionAttempts = 0;
    _lastFailedPeerId = null;

    _sessionId = sessionId;
    _peerId = peerId;
    _isLeader = isLeader;
    _setState(PairingState.preConnected);

    // Start heading validation
    _startHeadingValidation();
  }

  // ✅ Throttle heading messages to avoid BLE overload
  DateTime? _lastHeadingSentTime;
  static const _headingSendInterval = Duration(milliseconds: 500); // Send max 2x per second
  
  // ✅ FIX: Track whether peer heading was received (for delayed timer start)
  bool _peerHeadingReceived = false;
  static const Duration _peerHeadingWaitTimeout = Duration(seconds: 10);
  static const Duration _headingValidationDuration = Duration(seconds: 3);

  /// Start heading validation phase
  void _startHeadingValidation() {
    pairingLog('[CONN] 🧭 Starting heading validation');
    _setState(PairingState.headingValidating);

    // Cancel existing heading subscription if any
    _headingSubscription?.cancel();
    _lastHeadingSentTime = null; // Reset throttle
    _peerHeadingReceived = false;
    
    // Listen to heading updates and send them via P2P (throttled)
    _headingSubscription = headingValidator.headingUpdates.listen((heading) {
      _updateOurHeading(heading);
      
      // Send heading to peer via P2P message (throttled to avoid BLE overload)
      if (_peerId != null && _sessionId != null) {
        final now = DateTime.now();
        if (_lastHeadingSentTime == null || 
            now.difference(_lastHeadingSentTime!) >= _headingSendInterval) {
          _lastHeadingSentTime = now;
          _sendHeadingMessage(heading);
        }
      }
    });

    // ✅ FIX: Don't start the validation timer immediately.
    // Wait for first peer heading message to arrive, THEN start 3-second timer.
    // This ensures both devices have bidirectional BLE communication established.
    pairingLog('[CONN] ⏳ Waiting for peer heading data (max ${_peerHeadingWaitTimeout.inSeconds}s)...');
    _timers.schedule(_kTimerHeadingValidation, _peerHeadingWaitTimeout, () {
      pairingLog('[CONN] ⏰ Peer heading wait timeout! peerHeading=$_peerHeading');
      if (!_peerHeadingReceived) {
        pairingLog('[CONN] ❌ Never received peer heading data');
      }
      _completeHeadingValidation();
    });
  }
  
  /// ✅ FIX: Called when first peer heading arrives — starts the real validation countdown
  void _onFirstPeerHeadingReceived() {
    if (_peerHeadingReceived) return; // Already received
    _peerHeadingReceived = true;
    
    pairingLog('[CONN] ✅ First peer heading received! Starting ${_headingValidationDuration.inSeconds}s validation timer');
    
    // Cancel the long wait timeout and start the real validation timer
    _timers.cancel(_kTimerHeadingValidation);
    _timers.schedule(_kTimerHeadingValidation, _headingValidationDuration, () {
      pairingLog('[CONN] ⏰ Heading validation timer fired!');
      _completeHeadingValidation();
    });
  }
  
  /// Send heading via P2P message
  Future<void> _sendHeadingMessage(double heading) async {
    try {
      if (_sessionId == null) {
        pairingLog('[CONN] ⚠️ No session ID yet, skipping send');
        return;
      }
      
      final message = SensorSnapshotMessage(
        sid: _sessionId!,
        isFlat: true, // Assume flat during pairing
        headingDeg: heading,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        mid: null,
        nativeDeviceId: deviceId, // ✅ NEW: Send our native device ID
      );
      
      pairingLog('[CONN] 📤 Sending heading ${heading.toStringAsFixed(1)}° to peer');
      await blePlugin.send(message);
      pairingLog('[CONN] ✅ Heading sent successfully');
    } catch (e) {
      pairingLog('[CONN] ❌ Failed to send heading: $e');
    }
  }

  /// Receive peer heading (from P2P message)
  void receivePeerHeading(double heading) {
    _peerHeading = heading;
    
    // ✅ FIX: Trigger validation timer start on first peer heading
    if (_state == PairingState.headingValidating && !_peerHeadingReceived) {
      _onFirstPeerHeadingReceived();
    }
  }
  
  /// Update our heading
  void _updateOurHeading(double heading) {
    _ourHeading = heading;
    // pairingLog('[HEADING] 🧭 Our heading: ${heading.toStringAsFixed(1)}°');
  }

  // ✅ NEW: Retry counter for heading validation
  int _headingValidationRetries = 0;
  static const int _maxHeadingRetries = 3;
  
  /// Complete heading validation
  Future<void> _completeHeadingValidation() async {
    pairingLog('[CONN] ✓ Heading validation period complete');
    
    pairingLog('[CONN] 📊 DEBUG: ourHeading=$_ourHeading, peerHeading=$_peerHeading');
    
    // Check if heading data received from peer
    if (_ourHeading == null || _peerHeading == null) {
      pairingLog('[CONN] ❌ Heading validation failed (missing data)');
      pairingLog('[CONN]   └─ Our heading: ${_ourHeading?.toStringAsFixed(1) ?? "null"}°');
      pairingLog('[CONN]   └─ Peer heading: ${_peerHeading?.toStringAsFixed(1) ?? "null"}°');
      await _retryOrFailHeadingValidation('heading_missing');
      return;
    }

    // Check if facing each other
    final facing = HeadingValidation.isFacingEachOther(
      _ourHeading!,
      _peerHeading!,
    );
    final diff = HeadingValidation.getAngleDifference(
      _ourHeading!,
      _peerHeading!,
    );

    pairingLog('[CONN] 📐 Heading difference: ${diff.toStringAsFixed(1)}° (need 150°-210° for face-to-face)');
    if (facing) {
      pairingLog('[CONN] ✅ Face-to-face validation: PASSED');
    } else {
      pairingLog('[CONN] ❌ Face-to-face validation: FAILED (diff=${diff.toStringAsFixed(1)}°, need ~180°)');
    }

    if (!facing) {
      await _retryOrFailHeadingValidation('not_facing');
      return;
    }
    
    // ✅ Success: Stop heading subscription and reset retry counter
    _headingSubscription?.cancel();
    _headingSubscription = null;
    _headingValidationRetries = 0;
    pairingLog('[CONN] 🛑 Heading subscription stopped');

    // ✅ NEW: Determine leader using native device IDs (if available)
    if (_peerNativeDeviceId != null) {
      _isLeader = LeaderAlgorithm.selectLeader(deviceId, _peerNativeDeviceId!);
      pairingLog('[CONN] 👑 Leader elected: ${_isLeader ? 'THIS DEVICE' : 'PEER DEVICE'} (using native UUIDs)');
    } else {
      // ✅ FIX: Native↔BLE kimlik karşılaştırması iki cihazda ilişkisiz sonuç
      // verir; ikisi de follower kalırsa oyun hiç başlamaz. İki taraf da lider
      // varsayılır — GameEngine'in çakışma çözümü tek lidere indirir.
      _isLeader = true;
      pairingLog('[CONN] 👑 Peer native ID yok - lider varsayılıyor (çakışma çözümü devreder)');
    }

    _setState(PairingState.connected);
    pairingLog('[CONN] ✅✅✅ PAIRING SUCCESS ✅✅✅');
    
    // ✅ Notify if app is in background (lime vibration)
    _notifyIfBackground(NomatchNotificationType.radarMatch);
  }

  /// ✅ NEW: Retry heading validation or fail after max retries
  Future<void> _retryOrFailHeadingValidation(String reason) async {
    _headingValidationRetries++;
    pairingLog('[CONN] ⚠️ Heading validation attempt $_headingValidationRetries/$_maxHeadingRetries failed: $reason');
    
    if (_headingValidationRetries >= _maxHeadingRetries) {
      pairingLog('[CONN] ❌ Max heading validation retries reached, failing pairing');
      _headingSubscription?.cancel();
      _headingSubscription = null;
      _headingValidationRetries = 0;
      await _failPairing(reason);
      return;
    }
    
    // ✅ Retry: Clear heading data and restart validation (keep connection!)
    pairingLog('[CONN] 🔄 Retrying heading validation (attempt ${_headingValidationRetries + 1})...');
    _ourHeading = null;
    _peerHeading = null;
    _peerHeadingReceived = false; // ✅ Reset peer heading flag for retry

    // ✅ UI'a kısa bir uyarı pulse'ı için sinyal gönder
    if (!_headingRetryController.isClosed) {
      _headingRetryController.add(null);
    }

    // Restart heading validation - wait for peer heading again, then validate
    _timers.schedule(_kTimerHeadingValidation, _peerHeadingWaitTimeout, () {
      pairingLog('[CONN] ⏰ Heading validation retry timer fired!');
      _completeHeadingValidation();
    });
  }

  /// Handle peer disconnected
  void handlePeerDisconnected() {
    pairingLog('[DISC] 🔌 Peer disconnected');
    
    // ✅ Don't auto-reset if discovery mode is active - disconnects are expected
    if (_discoveryOnlyMode) {
      pairingLog('[DISC] 📱 Discovery mode active - ignoring disconnect');
      return;
    }
    
    // ✅ Don't auto-reset if share screen is active - user is still viewing results
    if (_isShareScreenActive) {
      pairingLog('[DISC] ⚠️ Share screen is active - ignoring disconnect (user can manually reset)');
      return;
    }
    
    // ✅ Don't auto-reset if game is active - try to reconnect
    if (_state == PairingState.game || _state == PairingState.playing) {
      pairingLog('[DISC] 🎮 Game is active - attempting reconnect...');
      _attemptGameReconnect();
      return;
    }
    
    // ✅ FIX: Pairing phase disconnect — show broken hearts animation, then auto-retry
    pairingLog('[DISC] 💔 Pairing phase disconnect — showing failure animation');
    _reset();
    _setState(PairingState.failed);
    // PairingFailedScreen handles 4s animation → hardReset → auto-restart
  }
  
  // ✅ Game reconnect state
  bool _isReconnecting = false;
  int _gameReconnectAttempts = 0;
  static const int _maxGameReconnectAttempts = 5;
  static const Duration _gameReconnectDelay = Duration(seconds: 2);
  
  /// Is currently reconnecting during game?
  bool get isReconnecting => _isReconnecting;
  
  /// Attempt to reconnect during active game
  void _attemptGameReconnect() {
    if (_gameReconnectAttempts >= _maxGameReconnectAttempts) {
      pairingLog('[RECONNECT] ❌ Max game reconnect attempts reached — showing failure animation');
      _isReconnecting = false;
      _connectionStatusController.add(false);
      
      // ✅ FIX: Show broken hearts animation instead of silent hardReset
      _disposeGameEngine();
      _timers.cancelAll();
      _setState(PairingState.failed);
      // PairingFailedScreen handles 4s animation → hardReset → auto-restart
      return;
    }
    
    _gameReconnectAttempts++;
    _isReconnecting = true;
    _connectionStatusController.add(false);
    
    // ✅ FIX: Stop game ticker to prevent rounds from expiring during reconnect
    _timers.cancel(_kTimerGameTicker);
    pairingLog('[RECONNECT] ⏸️ Game ticker paused');
    
    pairingLog('[RECONNECT] 🔄 Game reconnect attempt $_gameReconnectAttempts/$_maxGameReconnectAttempts');
    
    _timers.schedule(_kTimerGameReconnect, _gameReconnectDelay, () async {
      if (_state != PairingState.game && _state != PairingState.playing) {
        pairingLog('[RECONNECT] ⚠️ Game ended during reconnect, stopping');
        _isReconnecting = false;
        return;
      }
      
      try {
        // Try to reconnect
        if (_peerId != null) {
          pairingLog('[RECONNECT] 🔗 Reconnecting to peer: $_peerId');
          await blePlugin.connect(peerId: _peerId!);
          
          // Wait and test connection
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Send test heartbeat
          final msg = HeartbeatMessage(
            sid: _sessionId ?? '',
          );
          await blePlugin.send(msg);
          
          // Success!
          pairingLog('[RECONNECT] ✅ Game reconnect successful!');
          _isReconnecting = false;
          _gameReconnectAttempts = 0;
          _connectionStatusController.add(true); // Notify UI: connected
          
          // ✅ FIX: Restart game ticker after successful reconnect
          _startGameTicker();
          pairingLog('[RECONNECT] ▶️ Game ticker resumed');
        }
      } catch (e) {
        pairingLog('[RECONNECT] ❌ Game reconnect attempt failed: $e');
        // Try again
        _attemptGameReconnect();
      }
    });
  }

  // ✅ Track if game is already prepared
  bool _gamePreparationDone = false;
  
  /// Prepare game - called IMMEDIATELY when pairing succeeds (during animation)
  /// This initializes the engine and preloads questions in the background
  Future<void> prepareGame() async {
    if (_gamePreparationDone) {
      pairingLog('[GAME] ⚠️ Game already prepared, skipping');
      return;
    }
    
    pairingLog('[GAME] 🎮 Preparing game (background)...');
    pairingLog('[GAME] 🎮 _sessionId=$_sessionId, _peerId=$_peerId');
    
    // Cancel any pending timeouts
    _timers.cancel(_kTimerConnectionTimeout);
    _timers.cancel(_kTimerHeadingValidation);
    // Stop compass
    await headingValidator.stop();
    
    // Initialize game engine (heavy work - done during animation)
    if (_sessionId != null && _peerId != null) {
      await _initializeGameEngine(
        sessionId: _sessionId!,
        peerId: _peerId!,
      );
      _gamePreparationDone = true;
      pairingLog('[GAME] ✅ Game preparation complete (background)');
    } else {
      pairingLog('[GAME] ❌ Cannot prepare game: _sessionId or _peerId is null!');
    }
  }
  
  /// Show game - called when animation completes
  /// This starts the ticker and transitions to game screen
  Future<void> showGame() async {
    pairingLog('[GAME] 🎮 Showing game...');
    
    // If not prepared yet, prepare now (fallback)
    if (!_gamePreparationDone) {
      pairingLog('[GAME] ⚠️ Game not prepared, preparing now...');
      await prepareGame();
    }
    
    // Start game ticker (30 FPS)
    _startGameTicker();
    
    // Transition to game phase
    _setState(PairingState.game);
    pairingLog('[GAME] ✅ Game phase started');
  }
  
  /// ✅ FIX: Ensure ticker is running when game phase requires it
  void _ensureTickerForPhase(GamePhase phase) {
    final needsTicker = phase == GamePhase.playing || 
                        phase == GamePhase.pairing || 
                        phase == GamePhase.restarting;
    final tickerActive = _timers.isActive(_kTimerGameTicker);
    
    if (needsTicker && !tickerActive && _gameEngine != null) {
      pairingLog('[GAME] 🔄 Restarting ticker for phase: $phase');
      _startGameTicker();
    }
  }
  
  /// ✅ REFACTORED: Extracted ticker start logic
  void _startGameTicker() {
    if (_gameEngine == null) return;
    
    int tickCount = 0;
    _timers.schedulePeriodic(_kTimerGameTicker, const Duration(milliseconds: 33), (_) {
      tickCount++;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (tickCount <= 5 || tickCount % 30 == 0) {
        dev.log('[GAME-TICK] tick #$tickCount, now=$now');
      }
      _gameEngine?.onTick(now);
      
      // Stop ticker when game is terminal
      if (_gameEngine?.isGameTerminal ?? false) {
        pairingLog('[GAME] 🎮 Game terminal detected - stopping ticker');
        _timers.cancel(_kTimerGameTicker);
      }
    });
    pairingLog('[GAME] 🎮 Ticker started!');
  }
  
  /// Start game - legacy method for backwards compatibility
  Future<void> startGame() async {
    await prepareGame();
    await showGame();
  }
  
  /// Initialize game engine
  Future<void> _initializeGameEngine({
    required String sessionId,
    required String peerId,
  }) async {
    pairingLog('[GAME] 🎮 Initializing game engine...');
    pairingLog('[GAME] 🎮 Questions provider: LOADED');

    // ✅ NEW: Preload questions before starting game
    pairingLog('[GAME] 📚 Preloading questions...');
    await questions.preload();
    pairingLog('[GAME] ✅ Questions preloaded');
    
    // Dispose old engine if exists
    _gameEngineSubscription?.cancel();
    _gameEngineSubscription = null;
    _gameEngine = null;
    
    // Create transport for P2P messages
    final transport = _PairingManagerTransport(blePlugin);
    
    // Create engine
    _gameEngine = GameEngine(
      transport: transport,
      isLeader: _isLeader,
      externalRoundControl: false, // ✅ FIX: Allow engine to start rounds automatically
      sessionId: sessionId,
      localDeviceId: deviceId,
      questions: questions,
    );
    
    // ✅ FIXED: Connect peer (await reshuffle completion)
    await _gameEngine!.onPeerConnected(peerId: peerId);
    
    // Subscribe to game state updates
    _gameEngineSubscription = _gameEngine!.states.listen((gameState) {
      _gameStateController.add(gameState);
      pairingLog('[GAME] 🎮 Game state: ${gameState.phase}');
      
      // ✅ FIX: Restart ticker when game restarts (phase becomes playing again)
      _ensureTickerForPhase(gameState.phase);
    });
    
    pairingLog('[GAME] ✅ Game engine initialized');
  }

  /// Fail pairing
  Future<void> _failPairing(String reason) async {
    pairingLog('[PAIR] ❌ Pairing failed: $reason');
    _reset();
    _setState(PairingState.failed);
    // PairingFailedScreen 4s animasyon sonunda hardReset() çağırır → idle.
    // Kullanıcı üçgene basarak taramayı yeniden başlatır.
  }

  /// Stop pairing (pause, not permanent cleanup)
  Future<void> stop() async {
    pairingLog('[PAIR] 🛑 Stopping pairing');
    await headingValidator.stop();
    await blePlugin.stop();
    _disposeGameEngine(); // ✅ Dispose game engine to clear all state
    _reset();
    _setState(PairingState.idle);
  }
  
  /// 🔄 HARD RESET: Complete cleanup for fresh game start
  /// Call this when returning to pairing screen after game ends
  /// This ensures BLE connections are fully cleared and ready for new pairing
  Future<void> hardReset() async {
    pairingLog('[PAIR] 🔄🔄🔄 HARD RESET STARTED 🔄🔄🔄');
    
    // 0. Stop keep-alive first
    _stopKeepAlive();
    pairingLog('[PAIR] 💓 Keep-alive stopped');
    
    // 1. Dispose game engine completely
    _disposeGameEngine();
    pairingLog('[PAIR] 🎮 Game engine disposed');
    
    // 2. Stop all timers via pool
    _timers.cancelAll();
    pairingLog('[PAIR] ⏱️ All timers cancelled');
    
    // 3. Cancel heading subscription
    _headingSubscription?.cancel();
    _headingSubscription = null;
    
    // 4. Stop heading validator
    await headingValidator.stop();
    pairingLog('[PAIR] 🧭 Heading validator stopped');
    
    // 5. Hard reset BLE plugin (most important!)
    await blePlugin.hardReset();
    pairingLog('[PAIR] 📡 BLE plugin hard reset complete');

    // ✅ FIX: blePlugin.hardReset() auto-connect'i tekrar true yapıyor.
    // Bağlantı kararları her zaman PairingManager'da kalmalı (bkz. constructor).
    blePlugin.setAutoConnect(false);
    
    // 6. Reset ALL state variables
    _peerId = null;
    _sessionId = null;
    _peerNativeDeviceId = null;
    _ourHeading = null;
    _peerHeading = null;
    _isLeader = false;
    _gamePreparationDone = false;
    _headingValidationRetries = 0;
    _lastHeadingSentTime = null;
    _peerHeadingReceived = false; // ✅ Reset peer heading flag
    _isShareScreenActive = false;
    _isReconnecting = false;
    _gameReconnectAttempts = 0;
    _connectionAttempts = 0; // ✅ Reset connection attempts
    _lastFailedPeerId = null; // ✅ Clear failed peer tracking
    _isConnected = true; // ✅ Reset connection status
    _reconnectAttempts = 0; // ✅ Reset share-screen reconnect attempts
    
    // ✅ FIX: Reset discovery/public mode state (missing before!)
    _discoveryOnlyMode = false;
    _discoveredPeers.clear();
    _pendingPublicRequests.clear();
    _discoveredPeersController.add([]); // Notify UI: no peers
    _pendingRequestsController.add(false); // Notify UI: no pending requests
    
    pairingLog('[PAIR] 🧹 All state variables reset');
    
    // 7. Emit idle state
    _setState(PairingState.idle);
    
    // 8. Small delay for BLE stack to stabilize
    await Future.delayed(const Duration(milliseconds: 200));
    
    pairingLog('[PAIR] ✅✅✅ HARD RESET COMPLETE - Ready for new pairing ✅✅✅');
  }

  /// Dispose game engine completely
  void _disposeGameEngine() {
    _gameEngineSubscription?.cancel();
    _gameEngineSubscription = null;
    // _states StreamController'ı kapat ve bekleyen timer'ları temizle.
    // Future döndürüyor ama dispose sync bağlamlarda da çağrıldığından
    // fire-and-forget kullanılıyor; hata olsa da engine zaten null'lanıyor.
    _gameEngine?.dispose();
    _gameEngine = null;
    pairingLog('[PAIR] 🎮 Game engine disposed');
  }
  
  /// Reset state
  void _reset() {
    _timers.cancelAll();
    _headingSubscription?.cancel();
    _peerId = null;
    _sessionId = null;
    _peerNativeDeviceId = null;
    _ourHeading = null;
    _peerHeading = null;
    _isLeader = false;
    _gamePreparationDone = false;
    _headingValidationRetries = 0;
    _peerHeadingReceived = false; // ✅ Reset peer heading flag
    _isShareScreenActive = false;
    _isReconnecting = false;
    _gameReconnectAttempts = 0;
    _discoveryOnlyMode = false;
    _discoveredPeers.clear();
    _pendingPublicRequests.clear();
    // UI'ı bilgilendir — stream emit edilmezse ekran eski peer'ları göstermeye devam eder
    _discoveredPeersController.add([]);
    _pendingRequestsController.add(false);
    // Note: Don't reset _connectionAttempts here - we track across resets
    pairingLog('[PAIR] 🔄 State reset complete');
  }
  
  /// Handle top card tap
  void onLocalTapTop() {
    _gameEngine?.onLocalTapTop();
  }
  
  /// Handle bottom card tap
  void onLocalTapBottom() {
    _gameEngine?.onLocalTapBottom();
  }
  
  /// Handle P2P messages for game
  void _handleGameMessage(P2pMessage message) {
    _gameEngine?.onP2pMessage(message);
  }

  /// Update state and notify
  void _setState(PairingState state) {
    _state = state;
    _stateController.add(state);
    pairingLog('[STATE] State changed to: $state');
    dev.log('[PAIR] State: $state');
  }

  /// Handle received P2P message
  /// [blePeerId] is the BLE-level device ID of the sender (from MessageReceived event)
  void _handleMessageReceived(P2pMessage message, String blePeerId) {
    // In discovery mode, refresh peer's lastSeen when we receive any message
    // This keeps connected peers fresh even though they're not being "discovered"
    if (_discoveryOnlyMode && _peerId != null) {
      final peer = _discoveredPeers[_peerId];
      if (peer != null) {
        _discoveredPeers[_peerId!] = peer.copyWith(lastSeen: DateTime.now());
        // Don't emit update here - too noisy
      }
    }
    
    // Handle public mode pairing messages
    if (message is PairIntentMessage) {
      if (_discoveryOnlyMode) {
        _handlePublicPairRequest(message.sid, blePeerId);
      } else {
        // Radar mode: store as pending request and notify UI
        // Pass BLE peer ID so the peer is stored with the correct key
        // (BLE ID matches what discovery events report, not the native device ID in message.sid)
        _handlePendingPublicRequest(message.sid, blePeerId);
      }
      return;
    } else if (message is PairAckMessage) {
      if (_discoveryOnlyMode) {
        _handlePublicPairAccept(message.sid);
      }
      return;
    } else if (message is PairRejectMessage) {
      _handlePublicPairReject(blePeerId);
      return;
    }
    
    if (message is SensorSnapshotMessage) {
      pairingLog('[CONN] 📨 P2P message received: heading=${message.headingDeg.toStringAsFixed(1)}°');
      if (message.nativeDeviceId != null) {
        _peerNativeDeviceId = message.nativeDeviceId;
        pairingLog('[CONN] 📱 Peer native device ID: $_peerNativeDeviceId');
      }
      receivePeerHeading(message.headingDeg);

      // ✅ FIX: Peripheral-side reverse connection.
      // Peripheral cihaz PeerConnected event'i hiç almıyor (sadece central alır).
      // Bu yüzden _messageChar null kalıyor ve heading gönderemiyoruz.
      // Çözüm: karşıdan ilk heading geldiğinde biz de central olarak bağlanıyoruz.
      if (_state == PairingState.peerSearching && _peerId != null && !_discoveryOnlyMode) {
        pairingLog('[CONN] 🔄 Peripheral: ilk heading alındı, reverse connection başlatılıyor → $_peerId');
        _setState(PairingState.preConnected); // Tekrar tetiklenmesin diye state'i önceden değiştir
        _timers.cancel(_kTimerConnectionTimeout);
        blePlugin.connect(peerId: _peerId!).catchError((e) {
          pairingLog('[CONN] ❌ Reverse connection başarısız: $e');
        });
      }
    } else if (_state == PairingState.game || _state == PairingState.connected) {
      // ✅ FIX: Route game messages to engine when CONNECTED or GAME
      // This ensures GameStartMessage and RoundStartMessage are not dropped
      // when they arrive before the UI transitions to game state
      if (_gameEngine != null) {
        pairingLog('[MSG] 📨 Forwarding ${message.runtimeType} to game engine (state=$_state)');
        _handleGameMessage(message);
      } else {
        pairingLog('[MSG] ⚠️ Game message ${message.runtimeType} received but engine not ready (state=$_state)');
      }
    }
  }

  /// Get pairing result
  PairingResult getResult() {
    if (_state != PairingState.connected) {
      return PairingResult(success: false, errorReason: 'not_connected');
    }

    return PairingResult(
      success: true,
      peerId: _peerId,
      sessionId: _sessionId,
      isLeader: _isLeader,
    );
  }

  /// Cleanup
  Future<void> dispose() async {
    pairingLog('[PAIR] 🛑 Cleaning up pairing manager');
    
    // ✅ Cancel all subscriptions to prevent memory leaks
    await _bleEventsSub?.cancel();
    await _gameEngineSubscription?.cancel();
    await _headingSubscription?.cancel();
    
    // ✅ Dispose dependent resources
    _timers.dispose();
    await headingValidator.dispose();
    
    // ✅ Close all stream controllers
    // Note: close() is async and handles pending events
    await _stateController.close();
    await _gameStateController.close();
    await _connectionStatusController.close();
    await _discoveredPeersController.close();
    await _pendingRequestsController.close();
    await _headingRetryController.close();
    
    pairingLog('[PAIR] ✅ Cleanup complete');
  }
}

/// Transport implementation for game engine
class _PairingManagerTransport implements GameTransport {
  final BleP2pPlugin plugin;

  _PairingManagerTransport(this.plugin);

  @override
  Future<void> send(P2pMessage msg) => plugin.send(msg);
}

/// ✅ REFACTORED: Centralized timer management
/// Prevents timer leaks and simplifies cancel/dispose
class _TimerPool {
  final Map<String, Timer> _timers = {};
  bool _disposed = false;
  
  void schedule(String id, Duration delay, void Function() callback) {
    if (_disposed) return;
    _timers[id]?.cancel();
    _timers[id] = Timer(delay, () {
      _timers.remove(id);
      if (!_disposed) callback();
    });
  }
  
  void schedulePeriodic(String id, Duration interval, void Function(Timer) callback) {
    if (_disposed) return;
    _timers[id]?.cancel();
    _timers[id] = Timer.periodic(interval, (timer) {
      if (_disposed) {
        timer.cancel();
        _timers.remove(id);
        return;
      }
      callback(timer);
    });
  }
  
  void cancel(String id) {
    _timers.remove(id)?.cancel();
  }
  
  void cancelAll() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }
  
  bool isActive(String id) => _timers[id]?.isActive ?? false;
  
  void dispose() {
    _disposed = true;
    cancelAll();
  }
}
