// test/widget/bank_reconciliation_picpos_screen_test.dart
//
// تركيبُ شاشة «المطابقة البنكية» بهويّة PicPos — بعرضَين.
//
// ⚠️ **العرضان ليسا احتياطاً**: القائمتان المتجاورتان أوّلُ ما ينهار ضيقاً،
// وشاشاتٌ كاملةٌ انهارت من تركيبٍ لم يُقَس عند عرضَين.
//
// ⚠️ **وخزنةٌ بلا حسابٍ مرتبطٍ تُقصى بسطرٍ يشرح** — بلا حسابٍ لا دفترَ
// يُطابَق عليه، والصمتُ يجعلها تبدو مفقودة.
//
// ⚠️ **ولا اختيارَ تلقائيّاً لأيّ خزنة** (مراجعةٌ 2026-09-01، مأخذ ٢):
// الشاشةُ تبدأ بلا خزنةٍ مختارة، فاختبارُ الإقصاء يفتح المنتقيَ فعلاً
// (مأخذ ٧) بدل الاتّكال على اختيارٍ تلقائيٍّ يُظهر اسمَ خزنةٍ بلا تفاعل.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/domain/repositories/accounting_repository.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/presentation/accounting_picpos/bank_reconciliation_picpos_screen.dart';

// نمطُ المزيَّفات من `test/widget/analytics_picpos_screen_test.dart`:
// صنفٌ `implements` الواجهةَ، الدوالُّ المستعمَلةُ صريحةً بـ`@override`
// تعيد بياناتٍ ثابتة، و`noSuchMethod` احتياطاً للباقي — لأنّ الافتراضيَّ
// **يرمي** فيتعلّق المنتظِر.

/// خزنةٌ بنكيّة — `linked` هو `linkedAccountId`.
SafeData _bankSafe(int id, {required int? linked, String? name}) {
  return SafeData(
    id: id,
    name: name ?? 'خزنة بنكية $id',
    safeType: 'bank',
    balance: 0,
    isDefault: false,
    isActive: true,
    linkedAccountId: linked,
  );
}

class _FakeTreasury implements ITreasuryRepository {
  _FakeTreasury(this._safes);
  final List<SafeData> _safes;

  @override
  Future<List<SafeData>> getSafesList() async => _safes;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// مزيَّفٌ يلتقط الحسابَ الذي وصله `createReconciliation`، ويعيد تقريراً
/// قابلاً للتخصيص من `getReconciliationReport` — لقياسِ أنّ بطاقاتِ
/// المؤشّرات تعرض **قيمَ الخريطة المزيَّفة** لا أرقاماً ثابتةً في الشاشة.
class _FakeAccounting implements IAccountingRepository {
  _FakeAccounting({Map<String, dynamic>? report, this.sessionId = 1})
      : report = report ??
            const {
              'reconciliation': null,
              'statementBalance': 1000.0,
              'bookBalance': 1000.0,
              'difference': 0.0,
              'matchedCount': 0,
              'unmatchedCount': 0,
              'matchedLines': <dynamic>[],
              'unmatchedBankLines': <dynamic>[],
              'outstandingBookEntries': <dynamic>[],
            };

  final Map<String, dynamic> report;
  final int sessionId;

  int? createdBankAccountId;
  double? createdStatementBalance;

  @override
  Future<int> createReconciliation({
    required int bankAccountId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double statementBalance,
    int? userId,
  }) async {
    createdBankAccountId = bankAccountId;
    createdStatementBalance = statementBalance;
    return sessionId;
  }

  @override
  Future<Map<String, dynamic>> getReconciliationReport(
          int reconciliationId) async =>
      report;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<void> pump(WidgetTester tester, double width, {
  required List<SafeData> safes,
  IAccountingRepository? accounting,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        treasuryRepositoryProvider.overrideWithValue(_FakeTreasury(safes)),
        accountingRepositoryProvider
            .overrideWithValue(accounting ?? _FakeAccounting()),
      ],
      child: const MaterialApp(home: BankReconciliationPicposScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    testWidgets('الشاشةُ تُرسَم بلا فيضان عند ${width.toInt()}', (tester) async {
      await pump(tester, width, safes: [_bankSafe(1, linked: 5)]);

      expect(tester.takeException(), isNull);
      expect(find.text('المطابقة البنكية'), findsWidgets);
    });
  }

  testWidgets('🔴 خزنةٌ بلا حسابٍ مرتبطٍ تُقصى بسطرٍ يشرح', (tester) async {
    await pump(tester, 1920, safes: [
      _bankSafe(1, linked: 5, name: 'البنك الأهلي'),
      _bankSafe(2, linked: null, name: 'بنك بلا ربط'),
    ]);

    // سطرُ الشرح بنصّه الكامل — لا مطابقةً جزئيّةً على كلمة «حساب» يُرضيها
    // أيُّ نصٍّ مستقبليٍّ (مأخذ ٨: `find.textContaining` توكيدٌ ضعيف).
    expect(
      find.text('خزنةٌ بنكيّةٌ أو أكثرُ بلا حسابٍ مرتبطٍ — لا يمكن مطابقتُها'),
      findsOneWidget,
      reason: 'والإقصاءُ يُشرَح لا يُصمَت عليه',
    );

    // المرساةُ الحقيقيّة: بلا اختيارٍ تلقائيّ (مأخذ ٢)، لا اسمَ خزنةٍ يُرسَم
    // على الشاشة إطلاقاً قبل فتح المنتقي — فالاختبارُ يفتحه فعلاً وينظر
    // داخله (مأخذ ٧)، لا أن يتّكل على اختيارٍ تلقائيٍّ يُظهر اسماً بلا تفاعل.
    await tester.tap(find.text('اختر خزنة بنكية'));
    await tester.pumpAndSettle();

    expect(find.text('البنك الأهلي'), findsWidgets,
        reason: 'مرساة: المربوطةُ تظهر كخيارٍ داخل المنتقي');
    expect(find.text('بنك بلا ربط'), findsNothing,
        reason: 'بلا حسابٍ لا دفترَ يُطابَق عليه — فلا تظهر كخيار');
  });

  testWidgets('إنشاءُ جلسةٍ يعرض مؤشّراتِ التقرير الأربعة بقيمها الحقيقيّة',
      (tester) async {
    final accounting = _FakeAccounting(
      sessionId: 7,
      report: const {
        'reconciliation': null,
        'statementBalance': 15300.50,
        'bookBalance': 15250.75,
        'difference': 49.75,
        'matchedCount': 12,
        'unmatchedCount': 3,
        'matchedLines': <dynamic>[],
        'unmatchedBankLines': <dynamic>[],
        'outstandingBookEntries': <dynamic>[],
      },
    );

    await pump(
      tester,
      1920,
      safes: [_bankSafe(9, linked: 42, name: 'خزنة الاختبار')],
      accounting: accounting,
    );

    // اختيارُ الخزنة من المنتقي الحقيقيّ — لا حقن حالةٍ مباشرة.
    await tester.tap(find.text('اختر خزنة بنكية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خزنة الاختبار'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تطبيق'));
    await tester.pumpAndSettle();

    // رصيدُ كشفٍ صالح — بصيغة الفاصلة العشرالفيّة التي تعرضها الشاشةُ
    // نفسُها (مأخذ ٣: يجب أن تُقبَل لا أن تُرفَض بصفرٍ صامت).
    await tester.enterText(find.byType(TextField), '15,300.50');
    await tester.pumpAndSettle();

    await tester.tap(find.text('جلسة جديدة'));
    await tester.pumpAndSettle();

    expect(accounting.createdBankAccountId, 42,
        reason: 'الجلسةُ يجب أن تُفتَح على حساب الخزنة المختارة لا خزنةٍ '
            'أخرى');
    expect(accounting.createdStatementBalance, 15300.50,
        reason: 'رصيدُ الكشف المُدخَل بفاصلةٍ يجب أن يُحلَّل صحيحاً — لا '
            'يسقط إلى صفرٍ صامت');

    expect(find.text('15,250.75'), findsWidgets,
        reason: 'رصيدُ الدفتر يجب أن يأتي من `getReconciliationReport` '
            'المزيَّف');
    expect(find.text('15,300.50'), findsWidgets,
        reason: 'رصيدُ الكشف يجب أن يأتي من التقرير المزيَّف');
    expect(find.text('49.75'), findsWidgets,
        reason: 'الفرقُ يجب أن يأتي من التقرير المزيَّف');
    expect(find.text('12 / 3'), findsWidgets,
        reason: 'مطابَق/غيرُ مطابَق يجب أن يأتيا من التقرير المزيَّف');
  });
}
