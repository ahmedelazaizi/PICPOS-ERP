// test/widget/bank_reconciliation_picpos_screen_test.dart
//
// تركيبُ شاشة «المطابقة البنكية» بهويّة PicPos — بعرضَين.
//
// ⚠️ **العرضان ليسا احتياطاً**: القائمتان المتجاورتان أوّلُ ما ينهار ضيقاً،
// وشاشاتٌ كاملةٌ انهارت من تركيبٍ لم يُقَس عند عرضَين.
//
// ⚠️ **وخزنةٌ بلا حسابٍ مرتبطٍ تُقصى بسطرٍ يشرح** — بلا حسابٍ لا دفترَ
// يُطابَق عليه، والصمتُ يجعلها تبدو مفقودة.
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

class _FakeAccounting implements IAccountingRepository {
  @override
  Future<int> createReconciliation({
    required int bankAccountId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double statementBalance,
    int? userId,
  }) async =>
      1;

  @override
  Future<Map<String, dynamic>> getReconciliationReport(
          int reconciliationId) async =>
      {
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

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<void> pump(WidgetTester tester, double width, {
  required List<SafeData> safes,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        treasuryRepositoryProvider.overrideWithValue(_FakeTreasury(safes)),
        accountingRepositoryProvider.overrideWithValue(_FakeAccounting()),
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

    expect(find.text('البنك الأهلي'), findsWidgets,
        reason: 'مرساة: المربوطةُ تظهر');
    expect(find.text('بنك بلا ربط'), findsNothing,
        reason: 'بلا حسابٍ لا دفترَ يُطابَق عليه');
    expect(find.textContaining('حساب'), findsWidgets,
        reason: 'والإقصاءُ يُشرَح لا يُصمَت عليه');
  });
}
