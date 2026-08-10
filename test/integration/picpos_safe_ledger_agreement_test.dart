// ═══════════════════════════════════════════════════════════════════════════
// «الخزنة والأستاذ لا يتفقان» — H1 · H2 · H5
// ═══════════════════════════════════════════════════════════════════════════
//
// H1 · بيعةُ كاشٍ بلا خزنةٍ صالحة: `_recordSalesReceipt` يخرج بـ`return`
//   **صامت**. الفاتورةُ تُحفظ وقيدُها يُقيَّد (مدين نقدية) والدرجُ لا يتحرّك
//   إطلاقاً ⇒ عجزٌ عند الإقفال بحجم البيعة، وحسابُ النقدية في الأستاذ
//   منفصلٌ عن الخزائن. لا رسالةَ للكاشير ولا صفَّ فشلٍ يُراجَع.
//
// H2 · فرقُ الوردية يُقيَّد في الأستاذ بلا طرفٍ في الخزنة: عجزُ ٥٠ يُنقص
//   حسابَ النقدية ٥٠ ويترك `safes.balance` كما هو ⇒ الفجوةُ تتراكم كلَّ
//   وردية، ولا أثرَ للفرق في كشف حركة الخزنة.
//
// H5 · الدفعةُ الجزئية على عميلٍ معروف تُقيَّد على **حساب المراقبة** (‏١١٢١)
//   لا على حسابه الفرعيّ — بينما ثمانيةُ مواضعَ أخرى في نفس الملف تستعمل
//   `_resolvePartySubAccount`. فكشفُ حساب العميل من الأستاذ ينقصه الباقي.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    warehouseId = (await db.getDefaultWarehouse())!.id;
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير SL', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'sl_cashier',
      password: 'pw',
      displayName: 'SL Cashier',
      roleId: roleId,
    );
    productId = await db.insertProduct(ProductsCompanion.insert(
      code: 'SL-1',
      name: 'صنف',
      salePrice: const Value(100),
      costPrice: const Value(60),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 500,
      type: 'in',
      unitCost: 60,
    );
  });

  tearDown(() async => db.close());

  Future<int> sale({
    required double total,
    required double paid,
    int? customerId,
    String paymentMethod = 'cash',
    int? cashSafeId,
  }) =>
      db.createSalesInvoice(
        warehouseId: warehouseId,
        userId: userId,
        customerId: customerId,
        subtotal: total,
        discount: 0,
        tax: 0,
        total: total,
        paid: paid,
        paymentMethod: paymentMethod,
        cashAmount: paid,
        cashSafeId: cashSafeId,
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: total / 100,
            unitPrice: 100,
            total: total,
            costPrice: const Value(60),
          ),
        ],
      );

  Future<double> accountNet(int accountId) async {
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.accountId.equals(accountId)))
        .get();
    return lines.fold<double>(0, (s, l) => s + l.debit - l.credit);
  }

  /// نقديةُ الخزائن في الأستاذ — **مجموعُ الفرع** تحت `111` لا حسابٌ مفرد.
  ///
  /// كان يقرأ `1111` وحدَه. ومنذ صار لكلّ خزنةٍ حسابٌ فرعيٌّ خاصٌّ تحت `111`
  /// (‏`linkUnlinkedSafesToSubAccounts`) لم يعد رقمٌ واحدٌ يمثّل النقدية —
  /// وهو المقصودُ من التغيير نفسِه: الخزائنُ تُميَّز في الأستاذ. والمجموعُ
  /// هو ما يقابل «الدرج» في الطرف الآخر من هذه المساواة، فالمقيسُ ما زال
  /// «الدرجُ والأستاذ يتحرّكان معاً» لا موضعَ حسابٍ بعينه.
  Future<double> cashAccountNet() async {
    final parent = await db.getAccountByCode('111');
    if (parent == null) return 0;
    final children = await (db.select(db.accounts)
          ..where((a) => a.parentId.equals(parent.id)))
        .get();
    var sum = await accountNet(parent.id);
    for (final c in children) {
      sum += await accountNet(c.id);
    }
    return sum;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // H1
  // ═════════════════════════════════════════════════════════════════════════

  group('H1 — بيعةُ كاشٍ بلا خزنةٍ صالحة', () {
    Future<void> disableAllCashSafes() async {
      await (db.update(db.safes)..where((s) => s.safeType.equals('cash')))
          .write(const SafesCompanion(isActive: Value(false)));
    }

    test('ضابط: مع خزنةٍ صالحة، الدرجُ والأستاذ يتحرّكان معاً', () async {
      await sale(total: 200, paid: 200);
      final safe = (await db.getDefaultSafeByType('cash'))!;
      expect(safe.balance, closeTo(200, 0.01));
      expect(await cashAccountNet(), closeTo(200, 0.01));
    });

    test('بلا خزنةٍ صالحة: البيعةُ تُرفض ولا يبقى نصفُ عملية', () async {
      await disableAllCashSafes();

      await expectLater(
        sale(total: 200, paid: 200),
        throwsA(anything),
        reason: 'اتقاس `return` صامت: الفاتورةُ تتحفظ وقيدُها يتقيّد والدرجُ '
            'ما يتحركش ⇒ عجزٌ ٢٠٠ عند الإقفال بلا سبب.',
      );

      final invoices = await db.select(db.salesInvoices).get();
      expect(invoices, isEmpty,
          reason: 'الرفضُ لازم يرجّع كلَّ حاجة — لا فاتورةَ بلا نقدية.');
      expect(await cashAccountNet(), closeTo(0, 0.01),
          reason: 'ولا قيدَ نقديةٍ لبيعةٍ ما دخلتش الدرج.');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // H5
  // ═════════════════════════════════════════════════════════════════════════

  group('H5 — الدفعةُ الجزئية', () {
    test('الباقي يقع على الحساب الفرعيّ للعميل لا على المراقبة', () async {
      final customerId = await db.insertParty(PartiesCompanion.insert(
        name: 'عميل الدفعة',
        isCustomer: const Value(true),
      ));

      await sale(total: 500, paid: 300, customerId: customerId);

      final party = await (db.select(db.parties)
            ..where((p) => p.id.equals(customerId)))
          .getSingle();
      expect(party.accountId, isNotNull,
          reason: 'تجهيزة: العميل لازم يكون له حسابٌ فرعيّ');

      expect(
        await accountNet(party.accountId!),
        closeTo(200, 0.01),
        reason: 'اتقاس صفر — الباقي (٢٠٠) اتقيّد على حساب المراقبة ١١٢١، '
            'فكشفُ حساب العميل من الأستاذ ناقصٌ بمقدار الدين. وثمانيةُ '
            'مواضعَ في نفس الملف بتستعمل `_resolvePartySubAccount` أصلاً.',
      );
    });

    test('ضابط: البيعةُ الآجلةُ الكاملة بتقع على الفرعيّ فعلاً', () async {
      final customerId = await db.insertParty(PartiesCompanion.insert(
        name: 'عميل آجل',
        isCustomer: const Value(true),
      ));
      await sale(
          total: 400, paid: 0, customerId: customerId, paymentMethod: 'credit');

      final party = await (db.select(db.parties)
            ..where((p) => p.id.equals(customerId)))
          .getSingle();
      expect(await accountNet(party.accountId!), closeTo(400, 0.01));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // H2
  // ═════════════════════════════════════════════════════════════════════════

  group('H2 — فرقُ الوردية', () {
    test('العجزُ ينزل من الخزنة كما ينزل من الأستاذ', () async {
      final shiftId = await db.openShift(userId, 0);
      await sale(total: 200, paid: 200);

      final beforeClose = (await db.getDefaultSafeByType('cash'))!.balance;
      expect(beforeClose, closeTo(200, 0.01), reason: 'تجهيزة: الدرج فيه ٢٠٠');

      // الكاشير عدّ ١٥٠ — عجزُ ٥٠ حقيقيّ.
      await db.closeShiftWithAudit(shiftId, 150);

      final shift = await (db.select(db.shifts)
            ..where((s) => s.id.equals(shiftId)))
          .getSingle();
      expect(shift.variance, closeTo(-50, 0.01), reason: 'تجهيزة: العجزُ ٥٠');

      final varianceTxns = await (db.select(db.safeTransactions)
            ..where((t) => t.category.equals('shift_variance')))
          .get();
      expect(
        varianceTxns,
        isNotEmpty,
        reason: 'اتقاس صفر صفوف — الفرقُ يُقيَّد في الأستاذ (دائن نقدية ٥٠) '
            'بلا أيّ طرفٍ في الخزنة، فرصيدُ الخزنة يفضل أعلى من الأستاذ '
            'بـ٥٠ وتتراكم الفجوةُ كلَّ وردية، ولا أثرَ للعجز في كشف الحركة.',
      );
      expect(varianceTxns.first.amount, closeTo(50, 0.01));
      expect(varianceTxns.first.transactionType, 'payment');
    });

    test('ضابط: إقفالٌ بلا فرقٍ لا يكتب صفَّ تسوية', () async {
      final shiftId = await db.openShift(userId, 0);
      await sale(total: 200, paid: 200);
      await db.closeShiftWithAudit(shiftId, 200);

      final varianceTxns = await (db.select(db.safeTransactions)
            ..where((t) => t.category.equals('shift_variance')))
          .get();
      expect(varianceTxns, isEmpty);
    });
  });
}
