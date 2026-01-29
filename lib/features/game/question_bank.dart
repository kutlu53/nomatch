import 'dart:convert';

import 'package:flutter/services.dart';

/// A "question" is purely two images: top + bottom.
final class QuestionPair {
  final int qid;
  final String topAsset;
  final String bottomAsset;

  const QuestionPair({
    required this.qid,
    required this.topAsset,
    required this.bottomAsset,
  });

  factory QuestionPair.fromJson(Map<String, dynamic> json) {
    final qid = json['qid'];
    final top = json['top'];
    final bottom = json['bottom'];
    if (qid is! int || top is! String || bottom is! String) {
      throw const FormatException('Invalid question manifest item');
    }
    return QuestionPair(qid: qid, topAsset: top, bottomAsset: bottom);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'qid': qid,
        'top': topAsset,
        'bottom': bottomAsset,
      };
}

/// Deterministic question source used by leader-side qid selection.
abstract class QuestionProvider {
  int nextQid();
  QuestionPair getById(int qid);
}

/// Loads `assets/questions/questions_manifest.json` and provides deterministic qid iteration.
///
/// Determinism:
/// - QIDs are sorted ascending at load time.
/// - `nextQid()` returns the next id in that stable order (cyclic).
/// - Optional `seed` can produce a deterministic permutation (still cyclic).
final class ManifestQuestionBank implements QuestionProvider {
  final List<int> _order; // deterministic order
  final Map<int, QuestionPair> _byId;
  int _i = 0;

  ManifestQuestionBank._(this._order, this._byId);

  static Future<ManifestQuestionBank> loadFromAsset(
    String assetPath, {
    int? seed,
  }) async {
    final raw = await rootBundle.loadString(assetPath);
    return ManifestQuestionBank.fromJsonString(raw, seed: seed);
  }

  factory ManifestQuestionBank.fromJsonString(
    String jsonStr, {
    int? seed,
  }) {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! List) throw const FormatException('Manifest must be a JSON array');

    final byId = <int, QuestionPair>{};
    for (final item in decoded) {
      if (item is! Map) throw const FormatException('Manifest item must be an object');
      final pair = QuestionPair.fromJson(item.cast<String, dynamic>());
      byId[pair.qid] = pair;
    }
    if (byId.isEmpty) throw const FormatException('Manifest is empty');

    final order = byId.keys.toList()..sort();
    final seededOrder = seed == null ? order : _seededPermutation(order, seed);
    return ManifestQuestionBank._(seededOrder, byId);
  }

  @override
  int nextQid() {
    if (_order.isEmpty) throw StateError('QuestionBank has no items');
    final qid = _order[_i];
    _i = (_i + 1) % _order.length;
    return qid;
  }

  @override
  QuestionPair getById(int qid) {
    final v = _byId[qid];
    if (v == null) throw RangeError('Unknown qid: $qid');
    return v;
  }
}

// Deterministic permutation using a tiny xorshift32 PRNG (no dart:math Random).
List<int> _seededPermutation(List<int> sorted, int seed) {
  final a = List<int>.of(sorted);
  var s = seed == 0 ? 0x6d2b79f5 : seed;

  int nextU32() {
    // xorshift32
    s ^= (s << 13) & 0xFFFFFFFF;
    s ^= (s >> 17) & 0xFFFFFFFF;
    s ^= (s << 5) & 0xFFFFFFFF;
    s &= 0xFFFFFFFF;
    return s;
  }

  for (var i = a.length - 1; i > 0; i--) {
    final j = nextU32() % (i + 1);
    final tmp = a[i];
    a[i] = a[j];
    a[j] = tmp;
  }
  return a;
}

