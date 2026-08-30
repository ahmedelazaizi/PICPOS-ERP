// ═══════════════════════════════════════════════════════════════════════════
// متطلبات العميل 2026-07-25 · الموجة م1 — محاسبة المشتريات
// ═══════════════════════════════════════════════════════════════════════════
//
// ح-1 — خصم فاتورة المشتريات كان يُهمل بالكامل:
//   `purchase_invoice_crud.dart` يستقبل `discount` ولا يمرّره؛
//   `CreatePurchaseInvoiceParams` بلا حقل خصم؛ `createPurchaseInvoice` بلا
//   وسيط خصم. النتيجة: فاتورة 1000 بخصم 100 تُحفظ بإجمالي 1000 ومتبقٍ 100
//   ⇒ **ذمة مورد وهمية لن تُسدَّد أبداً** + مخزون مضخّم + حساب «خصم
//   المشتريات» (4316) لا يُدائن إطلاقاً.
//
// البند 6 — التمرير عبر الذمة (معتمَد من المالك):
//   قبلاً: الشراء النقدي يدائن الصندوق مباشرة وحساب المورد **لا يتحرّك**، فلا
//   يظهر أي أثر في كشف حساب المورد في الأستاذ.
//   بعداً: الفاتورة تدائن ذمة المورد بالكامل (نقدي أو آجل)، وسند السداد
//   المُنشأ تلقائياً يدين الذمة ويدائن **الصندوق الفعلي** عبر autoPostPayment.
//   أثر ميزان المراجعة مطابق، وحساب المورد يعرض كل شراء وكل سداد.
//
// هذا يُسقط ضمناً:
//   ح-3 — الشراء النقدي الجزئي كان يدائن النقدية بالإجمالي كاملاً.
//   ح-4 — القيد كان يذهب لحساب الصندوق العام لا لصندوق الفرع الدافع.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/services/api/api_purchase_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';

void main() {
  late AppDatabase db;
  late int branchId;
  late int warehouseId;
  late int supplierId;
  late int safeId;
  const double openingSafeBalance = 10000.0;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    branchId = await db.into(db.branches).insert(BranchesCompanion.insert(
          name: 'فرع م1',
          globalId: const Value('gid-br-m1'),
        ));
    warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
            name: 'مخزن م1',
            branchId: Value(branchId),
            globalId: const Value('gid-wh-m1')));
    supplierId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'مورد م1',
          isSupplier: const Value(true),
          isCustomer: const Value(false),
          globalId: const Value('gid-sup-m1'),
        ));

    // صندوق واحد افتراضي برصيد معلوم حتى تكون فروق الخزينة قاطعة.
    await db.delete(db.safes).go();
    safeId = await db.into(db.safes).insert(SafesCompanion.insert(
          name: 'صندوق م1',
          safeType: const Value('cash'),
          isDefault: const Value(true),
          isActive: const Value(true),
          balance: const Value(openingSafeBalance),
        ));
  });

  tearDown(() async => db.close());

  Future<int> makeProduct(String code) => db.insertProduct(
        ProductsCompanion.insert(
          code: code,
          name: 'منتج $code',
          salePrice: const Value(200.0),
          costPrice: const Value(0.0),
          currentStock: const Value(0),
          trackInventory: const Value(true),
        ),
      );

  Future<double> supplierBalance() async =>
      (await (db.select(db.parties)..where((p) => p.id.equals(supplierId)))
              .getSingle())
          .balance;

  /// مجموع (مدين − دائن) على كل الحسابات التي يبدأ رمزها بـ [codePrefix]
  /// عبر كل قيود اليومية الحيّة. يغطي الحسابات الفرعية (2111-XXXXX) تلقائياً.
  Future<double> netMovement(String codePrefix) async {
    final rows = await db.customSelect(
      "SELECT COALESCE(SUM(l.debit), 0) - COALESCE(SUM(l.credit), 0) AS net "
      'FROM journal_entry_lines l '
      'JOIN accounts a ON a.id = l.account_id '
      'JOIN journal_entries e ON e.id = l.entry_id '
      "WHERE a.code LIKE '$codePrefix%'",
    ).getSingle();
    return (rows.data['net'] as num).toDouble();
  }

  /// مجموع الأطراف المدينة والدائنة على مجموعة حسابات — للتفريق بين
  /// «لم يتحرّك الحساب إطلاقاً» و«تحرّك ذهاباً وإياباً فصافيه صفر».
  Future<({double debit, double credit})> movement(String codePrefix) async {
    final r = await db.customSelect(
      'SELECT COALESCE(SUM(l.debit), 0) AS d, COALESCE(SUM(l.credit), 0) AS c '
      'FROM journal_entry_lines l '
      'JOIN accounts a ON a.id = l.account_id '
      "WHERE a.code LIKE '$codePrefix%'",
    ).getSingle();
    return (
      debit: (r.data['d'] as num).toDouble(),
      credit: (r.data['c'] as num).toDouble()
    );
  }

  Future<double> safeBalance() async =>
      (await db.getSafeById(safeId))!.balance;

  // ═════════════════════════════════════════════════════════════════════════
  // ح-1 — الخصم
  // ═════════════════════════════════════════════════════════════════════════

  test('ح-1: الشراء النقدي بخصم يُحفظ بالصافي ولا يُنشئ ذمة وهمية', () async {
    final productId = await makeProduct('M1-DISC');

    // إجمالي البضاعة 1000، خصم 100، بلا ضريبة ⇒ الصافي 900، مدفوع 900 نقداً.
    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 900.0,
      discount: 100.0,
      paymentMethod: 'cash',
      safeId: safeId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    final inv = await (db.select(db.purchaseInvoices)
          ..where((p) => p.id.equals(invoiceId)))
        .getSingle();

    // خصم **تجاري** (قرار المالك 2026-07-25): المعيار IAS 2.11 يوجب خصمه من
    // تكلفة المخزون لا إثباته إيراداً — فالطريقة صافية لا إجمالية.
    expect(inv.subtotal, closeTo(900, 0.001),
        reason: 'الإجمالي يُخزَّن صافياً من الخصم التجاري');
    expect(inv.discount, closeTo(100, 0.001),
        reason: 'الخصم يبقى محفوظاً للعرض والتدقيق');
    expect(inv.total, closeTo(900, 0.001),
        reason: 'الصافي = الإجمالي − الخصم + الضريبة');
    expect(inv.status, 'paid',
        reason: 'دُفع الصافي كاملاً ⇒ الفاتورة مسدَّدة');
    expect(inv.total - inv.paid, closeTo(0, 0.001),
        reason: 'لا متبقٍ');
    expect(await supplierBalance(), closeTo(0, 0.001),
        reason: 'لا ذمة وهمية على المورد');

    // الطريقة الصافية: المخزون يُقيَّد بالتكلفة الحقيقية 900، ولا يُثبَت
    // الخصم إيراداً على 4316 إطلاقاً.
    expect(await netMovement('1136'), closeTo(900, 0.001),
        reason: 'المخزون يُقيَّد صافياً — الخصم التجاري يخفض التكلفة');
    expect((await movement('4316')).credit, closeTo(0, 0.001),
        reason: 'الخصم التجاري ليس إيراداً');

    // المتوسط المرجّح يعكس التكلفة الحقيقية: 900 ÷ 10 = 90 لا 100.
    final product = (await db.getProductById(productId))!;
    expect(product.costPrice, closeTo(90, 0.001),
        reason: 'IAS 2.11 — التكلفة بعد الخصم التجاري');
  });

  test('الخصم التجاري: مردود كامل يُرجع التكلفة الصافية لا الإجمالية', () async {
    // كان الاسترداد يُحسب من تكاليف السطور الإجمالية بينما المتبقي صافٍ من
    // الخصم ⇒ يظهر نقد في الخزنة لم يدفعه أحد. مع التكاليف الصافية يزول
    // العطل من جذره.
    final productId = await makeProduct('M1-RETDISC');

    await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 900.0,
      discount: 100.0,
      paymentMethod: 'cash',
      safeId: safeId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    final lines = await db.customSelect(
      'SELECT quantity, unit_cost FROM purchase_invoice_items '
      'ORDER BY id DESC LIMIT 1',
    ).getSingle();
    final unitCost = (lines.data['unit_cost'] as num).toDouble();
    final qty = (lines.data['quantity'] as num).toDouble();

    expect(unitCost, closeTo(90, 0.001),
        reason: 'تكلفة السطر صافية — عليها يُبنى أي مردود لاحق');
    expect(qty * unitCost, closeTo(900, 0.001),
        reason: 'مجموع السطور = المدفوع فعلاً ⇒ المردود لا يخلق نقداً');
  });

  // ═════════════════════════════════════════════════════════════════════════
  // البند 6 — التمرير عبر الذمة
  // ═════════════════════════════════════════════════════════════════════════

  test('البند 6: الشراء النقدي يمرّ عبر ذمة المورد ثم النقدية', () async {
    final productId = await makeProduct('M1-CASH');

    await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 1000.0,
      paymentMethod: 'cash',
      safeId: safeId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    final ap = await movement('2111');
    // جوهر مطلب العميل: حساب المورد يتحرّك في الشراء النقدي أيضاً.
    expect(ap.credit, closeTo(1000, 0.001),
        reason: 'الفاتورة تدائن ذمة المورد بالكامل حتى في الشراء النقدي');
    expect(ap.debit, closeTo(1000, 0.001),
        reason: 'سند السداد يدين ذمة المورد');
    expect(ap.credit - ap.debit, closeTo(0, 0.001),
        reason: 'صافي الذمة صفر بعد السداد الكامل');

    expect(await netMovement('1136'), closeTo(1000, 0.001));
    expect((await movement('1111')).credit, closeTo(1000, 0.001),
        reason: 'النقدية تُدائن مرة واحدة فقط عبر سند السداد');
    expect(await safeBalance(), closeTo(openingSafeBalance - 1000, 0.001));
  });

  test('ح-3: الشراء النقدي الجزئي يدائن النقدية بالمدفوع لا بالإجمالي',
      () async {
    final productId = await makeProduct('M1-PARTIAL');

    await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 400.0, // مدفوع جزئي مع طريقة «نقدي»
      paymentMethod: 'cash',
      safeId: safeId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    expect((await movement('1111')).credit, closeTo(400, 0.001),
        reason: 'النقدية تُدائن بالمدفوع فقط — لا بالإجمالي');
    expect(await safeBalance(), closeTo(openingSafeBalance - 400, 0.001),
        reason: 'الخزينة تطابق الأستاذ');

    final ap = await movement('2111');
    expect(ap.credit, closeTo(1000, 0.001));
    expect(ap.debit, closeTo(400, 0.001));
    expect(ap.credit - ap.debit, closeTo(600, 0.001),
        reason: 'المتبقي على المورد 600 في الأستاذ كما في كشف الحساب');
    expect(await supplierBalance(), closeTo(600, 0.001));
  });

  test('البند 6: الشراء الآجل يبقى كما هو (انحدار)', () async {
    final productId = await makeProduct('M1-CREDIT');

    await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0.0,
      paymentMethod: 'credit',
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    expect(await netMovement('1136'), closeTo(1000, 0.001));
    final ap = await movement('2111');
    expect(ap.credit, closeTo(1000, 0.001));
    expect(ap.debit, closeTo(0, 0.001), reason: 'لا سداد ⇒ لا خصم من الذمة');
    expect(await safeBalance(), closeTo(openingSafeBalance, 0.001),
        reason: 'الشراء الآجل لا يمسّ الخزينة');
  });

  test('ح-1: الخصم يصل نسخة العميل المحلية أيضاً (وضع المرآة)', () async {
    final productId = await makeProduct('M1-CACHE');

    final invoiceId = await db.insertPurchaseInvoiceWithoutStock(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 900.0,
      discount: 100.0,
      paymentMethod: 'cash',
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    final inv = await (db.select(db.purchaseInvoices)
          ..where((p) => p.id.equals(invoiceId)))
        .getSingle();
    expect(inv.discount, closeTo(100, 0.001));
    expect(inv.total, closeTo(900, 0.001),
        reason: 'نسخة المرآة يجب أن تعرض نفس الصافي الذي يعرضه السيرفر');
    expect(inv.status, 'paid');
  });

  test('ح-1: الخصم يعبر مسار العميل ← السيرفر ولا يُفقد في الطريق', () async {
    final productId = await makeProduct('M1-WIRE');
    final handler = ApiPurchaseHandler(db, {});

    final res = await handler.postPurchase(shelf.Request(
      'POST',
      Uri.parse('http://localhost:8080/api/purchases'),
      body: json.encode({
        'globalId': 'gid-pur-m1-wire',
        'supplierId': supplierId,
        'supplierGlobalId': 'gid-sup-m1',
        'warehouseId': warehouseId,
        'paid': 900,
        'discount': 100,
        'paymentMethod': 'cash',
        'items': [
          {
            'productId': productId,
            'quantity': 10,
            'unitCost': 100,
            'total': 1000,
          },
        ],
      }), context: {ApiUserCtx.userIdKey: 1},
    ));
    expect(res.statusCode, 200);

    final inv = await (db.select(db.purchaseInvoices)
          ..where((p) => p.globalId.equals('gid-pur-m1-wire')))
        .getSingle();
    expect(inv.discount, closeTo(100, 0.001),
        reason: 'الخصم يجب أن يصل السيرفر');
    expect(inv.total, closeTo(900, 0.001));
    expect(await supplierBalance(), closeTo(0, 0.001),
        reason: 'لا ذمة وهمية على السيرفر أيضاً');
  });

  test('البند 6: تعديل فاتورة نقدية يحافظ على التمرير عبر الذمة', () async {
    final productId = await makeProduct('M1-EDIT');
    final adminId = (await db
            .customSelect("SELECT id FROM users WHERE username = 'admin' LIMIT 1")
            .getSingle())
        .read<int>('id');

    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 1000.0,
      paymentMethod: 'cash',
      safeId: safeId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    // تعديل الكمية إلى 12 مع بقاء الطريقة «نقدي» والسداد الكامل.
    await db.updatePurchaseInvoice(
      invoiceId: invoiceId,
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 1200.0,
      paymentMethod: 'cash',
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: invoiceId,
          productId: productId,
          quantity: 12,
          unitCost: 100,
          total: 1200,
        ),
      ],
      userId: adminId,
    );

    // ملاحظة: عكس السداد القديم يتم بقيد **مضاد** لا بحذف، لذا تُقاس
    // الأطراف صافيةً لا إجمالياً.
    final livePurchaseApCredit = (await db.customSelect(
      'SELECT COALESCE(SUM(l.credit), 0) AS c FROM journal_entry_lines l '
      'JOIN accounts a ON a.id = l.account_id '
      'JOIN journal_entries e ON e.id = l.entry_id '
      "WHERE a.code LIKE '2111%' "
      "  AND e.reference_type IN ('purchase', 'purchase_invoice') "
      '  AND e.reference_id = $invoiceId',
    ).getSingle())
        .data['c'] as num;
    expect(livePurchaseApCredit.toDouble(), closeTo(1200, 0.001),
        reason: 'قيد المشتريات الحيّ بعد التعديل يدائن ذمة المورد بالإجمالي '
            'الجديد — لا يعود لدائن النقدية مباشرة');

    expect(await netMovement('2111'), closeTo(0, 0.001),
        reason: 'سُدِّد بالكامل ⇒ صافي الذمة صفر');
    expect(await netMovement('1111'), closeTo(-1200, 0.001),
        reason: 'صافي النقدية = المبلغ الجديد فقط بعد عكس القديم');
    expect(await safeBalance(), closeTo(openingSafeBalance - 1200, 0.001),
        reason: 'الخزينة تطابق الأستاذ بعد التعديل');
    expect(await netMovement('1136'), closeTo(1200, 0.001),
        reason: 'المخزون يعكس الإجمالي الجديد');
  });

  test('انحدار: إلغاء فاتورة نقدية يعكس رجل النقدية والذمة معاً', () async {
    // اكتُشف في مراجعة المطابقة بعد اعتماد التمرير عبر الذمة: الإلغاء كان
    // يعكس قيد المشتريات فقط. وقبل التمرير كانت رجل النقدية **داخل** ذلك
    // القيد فيصحّح الإلغاء نفسه؛ بعده صارت في قيد سداد منفصل لا يعكسه شيء
    // ⇒ الخزينة تُستردّ بينما الأستاذ يبقى مُدائناً بالنقدية، والذمة تنقلب
    // مدينة بمقدار المدفوع.
    final productId = await makeProduct('M1-VOID');

    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 1000.0,
      paymentMethod: 'cash',
      safeId: safeId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    // إلغاء فاتورة مدفوعة بالكامل يتطلّب صلاحية حرجة صريحة حتى للأدمن
    // (Spec 062) — تُمنح هنا كما في pir_mandatory_5_tests.
    final adminRow = await db
        .customSelect(
            "SELECT id, role_id FROM users WHERE username = 'admin' LIMIT 1")
        .getSingle();
    final adminId = adminRow.read<int>('id');
    final voidPerm = await (db.select(db.permissions)
          ..where((p) => p.code.equals(PermissionCodes.voidPaidInvoice))
          ..limit(1))
        .getSingle();
    await db.addPermissionToRole(adminRow.read<int>('role_id'), voidPerm.id);

    await db.voidPurchaseInvoice(invoiceId,
        reason: 'اختبار الإلغاء', deletedBy: adminId);

    expect(await netMovement('1111'), closeTo(0, 0.001),
        reason: 'صافي حركة النقدية في الأستاذ يجب أن يعود صفراً بعد الإلغاء');
    expect(await netMovement('2111'), closeTo(0, 0.001),
        reason: 'صافي ذمة المورد يجب أن يعود صفراً — لا أن تنقلب مدينة');
    expect(await netMovement('1136'), closeTo(0, 0.001),
        reason: 'المخزون يُعكس بالكامل');
    expect(await safeBalance(), closeTo(openingSafeBalance, 0.001),
        reason: 'الخزينة تعود لرصيدها الافتتاحي');
    expect(await supplierBalance(), closeTo(0, 0.001));
  });

  test('ح-1: إعادة حفظ فاتورة بخصم دون تغيير لا تُعيد الذمة الوهمية', () async {
    // اكتُشف في المراجعة: الخصم كان موصولاً في الإنشاء فقط، فأول تعديل — حتى
    // بلا أي تغيير — يعيد الإجمالي إجمالياً ويحذف قيد الخصم ⇒ يُنقَض ح-1.
    final productId = await makeProduct('M1-EDITDISC');
    final adminId = (await db
            .customSelect("SELECT id FROM users WHERE username = 'admin' LIMIT 1")
            .getSingle())
        .read<int>('id');

    final invoiceId = await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0.0,
      discount: 100.0,
      paymentMethod: 'credit',
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    // إعادة حفظ بنفس البنود ونفس الخصم.
    await db.updatePurchaseInvoice(
      invoiceId: invoiceId,
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0.0,
      discount: 100.0,
      paymentMethod: 'credit',
      userId: adminId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: invoiceId,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    final inv = await (db.select(db.purchaseInvoices)
          ..where((p) => p.id.equals(invoiceId)))
        .getSingle();
    expect(inv.total, closeTo(900, 0.001),
        reason: 'الإجمالي يبقى صافياً بعد التعديل');
    expect(inv.discount, closeTo(100, 0.001));
    expect(await netMovement('2111'), closeTo(-900, 0.001),
        reason: 'الذمة تبقى 900 — لا تعود 1000');
    expect(await supplierBalance(), closeTo(900, 0.001));
  });

  test('ح-4: القيد النقدي يذهب لحساب الصندوق الفعلي لا للصندوق الرئيسي',
      () async {
    // صندوق فرع مرتبط بحساب نقدية مستقل عن 1111.
    final branchCashAccountId = await db.into(db.accounts).insert(
        AccountsCompanion.insert(
            code: '1111-M1BR',
            name: 'صندوق فرع م1',
            accountType: 'asset',
            globalId: const Value('gid-acc-m1-br')));
    final branchSafeId = await db.into(db.safes).insert(SafesCompanion.insert(
          name: 'صندوق الفرع',
          safeType: const Value('cash'),
          isDefault: const Value(false),
          isActive: const Value(true),
          balance: const Value(5000.0),
          branchId: Value(branchId),
          linkedAccountId: Value(branchCashAccountId),
        ));

    final productId = await makeProduct('M1-BRANCH');
    await db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 1000.0,
      paymentMethod: 'cash',
      safeId: branchSafeId,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: 10,
          unitCost: 100,
          total: 1000,
        ),
      ],
    );

    final branchAcc = await db.getAccountByCode('1111-M1BR');
    final branchLines = await db.customSelect(
      'SELECT COALESCE(SUM(credit), 0) AS c FROM journal_entry_lines '
      'WHERE account_id = ${branchAcc!.id}',
    ).getSingle();
    expect((branchLines.data['c'] as num).toDouble(), closeTo(1000, 0.001),
        reason: 'الائتمان يقع على حساب الصندوق الدافع');
    expect(await safeBalance(), closeTo(openingSafeBalance, 0.001),
        reason: 'الصندوق الرئيسي لم يُمسّ');
  });
}
