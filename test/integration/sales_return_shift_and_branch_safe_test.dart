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
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/core/errors/app_exceptions.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/data/repositories/returns_repository_impl.dart';
import 'package:picpos_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/repositories/kitchen_repository.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';
import 'package:picpos_erp/domain/repositories/printers_repository.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/services/accounting_service.dart';

void main() {
  late AppDatabase db;
  late ReturnsRepositoryImpl repo;
  late SalesTransactionOrchestrator orchestrator;
    late int warehouseId;
  late int userId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    final accountingService = AccountingService(
      DriftAccountingRepository(db),
      _StubPartiesRepo(),
      _StubTreasuryRepo(),
      _StubProductRepo(),
      _StubInventoryRepo(),
      _StubSettingsRepo(),
      _StubAuditRepo(),
    );
    repo = ReturnsRepositoryImpl(db, accountingService);

    // مسارُ «المرتجع السريع» في نقطة البيع. ولا مطبخَ في التوقيع: أوامرُ
    // التحضير تُولَد من شاشة الطاولات وحدَها، فسقطت تبعيّةُ `KitchenService`
    // من المنسّق (2026-08-18) — يحرسها
    // `test/structural/kitchen_work_orders_from_tables_only_test.dart`.
    orchestrator = SalesTransactionOrchestrator(
      db,
      accountingService,
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
        password: 'mgr_pw_249',
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
    test('المرتجعُ السريع بلا ورديّة ⇒ يُرفَض ولا يخصم', () async {
      // الثغرةُ التي كانت قائمة: «المرتجع السريع» يسلك الأوركستريتر لا
      // `processSalesReturn`، فلم يكن يمرّ بحارسٍ إطلاقاً. يحرسه عمليّاً
      // `_ensureShiftOpen` من الشاشة — **ويُتخطّى لمدير النظام عمداً**
      // (Spec 135 NOTE 2) — فمديرٌ يُجري مرتجعاً سريعاً بلا ورديّة كان نقدُه
      // يخرج بلا نافذةٍ تحويه ⇒ عجزٌ وهميٌّ في ذمّة الكاشير التالي.
      final before = await cashSafeBalance(1);

      await expectLater(
        orchestrator.createSalesInvoice(
          customerId: null,
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
            CartItemEntity(
              productId: productId,
              productName: 'منتج',
              productCode: 'RET-01',
              quantity: 1,
              unitPrice: 100,
            ),
          ],
        ),
        throwsA(isA<ShiftRequiredException>()),
      );

      expect(await cashSafeBalance(1), before,
          reason: 'لا قرشَ خرج — الرفضُ قبل فتحِ المعاملة');
    });

    test('المرتجعُ السريع بورديّةٍ مفتوحة ⇒ يمضي', () async {
      await db.openShift(userId, 0);
      final before = await cashSafeBalance(1);

      await orchestrator.createSalesInvoice(
        customerId: null,
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
          CartItemEntity(
            productId: productId,
            productName: 'منتج',
            productCode: 'RET-01',
            quantity: 1,
            unitPrice: 100,
          ),
        ],
      );

      expect(await cashSafeBalance(1), closeTo(before - 100, 0.001));
    });

    test('بيعةٌ نقديّةٌ بلا ورديّة ⇒ تُرفَض ولا يدخل الدرجَ شيء', () async {
      // نظيرُ فجوةِ المرتجع بالإشارة المعاكسة: نقدٌ يدخل بلا نافذةٍ تحويه ⇒
      // الكاشيرُ التالي يعدّ درجَه **زائداً** ⇒ يُقيَّد «فائض نقدية» مدين
      // نقدية / دائن إيراد، والمبلغُ نفسُه قُيِّد بقيد البيعة. فالنقديةُ في
      // الأستاذ مرّتين وإيرادٌ لا وجودَ له.
      final before = await cashSafeBalance(1);

      await expectLater(
        orchestrator.createSalesInvoice(
          customerId: null,
          warehouseId: warehouseId,
          userId: userId,
          subtotal: 100,
          discount: 0,
          tax: 0,
          total: 100,
          paid: 100,
          paymentMethod: 'cash',
          items: [
            CartItemEntity(
              productId: productId,
              productName: 'منتج',
              productCode: 'RET-01',
              quantity: 1,
              unitPrice: 100,
            ),
          ],
        ),
        throwsA(isA<ShiftRequiredException>()),
      );

      expect(await cashSafeBalance(1), before);
    });

    test('بيعةٌ بنكيّةٌ بلا ورديّة ⇒ تمضي، فلا درجَ يُمَسّ', () async {
      await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'بنك البيع',
              safeType: const Value('bank'),
              isDefault: const Value(true),
              globalId: const Value('gid-safe-bank-sale'),
            ),
          );
      final drawerBefore = await cashSafeBalance(1);

      await orchestrator.createSalesInvoice(
        customerId: null,
        warehouseId: warehouseId,
        userId: userId,
        subtotal: 100,
        discount: 0,
        tax: 0,
        total: 100,
        paid: 100,
        paymentMethod: 'bank',
        items: [
          CartItemEntity(
            productId: productId,
            productName: 'منتج',
            productCode: 'RET-01',
            quantity: 1,
            unitPrice: 100,
          ),
        ],
      );

      expect(await cashSafeBalance(1), drawerBefore,
          reason: 'الخزنةُ البنكيّةُ ليست درجاً — لا ورديّةَ تُشترط ولا درجَ يتغيّر');
    });

    test('المسارُ الحقيقيُّ لنقطة البيع (`completeSalesTransaction`) محروسٌ كذلك',
        () async {
      // ⚠️ الحارسُ في `createSalesInvoice` وحدَه **لا يكفي**: نقطةُ البيع
      // تنادي `completeSalesTransaction`، وشقُّ وضعِ العميل فيها يكتب
      // فاتورتَه بـ`insertSalesInvoiceWithoutStock` ولا يمرّ بـ
      // `createSalesInvoice` إطلاقاً. فالحارسُ وُضع قبل تفرّعِ `isClientMode`.
      final before = await cashSafeBalance(1);

      // يرمي ولا يُرجِع `SaleResult.failure`: الفشلُ النصّيُّ يُضيّع النوعَ
      // فلا تعرف الواجهةُ أن تعرض «افتح ورديّة» بدل رسالةٍ حمراءَ لا مخرجَ
      // منها — نفسُ درسِ المزوّد في مسار المرتجع.
      await expectLater(
        orchestrator.completeSalesTransaction(
          SaleRequest(
            items: [
              CartItemEntity(
                productId: productId,
                productName: 'منتج',
                productCode: 'RET-01',
                quantity: 1,
                unitPrice: 100,
              ),
            ],
            paymentMethod: 'cash',
            paidAmount: 100,
            warehouseId: warehouseId,
            userId: userId,
          ),
        ),
        throwsA(isA<ShiftRequiredException>()),
      );

      expect(await cashSafeBalance(1), before, reason: 'ولا قرشَ دخل الدرج');
    });

    test('بيعةُ مديرٍ وورديّةُ الكاشير مفتوحة ⇒ تمضي بلا سؤال', () async {
      // لا يُحجَب المديرُ عن البيع: الدرجُ له ورديّةٌ وإن لم تكن باسمه، وهي
      // الحالةُ التي عالجها فصلُ `txs` عن `drawerTxs` أصلاً.
      final managerId = await db.createUser(
        username: 'mgr_sale',
        password: 'mgr_pw_550',
        displayName: 'مدير',
        roleId: (await db.select(db.roles).get()).first.id,
      );
      await db.openShift(userId, 0); // ورديّةُ الكاشير وحدَها
      final before = await cashSafeBalance(1);

      await orchestrator.createSalesInvoice(
        customerId: null,
        warehouseId: warehouseId,
        userId: managerId,
        subtotal: 100,
        discount: 0,
        tax: 0,
        total: 100,
        paid: 100,
        paymentMethod: 'cash',
        items: [
          CartItemEntity(
            productId: productId,
            productName: 'منتج',
            productCode: 'RET-01',
            quantity: 1,
            unitPrice: 100,
          ),
        ],
      );

      expect(await cashSafeBalance(1), closeTo(before + 100, 0.001));
    });

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

  group('ح‑١ — تمييزُ الدرج من الصندوق الرئيسي (`drawerMovementAllowed`)', () {
    // العائقُ الذي أخّر هذا البند كان: «لا يميّز النموذجُ خزنةَ الدرج من
    // الرئيسيّة». والقياسُ أسقطه: التمييزُ **قائمٌ** عبر `getCentralSafe()`
    // التي تحسم الرئيسيَّ بـglobalId مشتقٍّ مستقرّ (لا بالاسم، فالاسمُ قابلٌ
    // للتعديل). فالمحاسبُ في المقرّ مُعفًى والكاشيرُ على درجه محروس.
    //
    // والسؤالُ عن **فرعِ الخزنة** لا عن المستخدم: عقدُ السندات لا يحمل
    // `userId` أصلاً، فربطُ الحكمِ بالمستخدم كان سيُفتي بلا معلومة.
    test('درجٌ بلا ورديّة ⇒ ممنوع', () async {
      final drawer = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'درج الكاشير',
              safeType: const Value('cash'),
              globalId: const Value('gid-drawer-1'),
            ),
          );
      expect(await db.drawerMovementAllowed(drawer), isFalse);
    });

    test('نفسُ الدرج وورديّةٌ مفتوحة ⇒ مسموح', () async {
      final drawer = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'درج الكاشير 2',
              safeType: const Value('cash'),
              globalId: const Value('gid-drawer-2'),
            ),
          );
      await db.openShift(userId, 0);
      expect(await db.drawerMovementAllowed(drawer), isTrue);
    });

    test('الصندوقُ الرئيسيُّ مُعفًى ولو لا ورديّةَ إطلاقاً', () async {
      final central = await db.getCentralSafe();
      expect(central, isNotNull, reason: 'مزروعٌ في التهيئة الأساسيّة');
      expect(await db.drawerMovementAllowed(central!.id), isTrue,
          reason: 'المحاسبُ في المقرّ يسجّل سنداتِه بلا ورديّة');
    });

    test('الخزنةُ البنكيّةُ ليست درجاً ⇒ مسموحٌ بلا ورديّة', () async {
      final bank = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'بنك',
              safeType: const Value('bank'),
              globalId: const Value('gid-bank-1'),
            ),
          );
      expect(await db.drawerMovementAllowed(bank), isTrue);
    });

    test('درجُ فرعٍ آخرَ لا تُجيزه ورديّةُ فرعٍ غيره', () async {
      final branchA = await db.into(db.branches).insert(
            BranchesCompanion.insert(
                name: 'فرع أ', globalId: const Value('gid-br-a2')),
          );
      final branchB = await db.into(db.branches).insert(
            BranchesCompanion.insert(
                name: 'فرع ب', globalId: const Value('gid-br-b2')),
          );
      final drawerB = await db.into(db.safes).insert(
            SafesCompanion.insert(
              name: 'درج ب',
              safeType: const Value('cash'),
              branchId: Value(branchB),
              globalId: const Value('gid-drawer-b'),
            ),
          );
      await db.openShift(userId, 0, branchId: branchA); // ورديّةٌ على «أ» فقط

      expect(await db.drawerMovementAllowed(drawerB), isFalse,
          reason: 'ورديّةُ فرعٍ لا تفتح درجَ فرعٍ آخر');
    });
  });

  group('قفلُ الفترة المحاسبيّة — حراسةٌ قائمةٌ تُثبَّت', () {
    // ⚠️ اختبارُ انحدارٍ لا إصلاح. المواصفةُ زعمت (§٢‑٧) أنّ مسارَ المرتجع
    // يتخطّى قفلَ الفترة لأنّه يكتب صفَّ الخزنة بـ`insert` مباشرٍ متجنّباً
    // `createSafeTransaction` (ومعه `validateFinancialPeriod`). والزعمُ
    // **دقيقٌ حرفيّاً ومضلّلٌ عمليّاً**: المعاملةُ كلُّها تُرفض قبل أن يبقى
    // شيء — عبر `adjustStock` للصنف المخزنيّ، وعبر `createJournalEntry`
    // للخدمة. هذان الاختباران يمنعان انكسارَ ذلك بترتيبٍ مختلفٍ لاحقاً أو
    // بابتلاعِ استثناءٍ في مسار الترحيل.
    Future<void> closeCurrentPeriod() async {
      final now = DateTime.now();
      await (db.update(db.accountingPeriods)
            ..where((p) => p.month.equals(now.month) & p.year.equals(now.year)))
          .write(const AccountingPeriodsCompanion(isClosed: Value(true)));
    }

    test('مرتجعُ صنفٍ مخزنيٍّ في فترةٍ مقفلة ⇒ يُرفَض بلا أثر', () async {
      await db.openShift(userId, 0);
      final invoice = await sell(paid: 200);
      final safeBefore = await cashSafeBalance(1);
      final stockBefore = (await db.getProductById(productId))!.currentStock;

      await closeCurrentPeriod();

      await expectLater(returnAll(invoice), throwsA(isA<Exception>()));
      expect(await cashSafeBalance(1), safeBefore);
      expect((await db.getProductById(productId))!.currentStock, stockBefore);
    });

    test('بيعةٌ نقديّةٌ في فترةٍ مقفلة ⇒ تُرفَض بلا أثر', () async {
      await db.openShift(userId, 0);
      await closeCurrentPeriod();
      final before = await cashSafeBalance(1);

      await expectLater(sell(paid: 200, number: 'INV-CLOSED'),
          throwsA(isA<Exception>()));
      expect(await cashSafeBalance(1), before);
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

  // ignore: unused_element
class _StubKitchenRepo implements KitchenRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}

  // ignore: unused_element
class _StubPrintersRepo implements IPrintersRepository {
  @override
  dynamic noSuchMethod(Invocation inv) =>
      throw UnsupportedError('Stub: ${inv.memberName}');
}
