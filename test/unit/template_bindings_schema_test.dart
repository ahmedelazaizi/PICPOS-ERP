// طبقةُ حفظِ نموذج النطاقات — على قاعدةٍ **جديدة**.
//
// ── لماذا على الجديدة تحديداً ─────────────────────────────────────────────
// عطبٌ مرصودٌ في هذا المستودع (2026-08-27): أعمدةٌ أُضيفت بـ`ALTER TABLE` في
// هجرةٍ ولم تُعلَن قطُّ في صنف الجدول. و`onCreate` يبني من كيانات drift لا من
// الهجرات — فالتنصيبُ **الجديد** لا يملكها، وينهار المسارُ بـ«no such column»
// على كلِّ قاعدةٍ جديدة. وPicPos بلا تنصيباتٍ قديمةٍ أصلاً ⇒ كلُّ قاعدةٍ جديدة.
//
// فالقياسُ هنا على `AppDatabase.forTesting()` — وهي مسارُ التنصيب الجديد
// بعينه. ونجاحُه يعني أنّ الأعمدةَ مُعلَنةٌ في الأصناف لا مُلحَقةٌ بهجرةٍ وحدَها.

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<int> newTemplate() => db.into(db.invoiceTemplates).insert(
        InvoiceTemplatesCompanion.insert(
          name: 'قالب اختبار',
          type: const Value('a4'),
          paperSize: const Value('A4'),
          paperWidth: const Value(210),
        ),
      );

  group('أعمدةُ النطاقات على عناصر القالب', () {
    test('تُكتَب وتُقرأ على قاعدةٍ جديدة', () async {
      final tid = await newTemplate();

      await db.into(db.invoiceTemplateElements).insert(
            InvoiceTemplateElementsCompanion.insert(
              templateId: tid,
              elementType: 'variable',
              content: const Value('total_amount'),
              bandId: const Value('totals'),
              xMm: const Value(12.5),
              yMm: const Value(4.0),
              wMm: const Value(60.0),
              hMm: const Value(6.0),
              condition: const Value('discount > 0'),
            ),
          );

      final row = await (db.select(db.invoiceTemplateElements)
            ..where((t) => t.templateId.equals(tid)))
          .getSingle();

      expect(row.bandId, 'totals');
      expect(row.xMm, 12.5);
      expect(row.yMm, 4.0);
      expect(row.wMm, 60.0);
      expect(row.hMm, 6.0);
      expect(row.condition, 'discount > 0');
    });

    test('وتبقى فارغةً للقالب غير المهاجَر — لا قيمةَ مخترعة', () async {
      final tid = await newTemplate();
      await db.into(db.invoiceTemplateElements).insert(
            InvoiceTemplateElementsCompanion.insert(
              templateId: tid,
              elementType: 'variable',
              content: const Value('company_name'),
            ),
          );

      final row = await (db.select(db.invoiceTemplateElements)
            ..where((t) => t.templateId.equals(tid)))
          .getSingle();

      expect(row.bandId, isNull,
          reason: 'صفرٌ افتراضيٌّ يعني «موضعٌ حقيقيٌّ عند الحافّة»، و`null` '
              'وحدَها تقول «لم يُهاجَر بعد»');
      expect(row.xMm, isNull);
      expect(row.condition, isNull);
    });
  });

  group('layoutVersion يفصل التدفّقَ عن النطاقات', () {
    test('القالبُ الجديدُ يبدأ عند ١ — أي تدفّق', () async {
      final tid = await newTemplate();
      final t = await (db.select(db.invoiceTemplates)
            ..where((x) => x.id.equals(tid)))
          .getSingle();
      expect(t.layoutVersion, 1,
          reason: 'البدءُ عند ٢ يعلن قالباً مهاجَراً وهو ليس كذلك، فيقرؤه '
              'الراسمُ بالمسار الخطأ');
    });

    test('ويُرفع إلى ٢ عند الهجرة', () async {
      final tid = await newTemplate();
      await (db.update(db.invoiceTemplates)..where((x) => x.id.equals(tid)))
          .write(const InvoiceTemplatesCompanion(layoutVersion: Value(2)));

      final t = await (db.select(db.invoiceTemplates)
            ..where((x) => x.id.equals(tid)))
          .getSingle();
      expect(t.layoutVersion, 2);
    });
  });

  group('إعداداتُ الجدول', () {
    test('tableKind يبدأ items', () async {
      final tid = await newTemplate();
      await db.into(db.invoiceTableSettings).insert(
            InvoiceTableSettingsCompanion.insert(templateId: tid),
          );

      final s = await (db.select(db.invoiceTableSettings)
            ..where((x) => x.templateId.equals(tid)))
          .getSingle();
      expect(s.tableKind, 'items');
      expect(s.columnsJson, isNull,
          reason: 'غيابُها يعني «استعمل أعلام show* القديمة» — وهو ما يُبقي '
              'كلَّ قالبٍ قائمٍ يطبع كما كان');
    });

    test('و columnsJson يحمل الأعمدةَ بعناوينها', () async {
      final tid = await newTemplate();
      const json = '[{"key":"name","labelAr":"البيان","labelEn":"Item"}]';
      await db.into(db.invoiceTableSettings).insert(
            InvoiceTableSettingsCompanion.insert(
              templateId: tid,
              columnsJson: const Value(json),
            ),
          );

      final s = await (db.select(db.invoiceTableSettings)
            ..where((x) => x.templateId.equals(tid)))
          .getSingle();
      expect(s.columnsJson, json);
    });
  });

  group('جدولُ الرابطات', () {
    test('رابطةٌ كاملةُ المفتاح تُكتَب وتُقرأ', () async {
      final tid = await newTemplate();
      await db.into(db.templateBindings).insert(
            TemplateBindingsCompanion.insert(
              documentType: 'sales_invoice',
              templateId: tid,
              branchId: const Value(7),
              printerId: const Value(3),
              locale: const Value('ar'),
              copies: const Value(2),
              directPrint: const Value(true),
            ),
          );

      final b = await db.select(db.templateBindings).getSingle();
      expect(b.documentType, 'sales_invoice');
      expect(b.branchId, 7);
      expect(b.printerId, 3);
      expect(b.locale, 'ar');
      expect(b.copies, 2);
      expect(b.directPrint, isTrue);
      expect(b.priority, 0);
    });

    test('و«أيّاً كان» تُخزَّن null لا صفراً', () async {
      final tid = await newTemplate();
      await db.into(db.templateBindings).insert(
            TemplateBindingsCompanion.insert(
              documentType: 'sales_return',
              templateId: tid,
            ),
          );

      final b = await db.select(db.templateBindings).getSingle();
      expect(b.branchId, isNull,
          reason: 'الصفرُ معرِّفُ فرعٍ محتمل — فلا يصلح علامةً لـ«أيّ فرع»');
      expect(b.printerId, isNull);
      expect(b.locale, isNull);
    });

    test('والمرتجعُ يملك رابطتَه المستقلّةَ عن الفاتورة', () async {
      final invoiceTpl = await newTemplate();
      final returnTpl = await newTemplate();

      for (final (type, tpl) in [
        ('sales_invoice', invoiceTpl),
        ('sales_return', returnTpl),
      ]) {
        await db.into(db.templateBindings).insert(
              TemplateBindingsCompanion.insert(
                documentType: type,
                templateId: tpl,
              ),
            );
      }

      final rows = await db.select(db.templateBindings).get();
      final byType = {for (final r in rows) r.documentType: r.templateId};

      expect(byType['sales_invoice'], invoiceTpl);
      expect(byType['sales_return'], returnTpl);
      expect(byType['sales_invoice'], isNot(byType['sales_return']),
          reason: 'هذا هو كلُّ الغرض: بلا فئةٍ مستقلّةٍ للمرتجع يستحيل أن '
              'يكون له قالبٌ افتراضيٌّ خاصّ');
    });
  });

  test('رقمُ المخطَّط حدٌّ أدنى لا تجميد', () async {
    // تثبيتُه على رقمٍ بعينه كسر ترقيةَ ١٦٥ في هذا المستودع من قبل، وكان
    // الفشلَ الوحيدَ في بوّابةٍ كاملة. الأعمدةُ فوق هي الدليل، والرقمُ حدٌّ.
    expect(db.schemaVersion, greaterThanOrEqualTo(169));
  });
}
