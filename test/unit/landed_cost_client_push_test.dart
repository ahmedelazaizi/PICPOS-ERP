// v166 / المرحلة ٢ — تطبيقُ ورقة تحميلٍ من **عميل** يُرسَل ولا يُحسَب محلّيّاً.
//
// ═══ العطبُ الذي يمنعه هذا الملفّ ═══
//
// 🔴 **قيدان لحدثٍ واحد.** إزالةُ تكرار القيد المُرحَّل تلقائيّاً مفتاحُها
// `(referenceType, referenceId)` — و`referenceId` لورقة التحميل هو رقمُها
// **المحلّيّ**. ورقمُ الورقة على العميل يخالف رقمَها على الخادم بالتصميم
// (‏`DeltaPull` يُبقي الرقمَ المحلّيَّ ويسجّل خريطةً). فلو رحّل الطرفان
// لصار للحدث الواحد قيدان، ولا يمسكهما تكرارٌ لأنّ مفتاحَيهما مختلفان —
// ومخزونٌ يُعاد تقييمُه مرّتين.
//
// وهذا ليس افتراضاً: `purchases_repository_impl.dart` (‏ح-٦) يوثّق بوّابةً
// أُلغيت لهذا السبب بعينه.
//
// ═══ ولماذا مرساةٌ سالبةٌ لا تكفي ═══
//
// «لم يُرحَّل قيدٌ» تمرّ أيضاً لو كانت التجهيزةُ ناقصةً فلم يُرحَّل شيءٌ أصلاً.
// فالفحصُ الأخيرُ يشغّل **نفسَ** التجهيزة في الوضع المستقلّ ويشترط أنّ القيدَ
// يُرحَّل والتكلفةَ تُمزَج — فلو سقط ذاك سقط معه معنى كلِّ فحصٍ قبله.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';

/// عميلٌ يسجّل ما أُرسل — الغرضُ منه قلبُ [SyncInterceptor.isClientMode]
/// والتقاطُ المستند.
class _RecordingClient implements SyncInterceptor {
  int calls = 0;
  Map<String, dynamic>? document;

  @override
  bool get isClientModeImpl => true;

  @override
  bool get isMirrorModeImpl => false;

  @override
  Future<void> submitLandedCostApply(Map<String, dynamic> doc) async {
    calls++;
    document = doc;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late AppDatabase db;
  late int productId;
  late int invoiceId;
  late int purchaseItemId;

  /// تجهيزةٌ كاملةٌ: مورّدٌ وصنفٌ ومخزنٌ وفاتورةُ مشترياتٍ ببندٍ واحد.
  Future<int> seedSheet() async {
    final sheetId = await db.createLandedCostSheet(
      purchaseInvoiceId: invoiceId,
      sheetNumber: 'LC-${DateTime(2026, 8, 27).millisecondsSinceEpoch}',
    );
    await db.addLandedCostItem(
      sheetId: sheetId,
      costType: 'shipping',
      description: 'شحن بحري',
      amount: 1000,
    );
    await db.into(db.landedCostAllocations).insert(
          LandedCostAllocationsCompanion.insert(
            sheetId: sheetId,
            productId: productId,
            purchaseItemId: purchaseItemId,
            originalCost: 100,
            allocatedAmount: 1000,
            newUnitCost: 200,
            quantity: 10,
            globalId: Value('alloc-gid-$sheetId'),
          ),
        );
    return sheetId;
  }

  setUp(() async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();

    final supplierId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'مورّد الشحن',
            globalId: const Value('party-gid-1'),
          ),
        );
    productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            code: 'P-1',
            name: 'صنفُ اختبار',
            salePrice: const Value(300.0),
            costPrice: const Value(100.0),
            currentStock: const Value(10.0),
            globalId: const Value('product-gid-1'),
          ),
        );
    final warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'المخزن الرئيسي'),
        );
    invoiceId = await db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: 'PI-1',
            supplierId: supplierId,
            warehouseId: warehouseId,
            invoiceDate: DateTime(2026, 8, 20),
            globalId: const Value('invoice-gid-1'),
          ),
        );
    purchaseItemId = await db.into(db.purchaseInvoiceItems).insert(
          PurchaseInvoiceItemsCompanion.insert(
            invoiceId: invoiceId,
            productId: productId,
            quantity: 10,
            unitCost: 100,
            total: 1000,
            globalId: const Value('pitem-gid-1'),
          ),
        );
  });

  tearDown(() async {
    SyncInterceptor.instance = null;
    await db.close();
  });

  Future<List<JournalEntryData>> landedCostEntries() =>
      (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('landed_cost')))
          .get();

  group('وضعُ العميل — يُرسل ولا يحسب', () {
    late _RecordingClient client;
    late int sheetId;

    setUp(() async {
      sheetId = await seedSheet();
      client = _RecordingClient();
      SyncInterceptor.instance = client;
      await db.applyLandedCost(sheetId);
    });

    test('المستندُ أُرسل مرّةً واحدة', () {
      expect(client.calls, 1);
      expect(client.document, isNotNull);
    });

    test('🔴 ولا قيدَ رُحِّل محلّيّاً', () async {
      expect(
        await landedCostEntries(),
        isEmpty,
        reason: 'العميلُ رحّل قيداً ⇒ الخادمُ سيُرحّل ثانياً عند التطبيق، '
            'ومفتاحا الإزالة مختلفان (`referenceId` رقمٌ محلّيّ) فلا يمسكهما '
            'شيء: قيدان ومخزونٌ يُقيَّم مرّتين.',
      );
    });

    test('ولا تكلفةَ مُزجت محلّيّاً', () async {
      final product = await (db.select(db.products)
            ..where((p) => p.id.equals(productId)))
          .getSingle();
      expect(product.costPrice, 100,
          reason: 'التكلفةُ مُزجت على العميل ⇒ رقمان مختلفان للصنف نفسِه على '
              'جهازين، وأيُّهما الصحيحُ لا يُعرَف.');
    });

    test('والحالةُ صارت مطبَّقةً — علامةٌ تمنع تطبيقاً ثانياً', () async {
      final sheet = await (db.select(db.landedCostSheets)
            ..where((s) => s.id.equals(sheetId)))
          .getSingle();
      expect(sheet.status, 'applied');
    });

    test('🔴 والمفاتيحُ في المستند عالميّةٌ لا أرقامٌ محلّيّة', () {
      final doc = client.document!;
      expect(doc['purchaseInvoiceGlobalId'], 'invoice-gid-1',
          reason: 'رقمٌ محلّيٌّ يصل الخادمَ قد يطابق فاتورةً أخرى تماماً — '
              'فيُعاد بناءُ مستندٍ ليس هو.');

      final allocations = doc['allocations'] as List;
      expect(allocations, hasLength(1));
      final alloc = allocations.single as Map<String, dynamic>;
      expect(alloc['productGlobalId'], 'product-gid-1');
      expect(alloc['purchaseItemGlobalId'], 'pitem-gid-1');

      final items = doc['items'] as List;
      expect(items, hasLength(1));
      expect((items.single as Map<String, dynamic>)['amount'], 1000);
    });

    test('وتطبيقٌ ثانٍ لا يُرسل ثانيةً', () async {
      await db.applyLandedCost(sheetId);
      expect(client.calls, 1,
          reason: 'الحالةُ لم تعد `draft` فالحارسُ يمنع — وإلّا لتضاعف '
              'التطبيقُ بضغطتين على الزرّ.');
    });
  });

  test('⚓ مرساة: الوضعُ المستقلُّ ما زال يُرحّل ويمزج', () async {
    // بلا هذه المرساةِ يمرّ كلُّ فحصٍ أعلاه أخضرَ لو كانت التجهيزةُ ناقصةً
    // فلم يُرحَّل قيدٌ أصلاً — «لا شيء» يُشبه «مُنِع».
    final sheetId = await seedSheet();
    SyncInterceptor.instance = null; // مستقلّ
    await db.applyLandedCost(sheetId);

    final product = await (db.select(db.products)
          ..where((p) => p.id.equals(productId)))
        .getSingle();
    expect(product.costPrice, greaterThan(100),
        reason: 'التجهيزةُ لا تمزج تكلفةً حتّى في الوضع المستقلّ ⇒ فحوصُ '
            'المنعِ أعلاه بلا معنى.');

    final sheet = await (db.select(db.landedCostSheets)
          ..where((s) => s.id.equals(sheetId)))
        .getSingle();
    expect(sheet.status, 'applied');
  });
}
