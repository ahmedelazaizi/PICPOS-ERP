// test/widget/cheques_picpos_actions_test.dart
//
// عمودُ «إجراء» و«إيداع دفعة شيكات» — البندان الباقيان من رأس التصميم.
//
// ═══ الفجوةُ المقيسة ═══
//
// `HEADS.main.alt` = «إيداع دفعة شيكات»، وجداولُ `main:in`/`main:out` تضع
// **زرّاً في كلّ صفٍّ يتبع حالتَه** (‏إيداع · تحصيل · تجيير · إعادة إيداع ·
// عرض). والفوركُ كان بسبعة أعمدةٍ آخرُها «الحالة» — يعرض ولا يُنقل.
//
// ═══ وما يحرسه هذا الملفّ فعلاً ═══
//
// 🔴 **أنّ كلَّ زرٍّ يقع على نداءٍ يقبله الـDAO.** مقيسٌ في
//    `commercial_papers_dao.dart` أنّ `depositForCollection` يحرس نفسَه بـ
//    `if (!['pending','in_portfolio'].contains(paper.status)) throw` — فزرُّ
//    «إعادة إيداع» على ورقةٍ مرتجعةٍ لو وُجّه إليه لألقى **دائماً**. ومسارُه
//    الصحيحُ `updatePaperStatus(id,'deposited')`.
//
// 🔴 **وأنّ «مودع» حالتان لا واحدة**: `deposited` و`deposited_for_collection`
//    كلتاهما «عند البنك تحت التحصيل» في المبدِّل المحاسبيّ. وقراءةُ الأولى
//    وحدَها تُسقط كلَّ ورقةٍ أُودعت عبر `depositForCollection` من شريحة
//    «مودعة» ومن حسبة KPI — أيْ أنّ الإيداعَ ينجح والورقةُ تختفي.
//
// ⚠️ **ولا تُقاس بـ«لم ينهر»**: يُقاس **نصُّ الزرّ** لأنّ الخطأ الوارد هو
//    زرٌّ صحيحُ المظهر على مسارٍ خاطئ.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/commercial_papers_repository.dart'
    show ICommercialPapersRepository;
import 'package:ural_erp/presentation/settings_picpos/screens/cheques_picpos_screen.dart';

CommercialPaperData _paper({
  required int id,
  required String status,
  String direction = 'received',
  String type = 'cheque',
  String? number,
  double amount = 1000,
}) =>
    CommercialPaperData(
      id: id,
      paperNumber: number ?? 'CHQ-$id',
      type: type,
      direction: direction,
      partyId: 1,
      amount: amount,
      issueDate: DateTime(2026, 8, 1),
      dueDate: DateTime(2026, 9, 1),
      status: status,
      createdAt: DateTime(2026, 8, 1),
      rowVersion: 0,
    );

class _FakePapersRepo implements ICommercialPapersRepository {
  _FakePapersRepo(this.papers);

  final List<CommercialPaperData> papers;

  @override
  Stream<List<CommercialPaperData>> watchCommercialPapers({
    String? direction,
    String? status,
  }) =>
      Stream.value(papers);

  @override
  Stream<List<PaperStatusHistoryData>> watchPaperHistory(int id) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTreasuryRepo implements ITreasuryRepository {
  @override
  Future<List<SafeData>> getSafesList() async => const [
        SafeData(
          id: 4,
          name: 'بنك مصر — المعادي',
          safeType: 'bank',
          balance: 0,
          isDefault: false,
          isActive: true,
          accountNumber: '4471-882-1',
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(
  WidgetTester tester,
  double width, {
  required List<CommercialPaperData> papers,
  bool canWrite = true,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  const perm = 'commercial_papers_manage';

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        commercialPapersRepositoryProvider
            .overrideWithValue(_FakePapersRepo(papers)),
        treasuryRepositoryProvider.overrideWithValue(_FakeTreasuryRepo()),
        allPartiesProvider.overrideWith(
          (ref) => Stream.value(const <Party>[]),
        ),
        currentUserPermissionsProvider
            .overrideWith((ref) async => canWrite ? const [perm] : const []),
        // ⚠️ عمودُ «إجراء» يقرأ `hasPermissionProvider` لا القائمةَ الخامَّ —
        //    فهو المسارُ الذي فيه تجاوزُ مدير النظام. يُغطّى صراحةً.
        hasPermissionProvider(perm).overrideWith((ref) async => canWrite),
      ],
      child: const MaterialApp(home: ChequesPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    group('عرض $w', () {
      testWidgets('«إيداع دفعة شيكات» حاضرٌ في الرأس', (tester) async {
        await _open(tester, width, papers: [_paper(id: 1, status: 'pending')]);

        expect(find.text('إيداع دفعة شيكات'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('عمودُ «إجراء» موجودٌ في الجدول', (tester) async {
        await _open(tester, width, papers: [_paper(id: 1, status: 'pending')]);

        expect(find.text('إجراء'), findsWidgets);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('واردةٌ بالخزنة ⇒ «إيداع»', (tester) async {
        await _open(tester, width, papers: [_paper(id: 1, status: 'pending')]);

        expect(find.text('إيداع'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('كمبيالةٌ بالخزنة ⇒ «تجيير» لا «إيداع»', (tester) async {
        // 🔴 الإيداعُ البنكيُّ لورقةٍ لا بنكَ لها بلا معنى — والتصميمُ يضع
        //    «تجيير» في صفّها بالضبط.
        await _open(
          tester,
          width,
          papers: [_paper(id: 1, status: 'pending', type: 'promissory_note')],
        );

        expect(find.text('تجيير'), findsOneWidget);
        expect(find.text('إيداع'), findsNothing);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('مرتجعةٌ ⇒ «إعادة إيداع»', (tester) async {
        await _open(tester, width, papers: [_paper(id: 1, status: 'bounced')]);

        expect(find.text('إعادة إيداع'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('محصَّلةٌ ⇒ «عرض» لا كتابة', (tester) async {
        await _open(tester, width, papers: [_paper(id: 1, status: 'cashed')]);

        expect(find.text('عرض'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('صادرةٌ قائمةٌ ⇒ «تسجيل خصم» لا «إيداع»', (tester) async {
        await _open(
          tester,
          width,
          papers: [_paper(id: 1, status: 'pending', direction: 'issued')],
        );

        // تبويبةُ «الصادرة» هي الثانية.
        await tester.tap(find.text('الصادرة').first);
        await tester.pumpAndSettle();

        expect(find.text('تسجيل خصم'), findsOneWidget);
        expect(find.text('إيداع'), findsNothing);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets('بلا صلاحيةٍ ⇒ «عرض» وحدَه ولا زرَّ كتابةٍ في الصفّ',
          (tester) async {
        await _open(
          tester,
          width,
          papers: [_paper(id: 1, status: 'pending')],
          canWrite: false,
        );

        expect(find.text('عرض'), findsOneWidget);
        expect(find.text('إيداع'), findsNothing);
        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });

      testWidgets(
          'المُودعةُ برسم التحصيل تُقرأ «مودعة» — لا تختفي بعد الإيداع',
          (tester) async {
        // 🔴 عينُ العطب: `depositForCollection` يكتب
        //    `deposited_for_collection`، فقراءةُ `== 'deposited'` وحدَها
        //    تُسقط الورقةَ من الرقاقة ومن KPI ومن رقاقة الحالة.
        await _open(
          tester,
          width,
          papers: [_paper(id: 1, status: 'deposited_for_collection')],
        );

        // رقاقةُ الحالة تقرأ عربيّاً لا السلسلةَ الإنجليزيّةَ خامّةً.
        expect(find.text('deposited_for_collection'), findsNothing);
        expect(find.text('برسم التحصيل'), findsOneWidget);

        // والفعلُ التالي تحصيلٌ لا إيداعٌ ثانٍ.
        expect(find.text('تحصيل'), findsOneWidget);

        expect(tester.takeException(), isNull);
        await _teardown(tester);
      });
    });
  }
}
