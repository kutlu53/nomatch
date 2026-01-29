/// P2P Messages for BLE plugin
/// Minimal implementation for cross-platform compatibility

abstract class P2pMessage {
  Map<String, dynamic> toJson();
  String get messageType;
  
  // Base getters for compatibility
  int get v => 1;
  String get sid => '';
  String get t => messageType;
}

class SensorSnapshotMessage extends P2pMessage {
  final int v;
  final String sid;
  final bool isFlat;
  final double headingDeg;
  final int timestampMs;
  final String mid;

  SensorSnapshotMessage({
    this.v = 1,
    required this.sid,
    required this.isFlat,
    required this.headingDeg,
    required this.timestampMs,
    String? mid,
  }) : mid = mid ?? '';

  @override
  String get messageType => 'sensor_snapshot';

  @override
  Map<String, dynamic> toJson() {
    return {
      'v': v,
      'sid': sid,
      't': messageType,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'mid': mid,
      'isFlat': isFlat,
      'headingDeg': headingDeg,
      'timestampMs': timestampMs,
    };
  }

  factory SensorSnapshotMessage.fromJson(Map<String, dynamic> json) {
    return SensorSnapshotMessage(
      v: json['v'] ?? 1,
      sid: json['sid'] ?? '',
      isFlat: json['isFlat'] ?? false,
      headingDeg: (json['headingDeg'] as num?)?.toDouble() ?? 0.0,
      timestampMs: json['timestampMs'] ?? 0,
      mid: json['mid'] ?? '',
    );
  }
}

class SelectionMessage extends P2pMessage {
  final int v;  // Protocol version
  final String sid;
  final String choice;
  final int rid;
  final String mid;  // Message ID
  final int madeAtMs;  // Timestamp when made
  final int rev;  // Revision number
  final bool isFinal;

  SelectionMessage({
    this.v = 1,
    required this.sid,
    required this.choice,
    required this.rid,
    String? mid,
    int? madeAtMs,
    this.rev = 1,
    this.isFinal = true,
  })  : mid = mid ?? '',
        madeAtMs = madeAtMs ?? DateTime.now().millisecondsSinceEpoch;

  @override
  String get messageType => 'selection';

  @override
  Map<String, dynamic> toJson() {
    return {
      'v': v,
      'sid': sid,
      't': messageType,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'mid': mid,
      'rid': rid,
      'choice': choice,
      'madeAtMs': madeAtMs,
      'rev': rev,
      'isFinal': isFinal,
    };
  }

  factory SelectionMessage.fromJson(Map<String, dynamic> json) {
    return SelectionMessage(
      v: json['v'] ?? 1,
      sid: json['sid'] ?? '',
      choice: json['choice'] ?? '',
      rid: json['rid'] ?? 0,
      mid: json['mid'] ?? '',
      madeAtMs: json['madeAtMs'] ?? DateTime.now().millisecondsSinceEpoch,
      rev: json['rev'] ?? 1,
      isFinal: json['isFinal'] ?? true,
    );
  }
}

class RoundStartMessage extends P2pMessage {
  final int v;
  final String sid;
  final int rid;
  final int qid;
  final int deadlineMs;
  final String mid;
  final String leaderId;
  final String topAsset;
  final String bottomAsset;
  final int? startAtMs;

  RoundStartMessage({
    this.v = 1,
    required this.sid,
    required this.rid,
    required this.qid,
    required this.deadlineMs,
    String? mid,
    String? leaderId,
    String? topAsset,
    String? bottomAsset,
    this.startAtMs,
  })  : mid = mid ?? '',
        leaderId = leaderId ?? '',
        topAsset = topAsset ?? '',
        bottomAsset = bottomAsset ?? '';

  @override
  String get messageType => 'round_start';

  @override
  Map<String, dynamic> toJson() {
    return {
      'v': v,
      'sid': sid,
      't': messageType,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'mid': mid,
      'rid': rid,
      'qid': qid,
      'deadlineMs': deadlineMs,
      'leaderId': leaderId,
      'topAsset': topAsset,
      'bottomAsset': bottomAsset,
      if (startAtMs != null) 'startAtMs': startAtMs,
    };
  }

  factory RoundStartMessage.fromJson(Map<String, dynamic> json) {
    return RoundStartMessage(
      v: json['v'] ?? 1,
      sid: json['sid'] ?? '',
      rid: json['rid'] ?? 0,
      qid: json['qid'] ?? 0,
      deadlineMs: json['deadlineMs'] ?? 0,
      mid: json['mid'] ?? '',
      leaderId: json['leaderId'] ?? '',
      topAsset: json['topAsset'] ?? '',
      bottomAsset: json['bottomAsset'] ?? '',
      startAtMs: json['startAtMs'] as int?,
    );
  }
}

class HelloMessage extends P2pMessage {
  final int v;
  final String sid;

  HelloMessage({
    this.v = 1,
    required this.sid,
  });

  @override
  String get messageType => 'hello';

  @override
  Map<String, dynamic> toJson() {
    return {
      'v': v,
      'sid': sid,
      't': messageType,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
  }

  factory HelloMessage.fromJson(Map<String, dynamic> json) {
    return HelloMessage(
      v: json['v'] ?? 1,
      sid: json['sid'] ?? '',
    );
  }
}

class PairIntentMessage extends P2pMessage {
  final String sid;

  PairIntentMessage({required this.sid});

  @override
  String get messageType => 'pair_intent';

  @override
  Map<String, dynamic> toJson() {
    return {
      'v': 1,
      'sid': sid,
      't': messageType,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
  }

  factory PairIntentMessage.fromJson(Map<String, dynamic> json) {
    return PairIntentMessage(sid: json['sid'] ?? '');
  }
}

class PairAckMessage extends P2pMessage {
  final String sid;

  PairAckMessage({required this.sid});

  @override
  String get messageType => 'pair_ack';

  @override
  Map<String, dynamic> toJson() {
    return {
      'v': 1,
      'sid': sid,
      't': messageType,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
  }

  factory PairAckMessage.fromJson(Map<String, dynamic> json) {
    return PairAckMessage(sid: json['sid'] ?? '');
  }
}

class PairRejectMessage extends P2pMessage {
  final String sid;
  final String reason;

  PairRejectMessage({required this.sid, required this.reason});

  @override
  String get messageType => 'pair_reject';

  @override
  Map<String, dynamic> toJson() {
    return {
      'v': 1,
      'sid': sid,
      't': messageType,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'reason': reason,
    };
  }

  factory PairRejectMessage.fromJson(Map<String, dynamic> json) {
    return PairRejectMessage(
      sid: json['sid'] ?? '',
      reason: json['reason'] ?? '',
    );
  }
}

class GameStartMessage extends P2pMessage {
  final int v;
  final String sid;
  final int? startAtMs;

  GameStartMessage({
    this.v = 1,
    required this.sid,
    this.startAtMs,
  });

  @override
  String get messageType => 'game_start';

  @override
  Map<String, dynamic> toJson() {
    return {
      'v': v,
      'sid': sid,
      't': messageType,
      'ts': DateTime.now().millisecondsSinceEpoch,
      if (startAtMs != null) 'startAtMs': startAtMs,
    };
  }

  factory GameStartMessage.fromJson(Map<String, dynamic> json) {
    return GameStartMessage(
      v: json['v'] ?? 1,
      sid: json['sid'] ?? '',
      startAtMs: json['startAtMs'] as int?,
    );
  }
}

class HeartbeatMessage extends P2pMessage {
  final String sid;

  HeartbeatMessage({required this.sid});

  @override
  String get messageType => 'heartbeat';

  @override
  Map<String, dynamic> toJson() {
    return {
      'v': 1,
      'sid': sid,
      't': messageType,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
  }

  factory HeartbeatMessage.fromJson(Map<String, dynamic> json) {
    return HeartbeatMessage(sid: json['sid'] ?? '');
  }
}

class ShareOfferMessage extends P2pMessage {
  final int v;
  final String sid;
  final String kind;
  final String value;
  final String offerId;

  ShareOfferMessage({
    this.v = 1,
    required this.sid,
    required this.kind,
    required this.value,
    String? offerId,
  }) : offerId = offerId ?? '';

  @override
  String get messageType => 'share_offer';

  @override
  Map<String, dynamic> toJson() {
    return {
      'v': v,
      'sid': sid,
      't': messageType,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'offerId': offerId,
      'kind': kind,
      'value': value,
    };
  }

  factory ShareOfferMessage.fromJson(Map<String, dynamic> json) {
    return ShareOfferMessage(
      v: json['v'] ?? 1,
      sid: json['sid'] ?? '',
      kind: json['kind'] ?? '',
      value: json['value'] ?? '',
      offerId: json['offerId'] ?? '',
    );
  }
}

class ShareResponseMessage extends P2pMessage {
  final int v;
  final String sid;
  final bool accepted;
  final String decision;

  ShareResponseMessage({
    this.v = 1,
    required this.sid,
    required this.accepted,
    String? decision,
  }) : decision = decision ?? (accepted ? 'accept' : 'reject');

  @override
  String get messageType => 'share_response';

  @override
  Map<String, dynamic> toJson() {
    return {
      'v': v,
      'sid': sid,
      't': messageType,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'accepted': accepted,
      'decision': decision,
    };
  }

  factory ShareResponseMessage.fromJson(Map<String, dynamic> json) {
    return ShareResponseMessage(
      v: json['v'] ?? 1,
      sid: json['sid'] ?? '',
      accepted: json['accepted'] ?? false,
      decision: json['decision'] ?? (json['accepted'] ?? false ? 'accept' : 'reject'),
    );
  }
}

class ErrorMessage extends P2pMessage {
  final int v;
  final String sid;
  final String error;
  final String code;

  ErrorMessage({
    this.v = 1,
    required this.sid,
    required this.error,
    String? code,
  }) : code = code ?? error;

  @override
  String get messageType => 'error';

  @override
  Map<String, dynamic> toJson() {
    return {
      'v': v,
      'sid': sid,
      't': messageType,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'error': error,
      'code': code,
    };
  }

  factory ErrorMessage.fromJson(Map<String, dynamic> json) {
    return ErrorMessage(
      v: json['v'] ?? 1,
      sid: json['sid'] ?? '',
      error: json['error'] ?? '',
      code: json['code'] ?? json['error'] ?? '',
    );
  }
}
