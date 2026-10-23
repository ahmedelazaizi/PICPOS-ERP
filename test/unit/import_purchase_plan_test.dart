// حسابُ فاتورة الاستيراد — الدوالُّ الخالصة.
//
// ⚠️ **والاتّجاهُ هو الموضوع.** قلبُ الضرب إلى قسمةٍ لا يُنتج خطأً ولا
//    رسالةً: يُنتج رقماً بحجمٍ آخر. فكلُّ توكيدٍ هنا يثبّت **قيمةً محسوبةً
//    يدويّاً** لا «أكبرَ من صفر».

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/domain/models/import_purchase_plan.dart';

ImportDocumentFields _doc({
  String? customs,
  String? bl,
  String? country,
  String? port,
  String? lc,
  int? agentId,
  String? agentName,
  String? notes,
}) =>
    normalizeImportDocument(
      customsDeclarationNo: customs,
      billOfLading: bl,
      countryOfOrigin: country,
      port: port,
      letterOfCredit: lc,
      clearingAgentPartyId: agentId,
      clearingAgentName: agentName,
      notes: notes,
    );

void main() {
  group('التحويل — الاتّجاهُ ضربٌ لا قسمة', () {
    test('ألفُ وحدةٍ أجنبيّةٍ بسعر ٠٫٠٢ = عشرون محلّيّة', () {
      expect(
        foreignToLocal(foreign: 1000, localPerForeign: 0.02),
        20.0,
      );
    });

    test('وبسعرٍ أكبرَ من واحدٍ يكبر الرقمُ لا يصغر', () {
      // 🔴 قلبُ الاتّجاه هنا يعطي ٦٦٫٦٦٧ بدل ١٥٠٠٠ — كلاهما «رقم».
      expect(foreignToLocal(foreign: 1000, localPerForeign: 15), 15000.0);
    });

    test('وسعرُ ١ لا يغيّر شيئاً', () {
      expect(foreignToLocal(foreign: 1234.567, localPerForeign: 1), 1234.567);
    });

    test('ويُقرَّب إلى دقّة المال لا يُترَك كسراً عائماً', () {
      // ٣ خاناتٍ هي الافتراضُ (دينار)، فالرابعةُ تُقرَّب.
      expect(AppConstants.decimalPlaces, 3);
      expect(foreignToLocal(foreign: 1, localPerForeign: 0.00005), 0.0);
      expect(foreignToLocal(foreign: 1, localPerForeign: 0.0006), 0.001);
    });

    test('والصفرُ يبقى صفراً', () {
      expect(foreignToLocal(foreign: 0, localPerForeign: 15), 0.0);
    });
  });

  group('فحصُ سعر الصرف', () {
    test('بلا عملةٍ ولا سعرٍ — فاتورةٌ محلّيّةٌ تجوز', () {
      expect(
        validateExchangeRate(currencyId: null, localPerForeign: null),
        isNull,
      );
    });

    test('🔴 عملةٌ بلا سعرٍ تُرفَض — وإلّا قُرئت سعراً ١', () {
      final msg =
          validateExchangeRate(currencyId: 3, localPerForeign: null);
      expect(msg, isNotNull);
      expect(msg, contains('سعر الصرف'));
    });

    test('🔴 وسعرٌ بلا عملةٍ يُرفَض — مُعامِلٌ بلا وحدة', () {
      expect(
        validateExchangeRate(currencyId: null, localPerForeign: 0.02),
        isNotNull,
      );
    });

    test('وصفرٌ يُرفَض — يُصفّر الفاتورةَ كلَّها', () {
      expect(validateExchangeRate(currencyId: 3, localPerForeign: 0), isNotNull);
    });

    test('وسالبٌ يُرفَض — يقلب إشارةَ الذمّة', () {
      expect(
        validateExchangeRate(currencyId: 3, localPerForeign: -0.02),
        isNotNull,
      );
    });

    test('وسعرٌ موجبٌ صغيرٌ جدّاً يجوز — عملاتٌ حقيقيّةٌ كذلك', () {
      expect(
        validateExchangeRate(
            currencyId: 3, localPerForeign: kMinExchangeRate),
        isNull,
      );
    });

    test('وزوجٌ سليمٌ يمرّ', () {
      expect(
        validateExchangeRate(currencyId: 3, localPerForeign: 0.02),
        isNull,
      );
    });
  });

  group('تطبيعُ المستند', () {
    test('الفراغُ يصير null لا نصّاً فارغاً', () {
      final d = _doc(customs: '   ', bl: '', country: 'مصر');
      expect(d.customsDeclarationNo, isNull);
      expect(d.billOfLading, isNull);
      expect(d.countryOfOrigin, 'مصر');
    });

    test('والأطرافُ تُقلَّم', () {
      expect(_doc(port: '  الإسكندرية  ').port, 'الإسكندرية');
    });

    test('🔴 والطرفُ المسجَّلُ يُسقط النصّ — حقلان لا يقولان اسمَين', () {
      final d = _doc(agentId: 7, agentName: 'شركة التخليص');
      expect(d.clearingAgentPartyId, 7);
      expect(d.clearingAgentName, isNull);
    });

    test('وبلا طرفٍ يبقى النصّ', () {
      final d = _doc(agentName: 'شركة التخليص');
      expect(d.clearingAgentPartyId, isNull);
      expect(d.clearingAgentName, 'شركة التخليص');
    });
  });

  group('فحصُ أطوال المستند', () {
    test('لا حقلَ إلزاميّ — مستندٌ خالٍ يجوز', () {
      expect(validateImportDocument(_doc()), isNull);
    });

    test('🔴 وطولٌ يتجاوز عمودَ القاعدة يُرفَض قبل أن تتحرّك بضاعة', () {
      final msg = validateImportDocument(
        _doc(customs: 'x' * (kCustomsDeclarationNoMax + 1)),
      );
      expect(msg, isNotNull);
      expect(msg, contains('البيان الجمركي'));
    });

    test('وعلى الحدّ بالضبط يجوز', () {
      expect(
        validateImportDocument(_doc(bl: 'x' * kBillOfLadingMax)),
        isNull,
      );
    });

    test('وبوليصةٌ أطولُ تُسمّى باسمها في الرسالة', () {
      expect(
        validateImportDocument(_doc(bl: 'x' * (kBillOfLadingMax + 1))),
        contains('بوليصة الشحن'),
      );
    });

    test('واسمُ الوكيل كذلك', () {
      expect(
        validateImportDocument(
            _doc(agentName: 'x' * (kClearingAgentNameMax + 1))),
        contains('وكيل التخليص'),
      );
    });
  });

  group('الوسمُ يُكتَب ولو خلا', () {
    test('الخلوُّ يُقاس ولا يمنع', () {
      expect(importDocumentIsEmpty(_doc()), isTrue);
      expect(validateImportDocument(_doc()), isNull);
    });

    test('وحقلٌ واحدٌ يكفي ليخرج من الخلوّ', () {
      expect(importDocumentIsEmpty(_doc(port: 'جدة')), isFalse);
      expect(importDocumentIsEmpty(_doc(agentId: 4)), isFalse);
      expect(importDocumentIsEmpty(_doc(notes: 'شحنة')), isFalse);
    });
  });

  group('تحويلُ السطور', () {
    const line = (
      quantity: 10.0,
      unitCostForeign: 100.0,
      discountForeign: 0.0,
      taxRate: 14.0,
      taxEnabled: true,
    );

    test('التكلفةُ تُضرَب والكمّيّةُ لا', () {
      final out = convertImportLines(lines: [line], localPerForeign: 0.02);
      expect(out.single.unitCost, 2.0);
      // 🔴 ضربُ الكمّيّة كان يجعل عشرَ قطعٍ عُشرَ قطعة.
      expect(out.single.quantity, 10.0);
    });

    test('🔴 والنسبةُ لا تُضرَب — ١٤٪ تبقى ١٤٪', () {
      final out = convertImportLines(lines: [line], localPerForeign: 0.02);
      expect(out.single.taxRate, 14.0);
    });

    test('والضريبةُ تُحسَب على الصافي المحوَّل', () {
      final out = convertImportLines(lines: [line], localPerForeign: 0.02);
      // 10 × 2 = 20 · 14% = 2.8
      expect(out.single.taxAmount, 2.8);
      expect(out.single.total, 22.8);
    });

    test('وسطرٌ معفىً بلا ضريبةٍ مهما كانت نسبتُه', () {
      final out = convertImportLines(
        lines: [(
          quantity: 10.0,
          unitCostForeign: 100.0,
          discountForeign: 0.0,
          taxRate: 14.0,
          taxEnabled: false,
        )],
        localPerForeign: 0.02,
      );
      expect(out.single.taxAmount, 0.0);
      expect(out.single.total, 20.0);
    });

    test('والخصمُ يُحوَّل ويُطرَح قبل الضريبة', () {
      final out = convertImportLines(
        lines: [(
          quantity: 10.0,
          unitCostForeign: 100.0,
          discountForeign: 100.0,
          taxRate: 10.0,
          taxEnabled: true,
        )],
        localPerForeign: 0.02,
      );
      expect(out.single.discount, 2.0);
      // (20 − 2) × 10% = 1.8
      expect(out.single.taxAmount, 1.8);
      expect(out.single.total, 19.8);
    });

    test('وقائمةٌ فارغةٌ تُرجِع فارغة', () {
      expect(convertImportLines(lines: const [], localPerForeign: 0.02),
          isEmpty);
    });
  });

  group('الإجماليّان — الأجنبيُّ والمحلّيُّ معاً', () {
    test('يُعرَضان معاً ويختلفان بالسعر', () {
      final t = importTotalsPreview(
        lines: const [(
          quantity: 10.0,
          unitCostForeign: 100.0,
          discountForeign: 0.0,
          taxRate: 0.0,
          taxEnabled: false,
        )],
        localPerForeign: 0.02,
      );
      expect(t.foreign, 1000.0);
      expect(t.local, 20.0);
    });

    test('وخصمُ الترويسة يُطرَح من الأجنبيِّ ثمّ يُحوَّل', () {
      final t = importTotalsPreview(
        lines: const [(
          quantity: 10.0,
          unitCostForeign: 100.0,
          discountForeign: 0.0,
          taxRate: 0.0,
          taxEnabled: false,
        )],
        localPerForeign: 0.02,
        documentDiscountForeign: 200,
      );
      expect(t.foreign, 800.0);
      expect(t.local, 16.0);
    });
  });

  group('حمولةُ الخادم', () {
    test('🔴 رقمُ الطرف لا يسافر — أرقامُ الجهازَين تتباعد بالتصميم', () {
      final j = importDocumentToJson(_doc(agentId: 9, customs: 'C-1'));
      expect(j.containsKey('clearingAgentPartyId'), isFalse);
      expect(j['customsDeclarationNo'], 'C-1');
    });

    test('والعكسُ يُركّب الطرفَ من الحلّ لا من الحمولة', () {
      final j = importDocumentToJson(_doc(customs: 'C-1', port: 'جدة'));
      final back = importDocumentFromJson(j, clearingAgentPartyId: 42);
      expect(back.customsDeclarationNo, 'C-1');
      expect(back.port, 'جدة');
      expect(back.clearingAgentPartyId, 42);
    });

    test('ودورةٌ كاملةٌ تحفظ النصوص', () {
      final d = _doc(
        customs: 'C-9',
        bl: 'BL-1',
        country: 'الصين',
        port: 'شنغهاي',
        lc: 'LC-7',
        agentName: 'وكيل',
        notes: 'ملاحظة',
      );
      final back = importDocumentFromJson(importDocumentToJson(d));
      expect(back, d);
    });

    test('وحمولةٌ خاليةٌ تُنتج مستنداً خالياً لا أصفاراً', () {
      final back = importDocumentFromJson(const <String, dynamic>{});
      expect(importDocumentIsEmpty(back), isTrue);
    });
  });
}
