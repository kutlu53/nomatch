import 'package:flutter_test/flutter_test.dart';
import 'package:nomatch/features/game/question_bank.dart';

/// ManifestQuestionBank determinizm testleri.
///
/// Kritik: Leader ve follower AYNI seed ile AYNI soru sırasını üretmeli.
/// Sıra tutarsızlığı → oyuncular farklı görseller görür → oyun bozulur.
void main() {
  const manifest = '''
  [
    {"qid": 3, "top": "t3.webp", "bottom": "b3.webp"},
    {"qid": 1, "top": "t1.webp", "bottom": "b1.webp"},
    {"qid": 2, "top": "t2.webp", "bottom": "b2.webp"}
  ]
  ''';

  group('Yükleme ve doğrulama', () {
    test('qid sıralaması seed olmadan artan sıradadır', () {
      final bank = ManifestQuestionBank.fromJsonString(manifest);
      // Manifest 3,1,2 sırasında ama yükleme sonrası artan olmalı.
      expect(bank.nextQid(), 1);
      expect(bank.nextQid(), 2);
      expect(bank.nextQid(), 3);
    });

    test('nextQid döngüseldir (son elemandan sonra başa döner)', () {
      final bank = ManifestQuestionBank.fromJsonString(manifest);
      final seq = List.generate(7, (_) => bank.nextQid());
      expect(seq, [1, 2, 3, 1, 2, 3, 1]);
    });

    test('getById doğru çifti döndürür', () {
      final bank = ManifestQuestionBank.fromJsonString(manifest);
      final q = bank.getById(2);
      expect(q.topAsset, 't2.webp');
      expect(q.bottomAsset, 'b2.webp');
    });

    test('getById bilinmeyen qid için RangeError fırlatır', () {
      final bank = ManifestQuestionBank.fromJsonString(manifest);
      expect(() => bank.getById(999), throwsRangeError);
    });
  });

  group('Manifest hataları', () {
    test('boş dizi FormatException', () {
      expect(() => ManifestQuestionBank.fromJsonString('[]'),
          throwsFormatException);
    });

    test('dizi olmayan JSON FormatException', () {
      expect(() => ManifestQuestionBank.fromJsonString('{"qid":1}'),
          throwsFormatException);
    });

    test('eksik alanlı öğe FormatException', () {
      expect(
        () => ManifestQuestionBank.fromJsonString('[{"qid":1,"top":"t.webp"}]'),
        throwsFormatException,
      );
    });

    test('qid string ise FormatException', () {
      expect(
        () => ManifestQuestionBank.fromJsonString(
            '[{"qid":"1","top":"t","bottom":"b"}]'),
        throwsFormatException,
      );
    });
  });

  group('Seed permütasyonu (determinizm)', () {
    // 20 elemanlı manifest üret (permütasyonun görünür olması için).
    String bigManifest() {
      final items = List.generate(
        20,
        (i) => '{"qid": ${i + 1}, "top": "t${i + 1}", "bottom": "b${i + 1}"}',
      );
      return '[${items.join(',')}]';
    }

    test('aynı seed → aynı sıra (iki ayrı instance)', () {
      final a = ManifestQuestionBank.fromJsonString(bigManifest(), seed: 12345);
      final b = ManifestQuestionBank.fromJsonString(bigManifest(), seed: 12345);
      final seqA = List.generate(20, (_) => a.nextQid());
      final seqB = List.generate(20, (_) => b.nextQid());
      expect(seqA, seqB, reason: 'Aynı seed deterministik olmalı');
    });

    test('farklı seed → farklı sıra (çakışma beklenmez)', () {
      final a = ManifestQuestionBank.fromJsonString(bigManifest(), seed: 1);
      final b = ManifestQuestionBank.fromJsonString(bigManifest(), seed: 2);
      final seqA = List.generate(20, (_) => a.nextQid());
      final seqB = List.generate(20, (_) => b.nextQid());
      expect(seqA, isNot(equals(seqB)));
    });

    test('permütasyon tüm qid\'leri korur (kayıp/tekrar yok)', () {
      final a = ManifestQuestionBank.fromJsonString(bigManifest(), seed: 777);
      final seq = List.generate(20, (_) => a.nextQid());
      expect(seq.toSet(), List.generate(20, (i) => i + 1).toSet());
    });

    test('seed=0 çökmeye yol açmaz ve deterministiktir', () {
      // Kodda seed==0 özel olarak sabit bir başlangıç değerine map edilir.
      final a = ManifestQuestionBank.fromJsonString(bigManifest(), seed: 0);
      final b = ManifestQuestionBank.fromJsonString(bigManifest(), seed: 0);
      expect(List.generate(20, (_) => a.nextQid()),
          List.generate(20, (_) => b.nextQid()));
    });

    test('reorderWithSeed, constructor seed ile aynı sırayı üretir', () {
      final viaCtor =
          ManifestQuestionBank.fromJsonString(bigManifest(), seed: 4242);
      final base = ManifestQuestionBank.fromJsonString(bigManifest());
      final viaReorder = base.reorderWithSeed(4242);
      expect(List.generate(20, (_) => viaReorder.nextQid()),
          List.generate(20, (_) => viaCtor.nextQid()));
    });
  });
}
