import 'dart:developer' as dev;
import 'dart:math' as math;
import 'question_bank.dart';

/// Lazy loading question provider - sadece ilk erişimde yüklenir
class LazyQuestionProvider implements QuestionProvider {
  QuestionProvider? _loaded;
  bool _loading = false;
  
  Future<void> _ensureLoaded() async {
    if (_loaded != null || _loading) {
      dev.log("QUESTIONS: _ensureLoaded - already loaded or loading: _loaded=${_loaded != null}, _loading=$_loading");
      return;
    }
    _loading = true;
    
    try {
      dev.log("QUESTIONS: lazy loading started (without seed - will be set by reshuffleForSession)");
      // ✅ Load without seed - reshuffleForSession will set the proper seed
      _loaded = await ManifestQuestionBank.loadFromAsset(
        'assets/questions/questions_manifest.json',
        seed: null,  // ✅ No seed initially
      );
      dev.log("QUESTIONS: lazy loading completed - _loaded is now ${_loaded != null ? "LOADED" : "NULL"}");
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
      final fallback = _FallbackQuestionProvider().getById(qid);
      dev.log("QUESTIONS: fallback getById($qid) -> top=${fallback.topAsset}, bottom=${fallback.bottomAsset}");
      return fallback;
    }
    try {
      final pair = _loaded!.getById(qid);
      dev.log("QUESTIONS: getById($qid) -> top=${pair.topAsset}, bottom=${pair.bottomAsset}");
      return pair;
    } catch (e) {
      dev.log("QUESTIONS: getById($qid) error: $e, using fallback");
      return _FallbackQuestionProvider().getById(qid);
    }
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
  
  /// Session başladığında soruları belirtilen seed ile karıştır
  Future<void> reshuffleForSession(String sessionId, [int? explicitSeed]) async {
    // Eğer henüz load olmadıysa load et
    await _ensureLoaded();
    
    // ✅ Use explicit seed if provided (from leader), otherwise use default
    final int seed = explicitSeed ?? 0;
    dev.log("QUESTIONS: reshuffling with seed: $seed");
    
    try {
      // ✅ Completely reload with seed
      _loaded = await ManifestQuestionBank.loadFromAsset(
        'assets/questions/questions_manifest.json',
        seed: seed,
      );
      dev.log("QUESTIONS: ✅ reshuffle completed - new order with seed=$seed");
    } catch (e) {
      dev.log("QUESTIONS: ❌ ERROR during reshuffle: $e");
      // Fallback: error durumunda iterator reset et
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
