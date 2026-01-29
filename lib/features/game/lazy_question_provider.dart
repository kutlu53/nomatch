import 'dart:developer' as dev;
import 'dart:math' as math;
import 'question_bank.dart';

/// Lazy loading question provider - sadece ilk erişimde yüklenir
class LazyQuestionProvider implements QuestionProvider {
  QuestionProvider? _loaded;
  bool _loading = false;
  
  Future<void> _ensureLoaded() async {
    if (_loaded != null || _loading) return;
    _loading = true;
    
    try {
      dev.log("QUESTIONS: lazy loading started");
      // Random seed for question shuffling
      final seed = math.Random().nextInt(1000000);
      dev.log("QUESTIONS: using random seed: $seed");
      _loaded = await ManifestQuestionBank.loadFromAsset(
        'assets/questions/questions_manifest.json',
        seed: seed,
      );
      dev.log("QUESTIONS: lazy loading completed with shuffled questions");
    } catch (e) {
      dev.log("QUESTIONS: lazy loading failed: $e");
      _loaded = _FallbackQuestionProvider();
    } finally {
      _loading = false;
    }
  }
  
  @override
  QuestionPair getById(int qid) {
    if (_loaded == null) {
      // Henüz yüklenmemişse fallback döndür
      dev.log("QUESTIONS: getById called before loading, using fallback");
      return _FallbackQuestionProvider().getById(qid);
    }
    return _loaded!.getById(qid);
  }

  @override
  int nextQid() {
    if (_loaded == null) {
      // Henüz yüklenmemişse fallback döndür
      dev.log("QUESTIONS: nextQid called before loading, using fallback");
      return _FallbackQuestionProvider().nextQid();
    }
    return _loaded!.nextQid();
  }
  
  /// Oyun başlamadan önce questions'ı yükle
  Future<void> preload() async {
    await _ensureLoaded();
  }
  
  /// Session başladığında soruları yeniden karıştır
  Future<void> reshuffleForSession(String sessionId) async {
    // Session ID'den deterministic seed üret
    final seed = sessionId.hashCode.abs() % 1000000;
    dev.log("QUESTIONS: reshuffling with session-based seed: $seed (from sessionId: $sessionId)");
    
    _loaded = await ManifestQuestionBank.loadFromAsset(
      'assets/questions/questions_manifest.json',
      seed: seed,
    );
    
    dev.log("QUESTIONS: reshuffle completed - both devices will have same order");
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
