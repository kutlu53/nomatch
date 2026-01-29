/// P2P Message Codec for BLE plugin
/// Minimal implementation for cross-platform compatibility

import 'dart:convert';
import 'p2p_messages.dart';

class P2pCodec {
  /// Decode JSON string to P2pMessage
  P2pMessage decode(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final type = json['t'] as String? ?? '';

      switch (type) {
        case 'hello':
          return HelloMessage.fromJson(json);
        case 'sensor_snapshot':
          return SensorSnapshotMessage.fromJson(json);
        case 'selection':
          return SelectionMessage.fromJson(json);
        case 'round_start':
          return RoundStartMessage.fromJson(json);
        case 'pair_intent':
          return PairIntentMessage.fromJson(json);
        case 'pair_ack':
          return PairAckMessage.fromJson(json);
        case 'pair_reject':
          return PairRejectMessage.fromJson(json);
        case 'game_start':
          return GameStartMessage.fromJson(json);
        case 'heartbeat':
          return HeartbeatMessage.fromJson(json);
        case 'share_offer':
          return ShareOfferMessage.fromJson(json);
        case 'share_response':
          return ShareResponseMessage.fromJson(json);
        case 'error':
          return ErrorMessage.fromJson(json);
        default:
          throw Exception('Unknown message type: $type');
      }
    } catch (e) {
      throw Exception('Failed to decode message: $e');
    }
  }

  /// Encode P2pMessage to JSON string
  String encode(P2pMessage message) {
    return jsonEncode(message.toJson());
  }
}
