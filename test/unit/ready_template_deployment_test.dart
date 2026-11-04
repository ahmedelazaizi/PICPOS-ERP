// ترقيةُ القوالب الجاهزة على قاعدة SQLite **قائمة** فيها البذرةُ القديمة.
//
// التحقّق الحيّ 2026-11-03 (قاعدة sandbox): «إيصال مرتجع مبيعات» id=4 يحمل
// بذرةَ `_seedSalesReturnElements` مُهاجَرةً آليّاً إلى v2 (ستّة أعمدة، خطّ
// ١٢، `columns_json` فارغ) فيطبع أعمدةً متراكبة، و«ملصق ميزان» وقوالبُ
// 58mm/A5 غائبةٌ لأنّ البذرةَ لا تُنادى عند الإقلاع.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/ready_template_deployment.dart';
import 'package:picpos_erp/domain/printing/print_values.dart';
import 'package:picpos_erp/services/printing/template_migration.dart';
import 'package:picpos_erp/services/printing/template_render_pipeline.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';

import '../helpers/arabic_pdf_text.dart';
import '../helpers/pdf_probe.dart';

Future<String> _asset(String f) =>
    File('assets/invoice_templates/$f').readAsString();

const _seedName = 'إيصال مرتجع مبيعات';
const _copyName = 'إيصال مرتجع مبيعات — النسخة الجاهزة المحدثة';

/// قاعدةٌ «قديمة»: البذرةُ كاملةٌ إلّا ملصقَ الميزان (سابقٌ لـa43cace1)، وسجلُّ
/// التسليم فارغ — كقاعدة sandbox بالضبط.
Future<AppDatabase> _legacyDb() async {
  final db = AppDatabase.forTesting();
  await db.seedDefaultTemplates();
  final scale = (await db.getAllTemplates()).singleWhere(
    (t) => t.name == 'ملصق ميزان',
  );
  await db.deleteTemplate(scale.id);
  return db;
}

Future<InvoiceTemplate> _seeded(AppDatabase db) async =>
    (await db.getAllTemplates()).singleWhere(
      (t) => t.name == _seedName && t.templateCategory == 'sales_return',
    );

Future<String> _fingerprintOf(AppDatabase db, int id) async {
  final d = (await db.getTemplateWithData(id))!;
  return readyTemplateFingerprint(d.template, d.elements, d.tableSettings);
}

/// لقطةٌ كاملةٌ لعناصر قالبٍ — لإثبات «لم يُلمس» حرفيّاً.
Future<String> _snapshot(AppDatabase db, int id) async {
  final d = (await db.getTemplateWithData(id))!;
  return jsonEncode([
    for (final e in d.elements) e.toJson(),
    d.tableSettings?.toJson(),
    d.template.layoutVersion,
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('البصمةُ المثبَّتة = بذرةُ المرتجع الحيّة (v1 وبعد الهجرة الآليّة)', () async {
    final db = await _legacyDb();
    try {
      final t = await _seeded(db);
      expect(await _fingerprintOf(db, t.id), kLegacySalesReturn80Fingerprint);
      await TemplateMigration.migrate(db, t.id);
      expect((await db.getTemplateById(t.id))!.layoutVersion, 2);
      expect(await _fingerprintOf(db, t.id), kLegacySalesReturn80Fingerprint,
          reason: 'الهجرةُ الآليّة لا تغيّر ما يصل الورقة');
      final d = (await db.getTemplateWithData(t.id))!;
      expect(
        readyTemplatePositionsAreDerived(d.template, d.elements, d.tableSettings),
        isTrue,
      );
    } finally {
      await db.close();
    }
  });

  test('صفُّ قاعدة sandbox الحيّ (id=4، v2 مهاجَر) يطابق البصمة ويُرقّى', () async {
    final db = await _legacyDb();
    try {
      // البذرةُ تُستبدَل بنسخةٍ حرفيّةٍ من الصفّ المصدَّر من الحاوية
      // picpos-ui-audit (‏2026-11-03) — قيمُ PG كما هي.
      await db.deleteTemplate((await _seeded(db)).id);
      final fx = jsonDecode(await File(
        'test/fixtures/sandbox_sales_return_template_2026-11-03.json',
      ).readAsString()) as Map<String, dynamic>;
      final t = fx['template'] as Map<String, dynamic>;
      double? d(Object? v) => (v as num?)?.toDouble();
      final id = await db.into(db.invoiceTemplates).insert(
            InvoiceTemplatesCompanion.insert(
              name: t['name'] as String,
              type: Value(t['type'] as String),
              templateCategory: Value(t['template_category'] as String),
              isDefault: Value(t['is_default'] as bool),
              paperSize: Value(t['paper_size'] as String),
              paperWidth: Value(d(t['paper_width'])!),
              paperHeight: Value(d(t['paper_height'])),
              margins: Value(t['margins'] as String),
              layoutVersion: Value(t['layout_version'] as int),
              bandHeights: Value(t['band_heights'] as String?),
            ),
          );
      for (final e in (fx['elements'] as List).cast<Map<String, dynamic>>()) {
        await db.into(db.invoiceTemplateElements).insert(
              InvoiceTemplateElementsCompanion.insert(
                templateId: id,
                elementType: e['element_type'] as String,
                rowIndex: Value(e['row_index'] as int),
                sortOrder: Value(e['sort_order'] as int),
                flexWidth: Value(d(e['flex_width'])!),
                xPosition: Value(d(e['x_position'])!),
                yPosition: Value(d(e['y_position'])!),
                width: Value(d(e['width'])!),
                height: Value(d(e['height'])!),
                textAlign: Value(e['text_align'] as String),
                fontFamily: Value(e['font_family'] as String?),
                fontSize: Value(d(e['font_size'])!),
                isBold: Value(e['is_bold'] as bool),
                isItalic: Value(e['is_italic'] as bool),
                fontColor: Value(e['font_color'] as String),
                backgroundColor: Value(e['background_color'] as String?),
                borderColor: Value(e['border_color'] as String?),
                borderWidth: Value(d(e['border_width'])!),
                content: Value(e['content'] as String?),
                labelAr: Value(e['label_ar'] as String?),
                labelEn: Value(e['label_en'] as String?),
                isVisible: Value(e['is_visible'] as bool),
                section: Value(e['section'] as String),
                formula: Value(e['formula'] as String?),
                bandId: Value(e['band_id'] as String?),
                xMm: Value(d(e['x_mm'])),
                yMm: Value(d(e['y_mm'])),
                wMm: Value(d(e['w_mm'])),
                hMm: Value(d(e['h_mm'])),
                condition: Value(e['condition'] as String?),
              ),
            );
      }
      final s = fx['table'] as Map<String, dynamic>;
      await db.into(db.invoiceTableSettings).insert(
            InvoiceTableSettingsCompanion.insert(
              templateId: id,
              xPosition: Value(d(s['x_position'])!),
              yPosition: Value(d(s['y_position'])!),
              width: Value(d(s['width'])!),
              fontSize: Value(d(s['font_size'])!),
              showIndex: Value(s['show_index'] as bool),
              showProductCode: Value(s['show_product_code'] as bool),
              showProductName: Value(s['show_product_name'] as bool),
              showQuantity: Value(s['show_quantity'] as bool),
              showUnitPrice: Value(s['show_unit_price'] as bool),
              showDiscount: Value(s['show_discount'] as bool),
              showTax: Value(s['show_tax'] as bool),
              showTotal: Value(s['show_total'] as bool),
              showUnit: Value(s['show_unit'] as bool),
              showBarcode: Value(s['show_barcode'] as bool),
              showNotes: Value(s['show_notes'] as bool),
              headerBgColor: Value(s['header_bg_color'] as String),
              headerTextColor: Value(s['header_text_color'] as String),
              headerFontSize: Value(d(s['header_font_size'])!),
              headerFontFamily: Value(s['header_font_family'] as String?),
              rowBgColor: Value(s['row_bg_color'] as String),
              altRowBgColor: Value(s['alt_row_bg_color'] as String?),
              rowHeight: Value(d(s['row_height'])!),
              columnWidths: Value(s['column_widths'] as String?),
              tableKind: Value(s['table_kind'] as String),
              columnsJson: Value(s['columns_json'] as String?),
            ),
          );

      expect(await _fingerprintOf(db, id), kLegacySalesReturn80Fingerprint);
      final data = (await db.getTemplateWithData(id))!;
      expect(
        readyTemplatePositionsAreDerived(
          data.template,
          data.elements,
          data.tableSettings,
        ),
        isTrue,
        reason: 'مواضعُ الصفّ الحيّ هي ما تشتقّه الهجرةُ الآليّة',
      );
      final r = await db.deployReadyTemplates(loadAsset: _asset);
      expect(r.upgraded, ['$id:$_seedName']);
      expect(r.copied, isEmpty);
    } finally {
      await db.close();
    }
  });

  for (final migrated in [false, true]) {
    test('قالبٌ مبذورٌ لم يُمسّ (${migrated ? 'v2 مهاجَر' : 'v1'}) يُرقّى في مكانه', () async {
      final db = await _legacyDb();
      try {
        final t = await _seeded(db);
        if (migrated) await TemplateMigration.migrate(db, t.id);
        await db.into(db.templateBindings).insert(
              TemplateBindingsCompanion.insert(
                documentType: 'sales_return',
                templateId: t.id,
              ),
            );

        final r = await db.deployReadyTemplates(loadAsset: _asset);
        expect(r.failed, isEmpty);
        expect(r.upgraded, ['${t.id}:$_seedName']);
        expect(r.copied, isEmpty);

        final after = (await db.getTemplateWithData(t.id))!;
        // الصفُّ نفسُه: المعرِّف والاسم والفئة والافتراضيّة والربط.
        expect(after.template.name, _seedName);
        expect(after.template.templateCategory, 'sales_return');
        expect(after.template.isDefault, isTrue);
        expect(after.template.layoutVersion, 2);
        expect(
          (await db.select(db.templateBindings).get()).single.templateId,
          t.id,
        );
        // والمحتوى من الأصل المُصلَح: ثلاثةُ أعمدةٍ لا ستّة.
        final asset = jsonDecode(await _asset('thermal80_sales_return.json'));
        expect(after.elements.length, (asset['elements'] as List).length);
        expect(after.tableSettings!.columnsJson,
            asset['tableSettings']['columnsJson']);
        final cols = jsonDecode(after.tableSettings!.columnsJson!) as List;
        expect(cols.map((c) => c['key']), ['name', 'quantity', 'total']);
      } finally {
        await db.close();
      }
    });
  }

  test('المطبوعُ بعد الترقية: أرقامُ الجدول كاملةٌ في صفوفها (وقبلها مقصوصة)', () async {
    final db = await _legacyDb();
    try {
      final t = await _seeded(db);
      await TemplateMigration.migrate(db, t.id); // حالُ sandbox
      Future<List<PdfTextRun>> renderNow() async {
        final d = (await db.getTemplateWithData(t.id))!;
        final bytes = await TemplateRenderPipeline.render(
          template: d.template,
          orderedElements: TemplatedInvoiceService.orderElementsForPrint(d.elements),
          tableSettings: d.tableSettings,
          payload: PrintPayload(
            invoiceNumber: 'SRET-1040',
            date: DateTime.utc(2026, 11, 3),
            companyName: 'شركة بيك بوس للتجارة',
            companyAddress: '',
            companyPhone: '',
            subtotal: 4400,
            discount: 0,
            tax: 0,
            deliveryFee: 0,
            total: 4400,
            paid: 4400,
            remaining: 0,
            orderNumber: 'INV-2026-1040',
          ),
          items: [
            for (var i = 0; i < 5; i++)
              {
                'name': 'سكر معبأ ١ كجم $i',
                'quantity': 40.0,
                'price': 22.0,
                'discount': 0.0,
                'total': 880.0,
              },
          ],
        );
        final page = probePdf(bytes).pages.first;
        // ‏72mm = العرضُ الصالحُ للطباعة على ورق 80mm — سياسةُ `buildPaper`.
        expect(page.widthPts / (72 / 25.4), closeTo(72, 0.1));
        return page.texts;
      }

      int count(List<PdfTextRun> runs, String s) =>
          runs.where((r) => r.text == s).length;

      // قبل: ستّةُ أعمدةٍ بخطّ ١٢ على ٦٨مم — «880.00» تخرج «880.0» و«40.00»
      // تخرج «40.»، واسمُ الصنف يلتفّ إلى سطرٍ يدهس الصفَّ التالي.
      final before = await renderNow();
      expect(count(before, '880.00'), 0);
      expect(count(before, '40.00'), 0);

      await db.deployReadyTemplates(loadAsset: _asset);
      final after = await renderNow();
      expect(count(after, '880.00'), 5);
      expect(count(after, '40.00'), 5);
      // الاسمُ كاملٌ على سطر صفّه نفسِه (كلمتُه الأخيرة مع إجماليّه).
      for (final total in after.where((r) => r.text == '880.00')) {
        expect(
          after.any((r) => deshapeArabic(r.text) == 'كجم' && (r.y - total.y).abs() < 0.5),
          isTrue,
        );
      }
    } finally {
      await db.close();
    }
  });

  test('قالبٌ عدّله المستخدم (خطّ عنصر) لا يُلمس وتُضاف بجانبه نسخةٌ محدّثة', () async {
    final db = await _legacyDb();
    try {
      final t = await _seeded(db);
      final el = (await db.getTemplateElements(t.id)).first;
      await db.updateTemplateElement(
        el.id,
        const InvoiceTemplateElementsCompanion(fontSize: Value(18)),
      );
      final before = await _snapshot(db, t.id);

      final r = await db.deployReadyTemplates(loadAsset: _asset);
      expect(r.upgraded, isEmpty);
      expect(r.copied, [_copyName]);
      expect(await _snapshot(db, t.id), before, reason: 'عملُ المستخدم لا يُمسّ');

      final copy = (await db.getAllTemplates()).singleWhere((x) => x.name == _copyName);
      expect(copy.templateCategory, 'sales_return');
      expect(copy.isDefault, isFalse, reason: 'لا يخطف افتراضيّةَ قالب المستخدم');
      expect((await db.getTableSettings(copy.id))!.columnsJson, isNotNull);

      // الإقلاعُ التالي لا يكرّر النسخة.
      final r2 = await db.deployReadyTemplates(loadAsset: _asset);
      expect(r2.copied, isEmpty);
      expect(
        (await db.getAllTemplates()).where((x) => x.name == _copyName),
        hasLength(1),
      );
    } finally {
      await db.close();
    }
  });

  test('قالبٌ مهاجَر سُحب فيه عنصرٌ في المحرّر لا يُلمس', () async {
    final db = await _legacyDb();
    try {
      final t = await _seeded(db);
      await TemplateMigration.migrate(db, t.id);
      final el = (await db.getTemplateElements(t.id)).first;
      await db.updateTemplateElement(
        el.id,
        InvoiceTemplateElementsCompanion(xMm: Value((el.xMm ?? 0) + 3)),
      );
      final before = await _snapshot(db, t.id);
      final r = await db.deployReadyTemplates(loadAsset: _asset);
      expect(r.upgraded, isEmpty);
      expect(r.copied, [_copyName]);
      expect(await _snapshot(db, t.id), before);
    } finally {
      await db.close();
    }
  });

  test('القوالبُ الناقصة (ميزان + ستّة 58/A5) تُضاف مرّةً بلا تكرار', () async {
    final db = await _legacyDb();
    try {
      // نسخةٌ استوردها المستخدمُ يدويّاً من قبل — لا تُكرَّر.
      await db.importTemplateFromJson(await _asset('thermal58_sales_return.json'));
      final countBefore = (await db.getAllTemplates()).length;

      final r = await db.deployReadyTemplates(loadAsset: _asset);
      expect(r.failed, isEmpty);
      expect(r.added, containsAll([
        'ملصق ميزان',
        'طلب مطبخ حراري — 58mm',
        'إغلاق الوردية حراري — 58mm',
        'فاتورة مشتريات حرارية — 58mm',
        'مرتجع مبيعات — A5',
        'فاتورة مشتريات — A5',
      ]));
      expect(r.added, isNot(contains('مرتجع مبيعات حراري — 58mm')));
      final all = await db.getAllTemplates();
      expect(all.length, countBefore + 6);
      final scale = all.singleWhere((t) => t.name == 'ملصق ميزان');
      expect(scale.templateCategory, 'barcode');
      expect(scale.paperWidth, 58);
      for (final name in r.added) {
        expect(all.singleWhere((t) => t.name == name).isDefault, isFalse);
      }

      // تشغيلٌ ثانٍ وثالث: لا شيء.
      expect((await db.deployReadyTemplates(loadAsset: _asset)).changed, isFalse);
      expect((await db.getAllTemplates()).length, countBefore + 6);

      // قالبٌ حذفه المستخدمُ بعد تسليمه لا يعود.
      await db.deleteTemplate(scale.id);
      await db.deployReadyTemplates(loadAsset: _asset);
      expect(
        (await db.getAllTemplates()).where((t) => t.name == 'ملصق ميزان'),
        isEmpty,
      );
    } finally {
      await db.close();
    }
  });

  test('ملصقاتُ الباركود القائمة لا تُمسّ (لا هجرةَ لـ company_name)', () async {
    final db = await _legacyDb();
    try {
      final carton = (await db.getAllTemplates())
          .singleWhere((t) => t.name == 'ملصق كرتون كبير');
      final before = await _snapshot(db, carton.id);
      await db.deployReadyTemplates(loadAsset: _asset);
      expect(await _snapshot(db, carton.id), before);
      expect(
        (await db.getTemplateElements(carton.id)).map((e) => e.elementType),
        contains('company_name'),
      );
    } finally {
      await db.close();
    }
  });

  test('مسارُ الإقلاع الحقيقيّ: إعادةُ فتح قاعدةٍ ملفّيّة تُرقّي وتضيف (rootBundle)', () async {
    final dir = await Directory.systemTemp.createTemp('ready_tpl_');
    final file = File('${dir.path}${Platform.pathSeparator}picpos.sqlite');
    try {
      var db = AppDatabase.withExecutor(NativeDatabase(file));
      await db.seedDefaultTemplates();
      final scale = (await db.getAllTemplates())
          .singleWhere((t) => t.name == 'ملصق ميزان');
      await db.deleteTemplate(scale.id);
      final seeded = await _seeded(db);
      await TemplateMigration.migrate(db, seeded.id); // حالُ sandbox
      await db.close();

      // الفتحُ التالي يمرّ بـ`runBeforeOpen` ⇒ `deployReadyTemplates` بالأصول
      // الحقيقيّة من rootBundle — لا محمِّلَ محقوناً.
      db = AppDatabase.withExecutor(NativeDatabase(file));
      try {
        final all = await db.getAllTemplates();
        final cols = jsonDecode(
          (await db.getTableSettings(seeded.id))!.columnsJson!,
        ) as List;
        expect(cols.map((c) => c['key']), ['name', 'quantity', 'total']);
        expect(all.where((t) => t.name == 'ملصق ميزان'), hasLength(1));
        expect(all.where((t) => t.name == 'فاتورة مشتريات — A5'), hasLength(1));
        expect(all.where((t) => t.name == _copyName), isEmpty);
        expect(await db.getSettingValue(kReadyTemplatesDeliveredKey), isNotNull);
      } finally {
        await db.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('قاعدةٌ لم تُبذر: لا يُضاف شيء، والبذرةُ بعدها تعمل كاملة', () async {
    final db = AppDatabase.forTesting();
    try {
      // ملصقٌ مخصّصٌ وحده — النوعُ thermal والفئةُ barcode موجودان، لكن
      // المطبخَ والوردية والمرتجعَ والمشتريات لم تُبذر.
      await db.into(db.invoiceTemplates).insert(
            InvoiceTemplatesCompanion.insert(
              name: 'ملصقي',
              templateCategory: const Value('barcode'),
              paperSize: const Value('50x25'),
              paperWidth: const Value(50),
              paperHeight: const Value(25),
            ),
          );
      final r = await db.deployReadyTemplates(loadAsset: _asset);
      expect(r.upgraded, isEmpty);
      expect(r.added, ['ملصق ميزان']);
      expect(r.deferred, containsAll([
        'upgrade:sales_return_80mm@2026-11-03',
        'thermal58_kitchen.json',
        'thermal58_shift_closing.json',
        'thermal58_sales_return.json',
        'a5_purchase_invoice.json',
      ]));

      await db.seedDefaultTemplates();
      final names = (await db.getAllTemplates()).map((t) => t.name).toSet();
      expect(names, containsAll(['طلب المطبخ', 'تقرير إغلاق الوردية', _seedName,
          'فاتورة مشتريات']));

      // الإقلاعُ التالي يُكمل المؤجَّل: يُرقّي البذرةَ ويضيف الستّة.
      final r2 = await db.deployReadyTemplates(loadAsset: _asset);
      expect(r2.upgraded, hasLength(1));
      expect(r2.added, hasLength(6));
    } finally {
      await db.close();
    }
  });
}
