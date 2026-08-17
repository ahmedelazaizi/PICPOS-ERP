// ═══════════════════════════════════════════════════════════════════════════
// مرتجعُ المبيعات: الورديّةُ تشترط، والفرعُ يعيّن الدرج
// ═══════════════════════════════════════════════════════════════════════════
//
// المواصفة: docs/superpowers/specs/2026-08-18-sales-return-cash-shift-rule-design.md
//
// ── العطبُ الذي تحرسه هذه الاختبارات ────────────────────────────────────────
// نسبةُ حركةِ الخزنة إلى ورديّةٍ تتمّ بالنافذة الزمنيّة وحدَها —
// `safe_transactions` بلا عمود `shift_id`، و`_settleShift` يحسب `expectedCash`
// من `createdAt BETWEEN shift.startTime AND endTime`.
//
// فمرتجعٌ نقديٌّ يقع **بين** إقفالِ ورديّةٍ وفتحِ التالية لا ينتمي لأيّ نافذة:
//   • الورديّةُ المغلقةُ لا تراه — أعمدتُها كُتبت مرّةً عند الإقفال.
//   • والتاليةُ لا تراه — نافذتُها تبدأ بعده.
// والنقدُ خرج من الدرج فعلاً (والدرجُ مفرَّغٌ عند الإقفال بـSpec 107 فيصير
// سالباً). فيعدّ الكاشيرُ التالي درجَه ناقصاً بمقدار المرتجع بالضبط، ويُقيَّد
// «عجزُ نقدية» خصماً في ذمّته وهو لم يفعل شيئاً.
//
// ح‑١: لا صرفَ نقديٍّ بلا ورديّةٍ مفتوحة — ويُرفَض المرتجعُ **كلُّه**.
// ح‑٢: الدرجُ درجُ فرعِ الورديّة، لا الخزنةُ الافتراضيّةُ العامّة.
// ح‑٣: تعذُّرُ الخزنةِ يرمي ولا يُتخطّى صامتاً.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/errors/app_exceptions.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/drift_accounting_repository.dart';
import 'package:ural_erp/data/repositories/returns_repository_impl.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/domain/repositories/audit_repository_interface.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/domain/repositories/settings_repository.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/services/accounting_service.dart';

void main() {
  late AppDatabase db;
  late ReturnsRepositoryImpl repo;
  late int warehouseId;
  late int userId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    repo = ReturnsRepositoryImpl(
      db,
      AccountingService(
        DriftAccountingRepository(db),
        _StubPartiesRepo(),
        _StubTreasuryRepo(),
        _StubProductRepo(),
        _StubInventoryRepo(),
        _StubSettingsRepo(),
        _StubAuditRepo(),
      ),
    );

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'ret_shift',
      password: 'test123',
      displayName: 'كاشير المرتجعات',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'RET-01',
        name: 'منتج',
        salePrice: const Value(100.0),
        costPrice: const Value(60),
        currentStock: const Value(100),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 100,
      type: 'purchase',
      unitCost: 60,
      notes: 'رصيدٌ افتتاحيّ',
    );
  });

  // لا `db.close()`: مؤقّتُ drift ينتظر في المنطقة الوهميّة فيعلّق الاختبار.
  tearDown(() async {});

  Future<ProductEntity> productEntity() async {
    final p = await db.getProductById(productId);
    return ProductEntity(
      id: p!.id,
      name: p.name,
      code: p.code,
      salePrice: p.salePrice,
      costPrice: p.costPrice,
      currentStock: p.currentStock,
      minStock: p.minStock,
      trackInventory: p.trackInventory,
    );
  }

  /// بيعةٌ بقيمة [qty]×١٠٠، مدفوعٌ منها [paid]، بطريقة [method].
  Future<SalesInvoiceData> sell({
    double qty = 2,
    required double paid,
    String method = 'cash',
    int? customerId,
    String number = 'INV-1',
  }) async {
    final total = qty * 100;
    final id = await db.createSalesInvoice(
      invoiceNumber: number,
      warehouseId: warehouseId,
      userId: userId,
      customerId: customerId,
      subtotal: total,
      discount: 0,
      tax: 0,
      total: total,
      paid: paid,
      paymentMethod: method,
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: qty,
          unitPrice: 100,
          total: total,
          costPrice: const Value(60),
        ),
      ],
    );
    return (db.select(db.salesInvoices)..where((s) => s.id.equals(id)))
        .getSingle();
  }

  Future<bool> returnAll(SalesInvoiceData invoice) async {
    final items = await db.getSalesInvoiceItems(invoice.id);
    return repo.processSalesReturn(
      invoice: invoice,
      returnQuantities: {items.first.id: items.first.quantity},
      productCache: {productId: await productEntity()},
      reason: 'اختبار',
      userId: userId,
      userName: 'كاشير المرتجعات',
      isFullReturn: true,
    );
  }

  Future<double> cashSafeBalance(int safeId) async =>
      (await db.getSafeById(safeId))!.balance;

  group('ح‑١ — لا صرفَ نقديٍّ بلا ورديّةٍ مفتوحة', () {
    test('مرتجعٌ نقديٌّ بلا ورديّة ⇒ يُرفَض، ولا يتغيّر شيءٌ إطلاقاً', () async {
      final invoice = await sell(paid: 200);

      final safeBefore = await cashSafeBalance(1);
      final stockBefore = (await db.getProductById(productId))!.currentStock;
      final jeBefore = (await db.select(db.journalEntries).get()).length;
      final txBefore = (await db.select(db.safeTransactions).get()).length;

      await expectLater(
        returnAll(invoice),
        throwsA(isA<ShiftRequiredException>()),
      );

      // الرفضُ كاملٌ لا جزئيّ — هذا هو جوهرُ الحكم.
      expect(await cashSafeBalance(1), safeBefore,
          reason: 'لا قرشَ خرج من الدرج');
      expect((await db.getProductById(productId))!.currentStock, stockBefore,
          reason: 'ولا صنفَ عاد للمخزون');
      expect((await db.select(db.journalEntries).get()).length, jeBefore,
          reason: 'ولا قيدَ رُحِّل');
      expect((await db.select(db.safeTransactions).get()).length, txBefore,
          reason: 'ولا صفَّ خزنةٍ كُتب');

      final inv = await db.getSalesInvoiceById(invoice.id);
      expect(inv!.status, invoice.status,
          reason: 'وحالةُ الفاتورةِ الأصليّةِ لم تُمَسّ');
    });

    test('الاستثناءُ يحمل المبلغَ والكودَ ليميّزه العرض', () async {
      final invoice = await sell(paid: 200);

      try {
        await returnAll(invoice);
        fail('كان يجب أن يُرمى');
      } on ShiftRequiredException catch (e) {
        expect(e.code, 'SHIFT_REQUIRED_FOR_CASH_REFUND');
        expect(e.cashAmount, closeTo(200, 0.001));
      }
    });

    test('وبورديّةٍ مفتوحة ⇒ يمضي ويقع داخلَ نافذتها', () async {
      final shiftId = await db.openShift(userId, 0);
      final shift = await db.getCurrentOpenShift(userId);
      final invoice = await sell(paid: 200);

      expect(await returnAll(invoice), isTrue);

      final tx = await (db.select(db.safeTransactions)
            ..where((t) => t.category.equals('sales_return')))
          .getSingle();
      expect(tx.transactionType, 'payment');
      expect(tx.amount, closeTo(200, 0.001));
      expect(tx.createdAt.isBefore(shift!.startTime), isFalse,
          reason: 'يقع داخلَ نافذة الورديّة فيدخل expectedCash');

      // والبرهانُ القاطع: الإقفالُ يرى المرتجعَ فيطرحه من المتوقَّع.
      await db.closeShiftWithAudit(shiftId, 0);
      final closed = await (db.select(db.shifts)
            ..where((s) => s.id.equals(shiftId)))
          .getSingle();
      expect(closed.expectedCash, closeTo(0, 0.001),
          reason: 'بيعةٌ ٢٠٠ ومرتجعٌ ٢٠٠ ⇒ المتوقَّعُ صفر، لا عجزَ ولا فائض');
      expect(closed.variance, closeTo(0, 0.001),
          reason: 'الدرجُ عُدَّ صفراً والمتوقَّعُ صفر — لا عجزَ وهميّ');
    });

    test('مديرٌ بلا ورديّةٍ خاصّةٍ وورديّةُ الكاشير مفتوحة ⇒ يمضي', () async {
      // مديرُ النظام لا يفتح ورديّةً لنفسه عمداً (Spec 135 NOTE 2): يلتحق
      // بورديّة الكاشير ليقفلها. والدرجُ **له** ورديّةٌ مفتوحة، و`_settleShift`
      // يحسب المتوقَّع بالدرج لا بالمستخدم — فحركةُ المدير تدخل توقّعَ ورديّة
      // الكاشير ولا تُنتج عجزاً. فرفضُها كان سيكون رفضاً باطلاً.
      final managerId = await db.createUser(
        username: 'manager',
        password: 'test123',
        displayName: 'مدير',
        roleId: (await db.select(db.roles).get()).first.id,
      );
      await db.openShift(userId, 0); // ورديّةُ الكاشير وحدَها

      final invoice = await sell(paid: 200);
      final items = await db.getSalesInvoiceItems(invoice.id);

      final ok = await repo.processSalesReturn(
        invoice: invoice,
        returnQuantities: {items.first.id: items.first.quantity},
        productCache: {productId: await productEntity()},
        userId: managerId, // ← المديرُ هو المنفّذ، ولا ورديّةَ باسمه
        userName: 'مدير',
        isFullReturn: true,
      );

      expect(ok, isTrue,
          reason: 'الدرجُ له ورديّةٌ مفتوحة وإن لم تكن باسم المنفّذ');
    });

    test('مرتجعٌ آجلٌ بحتٌ بلا ورديّة ⇒ يمضي، فلا درجَ يُمَسّ', () async {
      final customerId = await db.into(db.parties).insert(
            PartiesCompanion.insert(name: 'عميل'),
          );
      final invoice =
          await sell(paid: 0, method: 'credit', customerId: customerId);

      expect(await returnAll(invoice), isTrue,
          reason: 'لم يدفع العميلُ شيئاً فلا نقدَ يُعاد ⇒ لا ورديّةَ تُشترط');
    });

    test('مرتجعٌ بنكيٌّ بحتٌ بلا ورديّة ⇒ يمضي', () async {
      await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'البنك',
              safeType: const Value('bank'),
              isDefault: const Value(true),
              globalId: const Value('gid-safe-bank'),
            ),
          );
      final invoice = await sell(paid: 200, method: 'transfer');

      expect(await returnAll(invoice), isTrue,
          reason: 'الخزنةُ البنكيّةُ ليست درجاً ولا تدخل expectedCash');
    });
  });

  group('ح‑٢ — الدرجُ درجُ فرعِ الورديّة', () {
    test('فرعان ⇒ الخصمُ على خزنةِ فرعِ الورديّة لا الافتراضيّةِ العامّة',
        () async {
      final branchB = await db.into(db.branches).insert(
            BranchesCompanion.insert(
                name: 'فرع ب', globalId: const Value('gid-br-b')),
          );
      final safeB = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'درج فرع ب',
              branchId: Value(branchB),
              balance: const Value(1000),
              safeType: const Value('cash'),
              globalId: const Value('gid-safe-b'),
            ),
          );

      await db.openShift(userId, 0, branchId: branchB);
      final invoice = await sell(paid: 200);
      // بعد البيعة: متحصَّلُها يقع على خزنةِ مخزنها (الافتراضيّةُ هنا)، وهو
      // سلوكُ البيع القائمُ ولا تمسّه هذه المواصفة. خطُّ الأساسِ يُقاس بعده
      // كي يعزل ما فعله **المرتجعُ** وحدَه.
      final defaultBefore = await cashSafeBalance(1);

      expect(await returnAll(invoice), isTrue);

      expect(await cashSafeBalance(safeB), closeTo(800, 0.001),
          reason: 'درجُ فرعِ الورديّةِ هو الذي دفع');
      expect(await cashSafeBalance(1), defaultBefore,
          reason: 'والخزنةُ الافتراضيّةُ العامّةُ لم تُمَسّ');
    });

    test('لا خزنةَ لفرع الورديّة ⇒ يرجع للافتراضيّةِ العامّة ويمضي', () async {
      final branchC = await db.into(db.branches).insert(
            BranchesCompanion.insert(
                name: 'فرع ج', globalId: const Value('gid-br-c')),
          );
      await db.openShift(userId, 0, branchId: branchC);
      final invoice = await sell(paid: 200);

      final before = await cashSafeBalance(1);
      expect(await returnAll(invoice), isTrue);
      expect(await cashSafeBalance(1), closeTo(before - 200, 0.001),
          reason: 'P3 آخرُ ملاذٍ لا فشل');
    });
  });

  group('ح‑٣ — لا تخطٍّ صامتٌ عند غياب الخزنة', () {
    test('لا خزنةَ نقديّةً إطلاقاً ⇒ يُرمى، والمرتجعُ لا يُحفَظ', () async {
      await db.openShift(userId, 0);
      final invoice = await sell(paid: 200);

      // تعطيلُ كلِّ خزنةٍ نقديّة — الحالةُ التي كان يمضي فيها المرتجعُ
      // بقيدٍ دائنُه النقديّة ودرجٍ لم يتحرّك.
      await (db.update(db.safes)..where((s) => s.safeType.equals('cash')))
          .write(const SafesCompanion(isActive: Value(false)));

      final stockBefore = (await db.getProductById(productId))!.currentStock;
      final jeBefore = (await db.select(db.journalEntries).get()).length;

      await expectLater(returnAll(invoice), throwsA(isA<Exception>()));

      expect((await db.getProductById(productId))!.currentStock, stockBefore,
          reason: 'المعاملةُ رجعت كلُّها — لا صنفَ عاد');
      expect((await db.select(db.journalEntries).get()).length, jeBefore,
          reason: 'ولا قيدَ يقول «خرج نقد» بلا نقدٍ خرج');
    });
  });

  group('المسارُ الثاني: `createSalesInvoice(saleType:return)`', () {
    // هذا هو المسارُ الذي يسلكه «المرتجع السريع» في نقطة البيع، **وهو نفسُه**
    // الذي يسلكه الخادمُ حين يصله مرتجعُ عميلٍ عبر `postSalesReturn`.
    //
    // يُقاس هنا لأنّ قراءةَ `api_sales_handler` وحدَها تُوهم أنّ الخادمَ لا
    // يحرّك درجاً (لا `safeTransactions` ولا `adjustSafeBalance` في نصّه):
    // الكتابةُ تقع داخلَ `createSalesInvoice` عبر `_recordSalesReceipt`.
    test('مرتجعٌ نقديٌّ بهذا المسار يخصم من الخزنة فعلاً', () async {
      final before = await cashSafeBalance(1);

      await db.createSalesInvoice(
        invoiceNumber: 'SRET-QUICK',
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 100,
        discount: 0,
        tax: 0,
        total: 100,
        paid: 100,
        paymentMethod: 'cash',
        saleType: 'return',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1,
            unitPrice: 100,
            total: 100,
            costPrice: const Value(60),
          ),
        ],
      );

      expect(await cashSafeBalance(1), closeTo(before - 100, 0.001),
          reason: 'الخادمُ يحرّك الدرجَ لمرتجع العميل — خلافاً لما توهمه '
              'قراءةُ معالج الـAPI وحدَه');

      final tx = await (db.select(db.safeTransactions)
            ..where((t) => t.category.equals('return')))
          .get();
      expect(tx, isNotEmpty, reason: 'وصفُّ خزنةٍ يُكتَب بفئة return');
    });
  });

  group('الإيصالُ يطبع ما تحرّك فعلاً', () {
    test('مرتجعُ بيعةٍ آجلة ⇒ الإيصالُ لا يزعم صرفاً نقديّاً', () async {
      final customerId = await db.into(db.parties).insert(
            PartiesCompanion.insert(name: 'عميل آجل'),
          );
      final invoice = await sell(
          paid: 0, method: 'credit', customerId: customerId, number: 'INV-CR');

      final printData = await repo.getSalesReturnPrintData(
        invoiceNumber: invoice.invoiceNumber,
        returnTotal: 200,
        returnQuantities: const {},
      );

      expect(printData, isNotNull);
      expect(printData!.cashRefund, closeTo(0, 0.001),
          reason: 'لم يخرج من الدرج قرشٌ، فلا يُطبع للعميل أنّه قبض');
      expect(printData.bankRefund, closeTo(0, 0.001));
    });

    test('مرتجعُ بيعةٍ نقديّةٍ مدفوعة ⇒ الإيصالُ يعرض النقدَ كاملاً', () async {
      final invoice = await sell(paid: 200, number: 'INV-CASH');

      final printData = await repo.getSalesReturnPrintData(
        invoiceNumber: invoice.invoiceNumber,
        returnTotal: 200,
        returnQuantities: const {},
      );

      expect(printData!.cashRefund, closeTo(200, 0.001));
    });
  });
}

// ── Collaborator stubs ──────────────────────────────────────────────────────

class _StubPartiesRepo implements IPartiesRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubTreasuryRepo implements ITreasuryRepository {
  @override
  Future<List<Map<String, dynamic>>> getSafeAccountsForReference(
          String referenceType, int referenceId) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubProductRepo implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubInventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubSettingsRepo implements ISettingsRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

class _StubAuditRepo implements IAuditRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}
