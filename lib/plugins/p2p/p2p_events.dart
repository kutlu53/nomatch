/// P2P Events for BLE plugin
/// Minimal implementation for cross-platform compatibility

import 'p2p_messages.dart';

enum P2pState { idle, discovering, hosting, connecting, connected }

enum P2pErrorCode { internal, bluetooth, network }

enum DisconnectReason { transportLost, userInitiated }

abstract class NomatchP2pEvent {
  const NomatchP2pEvent();
}

class P2pStateChanged extends NomatchP2pEvent {
  final P2pState state;
  final String? sessionId;

  const P2pStateChanged({required this.state, required this.sessionId});
}

class PeerDiscovered extends NomatchP2pEvent {
  final String peerId;
  final int rssi;
  final Map<String, String> meta;

  const PeerDiscovered({
    required this.peerId,
    required this.rssi,
    required this.meta,
  });
}

class PeerConnected extends NomatchP2pEvent {
  final String sessionId;
  final String peerId;
  final bool isLeader;

  const PeerConnected({
    required this.sessionId,
    required this.peerId,
    required this.isLeader,
  });
}

class PeerDisconnected extends NomatchP2pEvent {
  final String? sessionId;
  final String peerId;
  final DisconnectReason reason;

  const PeerDisconnected({
    required this.sessionId,
    required this.peerId,
    required this.reason,
  });
}

class MessageReceived extends NomatchP2pEvent {
  final String sessionId;
  final String fromPeerId;
  final P2pMessage message;

  const MessageReceived({
    required this.sessionId,
    required this.fromPeerId,
    required this.message,
  });
}

class P2pErrorEvent extends NomatchP2pEvent {
  final P2pErrorCode code;
  final String message;
  final Map<String, dynamic> details;

  const P2pErrorEvent({
    required this.code,
    required this.message,
    required this.details,
  });
}
