// سلسلةُ حسم القالب — سبعةُ مستوياتٍ من الأخصِّ للأعمّ، وأوّلُ مطابقةٍ تفوز.
//
// ── العطبُ الذي تمنعه ─────────────────────────────────────────────────────
// اليومَ الحسمُ يقوم على عَلَمٍ واحدٍ هو `isDefault`، وهو **عالميٌّ لا يعرف
// فرعاً ولا طابعةً ولا لغة**. فالفرعُ الذي يريد ترويسةً مختلفةً لا يستطيع،
// والطابعةُ الحراريّةُ تتلقّى قالبَ A4 فيُقصّ المطبوعُ صامتاً.
//
// والرابطةُ تحلّ محلَّ العَلَم: مفتاحٌ رباعيٌّ (نوعُ المستند + الفرع + الطابعة
// + اللغة) يُجرَّب من الأخصِّ للأعمّ.
//
// ── والمستوى الخامسُ يبقى عمداً ───────────────────────────────────────────
// حسمٌ بالفئة هو سلوكُ اليوم. إسقاطُه يعني أنّ كلَّ قاعدةٍ قائمةٍ تفقد قالبَها
// الافتراضيَّ لحظةَ الترقية — فيبقى ذيلاً للسلسلة لا بديلاً عنها.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/printing/template_resolver.dart';

const _doc = 'sales_invoice';

BindingRule _b(
  int templateId, {
  String documentType = _doc,
  int? branchId,
  int? printerId,
  String? locale,
}) =>
    BindingRule(
      templateId: templateId,
      documentType: documentType,
      branchId: branchId,
      printerId: printerId,
      locale: locale,
    );

TemplateResolution _resolve(
  List<BindingRule> bindings, {
  int? branchId = 7,
  int? printerId = 3,
  String locale = 'ar',
  int? quickSaleTemplateId,
  int? categoryDefaultTemplateId,
}) =>
    TemplateResolver.resolve(
      documentType: _doc,
      category: 'invoice',
      branchId: branchId,
      printerId: printerId,
      locale: locale,
      bindings: bindings,
      quickSaleTemplateId: quickSaleTemplateId,
      categoryDefaultTemplateId: categoryDefaultTemplateId,
    );

void main() {
  group('المستوياتُ السبعةُ كلٌّ على حدة', () {
    test('١ · مستند + فرع + طابعة + لغة', () {
      final r = _resolve([_b(11, branchId: 7, printerId: 3, locale: 'ar')]);
      expect(r.templateId, 11);
      expect(r.level, 1);
    });

    test('٢ · مستند + فرع + أيُّ طابعة + لغة', () {
      final r = _resolve([_b(12, branchId: 7, locale: 'ar')]);
      expect(r.templateId, 12);
      expect(r.level, 2);
    });

    test('٣ · مستند + أيُّ فرع + أيُّ طابعة + لغة', () {
      final r = _resolve([_b(13, locale: 'ar')]);
      expect(r.templateId, 13);
      expect(r.level, 3);
    });

    test('٤ · مستند + الكلّ', () {
      final r = _resolve([_b(14)]);
      expect(r.templateId, 14);
      expect(r.level, 4);
    });

    test('٥ · مِزلاجُ البيع السريع — يرجّح حين لا رابطة', () {
      final r = _resolve(const [], quickSaleTemplateId: 55);
      expect(r.templateId, 55);
      expect(r.level, 5);
    });

    test('٦ · حسمٌ بالفئة — سلوكُ اليوم يبقى للتوافق', () {
      final r = _resolve(const [], categoryDefaultTemplateId: 15);
      expect(r.templateId, 15);
      expect(r.level, 6);
    });

    test('٧ · التصميمُ المدمجُ حين لا شيء', () {
      final r = _resolve(const []);
      expect(r.templateId, isNull);
      expect(r.level, 7);
      expect(r.isBuiltIn, isTrue);
    });

    // ترتيبُ الخامس بين الرابعِ والسادس — لا يكفي أن يعمل كلٌّ على حدة.
    test('والمِزلاجُ يخسر أمام رابطةٍ ويفوز على الفئة', () {
      expect(
          _resolve([_b(14)], quickSaleTemplateId: 55, categoryDefaultTemplateId: 15)
              .templateId,
          14,
          reason: 'الرابطةُ نيّةٌ أخصُّ من مِزلاجٍ عامّ');
      expect(
          _resolve(const [],
                  quickSaleTemplateId: 55, categoryDefaultTemplateId: 15)
              .templateId,
          55,
          reason: '`isDefault` عَلَمٌ عالميٌّ لا يعرف نيّةً — والمِزلاجُ اختيار');
    });
  });

  group('الأخصُّ يفوز حين تتزاحم الرابطات', () {
    test('الرابطةُ الرباعيّةُ تسبق الثلاثيّةَ والعامّة', () {
      final r = _resolve([
        _b(14),
        _b(13, locale: 'ar'),
        _b(12, branchId: 7, locale: 'ar'),
        _b(11, branchId: 7, printerId: 3, locale: 'ar'),
      ]);
      expect(r.templateId, 11, reason: 'الترتيبُ في القائمة لا يقرّر — الخصوصيّة تقرّر');
    });

    test('وترتيبُ الإدخال المعكوسُ لا يغيّر النتيجة', () {
      final r = _resolve([
        _b(11, branchId: 7, printerId: 3, locale: 'ar'),
        _b(12, branchId: 7, locale: 'ar'),
        _b(14),
      ]);
      expect(r.templateId, 11);
    });
  });

  group('عدمُ المطابقة يسقط للمستوى التالي', () {
    test('فرعٌ آخرُ لا يخطف الرابطة', () {
      final r = _resolve([
        _b(11, branchId: 99, printerId: 3, locale: 'ar'),
        _b(14),
      ]);
      expect(r.templateId, 14, reason: 'رابطةُ الفرع ٩٩ لا تخصّ الفرع ٧');
    });

    test('لغةٌ أخرى لا تخطف الرابطة', () {
      final r = _resolve([_b(13, locale: 'en'), _b(14)]);
      expect(r.templateId, 14);
    });

    test('طابعةٌ أخرى لا تخطف الرابطة', () {
      final r = _resolve([
        _b(11, branchId: 7, printerId: 99, locale: 'ar'),
        _b(12, branchId: 7, locale: 'ar'),
      ]);
      expect(r.templateId, 12);
    });

    test('ونوعُ مستندٍ آخرَ لا يخطف شيئاً', () {
      final r = _resolve(
        [_b(11, documentType: 'purchase_invoice', branchId: 7)],
        categoryDefaultTemplateId: 15,
      );
      expect(r.templateId, 15, reason: 'رابطةُ المشتريات لا تخدم فاتورةَ مبيعات');
    });
  });

  group('المرتجعاتُ فئةٌ قائمةٌ بذاتها', () {
    // بدون `sales_return` يتقاسم المرتجعُ فئةَ الفاتورة، فيستحيل أن يكون له
    // قالبٌ افتراضيٌّ خاصّ — وهو ما يرصده «تصادمُ الفئة».
    test('مرتجعُ المبيعات يحسم لقالبه لا لقالب الفاتورة', () {
      final r = TemplateResolver.resolve(
        documentType: 'sales_return',
        category: 'invoice',
        branchId: 7,
        printerId: 3,
        locale: 'ar',
        bindings: [
          _b(20, documentType: 'sales_invoice'),
          _b(21, documentType: 'sales_return'),
        ],
      );
      expect(r.templateId, 21);
    });

    test('و`sales_return` نوعُ مستندٍ معترَفٌ به', () {
      expect(TemplateResolver.documentTypes, contains('sales_return'));
      expect(TemplateResolver.documentTypes, contains('purchase_return'));
    });
  });

  group('الأولويّةُ تفصل عند تساوي الخصوصيّة', () {
    test('الأعلى أولويّةً يفوز', () {
      final r = _resolve([
        const BindingRule(
            templateId: 30, documentType: _doc, locale: 'ar', priority: 1),
        const BindingRule(
            templateId: 31, documentType: _doc, locale: 'ar', priority: 9),
      ]);
      expect(r.templateId, 31);
    });
  });

  test('الحسمُ يحمل نسخَ الطباعة والطباعةَ المباشرة من الرابطة', () {
    final r = _resolve([
      const BindingRule(
        templateId: 40,
        documentType: _doc,
        branchId: 7,
        printerId: 3,
        locale: 'ar',
        copies: 3,
        directPrint: true,
      ),
    ]);
    expect(r.copies, 3);
    expect(r.directPrint, isTrue);
  });

  test('والمدمجُ يعطي نسخةً واحدةً بلا طباعةٍ مباشرة', () {
    final r = _resolve(const []);
    expect(r.copies, 1);
    expect(r.directPrint, isFalse);
  });
}
