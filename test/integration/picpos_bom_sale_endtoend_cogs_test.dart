// ═══════════════════════════════════════════════════════════════════════════
// بيعُ الصنف المركّب من **المسار الحقيقي** — لا بنداءٍ مباشرٍ للمصنع
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️ `bom_sale_cogs_test.dart` أخضرُ وهو **لا يغطّي هذا**: ينادي
// `AccountingService.generateSalesAccountingEntry` مباشرةً ويناوله
// `cogsBreakdown` جاهزاً بيده. فيثبت أن المصنع يحسن التصرّف لو **وصلَه**
// التفصيل، ولا يقول شيئاً عمّا إذا كان يصله أصلاً.
//
// والمسارُ الحقيقيّ فيه ترتيب: `SalesTransactionOrchestrator` ينادي
// `SalesMutationsDao.createSalesInvoice`، وهذا الأخير يُصدر القيدَ بنفسه في
// «‏Phase 8» **قبل** أن يعود للمنسّق، والمنسّقُ هو وحدَه من يملك
// `cogsBreakdown` (‏من `applyAutoDepleteForSale`).
//
// فالصنفُ المركّب تكلفتُه صفرٌ على سطر الفاتورة (‏تكلفتُه في خاماته)، وقيدُ
// «Phase 8» يُبنى من سطور الفاتورة وحدَها ⇒ **إيرادٌ بصفر تكلفة**: هامشٌ
// ١٠٠٪ والخاماتُ خرجت من المخزن فعلاً.
//
// الاختبار ده بيقيس الأستاذَ بعد بيعةٍ كاملةٍ من المنسّق، فلا يمكن أن يمرّ
// بترتيبٍ خاطئ مهما كان المصنعُ سليماً.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late SalesTransactionOrchestrator orch;
  late int userId;
  late int warehouseId;
  late int mealId;
  late int rawId;

  const rawCost = 30.0; // تكلفةُ الخامة للوحدة
  const rawPerMeal = 2.0; // كلُّ وجبةٍ تستهلك وحدتَين
  const mealPrice = 100.0;
  const mealQty = 1.0;
  const expectedCogs = rawCost * rawPerMeal * mealQty; // ٦٠

  /// صافي الحركة على حسابٍ بالكود المعطى عبر كل القيود (مدين − دائن).
  Future<double> netDebit(String purpose, String fallbackCode) async {
    final code = await db.getMappedAccountCode(
        purpose, AccountingDao.accountPurposes[purpose] ?? fallbackCode);
    final acc = await db.getAccountByCode(code);
    if (acc == null) return 0;
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.accountId.equals(acc.id)))
        .get();
    return lines.fold<double>(0, (s, l) => s + l.debit - l.credit);
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    orch = SalesTransactionOrchestrator(
      db,
      container.read(accountingServiceProvider),
      container.read(kitchenServiceProvider),
    );

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير BOM', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'bom_cashier',
      password: 'pw',
      displayName: 'BOM Cashier',
      roleId: roleId,
    );
    warehouseId = (await db.getDefaultWarehouse())!.id;

    // الصنفُ المركّب: لا يُتابَع مخزونياً وتكلفتُه صفر — الحالةُ الطبيعية.
    mealId = await db.insertProduct(ProductsCompanion.insert(
      code: 'MEAL-E2E',
      name: 'سيخ كباب',
      salePrice: const Value(mealPrice),
      costPrice: const Value(0),
      trackInventory: const Value(false),
    ));
    rawId = await db.insertProduct(ProductsCompanion.insert(
      code: 'RAW-E2E',
      name: 'لحمة',
      costPrice: const Value(rawCost),
      trackInventory: const Value(true),
    ));
    await db.adjustStock(
      productId: rawId,
      warehouseId: warehouseId,
      quantity: 100,
      type: 'in',
      unitCost: rawCost,
      notes: 'رصيدٌ افتتاحيّ',
    );

    final bomId = await db.into(db.billOfMaterials).insert(
          BillOfMaterialsCompanion.insert(
            finishedProductId: mealId,
            bomCode: 'BOM-E2E',
            autoDepleteOnSale: const Value(true),
            // FR-004: الخصمُ التلقائيّ يشترط قائمةً فعّالة — بدونها يتخطّى
            // البحثُ القائمةَ صامتاً ويقيس الاختبارُ حاجةً تانية خالص.
            isActive: const Value(true),
            depletionPolicy: const Value('always_auto_deplete'),
          ),
        );
    await db.into(db.bomComponents).insert(BomComponentsCompanion.insert(
          bomId: bomId,
          rawMaterialId: rawId,
          quantity: rawPerMeal,
        ));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<int> sellMeal() => orch.createSalesInvoice(
        customerId: null,
        warehouseId: warehouseId,
        userId: userId,
        subtotal: mealPrice,
        discount: 0,
        tax: 0,
        total: mealPrice,
        paid: mealPrice,
        paymentMethod: 'cash',
        items: [
          CartItemEntity(
            productId: mealId,
            productName: 'سيخ كباب',
            productCode: 'MEAL-E2E',
            quantity: mealQty,
            unitPrice: mealPrice,
          ),
        ],
      );

  test('ضابط: الخامة بتخرج من المخزن فعلاً', () async {
    await sellMeal();
    final raw = (await db.getProductById(rawId))!;
    expect(raw.currentStock, closeTo(100 - rawPerMeal * mealQty, 0.001),
        reason: 'لو ده وقع فالخصمُ التلقائيُّ نفسُه ما اشتغلش والاختبار '
            'اللي بعده هيقيس حاجة تانية خالص');
  });

  test('الأستاذ يحمل تكلفةَ الخامات — لا إيراداً بصفر تكلفة', () async {
    await sellMeal();

    expect(
      await netDebit('cogs', '5111'),
      closeTo(expectedCogs, 0.01),
      reason: 'اتقاس صفر — قيدُ «Phase 8» في SalesMutationsDao اتبنى من سطور '
          'الفاتورة وحدها، وتكلفةُ الصنف المركّب صفرٌ عليها. الخاماتُ خرجت '
          'من المخزن والأستاذُ ما شافش تكلفتَها: هامشٌ ١٠٠٪ وربحٌ وهميّ '
          'بحجم التكلفة.',
    );
  });

  test('وحسابُ المخزون ينزل بنفس المبلغ — ولا يتضخّم', () async {
    await sellMeal();

    // الرصيدُ الافتتاحيُّ هنا دخل بـ`adjustStock(type: 'in')` وهو **لا
    // يُقيَّد** في الأستاذ (ليس من `adjustmentAccountedTypes`)، فالحركةُ
    // الوحيدةُ على حساب المخزون هي الطرفُ الدائنُ لتكلفة البيعة.
    expect(
      await netDebit('inventory', '1131'),
      closeTo(-expectedCogs, 0.01),
      reason: 'المخزون لازم ينزل بتكلفة الخامات المستهلكة. لو فضل صفراً '
          'فحسابُ المخزون في الأستاذ منفصلٌ عن الرفّ، ومرتجعٌ لاحقٌ '
          '(اللي بيحترم تكلفةَ الخام) هيخلّي الفجوةَ دائمة.',
    );
  });

  test('الإيراد يُقيَّد مرّةً واحدة — لا قيدين لنفس البيعة', () async {
    final invoiceId = await sellMeal();

    final entries = await (db.select(db.journalEntries)
          ..where((j) => j.referenceId.equals(invoiceId)))
        .get();
    final revenueLike = entries
        .where((e) => e.referenceType == 'sale' || e.referenceType == 'sales_invoice')
        .toList();

    expect(revenueLike, hasLength(1),
        reason: 'المنسّقُ والـDAO الاثنان بيصدروا قيداً لنفس البيعة بمرجعين '
            'مختلفين (sale / sales_invoice)، فالتكرار ما بيتحرسش بحارس '
            'الازدواج — إيرادٌ مرّتين في الأستاذ.');
    expect(
      await netDebit('sales_revenue', '4121'),
      closeTo(-mealPrice, 0.01),
      reason: 'صافي الإيراد دائنٌ بقيمة البيعة مرّةً واحدة.',
    );
  });
}
