// خطّةُ طلبِ استبعاد الأصل — الحسابُ الخالص.
//
// ⚠️ ما يُقاس هنا **قواعدُ** لا صيغ: علامةُ النتيجة واسمُها · حالةُ الأصل
//    بعد الاعتماد · وما تفرضه كلُّ طريقةٍ وما تُسقطه.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/asset_disposal_plan.dart';

String? _v({
  String method = 'sale',
  double value = 9500,
  String collection = 'cash',
  int? buyer,
  int? safe = 1,
  String reason = 'استبدال الجهاز',
  String assetStatus = 'active',
}) =>
    validateAssetDisposal(
      method: method,
      disposalValue: value,
      collectionMethod: collection,
      buyerPartyId: buyer,
      safeId: safe,
      reason: reason,
      assetStatus: assetStatus,
    );

void main() {
  group('🔴 النتيجةُ باسمها الموافق لعلامتها', () {
    test('بيعٌ دون الدفتريّة خسارة', () {
      // تصميمُ المالك: تكلفةٌ ١٢٠٠٠ · مجمَّعٌ ٢٠٠٠ · بيعٌ ٩٥٠٠ ⇒ خسارةُ ٥٠٠.
      final o = computeDisposalOutcome(
          originalCost: 12000, accumulatedDepreciation: 2000, disposalValue: 9500);
      expect(o.bookValue, 10000);
      expect(o.gainLoss, -500);
      expect(o.isGain, isFalse);
      expect(o.label, 'الخسارة المتوقَّعة');
    });

    test('🔴 وبيعٌ فوقَها ربحٌ — لا «خسارةٌ» بالسالب', () {
      // 🔴 التصميمُ يسمّي الحقلَ «الخسارة المتوقعة» دائماً؛ وعرضُ ربحٍ تحته
      //    يقلب إشارةَ رقمٍ يدخل قائمةَ الدخل.
      final o = computeDisposalOutcome(
          originalCost: 12000, accumulatedDepreciation: 2000, disposalValue: 11000);
      expect(o.gainLoss, 1000);
      expect(o.isGain, isTrue);
      expect(o.label, 'الربح المتوقَّع');
    });

    test('وبيعٌ بالدفتريّة بلا ربحٍ ولا خسارة', () {
      final o = computeDisposalOutcome(
          originalCost: 12000, accumulatedDepreciation: 2000, disposalValue: 10000);
      expect(o.gainLoss, 0);
      expect(o.isGain, isFalse);
      expect(o.label, 'بلا ربحٍ ولا خسارة');
    });

    test('وإعدامٌ بلا ثمنٍ خسارتُه الدفتريّةُ كلُّها', () {
      final o = computeDisposalOutcome(
          originalCost: 12000, accumulatedDepreciation: 2000, disposalValue: 0);
      expect(o.gainLoss, -10000);
      expect(o.label, 'الخسارة المتوقَّعة');
    });

    test('وأصلٌ مُهلَكٌ تماماً يُباع ربحاً كاملاً', () {
      final o = computeDisposalOutcome(
          originalCost: 12000, accumulatedDepreciation: 12000, disposalValue: 300);
      expect(o.bookValue, 0);
      expect(o.gainLoss, 300);
      expect(o.isGain, isTrue);
    });
  });

  group('🔴 حالةُ الأصل بعد الاعتماد', () {
    test('البيعُ `sold` — وسبعةُ مواضعِ قراءةٍ تنتظره', () {
      // 🔴 `disposeAsset` تكتب `'disposed'` دائماً، فوسمُ «بيع» لا يظهر
      //    أبداً ومرشِّحُه يعدّ صفراً مهما بيع من أصول.
      expect(assetStatusAfterDisposal('sale'), 'sold');
    });

    test('وما عداه `disposed`', () {
      for (final m in ['scrap', 'donation', 'writeoff']) {
        expect(assetStatusAfterDisposal(m), 'disposed', reason: m);
      }
    });
  });

  group('فحصُ الطلب', () {
    test('البيعُ النقديُّ بخزنةٍ يمرّ', () => expect(_v(), isNull));

    test('والبيعُ الآجلُ بمشترٍ مسجَّلٍ يمرّ',
        () => expect(_v(collection: 'credit', buyer: 7, safe: null), isNull));

    test('🔴 والآجلُ بلا مشترٍ يُرفَض — بلا طرفٍ لا ذمّةَ تُحمَّل', () {
      expect(_v(collection: 'credit', buyer: null, safe: null),
          contains('مشترياً مسجَّلاً'));
    });

    test('🔴 والنقديُّ بلا خزنةٍ يُرفَض — نقدٌ يزيد في الدفتر لا في درج', () {
      // 🔴 `disposeAsset` القائمةُ تقيّد مدينَ نقديّةٍ ولا تحرّك خزنةً
      //    إطلاقاً، فرصيدُ النقد في الأستاذ يفارق مجموعَ الخزائن.
      expect(_v(collection: 'cash', safe: null), contains('الخزينة'));
    });

    test('وبيعٌ بلا قيمةٍ يُرفَض', () {
      expect(_v(value: 0), contains('قيمة البيع'));
      expect(_v(value: -5), contains('قيمة البيع'));
    });

    test('🔴 وقيمةٌ على إعدامٍ تُرفَض — بيعٌ سُمّي بغير اسمه', () {
      expect(_v(method: 'scrap', value: 500), contains('بلا ثمن'));
      expect(_v(method: 'donation', value: 1), contains('بلا ثمن'));
    });

    test('والإعدامُ بلا ثمنٍ يمرّ بلا خزنةٍ ولا مشترٍ', () {
      expect(_v(method: 'scrap', value: 0, safe: null), isNull);
      expect(_v(method: 'writeoff', value: 0, safe: null, buyer: null), isNull);
    });

    test('وسببٌ فارغٌ يُرفَض', () {
      expect(_v(reason: ''), contains('سبب الاستبعاد'));
      expect(_v(reason: '   '), contains('سبب الاستبعاد'));
    });

    test('🔴 وأصلٌ غيرُ نشطٍ لا يُستبعَد مرّتين', () {
      // 🔴 استبعادٌ ثانٍ يقيّد مجمَّعَ الإهلاك وتكلفةَ الأصل مرّةً أخرى —
      //    والقيدُ متّزنٌ فلا فحصَ اتّزانٍ يمسكه.
      expect(_v(assetStatus: 'disposed'), contains('غير نشط'));
      expect(_v(assetStatus: 'sold'), contains('غير نشط'));
    });

    test('وطريقةٌ مجهولةٌ تُرفَض', () {
      expect(_v(method: 'lost'), contains('غير معروفة'));
    });
  });

  group('التطبيع', () {
    test('🔴 الإعدامُ يُصفّر القيمةَ ويُسقط الخزنة', () {
      final n = normalizeDisposal(
        method: 'scrap',
        disposalValue: 500,
        collectionMethod: 'credit',
        buyerPartyId: 7,
        safeId: 3,
      );
      expect(n.disposalValue, 0);
      expect(n.safeId, isNull);
      expect(n.collectionMethod, 'cash');
      // ⚠️ والمتبرَّعُ له يبقى: هو مَن استلم لا مدينٌ على ذمّته.
      expect(n.buyerPartyId, 7);
    });

    test('🔴 والآجلُ لا يدخل درجاً', () {
      final n = normalizeDisposal(
        method: 'sale',
        disposalValue: 9500,
        collectionMethod: 'credit',
        buyerPartyId: 7,
        safeId: 3,
      );
      expect(n.safeId, isNull,
          reason: '🔴 خزنةٌ مع آجلٍ تُحرّك درجاً لم يدخله مال');
      expect(n.collectionMethod, 'credit');
      expect(n.disposalValue, 9500);
    });

    test('والنقديُّ يحتفظ بخزنته', () {
      final n = normalizeDisposal(
        method: 'sale',
        disposalValue: 9500,
        collectionMethod: 'cash',
        safeId: 3,
      );
      expect(n.safeId, 3);
      expect(n.collectionMethod, 'cash');
    });

    test('وتحصيلٌ مجهولٌ يسقط إلى النقديّ لا يُكتَب كما هو', () {
      final n = normalizeDisposal(
        method: 'sale',
        disposalValue: 100,
        collectionMethod: 'barter',
        safeId: 2,
      );
      expect(n.collectionMethod, 'cash');
    });
  });

  test('والعناوينُ تغطّي كلَّ قيمةٍ يعرفها العمود', () {
    for (final m in kDisposalMethods) {
      expect(disposalMethodLabel(m), isNot(m),
          reason: 'طريقةٌ تُعرَض برمزها الإنجليزيّ: $m');
    }
    expect(disposalCollectionLabel('cash'), 'نقدي');
    expect(disposalCollectionLabel('credit'), contains('آجل'));
  });
}
