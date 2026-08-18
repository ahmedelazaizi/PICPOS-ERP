// ═══════════════════════════════════════════════════════════════════════════
// نطاقُ النسبة على مستوى المستودع — حلُّ محلِّ ستِّ نسخٍ من شرطِ Spec 103
// ═══════════════════════════════════════════════════════════════════════════
//
// المُحدِّد (`isClientMode` + `client_branch_id`) ليس اختراعاً هنا: هو نفسُه
// الذي يستعمله `BranchRepositoryImpl.getActiveBranch()` منذ البداية، فوُضع
// الجوابُ بجواره بدل أن يُنسخ في كلِّ شاشة.
//
// ⚠️ وسلوكٌ محفوظٌ عن قصد: جهازُ عميلٍ **بلا** `client_branch_id` يُعامَل بلا
// حصر (لا مقفولاً). هذا ما يفعله شرطُ Spec 103 اليوم، وتغييرُه يوقف جهازاً
// ناقصَ الاقتران عن إصدارِ أيِّ مستند — قرارٌ يخصُّ المالك لا إصلاحاً تابعاً.
// (يختلف عن `clientScopeProvider` الذي يفشل مقفولاً لأنه يجيب سؤالَ الرؤية.)

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/data/repositories/branch_repository_impl.dart';

class _ClientModeInterceptor implements SyncInterceptor {
  @override
  bool get isClientModeImpl => true;
  @override
  bool get isMirrorModeImpl => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late AppDatabase db;
  late BranchRepositoryImpl repo;
  late int tantaBranchId;
  late int tantaWarehouseId;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = BranchRepositoryImpl(db);

    tantaBranchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع طنطا',
            globalId: const Value('gid-branch-tanta-scope'),
          ),
        );
    tantaWarehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'مخزن طنطا',
            branchId: Value(tantaBranchId),
            globalId: const Value('gid-wh-tanta-scope'),
          ),
        );
    // مخزنٌ بلا فرعٍ — عامٌّ في الرؤية، ممنوعٌ في النسبة.
    await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'مخزنٌ بلا فرع',
            globalId: const Value('gid-wh-branchless-scope'),
          ),
        );
  });

  tearDown(() async {
    SyncInterceptor.instance = null;
    SharedPreferences.setMockInitialValues({});
    await db.close();
  });

  void enterClientMode({int? branchId}) {
    SyncInterceptor.instance = _ClientModeInterceptor();
    SharedPreferences.setMockInitialValues(
        branchId == null ? {} : {'client_branch_id': branchId});
  }

  group('getAssignmentBranchId', () {
    test('جهازٌ مستقل ⇒ null (بلا حصر)', () async {
      expect(await repo.getAssignmentBranchId(), isNull);
    });

    test('جهازُ عميلٍ مقترن ⇒ فرعُه', () async {
      enterClientMode(branchId: tantaBranchId);
      expect(await repo.getAssignmentBranchId(), tantaBranchId);
    });

    test('جهازُ عميلٍ بلا اقتران ⇒ null — سلوكٌ محفوظٌ لا مُستحدَث', () async {
      enterClientMode();
      expect(await repo.getAssignmentBranchId(), isNull,
          reason: 'الحصرُ هنا كان يوقف جهازاً ناقصَ التنصيب عن كلِّ مستند');
    });
  });

  group('getAssignableWarehouses', () {
    test('جهازٌ مستقل ⇒ كلُّ المخازن', () async {
      final names = (await repo.getAssignableWarehouses()).map((w) => w.name);
      expect(names, containsAll(['مخزن طنطا', 'مخزنٌ بلا فرع']));
    });

    test('جهازُ عميلٍ ⇒ مخازنُ فرعِه وحدَها، ولا المخزنُ العديمُ الفرع',
        () async {
      enterClientMode(branchId: tantaBranchId);

      final result = await repo.getAssignableWarehouses();

      expect(result.map((w) => w.id), [tantaWarehouseId]);
      expect(result.map((w) => w.name), isNot(contains('مخزنٌ بلا فرع')));
    });

    test('المحذوفُ ناعماً والمعطَّلُ خارجَ القائمة', () async {
      final deletedId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'مخزنٌ محذوف',
              branchId: Value(tantaBranchId),
              // شاهدُ الحذف يصل من الخادم عبر `DeltaPull`، والصفُّ يبقى محلّياً.
              deletedAt: Value(DateTime(2026, 8, 1)),
              globalId: const Value('gid-wh-deleted-scope'),
            ),
          );
      final inactiveId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'مخزنٌ معطَّل',
              branchId: Value(tantaBranchId),
              isActive: const Value(false),
              globalId: const Value('gid-wh-inactive-scope'),
            ),
          );

      final ids = (await repo.getAssignableWarehouses()).map((w) => w.id);

      expect(ids, isNot(contains(deletedId)));
      expect(ids, isNot(contains(inactiveId)),
          reason: '`isActive` هو مُحدِّدُ «مخزنٍ صالح» في بقيّةِ المستودع');
      expect(ids, contains(tantaWarehouseId));
    });

    test('keepSelected يُبقي المخزنَ الخارجَ عن النطاق حاضراً', () async {
      final deletedId = await db.into(db.warehouses).insert(
            WarehousesCompanion.insert(
              name: 'مخزنٌ محذوف',
              branchId: Value(tantaBranchId),
              deletedAt: Value(DateTime(2026, 8, 1)),
              globalId: const Value('gid-wh-deleted-keep'),
            ),
          );

      final ids = (await repo.getAssignableWarehouses(keepSelected: deletedId))
          .map((w) => w.id);

      expect(ids, contains(deletedId),
          reason: 'قائمةٌ بلا قيمتِها المنتقاةِ تُسقط `DropdownButton`، '
              'وإسقاطُ القيمةِ صامتاً يعيد كتابةَ صفٍّ قائم');
      expect(ids, contains(tantaWarehouseId));
    });

    test('keepSelected لمعرّفٍ لا وجودَ له لا يكسر القائمة', () async {
      expect(
        (await repo.getAssignableWarehouses(keepSelected: 999999)).map((w) => w.id),
        contains(tantaWarehouseId),
      );
    });

    test('فرعٌ بلا مخازن ⇒ القائمةُ الكاملةُ لا الخاوية', () async {
      final emptyBranchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'فرعٌ بلا مخازن',
              globalId: const Value('gid-branch-empty-scope'),
            ),
          );
      enterClientMode(branchId: emptyBranchId);

      expect((await repo.getAssignableWarehouses()).length, greaterThan(1));
    });
  });
}
