// المرحلة 7 — إعادة إنتاج عيبَي التحقق الحي 2026-11-03 (البندان 4 و6).
//
// التسلسل الحي نفسه على الصندوق النقدي الافتراضي (مرتبط بحساب فرعي):
// بيع نقدي ← مصروف نقدي 10 (سند صرف) ← سند قبض نقدي 10، وتابا «لوحة القيادة»
// و«الخزينة» مفتوحان طوال الجلسة (التابات تبقى مبنية في `IndexedStack`)،
// فالمزوّدات هنا تُستمَع منذ البداية ولا تُبنى من جديد قبل كل قراءة.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/dashboard_filter_provider.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/data/repositories/treasury_repository_impl.dart';
import 'package:picpos_erp/services/accounting_service.dart';

import '../scenarios/scenario_world.dart';

void main() {
  late ScenarioWorld world;
  late ProviderContainer app;

  setUp(() async {
    world = await ScenarioWorld.create();
    app = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(world.db),
      branchScopeProvider
          .overrideWith((ref) async => const BranchScope.fullAccess()),
      // نفس كسر الدورة في ScenarioWorld: accountingService ↔ treasuryRepo.
      accountingServiceProvider.overrideWith((ref) => AccountingService(
            ref.watch(accountingRepositoryProvider),
            ref.watch(partiesRepositoryProvider),
            TreasuryRepositoryImpl(world.db, ref),
            ref.watch(productRepositoryProvider),
            ref.watch(inventoryRepositoryProvider),
            ref.watch(settingsRepositoryProvider),
            ref.watch(auditRepositoryProvider),
          )),
    ]);
  });
  tearDown(() async {
    app.dispose();
    await world.dispose();
  });

  /// يترك تيارات drift ومزوّدات Riverpod تستقرّ بعد كتابةٍ ما.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<double> dbSafeBalance() => world.safeBalance();

  Future<double> watchedSafeBalance() async {
    final safes = await app.read(scopedSafesProvider.future);
    return safes.singleWhere((s) => s.id == world.cashSafeId).balance;
  }

  Future<void> cashExpense10() async {
    await app.read(treasuryRepositoryProvider).createPaymentVoucher(
          amount: 10,
          category: 'other_expense',
          description: 'phase7 cash expense',
          safeId: world.cashSafeId,
          userId: world.userId,
        );
  }

  Future<void> cashReceipt10(int customerId) async {
    await app.read(treasuryRepositoryProvider).createReceiptVoucher(
          amount: 10,
          category: 'customers',
          partyId: customerId,
          safeId: world.cashSafeId,
          userId: world.userId,
          description: 'phase7 cash receipt',
        );
  }

  test(
      'treasury reconciliation and safe watchers follow every live step '
      '(sale → cash expense → cash receipt)', () async {
    final product = await world.addProduct('P7-REC', price: 100, cost: 60, stock: 5);
    final customer = await world.addCustomer('P7 customer');
    // تابا اللوحة والخزينة مفتوحان منذ الدخول.
    app.listen(scopedSafesProvider, (_, _) {});
    app.listen(dashboardCashBalanceProvider, (_, _) {});
    app.listen(cashBoxLedgerReconciliationProvider, (_, _) {});
    expect(await watchedSafeBalance(), closeTo(await dbSafeBalance(), kEps));

    final steps = <String, Future<void> Function()>{
      'cash sale': () => world.sell([world.line(product, 1, 100)]),
      'cash expense 10': cashExpense10,
      'cash receipt 10': () => cashReceipt10(customer),
    };
    // كل التعارضات تُجمع لكل خطوة ثم يُفحص الكل، ليُظهر الفشلُ القصةَ كاملة.
    final mismatches = <String>[];
    void check(String what, double? actual, double expected) {
      if (actual == null || (actual - expected).abs() > kEps) {
        mismatches.add('$what: actual=$actual expected=$expected');
      }
    }

    for (final step in steps.entries) {
      await step.value();
      await settle();
      final stored = await dbSafeBalance();

      check('${step.key} / scopedSafesProvider', await watchedSafeBalance(), stored);
      check('${step.key} / dashboard cash card',
          app.read(dashboardCashBalanceProvider).value, stored);

      // حوار «مراجعة الأرصدة» ← قسم «الخزائن».
      final discrepancies =
          await app.read(reconciliationServiceProvider).reconcileSafes();
      for (final d in discrepancies) {
        mismatches.add('${step.key} / reconcileSafes: stored=${d.cachedValue} '
            'calculated=${d.calculatedValue} diff=${d.difference}');
      }

      // مزوّد المرحلة 6ب: رصيد الصندوق يطابق القاعدة والفرق = صندوق − أستاذ.
      final ledger =
          await app.read(cashBoxLedgerReconciliationProvider.future);
      final cashName = (await world.db.getSafeById(world.cashSafeId))!.name;
      final cash = ledger.singleWhere((c) => c.safeName == cashName);
      check('${step.key} / ledger provider safeBalance', cash.safeBalance, stored);
      check('${step.key} / ledger provider difference', cash.difference, 0);
    }
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });

  test('dashboard KPIs refresh after a sale while the dashboard tab stays open',
      () async {
    final product = await world.addProduct('P7-KPI', price: 100, cost: 60, stock: 5);
    app.listen(dashboardKpiProvider, (_, _) {});
    final before = await app.read(dashboardKpiProvider.future);
    expect(before.invoiceCount, 0);
    expect(before.revenue, closeTo(0, kEps));

    await world.sell([world.line(product, 1, 100)]);
    await settle();

    // ضابط: مزوّدٌ مبنيٌّ من جديد يقرأ الرقم الصحيح ⇒ الاستعلام سليم.
    final fresh = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(world.db),
      branchScopeProvider
          .overrideWith((ref) async => const BranchScope.fullAccess()),
    ]);
    addTearDown(fresh.dispose);
    final freshKpi = await fresh.read(dashboardKpiProvider.future);
    expect(freshKpi.invoiceCount, 1);
    expect(freshKpi.revenue, closeTo(100, kEps));

    // العيب: التاب المفتوح يحتفظ بلقطة ما قبل البيع.
    final live = await app.read(dashboardKpiProvider.future);
    expect(live.invoiceCount, 1, reason: 'open dashboard kept pre-sale snapshot');
    expect(live.revenue, closeTo(100, kEps));
  });
}
