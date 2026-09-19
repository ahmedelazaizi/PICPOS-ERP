// 🔴 مرشِّحُ الفرع في كشف الحساب: **النافذةُ تشمل ما لا فرعَ له والافتتاحيُّ
//    يُسقطه.**
//
// ═══ العطب ═══
//
// `getPartyStatement(..., branchId:)` يُرشِّح مرّتين على شعبتين مختلفتين:
//
//   ‏• **حركةُ الفترة** — بـdrift:
//       `warehouses.branchId.equals(b) | warehouses.branchId.isNull()`
//       `safes.branchId.equals(b)      | safes.branchId.isNull()`
//   ‏• **الرصيدُ الافتتاحيّ** — بـSQL مكتوبةٍ بيدها:
//       `warehouse_id IN (SELECT id FROM warehouses WHERE branch_id = ?)`
//       `... JOIN safes s ... AND s.branch_id = ?`
//
// والفرقُ `OR branch_id IS NULL`. فمخزنٌ عامٌّ أو خزنةٌ عامّةٌ — وهي الحالةُ
// الافتراضيّةُ في تجهيزةٍ لم تُقسَّم فروعاً بعد — **تدخل النافذةَ وتخرج من
// الافتتاحيّ**.
//
// ═══ الأثر ═══
//
// الكشفُ يبدأ من رصيدٍ افتتاحيٍّ **أصغرَ ممّا يقابل حركتَه**، فالرصيدُ الختاميُّ
// ينقص بمقدار كلّ حركةٍ سابقةٍ للفترة مرّت بمخزنٍ أو خزنةٍ بلا فرع. ولا فحصَ
// اتّزانٍ يمسكه: الكشفُ متّسقٌ مع نفسه (‏افتتاحيٌّ + حركةٌ = ختاميّ)، والرقمُ
// الخاطئُ هو نقطةُ البدء.
//
// وهو عطبٌ **كامنٌ حتى اليوم**: لا منادٍ يمرّر `branchId` من شاشة. وقرارُ
// المالك على الصورة `(7)` — «مرشِّحُ فرعٍ ظاهر» — هو ما يوقظه، فيُصلَح قبل أن
// يُوصَّل.
//
// ═══ والاتّجاهُ: الافتتاحيُّ يلحق بالنافذة لا العكس ═══
//
// `branch_id IS NULL` تعني «غيرُ مخصَّصٍ لفرع» لا «فرعٌ آخر». فالمخزنُ العامُّ
// يخصّ الكلَّ ويظهر لكلّ فرع — وهذا ما تقوله النافذةُ بالفعل. وشدُّ النافذة
// إلى SQL الافتتاحيّ كان سيُخفي حركةَ التجهيزات التي لم تُقسَّم فروعاً أصلاً،
// وهي الأغلبيّة.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branchA;
  late int sharedWh; // بلا فرع
  late int branchWh; // على فرع أ
  late int sharedSafe; // بلا فرع
  late int userId;
  late int customerId;
  late int supplierId;

  final from = DateTime(2026, 9, 1);
  final to = DateTime(2026, 9, 30);
  final before = DateTime(2026, 8, 10);
  final inside = DateTime(2026, 9, 10);

  setUp(() async {
    db = AppDatabase.forTesting();
    branchA = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع أ', globalId: const Value('gid-br-sym-a')));
    sharedWh = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(name: 'مخزنٌ عامّ'));
    branchWh = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'مخزنُ فرعِ أ', branchId: Value(branchA)));
    sharedSafe = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'خزنةٌ عامّة', globalId: const Value('gid-safe-sym')));
    userId = await db.into(db.users).insert(UsersCompanion.insert(
        username: 'sym_user', passwordHash: 'x', displayName: 'مستخدم'));
    customerId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'عميلُ التماثل'));
    // ⚠️ `isCustomer` افتراضُها `true`، و`getPartyStatement` يفرّع
    //    `if (party.isCustomer) … else …` — فطرفٌ بالصفتين يُحسَب افتتاحيُّه
    //    بمعادلة العميل وحدَها ولا تُقرأ شعبةُ المورد أصلاً.
    supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(
        name: 'موردُ التماثل',
        isCustomer: const Value(false),
        isSupplier: const Value(true)));
  });

  tearDown(() => db.close());

  Future<void> sale({
    required String number,
    required int warehouseId,
    required DateTime date,
    required double total,
  }) =>
      db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            customerId: Value(customerId),
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: date,
            subtotal: Value(total),
            total: Value(total),
          ));

  Future<void> receipt({
    required String number,
    required int safeId,
    required DateTime date,
    required double amount,
  }) =>
      db.into(db.safeTransactions).insert(SafeTransactionsCompanion.insert(
            voucherNumber: number,
            safeId: safeId,
            transactionType: 'receipt',
            category: 'sales',
            amount: amount,
            balanceAfter: 0,
            partyId: Value(customerId),
            createdAt: Value(date),
          ));

  /// رصيدُ أوّلِ الفترة كما يقرؤه الكشف — صفرٌ حين لا يُدرَج صفُّه.
  double opening(List<PartyStatementEntry> rows) => rows
      .where((e) => e.entryType == 'opening')
      .fold<double>(0, (_, e) => e.balance);

  group('🔴 المخزنُ العامُّ يدخل النافذةَ ويخرج من الافتتاحيّ', () {
    test('بيعةٌ سابقةٌ في مخزنٍ بلا فرعٍ تُحسَب في الرصيد الافتتاحيّ',
        () async {
      await sale(
          number: 'INV-OLD', warehouseId: sharedWh, date: before, total: 100);
      await sale(
          number: 'INV-NEW', warehouseId: sharedWh, date: inside, total: 50);

      final rows = await db.getPartyStatement(customerId,
          fromDate: from, toDate: to, branchId: branchA);

      // 🔴 قبل الإصلاح: ٠ — لأنّ SQL الافتتاحيّ يشترط `branch_id = ?` على
      //    مخزنٍ قيمتُه NULL، بينما صفُّ الفترة يمرّ بـ`isNull()`.
      expect(opening(rows), 100,
          reason: 'البيعةُ السابقةُ مرّت بنفس المخزن الذي مرّت به بيعةُ '
              'الفترة — فإمّا يظهران معاً أو يغيبان معاً');
      expect(rows.last.balance, 150,
          reason: 'الختاميُّ = الافتتاحيُّ + حركةُ الفترة');
    });

    test('ومخزنُ الفرع نفسُه ضابطٌ — لم يكن الافتتاحيُّ معطَّلاً بالكامل',
        () async {
      await sale(
          number: 'INV-OLD-B', warehouseId: branchWh, date: before, total: 70);
      await sale(
          number: 'INV-NEW-B', warehouseId: branchWh, date: inside, total: 30);

      final rows = await db.getPartyStatement(customerId,
          fromDate: from, toDate: to, branchId: branchA);
      expect(opening(rows), 70);
      expect(rows.last.balance, 100);
    });

    test('وبلا مرشِّحِ فرعٍ لا فرقَ أصلاً — الشرطُ كلُّه يسقط', () async {
      await sale(
          number: 'INV-OLD-N', warehouseId: sharedWh, date: before, total: 100);
      await sale(
          number: 'INV-NEW-N', warehouseId: sharedWh, date: inside, total: 50);

      final rows = await db.getPartyStatement(customerId,
          fromDate: from, toDate: to);
      expect(opening(rows), 100);
      expect(rows.last.balance, 150);
    });

    test('🔴 ومجموعُ الفروع لا يزيد على الكلّ ولا ينقص عنه', () async {
      // شرطُ التماثل الحقيقيّ: فرعٌ واحدٌ مُعرَّفٌ ⇒ كشفُه = الكشفُ الكامل.
      // وكسرُه يعني أنّ إجماليّاتِ الفروع لا تجمع إلى إجماليِّ الشركة.
      await sale(
          number: 'INV-S1', warehouseId: sharedWh, date: before, total: 100);
      await sale(
          number: 'INV-S2', warehouseId: branchWh, date: before, total: 40);
      await sale(
          number: 'INV-S3', warehouseId: sharedWh, date: inside, total: 25);

      final all = await db.getPartyStatement(customerId,
          fromDate: from, toDate: to);
      final onBranch = await db.getPartyStatement(customerId,
          fromDate: from, toDate: to, branchId: branchA);
      expect(onBranch.last.balance, all.last.balance,
          reason: 'كلُّ مخزنٍ في التجهيزة إمّا عامٌّ أو على فرعِ أ — '
              'فالكشفان يجب أن يتطابقا');
    });
  });

  group('🔴 والخزنةُ العامّةُ مثلُها', () {
    test('سندُ قبضٍ سابقٌ من خزنةٍ بلا فرعٍ يُنقص الرصيدَ الافتتاحيّ',
        () async {
      await sale(
          number: 'INV-SF', warehouseId: sharedWh, date: before, total: 200);
      await receipt(
          number: 'RV-OLD', safeId: sharedSafe, date: before, amount: 80);

      final rows = await db.getPartyStatement(customerId,
          fromDate: from, toDate: to, branchId: branchA);
      expect(opening(rows), 120,
          reason: '٢٠٠ بيعةً ناقصَ ٨٠ تحصيلاً — والتحصيلُ من خزنةٍ عامّةٍ '
              'يُقرأ في النافذة فلْيُقرأ في الافتتاحيّ');
    });

    test('وعلى المورد كذلك — الشعبةُ الثانيةُ نسخةٌ من الأولى', () async {
      await db.into(db.purchaseInvoices).insert(PurchaseInvoicesCompanion.insert(
            invoiceNumber: 'PINV-OLD',
            supplierId: supplierId,
            warehouseId: sharedWh,
            invoiceDate: before,
            subtotal: const Value(300),
            total: const Value(300),
          ));

      final rows = await db.getPartyStatement(supplierId,
          fromDate: from, toDate: to, branchId: branchA);
      expect(opening(rows), 300,
          reason: 'شعبةُ المورد تحمل نفسَ SQL — وإصلاحُ العميل وحدَه يترك '
              'نصفَ العطب');
    });
  });

  group('🔴 والطرفُ بالصفتين: نافذتان وافتتاحيٌّ واحد', () {
    test('عميلٌ **ومورّدٌ** معاً — الافتتاحيُّ يقرأ شراءَه كما يقرأ بيعَه',
        () async {
      // 🔴 نفسُ شكل العطب أعلاه في موضعٍ آخرَ من نفس الدالّة: صفوفُ الفترة
      //    تُبنى بـ**شرطَين مستقلَّين** (`if (isCustomer)` ثمّ
      //    `if (isSupplier)`) فيظهر البيعُ والشراءُ معاً؛ والافتتاحيُّ
      //    `if (isCustomer) … else …` فيقرأ شعبةً واحدةً ويُسقط الأخرى.
      //
      //    فطرفٌ بالصفتين — وهي حالةٌ شائعةٌ: مورّدٌ نشتري منه ونبيع له —
      //    يبدأ كشفُه من رصيدٍ يُغفل كلَّ فواتير شرائه السابقة.
      final both = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'طرفٌ بالصفتين',
          isCustomer: const Value(true),
          isSupplier: const Value(true)));

      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'INV-BOTH',
            customerId: Value(both),
            warehouseId: sharedWh,
            userId: userId,
            invoiceDate: before,
            subtotal: const Value(500),
            total: const Value(500),
          ));
      await db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: 'PINV-BOTH',
              supplierId: both,
              warehouseId: sharedWh,
              invoiceDate: before,
              subtotal: const Value(200),
              total: const Value(200),
            ),
          );

      final rows =
          await db.getPartyStatement(both, fromDate: from, toDate: to);
      // اتّجاهُ العميل: مدينٌ موجب. فالبيعُ ٥٠٠ والشراءُ ٢٠٠ يقابله ⇒ ٣٠٠.
      expect(opening(rows), 300,
          reason: 'الافتتاحيُّ حُسب بشعبةِ العميل وحدَها فبقي ٥٠٠ — '
              'وفواتيرُ الشراء تظهر في الفترة ولا تظهر قبلها');
    });
  });

  group('🔴 ومردودُ البيع السابقُ يُضاف بدل أن يُطرَح', () {
    test('مرتجعُ نقطةِ بيعٍ قبل الفترة يُنقص الرصيدَ الافتتاحيّ لا يزيده',
        () async {
      // 🔴 صفوفُ الفترة تفرّع على `saleType == 'return'` فتضع المبلغَ
      //    **دائناً** (‏Spec 113)؛ وSQL الافتتاحيّ `SUM(total)` بلا شرطٍ على
      //    النوع فتضعه **مديناً**. فمرتجعٌ بـ٤٠ يظهر في الرصيد الافتتاحيّ
      //    بـ‎+٤٠‎ بدل ‎−٤٠‎ — انحرافٌ ضعفُ قيمته.
      await sale(
          number: 'INV-R1', warehouseId: sharedWh, date: before, total: 100);
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'RET-R1',
            customerId: Value(customerId),
            warehouseId: sharedWh,
            userId: userId,
            invoiceDate: before,
            subtotal: const Value(40),
            total: const Value(40),
            saleType: const Value('return'),
          ));

      final rows =
          await db.getPartyStatement(customerId, fromDate: from, toDate: to);
      expect(opening(rows), 60,
          reason: '١٠٠ بيعاً ناقصَ ٤٠ مرتجعاً — والمرتجعُ داخلَ الفترة '
              'يُقرأ دائناً، فليُقرأ دائناً قبلها');
    });

    test('وضابطٌ: بيعةٌ وحدَها قبل الفترة تبقى كما هي', () async {
      await sale(
          number: 'INV-R2', warehouseId: sharedWh, date: before, total: 100);
      final rows =
          await db.getPartyStatement(customerId, fromDate: from, toDate: to);
      expect(opening(rows), 100);
    });
  });
}
