// ربطُ الخزنة بمركز التكلفة — هل يصل إلى الدفاتر؟
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// نفسُ فئة §٣-ب: **سطحُ إعدادٍ يكتب قيمةً لا يقرؤها أحد.**
//
// شاشةُ إدارة الصناديق تربط كلَّ خزنةٍ بمركز تكلفة (`safes.costCenterId`،
// وللعمود مرجعٌ حقيقيٌّ إلى `cost_centers`). والمشغّلُ يربط ويحفظ — ثم يفتح
// تقريرَ مراكز التكلفة فلا يجد حركةَ الخزنة فيه.
//
// والسبب: `createReceiptVoucher` و`createPaymentVoucher` يكتبان
// `costCenterId: Value(costCenterId)` من **المنادي وحدَه**، بلا أيّ رجوعٍ
// إلى مركز الخزنة. فسندٌ يُنشأ من حوارٍ لا يسأل عن مركز تكلفة يقع بلا مركز
// مهما كانت خزنتُه مربوطة.
//
// ⚠️ والفرعُ **يصل** بالفعل (`autoPostReceipt` و`autoPostPayment` يقرآن
// `safe?.branchId`، و`_resolveBranchSafeAccount` يستعمله). فالعطبُ في
// مركز التكلفة وحدَه — وهذا الملفُّ يقيس الاثنين كي لا يُصلَح أحدُهما
// فينكسر الآخرُ صامتاً.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int costCenterId;
  late int otherCostCenterId;
  late int branchId;
  late int safeId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع المعادي',
            globalId: const Value('gid-br-cc'),
          ),
        );
    costCenterId = await db.into(db.costCenters).insert(
          CostCentersCompanion.insert(
            name: 'مركز المعادي',
            code: 'CC-MAADI',
            globalId: const Value('gid-cc-maadi'),
          ),
        );
    otherCostCenterId = await db.into(db.costCenters).insert(
          CostCentersCompanion.insert(
            name: 'مركز آخر',
            code: 'CC-OTHER',
            globalId: const Value('gid-cc-other'),
          ),
        );
    safeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'درج المعادي',
            safeType: const Value('cash'),
            branchId: Value(branchId),
            costCenterId: Value(costCenterId),
            globalId: const Value('gid-safe-cc'),
          ),
        );
  });

  tearDown(() => db.close());

  Future<SafeTransactionData> txnOf(int id) =>
      (db.select(db.safeTransactions)..where((t) => t.id.equals(id)))
          .getSingle();

  group('الخزنةُ المربوطةُ بمركزِ تكلفةٍ تُورّثه لحركاتها', () {
    test('سندُ قبضٍ بلا مركزٍ صريح يرث مركزَ خزنته', () async {
      final id = await db.createReceiptVoucher(
        amount: 500,
        category: 'other',
        safeId: safeId,
        description: 'قبضٌ على درج المعادي',
      );

      expect((await txnOf(id)).costCenterId, costCenterId,
          reason: 'الربطُ في شاشة الصناديق بلا هذا الوراثةِ حبرٌ على ورق: '
              'يُحفظ ولا يظهر في تقرير مراكز التكلفة أبداً');
    });

    test('سندُ صرفٍ بلا مركزٍ صريح يرث مركزَ خزنته', () async {
      final id = await db.createPaymentVoucher(
        amount: 200,
        category: 'other',
        safeId: safeId,
        description: 'صرفٌ من درج المعادي',
      );

      expect((await txnOf(id)).costCenterId, costCenterId);
    });

    test('ومركزُ المنادي الصريحُ أولى — لا يُداس بمركز الخزنة', () async {
      // الوراثةُ سدُّ فراغٍ لا تجاوزٌ على اختيار. حوارٌ يسأل عن مركزٍ ويأخذ
      // إجابةَ المستخدم يجب أن تصل كما هي.
      final id = await db.createReceiptVoucher(
        amount: 500,
        category: 'other',
        safeId: safeId,
        costCenterId: otherCostCenterId,
        description: 'قبضٌ بمركزٍ مغاير',
      );

      expect((await txnOf(id)).costCenterId, otherCostCenterId,
          reason: 'اختيارُ المستخدم الصريحُ أولى من أيّ وراثة');
    });

    test('وخزنةٌ بلا مركزٍ تُبقي الحركةَ بلا مركز', () async {
      final bare = await db.into(db.safes).insert(SafesCompanion.insert(
            name: 'خزنةٌ بلا مركز',
            safeType: const Value('cash'),
            globalId: const Value('gid-safe-nocc'),
          ));

      final id = await db.createReceiptVoucher(
        amount: 100,
        category: 'other',
        safeId: bare,
        description: 'قبضٌ بلا مركز',
      );

      expect((await txnOf(id)).costCenterId, isNull,
          reason: 'لا يُخترع مركزٌ من عدم');
    });
  });

  group('ضابط: الفرعُ كان يصل سلفاً ويجب أن يبقى', () {
    test('قيدُ سند القبض يحمل فرعَ الخزنة', () async {
      await db.createReceiptVoucher(
        amount: 500,
        category: 'other',
        safeId: safeId,
        description: 'قبضٌ على درج المعادي',
      );

      final entries = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('receipt_voucher')))
          .get();
      expect(entries, isNotEmpty, reason: 'سندُ القبض يُرحَّل');
      expect(entries.first.branchId, branchId,
          reason: '`autoPostReceipt` يقرأ `safe?.branchId` — لو انفكّ هذا '
              'ضاع تمييزُ الفروع في الأستاذ');
    });
  });
}
