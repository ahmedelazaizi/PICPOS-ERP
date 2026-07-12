// ═════════════════════════════════════════════════════════════════════════
// Spec 115 — Parties Screen Rebuild Loop integration test
//
// 3 سيناريوهات تُختبر الإصلاحات الثلاث L3/L1/L2:
//   - Scenario A (L3): AsyncLoading transient على branchScopeProvider
//   - Scenario B (L1): no-op writes على جدول parties
//   - Scenario C (L2): burst writes متلاحقة (محاكاة multi-client)
//
// كل سيناريو يفشل قبل تطبيق الطبقة المُقابلة (وما قبلها)، وينجح بعدها.
// الـ assertions تطابق الـ POST-fix expected counts (بعد L3 + L1 + L2).
//
// مرجع: specs/115-parties-rebuild-loop/research.md
// FR-006a in spec.md
// ═════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';

void main() {
  group('Spec 115 — parties rebuild loop', () {
    late AppDatabase db;
    late int partyId1;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.syncDefaultAccounts();

      partyId1 = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'Test Customer 1',
              isCustomer: const Value(true),
              isSupplier: const Value(false),
              globalId: const Value('gid-party-1'),
              balance: const Value(0),
              creditLimit: const Value(1000),
              isGlobal: const Value(true),
            ),
          );
      await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'Test Customer 2',
              isCustomer: const Value(true),
              isSupplier: const Value(false),
              globalId: const Value('gid-party-2'),
              balance: const Value(500),
              creditLimit: const Value(2000),
              isGlobal: const Value(true),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    /// يبني ProviderContainer مع overrides تُحاكي server-mode admin:
    /// - databaseProvider → in-memory db
    /// - branchScopeProvider → fullAccess
    ProviderContainer buildContainer() {
      return ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          branchScopeProvider.overrideWith(
            (ref) async => const BranchScope.fullAccess(),
          ),
        ],
      );
    }

    /// يستمع لـ allPartiesProvider ويحسب emissions ذات data.
    /// يحفظ subscription مفتوحة (autoDispose-safe).
    _EmissionCounter trackEmissions(ProviderContainer container) {
      final counter = _EmissionCounter();
      counter.sub = container.listen<AsyncValue<List<Party>>>(
        allPartiesProvider,
        (prev, next) {
          next.whenData((list) {
            counter.count++;
            counter.lastList = list;
            counter.onEmission?.complete();
            counter.onEmission = null;
          });
        },
        fireImmediately: true,
      );
      return counter;
    }

    /// ينتظر أول emission بعد الآن (timeout 1s).
    Future<void> waitForNextEmission(_EmissionCounter counter) {
      counter.onEmission = Completer<void>();
      return counter.onEmission!.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () => counter.onEmission = null,
      );
    }

    test('Scenario A (L3+L1) — AsyncLoading transient: ≤ 5 emissions في 10 invalidations',
        () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final counter = trackEmissions(container);
      addTearDown(() => counter.sub.close());

      // انتظر initial load
      await waitForNextEmission(counter);
      // الـ list يحتوي الـ 2 المُضافين + أي seeded من forTesting (مثلاً 3
      // delivery companies + cash customer). المهم: غير-فارغة، لتمييزها
      // عن empty الذي يأتي من _emptyParties() في الـ pre-fix flicker.
      expect(counter.lastList, isNotNull);
      expect(counter.lastList!.length, greaterThanOrEqualTo(2),
          reason: 'Initial load يجب أن يحتوي على الأقل 2 parties (المُضافون)');
      counter.count = 0; // reset baseline

      // 10 invalidations لـ branchScopeProvider — يحاكي auth-driven re-runs
      // قبل L3: كل invalidation تنتج 2 emissions ([] flicker → real list)
      // قبل L1 (مع L3): كل invalidation تنتج 1 emission (re-subscription)
      // بعد L3 + L1: 0 emissions (distinct dedupes subscription re-emit)
      for (int i = 0; i < 10; i++) {
        container.invalidate(branchScopeProvider);
        // أعطِ الـ scheduler فرصة لتحرير الـ provider re-eval + الـ stream sub
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      // اسمح للأحداث المتأخّرة بالتجمّع
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // PASS criterion (post-L3+L1): ≤ 5
      // pre-fix expected: ~20 (10 × flicker pair)
      expect(
        counter.count,
        lessThanOrEqualTo(5),
        reason:
            'بعد L3 + L1: AsyncLoading transient لا يُسقط previousData (.value)، '
            'و distinct() يبتلع subscription re-emits المتطابقة. '
            'pre-fix: ~20 emission (10 × flicker)',
      );
    });

    test('Scenario B (L1) — no-op writes: ≤ 1 emission في 30 writes متطابقة',
        () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final counter = trackEmissions(container);
      addTearDown(() => counter.sub.close());

      await waitForNextEmission(counter);
      final baseline = counter.lastList!;
      counter.count = 0;

      // 30 no-op updates: إعادة كتابة نفس balance.
      // Drift يُصدر stream emit على كل write (event-driven حتى لو value
      // didn't change). بعد L1 (.distinct): القائمة الناتجة متطابقة دائماً
      // → 0 emissions
      // قبل L1: 30 emissions
      final originalBalance =
          baseline.firstWhere((p) => p.id == partyId1).balance;
      for (int i = 0; i < 30; i++) {
        await (db.update(db.parties)..where((p) => p.id.equals(partyId1)))
            .write(PartiesCompanion(balance: Value(originalBalance)));
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));

      // PASS criterion (post-L1): ≤ 1
      // pre-L1: ~30
      expect(
        counter.count,
        lessThanOrEqualTo(1),
        reason:
            'بعد L1: distinct() يطابق القوائم بعمق. 30 no-op writes تنتج '
            '30 Drift emissions لكن القائمة الناتجة متطابقة → distinct '
            'يبتلعها كلها.',
      );
    });

    test('Scenario C (L2) — burst writes: ≤ 8 emissions في 50 writes خلال 1s',
        () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      final counter = trackEmissions(container);
      addTearDown(() => counter.sub.close());

      await waitForNextEmission(counter);
      counter.count = 0;

      // 50 writes بأرصدة مختلفة محاكاة burst sync من clients متعدّدة.
      // قبل L2: 50 emissions (Drift يُصدر، distinct لا يُدعى لأن القيم مختلفة)
      // بعد L2 (debounceTime 200ms): الـ 50 emissions تتجمّع في windows
      // 200ms → max 5-8 windows
      for (int i = 0; i < 50; i++) {
        await (db.update(db.parties)..where((p) => p.id.equals(partyId1)))
            .write(PartiesCompanion(balance: Value(100.0 + i)));
      }

      // اسمح للـ debounce window يطلق آخر تجميعة + delay عدم استقرار
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // PASS criterion (post-L2): ≤ 8
      // pre-L2: ~50
      expect(
        counter.count,
        lessThanOrEqualTo(8),
        reason:
            'بعد L2: debounceTime(200ms) يجمّع emissions في windows. '
            '50 writes في < 1s تقع في 5-8 windows max. pre-fix: ~50.',
      );
    });
  });
}

class _EmissionCounter {
  late ProviderSubscription<AsyncValue<List<Party>>> sub;
  int count = 0;
  List<Party>? lastList;
  Completer<void>? onEmission;
}
