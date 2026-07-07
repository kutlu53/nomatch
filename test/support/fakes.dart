import 'dart:async';

import 'package:nomatch/features/game/game_engine.dart';
import 'package:nomatch/features/game/question_bank.dart';
import 'package:nomatch/plugins/p2p/p2p_messages.dart';

/// Testlerde GameEngine'in gönderdiği tüm mesajları yakalayan sahte transport.
class FakeTransport implements GameTransport {
  final List<P2pMessage> sent = <P2pMessage>[];

  /// Bir sonraki send çağrısında hata fırlatmak için (BLE kopması simülasyonu).
  bool throwOnSend = false;

  @override
  Future<void> send(P2pMessage msg) async {
    if (throwOnSend) {
      throw StateError('fake transport disconnected');
    }
    sent.add(msg);
  }

  List<T> ofType<T>() => sent.whereType<T>().toList();
  T? lastOfType<T>() {
    final list = ofType<T>();
    return list.isEmpty ? null : list.last;
  }

  int countOfType<T>() => ofType<T>().length;

  void clear() => sent.clear();
}

/// Deterministik, döngüsel qid üreten sahte soru sağlayıcı.
/// Gerçek ManifestQuestionBank/LazyQuestionProvider olmadığı için
/// GameEngine reshuffle adımını atlar (asset yüklemesi tetiklenmez).
class SeqQuestions implements QuestionProvider {
  final List<int> ids;
  int _i = 0;

  SeqQuestions(this.ids);

  @override
  int nextQid() {
    final qid = ids[_i % ids.length];
    _i++;
    return qid;
  }

  @override
  QuestionPair getById(int qid) => QuestionPair(
        qid: qid,
        topAsset: 'assets/q/${qid}_top.webp',
        bottomAsset: 'assets/q/${qid}_bottom.webp',
      );
}

/// Bir koşul sağlanana kadar gerçek event loop'u ilerletir (zamanlayıcı bekleyen
/// senaryolar için). flutter_test gerçek zamanlı çalıştığından poll yeterli.
Future<void> pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('pumpUntil timed out${reason == null ? '' : ': $reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 8));
  }
}
