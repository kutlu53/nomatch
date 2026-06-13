import 'dart:math' as math;
import '../../../core/debug_config.dart';
import 'question_bank.dart';

/// Lazy loading question provider - sadece ilk erişimde yüklenir
class LazyQuestionProvider implements QuestionProvider {
  QuestionProvider? _loaded;
  bool _loading = false;
  
  Future<void> _ensureLoaded() async {
    if (_loaded != null || _loading) return;
    _loading = true;
    
    try {
      questionsLog('lazy loading started');
      _loaded = await ManifestQuestionBank.loadFromAsset(
        'assets/questions/questions_manifest.json',
        seed: null,
      );
      questionsLog('lazy loading completed');
    } catch (e) {
      questionsLog('lazy loading failed: $e');
      _loaded = _FallbackQuestionProvider();
    } finally {
      _loading = false;
    }
  }
  
  @override
  QuestionPair getById(int qid) {
    if (_loaded == null) {
      return _FallbackQuestionProvider().getById(qid);
    }
    try {
      return _loaded!.getById(qid);
    } catch (e) {
      questionsLog('getById($qid) error: $e');
      return _FallbackQuestionProvider().getById(qid);
    }
  }

  @override
  int nextQid() {
    if (_loaded == null) return _FallbackQuestionProvider().nextQid();
    return _loaded!.nextQid();
  }
  
  /// Oyun başlamadan önce questions'ı yükle
  Future<void> preload() async {
    await _ensureLoaded();
  }
  
  /// Session başladığında soruları belirtilen seed ile karıştır
  Future<void> reshuffleForSession(String sessionId, [int? explicitSeed]) async {
    await _ensureLoaded();

    final int seed = explicitSeed ?? 0;
    questionsLog('reshuffling with seed: $seed');

    try {
      // Zaten yüklüyse JSON'ı yeniden okumak yerine mevcut veriden yeni sıralama üret
      if (_loaded is ManifestQuestionBank) {
        _loaded = (_loaded as ManifestQuestionBank).reorderWithSeed(seed);
      } else {
        _loaded = await ManifestQuestionBank.loadFromAsset(
          'assets/questions/questions_manifest.json',
          seed: seed,
        );
      }
      questionsLog('reshuffle completed');
    } catch (e) {
      questionsLog('ERROR during reshuffle: $e');
      if (_loaded is ManifestQuestionBank) {
        (_loaded as ManifestQuestionBank).resetIterator();
      }
    }
  }
}

class _FallbackQuestionProvider implements QuestionProvider {
  @override
  QuestionPair getById(int qid) {
    return QuestionPair(
      qid: qid,
      topAsset: 'assets/branding/logo.png',
      bottomAsset: 'assets/branding/logo.png',
    );
  }

  @override
  int nextQid() => 1;
}
