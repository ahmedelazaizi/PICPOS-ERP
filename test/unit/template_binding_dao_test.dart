// حلقةُ «فعِّل ← احسم ← احذف» على قاعدةٍ حقيقيّة.
//
// ── الأعطابُ الثلاثةُ التي تمنعها، وكلُّها من عقد الأزرار ─────────────────
// ١ · **الإلغاءُ الصامت.** تفعيلُ قالبٍ يُلغي المتعارضَ معه. وإلغاؤه بلا
//     إخبارٍ يجعل المستخدمَ يظنّ قالبين مفعّلَين، فيطبع من أحدهما ويجد
//     الآخر. فالدالّةُ **تُرجع** ما ألغته لا تكتفي بفعله.
//
// ٢ · **حذفُ قالبٍ مربوط.** بدون رفضٍ صريحٍ تُطبع مستنداتٌ بلا قالبٍ بعد
//     أسابيعَ بلا سببٍ ظاهر — والرابطةُ تشير إلى صفٍّ لم يعد موجوداً.
//
// ٣ · **ربطُ قالبٍ أعرضَ من طابعته.** يُقصّ المطبوعُ صامتاً، وعمودُ الإجمالي
//     أوّلُ ما يضيع.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<int> newTemplate({String name = 'قالب', double width = 210}) =>
      db.into(db.invoiceTemplates).insert(
            InvoiceTemplatesCompanion.insert(
              name: name,
              type: Value(width < 100 ? 'thermal' : 'a4'),
              paperWidth: Value(width),
            ),
          );

  group('التفعيلُ يُلغي المتعارضَ ويُخبر', () {
    test('أوّلُ تفعيلٍ لا يُلغي شيئاً', () async {
      final t = await newTemplate();
      final cancelled = await db.activateBinding(
        documentType: 'sales_invoice',
        templateId: t,
      );
      expect(cancelled, isEmpty);
      expect(await db.select(db.templateBindings).get(), hasLength(1));
    });

    test('وتفعيلُ قالبٍ ثانٍ بنفس المفتاح يُلغي الأوّلَ ويُرجعه', () async {
      final first = await newTemplate(name: 'الأوّل');
      final second = await newTemplate(name: 'الثاني');

      await db.activateBinding(
        documentType: 'sales_invoice',
        templateId: first,
      );
      final cancelled = await db.activateBinding(
        documentType: 'sales_invoice',
        templateId: second,
      );

      expect(cancelled.map((b) => b.templateId), [first],
          reason: 'الإلغاءُ الصامتُ يجعل المستخدمَ يظنّ قالبين مفعّلَين');

      final rows = await db.select(db.templateBindings).get();
      expect(rows, hasLength(1), reason: 'لا تتعايش رابطتان بنفس المفتاح');
      expect(rows.single.templateId, second);
    });

    test('ومفتاحٌ مختلفٌ لا يُلغي شيئاً — الفرعُ جزءٌ من المفتاح', () async {
      final a = await newTemplate(name: 'أ');
      final b = await newTemplate(name: 'ب');

      await db.activateBinding(documentType: 'sales_invoice', templateId: a);
      final cancelled = await db.activateBinding(
        documentType: 'sales_invoice',
        templateId: b,
        branchId: 7,
      );

      expect(cancelled, isEmpty);
      expect(await db.select(db.templateBindings).get(), hasLength(2),
          reason: 'رابطةُ الفرع ٧ أخصُّ من العامّة، فتتعايشان');
    });

    test('ونوعُ مستندٍ مختلفٌ لا يُلغي شيئاً', () async {
      final a = await newTemplate();
      final b = await newTemplate();
      await db.activateBinding(documentType: 'sales_invoice', templateId: a);
      final cancelled = await db.activateBinding(
        documentType: 'sales_return',
        templateId: b,
      );
      expect(cancelled, isEmpty);
    });
  });

  group('الحسمُ يقرأ الرابطاتِ من القاعدة', () {
    test('يحسم للقالب المربوط', () async {
      final t = await newTemplate();
      await db.activateBinding(
        documentType: 'sales_invoice',
        templateId: t,
        branchId: 7,
        locale: 'ar',
      );

      final r = await db.resolveTemplateFor(
        documentType: 'sales_invoice',
        category: 'invoice',
        branchId: 7,
        locale: 'ar',
      );

      expect(r.templateId, t);
      expect(r.level, 2, reason: 'مستند + فرع + أيُّ طابعة + لغة');
    });

    test('ويسقط للفئة حين لا رابطة — سلوكُ اليوم يبقى', () async {
      final t = await newTemplate();
      await (db.update(db.invoiceTemplates)..where((x) => x.id.equals(t)))
          .write(const InvoiceTemplatesCompanion(
        templateCategory: Value('invoice'),
        type: Value('a4'),
      ));
      // عبر الواجهة التي تحفظ الثابت «افتراضيٌّ واحدٌ لكلِّ نوعٍ وفئة» —
      // الكتابةُ المباشرةُ تكسره وتُخفي العطبَ الذي يليه.
      await db.setDefaultTemplate(t);

      final r = await db.resolveTemplateFor(
        documentType: 'sales_invoice',
        category: 'invoice',
        paperType: 'a4',
      );

      expect(r.templateId, t);
      expect(r.level, 6);
    });

    test('وللمدمج حين لا شيء إطلاقاً', () async {
      final r = await db.resolveTemplateFor(
        documentType: 'sales_invoice',
        category: 'invoice',
      );
      expect(r.isBuiltIn, isTrue);
      expect(r.level, 7);
    });
  });

  group('حذفُ قالبٍ مربوطٍ يُرفض', () {
    test('يُرفض ويذكر عددَ الرابطات', () async {
      final t = await newTemplate();
      await db.activateBinding(documentType: 'sales_invoice', templateId: t);

      expect(
        () => db.deleteTemplateGuarded(t),
        throwsA(isA<TemplateBoundException>()),
        reason: 'الحذفُ الصامتُ يُنتج مستنداتٍ بلا قالبٍ بعد أسابيعَ بلا '
            'سببٍ ظاهر',
      );

      expect(await db.getTemplateById(t), isNotNull);
    });

    test('ويمرّ بعد فكِّ الرابطة', () async {
      final t = await newTemplate();
      await db.activateBinding(documentType: 'sales_invoice', templateId: t);
      await db.deactivateBinding(documentType: 'sales_invoice');

      await db.deleteTemplateGuarded(t);
      expect(await db.getTemplateById(t), isNull);
    });

    test('وقالبٌ بلا رابطةٍ يُحذف مباشرةً', () async {
      final t = await newTemplate();
      await db.deleteTemplateGuarded(t);
      expect(await db.getTemplateById(t), isNull);
    });
  });

  group('حارسُ عرض الورق عند الربط', () {
    test('قالبُ A4 على طابعةٍ ٨٠مم يُرفض', () async {
      final t = await newTemplate(width: 210);
      expect(
        () => db.activateBinding(
          documentType: 'sales_invoice',
          templateId: t,
          printerId: 3,
          printerWidthMm: 80,
        ),
        throwsA(isA<PaperMismatchException>()),
      );
      expect(await db.select(db.templateBindings).get(), isEmpty,
          reason: 'الرفضُ لا يترك رابطةً نصفَ مكتوبة');
    });

    test('والمطابقُ يمرّ', () async {
      final t = await newTemplate(width: 80);
      await db.activateBinding(
        documentType: 'sales_receipt',
        templateId: t,
        printerId: 3,
        printerWidthMm: 80,
      );
      expect(await db.select(db.templateBindings).get(), hasLength(1));
    });

    test('وعرضٌ مجهولٌ لا يمنع', () async {
      final t = await newTemplate(width: 210);
      await db.activateBinding(
        documentType: 'sales_invoice',
        templateId: t,
        printerId: 3,
      );
      expect(await db.select(db.templateBindings).get(), hasLength(1));
    });
  });

  test('فكُّ رابطةٍ غير موجودةٍ لا ينفجر', () async {
    expect(await db.deactivateBinding(documentType: 'sales_invoice'), 0);
  });
}
