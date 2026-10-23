// test/unit/deposit_papers_action_test.dart
//
// إيداعُ دفعةِ أوراقٍ برسم التحصيل — **الحلقةُ تُكمَل والحصيلةُ تُفصَّل**.
//
// ═══ العطبان اللذان يحرسهما هذا الملفّ ═══
//
// `DLGS.deposit` في التصميم يودع دفعةً بقسيمةٍ واحدة، و`depositForCollection`
// في المستودع تأخذ ورقةً واحدة. فالدفعةُ حلقةٌ — وللحلقة طريقتان خاطئتان:
//
// 🔴 **أن تتوقّف عند أوّل فشل** ⇒ ثلاثةُ شيكاتٍ أُودعت واثنان لا، والقسيمةُ
//    في البنك تحمل الخمسةَ. والمستشار لا يعرف أيّها سقط.
//
// 🔴 **أن تبتلع الفشل** ⇒ «تمّ الإيداع» على شاشةٍ وشيكٌ ما زال بالخزنة.
//
// ⇒ فالعقدُ هنا: تُكمَل الحلقةُ دائماً، ويُرجَع **مَن نجح ومَن فشل** بالاسم.
//
// ⚠️ وتُقاس **الأرقامُ** لا الحالات: «أُودع شيءٌ» يمرّ على ورقةٍ واحدةٍ من
// خمس. فالاختبارُ يثبّت عددَ الاستدعاءات ومعرِّفاتِها ومعاملَ البنك.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/repositories/commercial_papers_repository.dart';
import 'package:picpos_erp/presentation/screens/commercial_papers/deposit_papers_action.dart';

class _RecordingRepo implements ICommercialPapersRepository {
  _RecordingRepo({this.failOn = const {}});

  /// معرِّفاتٌ تُلقي بدل أن تنجح — لمحاكاة الفشل الجزئيّ.
  final Set<int> failOn;

  final List<Map<String, Object?>> deposits = [];

  @override
  Future<void> depositForCollection(
    int id,
    int bankSafeId, {
    int? changedBy,
    String? notes,
  }) async {
    if (failOn.contains(id)) {
      throw StateError('Commercial paper not found: $id');
    }
    deposits.add({
      'id': id,
      'bankSafeId': bankSafeId,
      'changedBy': changedBy,
      'notes': notes,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('depositPapersForCollection', () {
    test('يودع كلَّ ورقةٍ في الدفعة مرّةً واحدةً بنفس البنك والقسيمة',
        () async {
      final repo = _RecordingRepo();

      final result = await depositPapersForCollection(
        repo: repo,
        paperIds: const [11, 12, 13],
        bankSafeId: 4,
        changedBy: 7,
        notes: 'قسيمة DEP-2026-0142',
      );

      // ⚠️ العددُ لا الحالة: «أُودع شيءٌ» يمرّ على واحدةٍ من ثلاث.
      expect(repo.deposits.length, 3);
      expect(repo.deposits.map((d) => d['id']).toList(), [11, 12, 13]);

      // البنكُ والقسيمةُ يخصّان الدفعةَ كلَّها، فيتكرّران على كلّ ورقة.
      for (final d in repo.deposits) {
        expect(d['bankSafeId'], 4);
        expect(d['changedBy'], 7);
        expect(d['notes'], 'قسيمة DEP-2026-0142');
      }

      expect(result.deposited, [11, 12, 13]);
      expect(result.failed, isEmpty);
      expect(result.allSucceeded, isTrue);
      expect(result.count, 3);
    });

    test('ورقةٌ فاشلةٌ في الوسط لا توقف البقيّة — وتُذكَر بالاسم', () async {
      final repo = _RecordingRepo(failOn: {12});

      final result = await depositPapersForCollection(
        repo: repo,
        paperIds: const [11, 12, 13],
        bankSafeId: 4,
      );

      // 🔴 لو توقّفت الحلقةُ عند ١٢ لكان هذا واحداً لا اثنَين.
      expect(repo.deposits.length, 2);
      expect(repo.deposits.map((d) => d['id']).toList(), [11, 13]);

      expect(result.deposited, [11, 13]);
      expect(result.failed.keys.toList(), [12]);
      expect(result.allSucceeded, isFalse);
      expect(result.count, 2);
    });

    test('فشلُ الجميع يُرجع حصيلةً فارغةً لا استثناءً', () async {
      final repo = _RecordingRepo(failOn: {11, 12});

      final result = await depositPapersForCollection(
        repo: repo,
        paperIds: const [11, 12],
        bankSafeId: 4,
      );

      expect(repo.deposits, isEmpty);
      expect(result.deposited, isEmpty);
      expect(result.failed.length, 2);
      expect(result.allSucceeded, isFalse);
    });

    test('دفعةٌ فارغةٌ لا تكتب شيئاً', () async {
      final repo = _RecordingRepo();

      final result = await depositPapersForCollection(
        repo: repo,
        paperIds: const [],
        bankSafeId: 4,
      );

      expect(repo.deposits, isEmpty);
      expect(result.allSucceeded, isTrue);
      expect(result.count, 0);
    });
  });
}
