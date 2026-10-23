// مِكنسةُ الفاتورة الإلكترونيّة ورايتُها — على PostgreSQL الحقيقيّة.
//
// ═══ لماذا سويّةٌ خاصّة ═══
//
// الخادمُ PostgreSQL حصراً (قرارُ مالك)، وهذا الكودُ **لا يعمل إلّا عليه**:
// المِكنسةُ تمسح والرايةُ تُكتب على الخادم وحدَه. فاختبارُ SQLite يقيس ما لا
// يُشغَّل في الإنتاج.
//
// وأخطرُ عطبَي جلسة 2026-09-02 كانا على PG وحدَها ولم تلمسهما البوّابةُ
// إطلاقاً — أحدُهما بذرُ إقلاعٍ ميّتٌ صامتاً لأنّ `?` لا تُترجَم في كلّ سياق.
//
// ═══ وما يُقاس هنا بالضبط ═══
//
// ١) **استعلامٌ فرعيٌّ** (`isNotInQuery`) — بنيةٌ لم يسبق أن استُعملت في هذا
//    المسار، وترجمتُها إلى PostgreSQL ليست مضمونةً بالقياس على SQLite.
// ٢) **الرايةُ داخل معاملة**: `saveEInvoiceConfig` صار يكتب الإعدادَ والرايةَ
//    في معاملةٍ واحدة. والمعاملاتُ على PG لها سلوكُ إجهاضٍ مختلف.
// ٣) **لقطةُ ضريبة البند** تُقرأ من الصفّ لا من المنتج — على القاعدة الحيّة.

@Tags(['pg'])
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/models/receipt_qr_decision.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;
  late AppDatabase db;
  late int whId;

  setUpAll(() async {
    fx = await bootPgTestSchema();
    db = fx.db;

    final branchId = await db.into(db.branches).insert(
        BranchesCompanion.insert(name: 'ف', globalId: const Value('br-pgei')));
    whId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'م',
        branchId: Value(branchId),
        globalId: const Value('wh-pgei')));
  });

  tearDownAll(() async => fx.tearDown());

  Future<int> sale(String number, {String saleType = 'default'}) =>
      db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: whId,
            userId: 1,
            invoiceDate: DateTime(2026, 9, 1),
            total: const Value(115),
            subtotal: const Value(100),
            tax: const Value(15),
            saleType: Value(saleType),
          ));

  group('رايةُ التفعيل على PostgreSQL', () {
    test('🔴 تُكتب مع الإعداد في معاملةٍ واحدة', () async {
      await db.saveEInvoiceConfig(
        platform: 'eta',
        clientId: 'id',
        clientSecret: 'secret',
        registrationNumber: '100-200-300',
        isEnabled: true,
      );

      expect(await db.getSettingValue(kEInvoiceEnabledSettingKey), 'true',
          reason: 'المعاملةُ على PG لها سلوكُ إجهاضٍ مختلف — والرايةُ هي ما '
              'يحكم رمزَ الإيصال على كلّ جهاز');
    });

    test('وتُنزَل بتعطيل الإعداد', () async {
      await db.saveEInvoiceConfig(
        platform: 'eta',
        clientId: 'id',
        clientSecret: 'secret',
        registrationNumber: '100-200-300',
        isEnabled: false,
      );

      expect(await db.getSettingValue(kEInvoiceEnabledSettingKey), 'false');

      // تُعاد للتفعيل — الاختباراتُ التالية تحتاج إعداداً مُفعَّلاً.
      await db.saveEInvoiceConfig(
        platform: 'eta',
        clientId: 'id',
        clientSecret: 'secret',
        registrationNumber: '100-200-300',
        isEnabled: true,
      );
    });
  });

  group('مِكنسةُ الطابور على PostgreSQL', () {
    test('🔴 الاستعلامُ الفرعيُّ يُترجَم ويعمل', () async {
      final id = await sale('PG-SW-1');

      final due = await db.findSalesNeedingEInvoiceSubmission(limit: 50);

      expect(due, contains(id),
          reason: 'بنيةُ `isNotInQuery` لم تُستعمل في هذا المسار من قبل — '
              'وترجمتُها إلى PostgreSQL ليست مضمونةً بالقياس على SQLite');
    });

    test('🔴 وفاتورةٌ لها تقديمٌ تخرج من المسح', () async {
      final id = await sale('PG-SW-2');
      await db.createSubmission(saleId: id, platform: 'eta');

      expect(await db.findSalesNeedingEInvoiceSubmission(limit: 50),
          isNot(contains(id)),
          reason: 'التقاطُها ثانيةً يُنتج مستندَين ضريبيَّين لفاتورةٍ واحدة');
    });

    test('والمرتجعُ خارجَ المكنسة', () async {
      final id = await sale('PG-SW-R', saleType: 'return');

      expect(await db.findSalesNeedingEInvoiceSubmission(limit: 50),
          isNot(contains(id)));
    });
  });

  test('🔴 حمولةُ المستند تقرأ لقطةَ ضريبة البند على القاعدة الحيّة', () async {
    final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
            code: 'PG-TAX', name: 'صنف', taxRate: const Value(5)));
    final saleId = await sale('PG-TAX-1');
    await db.into(db.salesInvoiceItems).insert(
        SalesInvoiceItemsCompanion.insert(
      invoiceId: saleId,
      productId: productId,
      quantity: 1,
      unitPrice: 100,
      total: 100,
      taxRate: const Value(5),
      taxAmount: const Value(5),
    ));

    // الضريبةُ الحيّةُ تتغيّر بعد البيع.
    await (db.update(db.products)..where((p) => p.id.equals(productId)))
        .write(const ProductsCompanion(taxRate: Value(25)));

    final payload = await db.buildInvoicePayload(saleId, 'eta');
    final item = (payload['items'] as List).first as Map;

    expect(item['taxRate'], 5.0,
        reason: 'الفاتورةُ حُرِّرت بـ٥٪ ودفع العميلُ ٥٪ — فتُقدَّم بـ٥٪');
    expect(item['taxAmount'], 5.0);
  });
}
