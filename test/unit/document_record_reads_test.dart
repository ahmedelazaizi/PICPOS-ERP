// قراءتا **سجلّ المستندات** — خ‑٩.
//
// ═══ 🔴 ‏١) سندُ الشيك ليس نوعَه — وترشيحٌ ساذجٌ يُخفيه ═══
//
// سندُ القبض النقديُّ يكتب `transaction_type = 'receipt'`. أمّا سندُ
// الشيك فيكتب نوعاً ثالثاً (`cheque_voucher`) لأنّ
// `treasury_repository_impl` يمرّر `skipSafeTransaction: true` للشيك.
// فسجلٌّ يرشّح بـ`'receipt'` وحدَه **يُخفي كلَّ سندات الشيكات** — ويسأل
// المستخدمُ «أين سندي؟» ولا جواب.
//
// والفاصلُ بين اتّجاهَي سند الشيك **بادئةُ رقمه** (`RV`/`PV`) لا
// `category`: البادئةَ يكتبها الـDAO بيده، والتصنيفَ يمرّره كلُّ منادٍ.
//
// ═══ 🔴 ‏٢) والمحذوفُ ناعماً لا يُعرَض ═══
//
// `watchTransactions` القائمةُ **لا ترشّح `deleted_at`** إطلاقاً (بخلاف
// `watchRecentTransactions` بجوارها). فسجلٌّ مبنيٌّ عليها يعرض سنداً
// حُذف — ويُطبَع ويُراجَع وكأنّه قائم.
//
// ═══ 🔴 ‏٣) ومردودُ المشتريات يُقرأ من جدوله بتاريخه ═══
//
// القراءةُ الوحيدةُ القائمةُ اليوم (`getPurchaseReturnHistory`) **لا تلمس
// `purchase_returns` إطلاقاً**: تقرأ `purchase_invoices` في مدىً زمنيٍّ ثمّ
// ترشّح على `status`. وأثرُ ذلك ثلاثةُ أعطابٍ في قراءةٍ واحدة:
//
//   • المدى على **تاريخ الفاتورة** لا تاريخ المردود — فمردودُ اليوم على
//     فاتورةٍ عمرُها سنتان **لا يظهر أبداً**؛
//   • الصفُّ فاتورةٌ لا مردود — فثلاثةُ مردوداتٍ على فاتورةٍ تظهر صفّاً
//     واحداً، ولا سبيلَ لفتح واحدٍ منها بعينه؛
//   • ولا `id` لمردودٍ يُفتَح، فالمرفقاتُ (§٨) بلا مرساة.
//
// ⚠️ **وحارسُ المدى يُقاس على حدوده**: `isBetween` شاملٌ للطرفين، فصفٌّ
//    على الحدّ تماماً يجب أن يدخل.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/document_record.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  // ═══════════════════════════════════════════════════════════════════
  // بذورٌ — تُكتَب بالإدراج المباشر لا بمحرّك السندات: المقيسُ هنا
  // **القراءة**، وإقحامُ المحرّك يجعل الفشلَ غامضاً بين الطرفين.
  // ═══════════════════════════════════════════════════════════════════

  /// ⚠️ **معرّفاتٌ بعيدةٌ عن بذر الإقلاع**: `AppDatabase.forTesting()` يزرع
  /// خزنةً افتراضيّةً عند `id = 1`، فالإصرارُ عليه يُسقط البذرَ بـUNIQUE.
  Future<int> seedSafe({
    int id = 101,
    String name = 'خزنة رئيسية',
    int? branchId,
  }) async {
    await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: name,
            safeType: const Value('cash'),
            branchId: Value(branchId),
            id: Value(id),
          ),
        );
    return id;
  }

  /// فرعٌ حقيقيٌّ — `safes.branch_id` و`purchase_returns.branch_id`
  /// مفتاحان أجنبيّان، فرقمٌ لا وجودَ له يُسقط الإدراجَ لا الترشيح.
  Future<int> seedBranch({required int id, String? name}) async {
    await db.into(db.branches).insert(
          BranchesCompanion.insert(name: name ?? 'فرع $id', id: Value(id)),
        );
    return id;
  }

  Future<int> seedParty({int id = 9, String name = 'عميل الجنوب'}) async {
    await db.into(db.parties).insert(
          PartiesCompanion.insert(name: name, id: Value(id)),
        );
    return id;
  }

  Future<int> seedTxn({
    required String voucherNumber,
    required String type,
    required DateTime at,
    int safeId = 101,
    int? partyId,
    String category = 'customer_payment',
    double amount = 100,
    double discount = 0,
    String? description,
    DateTime? deletedAt,
  }) =>
      db.into(db.safeTransactions).insert(
            SafeTransactionsCompanion.insert(
              voucherNumber: voucherNumber,
              safeId: safeId,
              transactionType: type,
              category: category,
              amount: amount,
              balanceAfter: 0,
              discount: Value(discount),
              partyId: Value(partyId),
              description: Value(description),
              createdAt: Value(at),
              deletedAt: Value(deletedAt),
            ),
          );

  Future<List<VoucherRecord>> readVouchers({
    required VoucherDirection direction,
    DateTime? from,
    DateTime? to,
    Set<int>? branchIds,
    String? search,
  }) =>
      db.watchVoucherRecords(
        direction: direction,
        from: from,
        to: to,
        branchIds: branchIds,
        search: search,
      ).first;

  // ═══════════════════════════════════════════════════════════════════
  group('سجلُّ السندات', () {
    setUp(() async {
      await seedSafe();
      await seedParty();
    });

    test('مرساةٌ — السندُ النقديُّ يُقرأ بحقوله', () async {
      await seedTxn(
        voucherNumber: 'RV-1',
        type: 'receipt',
        at: DateTime(2026, 5, 10),
        partyId: 9,
        amount: 250,
        discount: 10,
        description: 'تحصيل',
      );

      final rows = await readVouchers(direction: VoucherDirection.receipt);
      expect(rows, hasLength(1));
      final r = rows.single;
      expect(r.voucherNumber, 'RV-1');
      expect(r.amount, 250);
      expect(r.discount, 10);
      expect(r.partyName, 'عميل الجنوب',
          reason: 'اسمُ الطرف لم يُضمَّ — فالسجلُّ أرقامٌ بلا أصحاب');
      expect(r.safeName, 'خزنة رئيسية');
      expect(r.isCheque, isFalse);
      expect(r.description, 'تحصيل');
    });

    test('🔴 وسندُ الشيك يظهر في سجلّه — نوعُه ثالثٌ لا «receipt»',
        () async {
      await seedTxn(
          voucherNumber: 'RV-7',
          type: 'receipt',
          at: DateTime(2026, 5, 10));
      await seedTxn(
          voucherNumber: 'RV-8',
          type: kChequeVoucherTxnTypeValue,
          at: DateTime(2026, 5, 11));

      final rows = await readVouchers(direction: VoucherDirection.receipt);
      expect(rows.map((r) => r.voucherNumber), containsAll(['RV-7', 'RV-8']),
          reason: '🔴 سندُ الشيك غائبٌ عن سجلّ القبض — وهو مستندٌ محفوظٌ '
              'يبحث عنه صاحبُه');
      expect(rows.firstWhere((r) => r.voucherNumber == 'RV-8').isCheque, isTrue,
          reason: 'لم يُوسَم شيكاً — فيُجمَع مع النقد ويُعَدُّ المالُ مرّتين');
      expect(
          rows.firstWhere((r) => r.voucherNumber == 'RV-7').isCheque, isFalse);
    });

    test('🔴 والاتّجاهُ يفصل سندَي الشيك بالبادئة لا بالتصنيف', () async {
      // نفسُ التصنيف في الاثنين عمداً — فلو كان التصنيفُ هو الفاصلَ لَاختلطا.
      await seedTxn(
        voucherNumber: 'RV-20',
        type: kChequeVoucherTxnTypeValue,
        at: DateTime(2026, 5, 10),
        category: 'other',
      );
      await seedTxn(
        voucherNumber: 'PV-21',
        type: kChequeVoucherTxnTypeValue,
        at: DateTime(2026, 5, 10),
        category: 'other',
      );

      final receipts = await readVouchers(direction: VoucherDirection.receipt);
      final payments = await readVouchers(direction: VoucherDirection.payment);

      expect(receipts.map((r) => r.voucherNumber), ['RV-20']);
      expect(payments.map((r) => r.voucherNumber), ['PV-21'],
          reason: '🔴 سندُ شيكِ الصرف ظهر في سجلّ القبض أو غاب عن سجلّه');
    });

    test('🔴 والمحذوفُ ناعماً لا يُعرَض', () async {
      await seedTxn(
          voucherNumber: 'RV-9',
          type: 'receipt',
          at: DateTime(2026, 5, 10));
      await seedTxn(
        voucherNumber: 'RV-10',
        type: 'receipt',
        at: DateTime(2026, 5, 10),
        deletedAt: DateTime(2026, 5, 12),
      );

      final rows = await readVouchers(direction: VoucherDirection.receipt);
      expect(rows.map((r) => r.voucherNumber), ['RV-9'],
          reason: '🔴 سندٌ محذوفٌ يُعرَض في السجلّ — يُطبَع ويُراجَع '
              'وكأنّه قائم');
    });

    test('ولا يُخلَط اتّجاهٌ بآخرَ ولا نوعٌ رابع', () async {
      await seedTxn(
          voucherNumber: 'RV-1',
          type: 'receipt',
          at: DateTime(2026, 5, 10));
      await seedTxn(
          voucherNumber: 'PV-1',
          type: 'payment',
          at: DateTime(2026, 5, 10));
      await seedTxn(
          voucherNumber: 'TR-1',
          type: 'transfer',
          at: DateTime(2026, 5, 10));

      expect(
          (await readVouchers(direction: VoucherDirection.receipt))
              .map((r) => r.voucherNumber),
          ['RV-1']);
      expect(
          (await readVouchers(direction: VoucherDirection.payment))
              .map((r) => r.voucherNumber),
          ['PV-1'],
          reason: 'التحويلُ ليس سنداً — ودخولُه السجلَّ يُفسد مجاميعَه');
    });

    test('والمدى شاملٌ لطرفَيه', () async {
      await seedTxn(
          voucherNumber: 'قبل',
          type: 'receipt',
          at: DateTime(2026, 4, 30, 23, 59));
      await seedTxn(
          voucherNumber: 'الحدُّ الأدنى',
          type: 'receipt',
          at: DateTime(2026, 5, 1));
      await seedTxn(
          voucherNumber: 'الحدُّ الأعلى',
          type: 'receipt',
          at: DateTime(2026, 5, 31));
      await seedTxn(
          voucherNumber: 'بعد',
          type: 'receipt',
          at: DateTime(2026, 6, 1, 0, 1));

      final rows = await readVouchers(
        direction: VoucherDirection.receipt,
        from: DateTime(2026, 5, 1),
        to: DateTime(2026, 5, 31),
      );
      expect(rows.map((r) => r.voucherNumber),
          containsAll(['الحدُّ الأدنى', 'الحدُّ الأعلى']));
      expect(rows.map((r) => r.voucherNumber), isNot(contains('قبل')));
      expect(rows.map((r) => r.voucherNumber), isNot(contains('بعد')));
    });

    test('🔴 والمدى مقصورٌ على فروع المستخدم', () async {
      // Spec 151 Track-3 — نفسُ ما يفعله `getPurchaseReturnHistory`
      // للمردودات: مستخدمٌ محصورٌ بفرعٍ لا يرى سنداتِ غيره.
      await seedBranch(id: 2);
      await seedSafe(id: 102, name: 'خزنة الفرع', branchId: 2);
      await seedBranch(id: 3);
      await seedSafe(id: 103, name: 'خزنة فرعٍ آخر', branchId: 3);
      await seedTxn(
          voucherNumber: 'لفرعي',
          type: 'receipt',
          safeId: 102,
          at: DateTime(2026, 5, 10));
      await seedTxn(
          voucherNumber: 'لغيري',
          type: 'receipt',
          safeId: 103,
          at: DateTime(2026, 5, 10));

      final scoped = await readVouchers(
          direction: VoucherDirection.receipt, branchIds: {2});
      expect(scoped.map((r) => r.voucherNumber), isNot(contains('لغيري')),
          reason: '🔴 سنداتُ فرعٍ آخرَ ظهرت لمستخدمٍ محصور');
      expect(scoped.map((r) => r.voucherNumber), contains('لفرعي'));
    });

    test('وخزنةٌ بلا فرعٍ لا تسقط من مستخدمٍ محصور', () async {
      await seedBranch(id: 2);
      await seedSafe(id: 102, name: 'خزنة الفرع', branchId: 2);
      await seedTxn(
          voucherNumber: 'بلا فرع',
          type: 'receipt',
          safeId: 101,
          at: DateTime(2026, 5, 10));
      await seedTxn(
          voucherNumber: 'لفرعي',
          type: 'receipt',
          safeId: 102,
          at: DateTime(2026, 5, 10));

      final scoped = await readVouchers(
          direction: VoucherDirection.receipt, branchIds: {2});
      expect(scoped.map((r) => r.voucherNumber),
          containsAll(['بلا فرع', 'لفرعي']),
          reason: 'صفوفُ ما قبل ١٣٣ بلا فرعٍ اختفت — وهي مالٌ قائم');
    });

    test('والبحثُ يمسك الرقمَ والبيانَ واسمَ الطرف', () async {
      await seedTxn(
          voucherNumber: 'RV-777',
          type: 'receipt',
          at: DateTime(2026, 5, 10));
      await seedTxn(
        voucherNumber: 'RV-888',
        type: 'receipt',
        at: DateTime(2026, 5, 10),
        description: 'دفعةُ التسوية',
      );
      await seedTxn(
        voucherNumber: 'RV-999',
        type: 'receipt',
        at: DateTime(2026, 5, 10),
        partyId: 9,
      );

      expect(
          (await readVouchers(
                  direction: VoucherDirection.receipt, search: '777'))
              .map((r) => r.voucherNumber),
          ['RV-777']);
      expect(
          (await readVouchers(
                  direction: VoucherDirection.receipt, search: 'التسوية'))
              .map((r) => r.voucherNumber),
          ['RV-888']);
      expect(
          (await readVouchers(
                  direction: VoucherDirection.receipt, search: 'الجنوب'))
              .map((r) => r.voucherNumber),
          ['RV-999'],
          reason: 'البحثُ باسم الطرف لا يعمل — وهو أوّلُ ما يُكتَب في خانة '
              'البحث');
    });

    test('والأحدثُ أوّلاً', () async {
      await seedTxn(
          voucherNumber: 'الأقدم',
          type: 'receipt',
          at: DateTime(2026, 5, 10));
      await seedTxn(
          voucherNumber: 'الأحدث',
          type: 'receipt',
          at: DateTime(2026, 5, 12));

      final rows = await readVouchers(direction: VoucherDirection.receipt);
      expect(rows.map((r) => r.voucherNumber), ['الأحدث', 'الأقدم']);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  group('سجلُّ مردودات المشتريات', () {
    Future<int> seedSupplier({int id = 4, String name = 'مورد الشمال'}) async {
      await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: name,
              id: Value(id),
              isSupplier: const Value(true),
            ),
          );
      return id;
    }

    Future<int> seedInvoice({
      int id = 30,
      String number = 'PI-30',
      int supplierId = 4,
      DateTime? at,
    }) async {
      await db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: number,
              supplierId: supplierId,
              invoiceDate: at ?? DateTime(2024, 1, 1),
              warehouseId: 1,
              id: Value(id),
            ),
          );
      return id;
    }

    Future<int> seedReturn({
      required DateTime at,
      int invoiceId = 30,
      int supplierId = 4,
      double total = 50,
      double tax = 5,
      String refundMethod = 'credit',
      String? reason,
      int? branchId,
      bool deleted = false,
    }) =>
        db.into(db.purchaseReturns).insert(
              PurchaseReturnsCompanion.insert(
                originalInvoiceId: invoiceId,
                supplierId: supplierId,
                returnDate: at,
                total: Value(total),
                tax: Value(tax),
                subtotal: Value(total - tax),
                refundMethod: Value(refundMethod),
                reason: Value(reason),
                branchId: Value(branchId),
                isDeleted: Value(deleted),
              ),
            );

    setUp(() async {
      await seedSupplier();
      await seedInvoice();
    });

    Future<int> seedBranchLocal(int id) async {
      await db.into(db.branches).insert(
            BranchesCompanion.insert(name: 'فرع $id', id: Value(id)),
          );
      return id;
    }

    test('مرساةٌ — المردودُ يُقرأ بحقوله ومعه فاتورتُه ومورّدُه', () async {
      await seedReturn(
          at: DateTime(2026, 5, 10), total: 120, tax: 20, reason: 'تالف');

      final rows = await db.watchPurchaseReturnRecords().first;
      expect(rows, hasLength(1));
      final r = rows.single;
      expect(r.total, 120);
      expect(r.tax, 20);
      expect(r.subtotal, 100);
      expect(r.originalInvoiceNumber, 'PI-30',
          reason: 'رقمُ الفاتورة الأصل غائبٌ — فالمردودُ بلا ما يُعرَف به');
      expect(r.supplierName, 'مورد الشمال');
      expect(r.reason, 'تالف');
      expect(r.id, greaterThan(0),
          reason: 'بلا `id` لا يُفتَح المردودُ ولا تُرسى عليه مرفقاتُه');
    });

    test('🔴 ومردودُ اليوم على فاتورةٍ قديمةٍ يظهر — المدى على تاريخ المردود',
        () async {
      // 🔴 عينُ عطب `getPurchaseReturnHistory`: مداها على `invoice_date`،
      //    فمردودٌ حديثٌ على فاتورةٍ عمرُها سنتان لا يظهر أبداً.
      await seedInvoice(id: 31, number: 'PI-31', at: DateTime(2024, 1, 1));
      await seedReturn(invoiceId: 31, at: DateTime(2026, 5, 10));

      final rows = await db
          .watchPurchaseReturnRecords(
            from: DateTime(2026, 5, 1),
            to: DateTime(2026, 5, 31),
          )
          .first;
      expect(rows, hasLength(1),
          reason: '🔴 المدى يقيس تاريخَ الفاتورة لا تاريخَ المردود — '
              'فمردودُ اليومِ غائبٌ عن سجلّ اليوم');
      expect(rows.single.originalInvoiceNumber, 'PI-31');
    });

    test('🔴 وثلاثةُ مردوداتٍ على فاتورةٍ ثلاثةُ صفوفٍ لا صفٌّ واحد',
        () async {
      await seedReturn(at: DateTime(2026, 5, 10), total: 10);
      await seedReturn(at: DateTime(2026, 5, 11), total: 20);
      await seedReturn(at: DateTime(2026, 5, 12), total: 30);

      final rows = await db.watchPurchaseReturnRecords().first;
      expect(rows, hasLength(3),
          reason: '🔴 الصفُّ فاتورةٌ لا مردود — فلا سبيلَ لفتح واحدٍ بعينه');
      expect(rows.map((r) => r.total), [30, 20, 10],
          reason: 'الأحدثُ أوّلاً');
    });

    test('🔴 والمحذوفُ لا يُعرَض', () async {
      await seedReturn(at: DateTime(2026, 5, 10), total: 10);
      await seedReturn(at: DateTime(2026, 5, 11), total: 20, deleted: true);

      final rows = await db.watchPurchaseReturnRecords().first;
      expect(rows.map((r) => r.total), [10],
          reason: '🔴 مردودٌ محذوفٌ يُعرَض ويُطبَع');
    });

    test('والمدى شاملٌ لطرفَيه', () async {
      await seedReturn(at: DateTime(2026, 4, 30), total: 1);
      await seedReturn(at: DateTime(2026, 5, 1), total: 2);
      await seedReturn(at: DateTime(2026, 5, 31), total: 3);
      await seedReturn(at: DateTime(2026, 6, 1), total: 4);

      final rows = await db
          .watchPurchaseReturnRecords(
            from: DateTime(2026, 5, 1),
            to: DateTime(2026, 5, 31),
          )
          .first;
      expect(rows.map((r) => r.total), [3, 2]);
    });

    test('🔴 والمدى مقصورٌ على فروع المستخدم', () async {
      await seedBranchLocal(2);
      await seedBranchLocal(3);
      await seedReturn(at: DateTime(2026, 5, 10), total: 11, branchId: 2);
      await seedReturn(at: DateTime(2026, 5, 10), total: 22, branchId: 3);

      final rows =
          await db.watchPurchaseReturnRecords(branchIds: {2}).first;
      expect(rows.map((r) => r.total), isNot(contains(22)),
          reason: '🔴 مردوداتُ فرعٍ آخرَ ظهرت لمستخدمٍ محصور — Spec 151');
      expect(rows.map((r) => r.total), contains(11));
    });

    test('ومردودٌ بلا فرعٍ لا يسقط من مستخدمٍ محصور', () async {
      await seedBranchLocal(2);
      await seedReturn(at: DateTime(2026, 5, 10), total: 11, branchId: 2);
      await seedReturn(at: DateTime(2026, 5, 10), total: 99);

      final rows =
          await db.watchPurchaseReturnRecords(branchIds: {2}).first;
      expect(rows.map((r) => r.total), containsAll([11, 99]));
    });

    test('والبحثُ يمسك رقمَ الفاتورة واسمَ المورّد', () async {
      await seedSupplier(id: 5, name: 'مورد الشرق');
      await seedInvoice(id: 32, number: 'PI-XYZ', supplierId: 5);
      await seedReturn(at: DateTime(2026, 5, 10), total: 7);
      await seedReturn(
          invoiceId: 32, supplierId: 5, at: DateTime(2026, 5, 11), total: 8);

      expect(
          (await db.watchPurchaseReturnRecords(search: 'XYZ').first)
              .map((r) => r.total),
          [8]);
      expect(
          (await db.watchPurchaseReturnRecords(search: 'الشرق').first)
              .map((r) => r.total),
          [8],
          reason: 'البحثُ باسم المورّد لا يعمل');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  test('🔴 ونوعُ سند الشيك قيمةٌ واحدةٌ في الملفَّين', () {
    // `document_record.dart` **لا يستورد `data/database`** (ولا يجوز له:
    // يقرؤه العرضُ، و`presentation_db_import_guard` مقفول)، فالقيمةُ
    // مكرّرةٌ عمداً. وافتراقُها يعني سجلّاً يرشّح على نوعٍ لا يُكتَب —
    // فيخلو من سندات الشيكات كلِّها بلا خطأٍ ولا تحذير.
    final dao = File('lib/data/database/daos/treasury_dao.dart')
        .readAsStringSync();
    expect(dao, contains("kChequeVoucherTxnType = 'cheque_voucher'"),
        reason: 'تبدّلت القيمةُ في الـDAO — والنسخةُ في domain لم تتبعها');
    expect(kChequeVoucherTxnTypeValue, 'cheque_voucher');
  });

  // ═══════════════════════════════════════════════════════════════════
  group('الفاصلُ الحاسمُ في الترتيب', () {
    // ⚠️ **ولماذا بنيويّاً لا سلوكيّاً**: عند تساوي `created_at` تماماً
    //    يُرتِّب SQLite بما يشاء، وقد **وافق** العقدَ صدفةً في هذه البيئة —
    //    فطفرةٌ تحذف الفاصلَ نجت من فحصٍ سلوكيٍّ كامل (‏R6). والمقيسُ هنا
    //    أنّنا **لا نتّكل على ترتيب المحرّك عند التعادل**: ساعةُ ويندوز
    //    ~١٥ms، وسندان في نفس الثانية واقعٌ لا فرض، وصفوفٌ تتقافز بين
    //    إعادتَي بناءٍ تُقرأ على أنّها بياناتٌ تتغيّر.
    String readSource(String path) => File(path).readAsStringSync();

    /// جسمُ دالّةٍ بعينها — فمطابقةٌ على الملفّ كلِّه تمرّ بترتيب جارتها.
    String bodyOf(String path, String signature) {
      final src = readSource(path);
      final at = src.indexOf(signature);
      expect(at, greaterThan(0), reason: 'لم تعد الدالّةُ موجودةً: $signature');
      return src.substring(at, at + 3000);
    }

    test('سجلُّ السندات يرتّب بالتاريخ **ثمّ** بالمعرّف', () {
      final body = bodyOf('lib/data/database/daos/treasury_dao.dart',
          'Stream<List<VoucherRecord>> watchVoucherRecords(');
      expect(body, contains('OrderingTerm.desc(safeTransactions.createdAt)'));
      expect(body, contains('OrderingTerm.desc(safeTransactions.id)'),
          reason: 'سقط الفاصلُ الحاسم — والترتيبُ صار رهنَ المحرّك');
    });

    test('وسجلُّ المردودات كذلك', () {
      final body = bodyOf('lib/data/database/daos/purchase_dao.dart',
          'Stream<List<PurchaseReturnRecord>> watchPurchaseReturnRecords(');
      expect(body, contains('OrderingTerm.desc(purchaseReturns.returnDate)'));
      expect(body, contains('OrderingTerm.desc(purchaseReturns.id)'),
          reason: 'سقط الفاصلُ الحاسم — و`return_date` يومٌ بلا ساعةٍ في '
              'أغلب الكتابات، فمردودات اليوم الواحد تتقافز');
    });
  });
}
