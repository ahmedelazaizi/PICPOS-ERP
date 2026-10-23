// وسمُ الاستيراد ولقطةُ عملته — أوّلُ كاتبٍ لجدول v174.
//
// ═══ 🔴 ما يُقاس هنا ولماذا ═══
//
// ‏١) **الوسمُ في معاملة الفاتورة لا بعدَها.** صفُّ `ImportPurchaseDetails`
//    هو **الفارقُ الوحيد** بين فاتورةِ استيرادٍ وفاتورةٍ محلّيّة، فكتابتُه
//    بعد المعاملة تعني أنّ سقوطَه يترك فاتورةً بذمّةٍ ومخزونٍ وقيدٍ **بلا
//    وسم**: تبدو محلّيّةً إلى الأبد وتغيب عن الشاشة التي أُنشئت فيها، ولا
//    شيءَ يقول إنّ شيئاً سقط.
//
// ‏٢) 🔴 **وعملةٌ بلا سعرٍ تُرفَض.** `null` في `exchange_rate` يُقرأ لاحقاً
//    على أنّه ١، فتُقيَّد ألفُ دولارٍ على المورّد بألفِ وحدةٍ محلّيّة —
//    والقيدُ **متّزنٌ على الرقم الخاطئ** فلا يمسكه فحصُ اتّزان.
//
// ‏٣) 🔴 **والمبالغُ المخزَّنةُ محلّيّةٌ بالفعل.** التحويلُ يقع في النموذج
//    مرّةً واحدة، واللقطةُ **وصفٌ لا مُعامِل** — فلا يضربها قارئ.
//
// ‏٤) **وإنشاءُ الوسم بابٌ واحد.** `updateImportPurchaseDetails` تُحرِّر ولا
//    تُنشئ: بابٌ ثانٍ كان يحوّل فاتورةً محلّيّةً إلى خارجيّةٍ بعد أن
//    رُحِّلت — تصنيفٌ يتبدّل من الخلف.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/models/import_purchase_plan.dart';

void main() {
  late AppDatabase db;
  late int supplierId;
  late int warehouseId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    warehouseId = (await db.getDefaultWarehouse())!.id;
    supplierId = await db.into(db.parties).insert(
        PartiesCompanion.insert(name: 'مورد صيني', isSupplier: const Value(true)));
  });

  tearDown(() => db.close());

  Future<int> seedProduct(String code) => db.insertProduct(
        ProductsCompanion.insert(
          code: code,
          name: 'صنف $code',
          salePrice: const Value(200.0),
          costPrice: const Value(0.0),
          trackInventory: const Value(true),
        ),
      );

  ImportDocumentFields doc({
    String? customs = 'C-100',
    String? bl = 'BL-9',
    String? country = 'الصين',
    String? port = 'شنغهاي',
    String? lc,
    int? agentId,
    String? agentName,
  }) =>
      normalizeImportDocument(
        customsDeclarationNo: customs,
        billOfLading: bl,
        countryOfOrigin: country,
        port: port,
        letterOfCredit: lc,
        clearingAgentPartyId: agentId,
        clearingAgentName: agentName,
      );

  Future<int> createImport({
    int? currencyId,
    double? exchangeRate,
    ImportDocumentFields? details,
    double unitCost = 100,
    double quantity = 10,
  }) async {
    final pid = await seedProduct('IMP-${DateTime.now().microsecondsSinceEpoch}');
    return db.createPurchaseInvoice(
      supplierId: supplierId,
      warehouseId: warehouseId,
      paid: 0,
      paymentMethod: 'credit',
      currencyId: currencyId,
      exchangeRate: exchangeRate,
      importDetails: details,
      items: [
        PurchaseInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: pid,
          quantity: quantity,
          unitCost: unitCost,
          total: quantity * unitCost,
        ),
      ],
    );
  }

  Future<int> seedCurrency(String code, double rate) =>
      db.into(db.currencies).insert(CurrenciesCompanion.insert(
            code: code,
            name: 'عملة $code',
            symbol: code,
            exchangeRate: Value(rate),
          ));

  group('١ · الوسمُ يُكتَب مع الفاتورة', () {
    test('فاتورةٌ بوسمها — صفٌّ واحدٌ مرتبطٌ بها', () async {
      final id = await createImport(details: doc());
      final row = await db.getImportPurchaseDetailsFor(id);
      expect(row, isNotNull);
      expect(row!.purchaseInvoiceId, id);
      expect(row.customsDeclarationNo, 'C-100');
      expect(row.billOfLading, 'BL-9');
      expect(row.countryOfOrigin, 'الصين');
      expect(row.port, 'شنغهاي');
    });

    test('وفاتورةٌ بلا وسمٍ تبقى محلّيّةً — لا صفَّ لها', () async {
      final id = await createImport();
      expect(await db.getImportPurchaseDetailsFor(id), isNull);
    });

    test('🔴 ووسمٌ خالٍ يُكتَب كذلك — هو الفارقُ لا محتواه', () async {
      // «استيرادٌ لم تصل أوراقُه بعد» حالةٌ حقيقيّة، وعدمُ كتابته كان
      // يُخفي الفاتورةَ عن الشاشة التي أُنشئت فيها.
      final id = await createImport(details: normalizeImportDocument());
      final row = await db.getImportPurchaseDetailsFor(id);
      expect(row, isNotNull);
      expect(importDocumentIsEmpty(doc(
        customs: row!.customsDeclarationNo,
        bl: row.billOfLading,
        country: row.countryOfOrigin,
        port: row.port,
      )), isTrue);
    });

    test('ويحمل معرِّفاً عالميّاً يسبق أوّلَ مزامنة', () async {
      final id = await createImport(details: doc());
      final row = await db.getImportPurchaseDetailsFor(id);
      expect(row!.globalId, isNotNull);
      expect(row.globalId, isNotEmpty);
    });

    test('🔴 وحقلٌ أطولُ من عمودِه يُسقط الفاتورةَ كلَّها — لا نصفَها',
        () async {
      // الفحصُ يقع **قبل** المعاملة، فلا بضاعةَ تتحرّك ولا ذمّةَ تُحمَّل.
      final before = (await db.select(db.purchaseInvoices).get()).length;
      await expectLater(
        createImport(details: normalizeImportDocument(billOfLading: 'x' * 61)),
        throwsA(isA<ArgumentError>()),
      );
      expect((await db.select(db.purchaseInvoices).get()).length, before,
          reason: 'كُتبت فاتورةٌ رغم رفضِ وسمها');
    });
  });

  group('٢ · لقطةُ العملة', () {
    test('تُخزَّن كما مُرِّرت', () async {
      final cid = await seedCurrency('USD', 0.71);
      final id = await createImport(
          currencyId: cid, exchangeRate: 0.71, details: doc());
      final inv = await db.getPurchaseInvoiceById(id);
      expect(inv!.currencyId, cid);
      expect(inv.exchangeRate, 0.71);
    });

    test('🔴 عملةٌ بلا سعرٍ تُرفَض — وإلّا قُرئت سعراً ١', () async {
      final cid = await seedCurrency('EUR', 0.8);
      await expectLater(
        createImport(currencyId: cid, details: doc()),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('🔴 وسعرٌ بلا عملةٍ يُرفَض — مُعامِلٌ بلا وحدة', () async {
      await expectLater(
        createImport(exchangeRate: 0.71, details: doc()),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('وسعرُ صفرٍ يُرفَض', () async {
      final cid = await seedCurrency('JPY', 1);
      await expectLater(
        createImport(currencyId: cid, exchangeRate: 0, details: doc()),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('🔴 والمبلغُ المخزَّنُ هو الممرَّرُ — لا يُضرَب بالسعر ثانيةً',
        () async {
      // التحويلُ يقع في النموذج. وضربٌ هنا كان يجعل ذمّةَ المورّد
      // جزءاً من ألفٍ من قيمتها بلا رسالةِ خطأ.
      final cid = await seedCurrency('USD', 0.71);
      final id = await createImport(
        currencyId: cid,
        exchangeRate: 0.71,
        unitCost: 71,
        quantity: 10,
        details: doc(),
      );
      final inv = await db.getPurchaseInvoiceById(id);
      expect(inv!.total, closeTo(710, 0.001));
      expect(inv.subtotal, closeTo(710, 0.001));
    });

    test('والفاتورةُ المحلّيّةُ تبقى بلا عملةٍ ولا سعر', () async {
      final id = await createImport(details: doc());
      final inv = await db.getPurchaseInvoiceById(id);
      expect(inv!.currencyId, isNull);
      expect(inv.exchangeRate, isNull);
    });
  });

  group('٣ · صفوفُ الشاشة', () {
    test('تُرجِع الموسومةَ وحدَها', () async {
      await createImport(details: doc());
      await createImport(); // محلّيّة
      final rows = await db.getImportPurchaseRows();
      expect(rows, hasLength(1));
      expect(rows.single.supplierName, 'مورد صيني');
    });

    test('وتحمل رمزَ العملة حين تكون أجنبيّة', () async {
      final cid = await seedCurrency('USD', 0.71);
      await createImport(
          currencyId: cid, exchangeRate: 0.71, details: doc());
      final rows = await db.getImportPurchaseRows();
      expect(rows.single.currencyCode, 'USD');
    });

    test('واسمُ الوكيل يُقرأ من الطرف لا من لقطةٍ نصّيّة', () async {
      final agentId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
              name: 'مخلّص جمركي', isSupplier: const Value(true)));
      await createImport(details: doc(agentId: agentId));
      final rows = await db.getImportPurchaseRows();
      expect(rows.single.clearingAgent, 'مخلّص جمركي');
    });

    test('وبلا طرفٍ يُقرأ النصُّ الحرّ', () async {
      await createImport(details: doc(agentName: 'وكيل غير مسجَّل'));
      final rows = await db.getImportPurchaseRows();
      expect(rows.single.clearingAgent, 'وكيل غير مسجَّل');
    });

    test('🔴 والمسوّدةُ لا تُجمَع مع المطبَّق — تكلفةٌ لم تدخل الدفتر',
        () async {
      final id = await createImport(details: doc());
      await db.into(db.landedCostSheets).insert(
            LandedCostSheetsCompanion.insert(
              purchaseInvoiceId: id,
              sheetNumber: 'LC-1',
              totalAdditionalCost: const Value(300),
              status: const Value('applied'),
            ),
          );
      await db.into(db.landedCostSheets).insert(
            LandedCostSheetsCompanion.insert(
              purchaseInvoiceId: id,
              sheetNumber: 'LC-2',
              totalAdditionalCost: const Value(50),
              status: const Value('draft'),
            ),
          );
      final row = (await db.getImportPurchaseRows()).single;
      expect(row.landedApplied, 300);
      expect(row.landedDraft, 50);
    });

    test('وورقةٌ ملغاةٌ لا تُحسَب في أيٍّ منهما', () async {
      final id = await createImport(details: doc());
      await db.into(db.landedCostSheets).insert(
            LandedCostSheetsCompanion.insert(
              purchaseInvoiceId: id,
              sheetNumber: 'LC-3',
              totalAdditionalCost: const Value(900),
              status: const Value('cancelled'),
            ),
          );
      final row = (await db.getImportPurchaseRows()).single;
      expect(row.landedApplied, 0);
      expect(row.landedDraft, 0);
    });
  });

  group('٤ · التحرير', () {
    test('يُبدّل الحقولَ المستنديّة', () async {
      final id = await createImport(details: doc());
      await db.updateImportPurchaseDetails(
        purchaseInvoiceId: id,
        fields: normalizeImportDocument(
          customsDeclarationNo: 'C-777',
          port: 'جدة',
        ),
      );
      final row = await db.getImportPurchaseDetailsFor(id);
      expect(row!.customsDeclarationNo, 'C-777');
      expect(row.port, 'جدة');
      // وما لم يُمرَّر يُمحى: الحقلُ الفارغُ قرارٌ لا سهو.
      expect(row.billOfLading, isNull);
    });

    test('🔴 ولا يُنشئ وسماً لفاتورةٍ محلّيّة — تصنيفٌ لا يتبدّل من الخلف',
        () async {
      final id = await createImport();
      await expectLater(
        db.updateImportPurchaseDetails(
          purchaseInvoiceId: id,
          fields: normalizeImportDocument(port: 'جدة'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(await db.getImportPurchaseDetailsFor(id), isNull);
    });

    test('وطولٌ يتجاوز العمودَ يُرفَض ولا يُبدّل شيئاً', () async {
      final id = await createImport(details: doc());
      await expectLater(
        db.updateImportPurchaseDetails(
          purchaseInvoiceId: id,
          fields: normalizeImportDocument(port: 'x' * 61),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect((await db.getImportPurchaseDetailsFor(id))!.port, 'شنغهاي');
    });
  });
}
