// «أثر الإعدادات الحالية» — لوحةُ المعاينة في §٤.
//
// المصدرُ `buildPreview()` في
// `invoice_templates/design/PicPos Quick Sale Settings.dc.html`.
//
// ═══ لماذا هذا أثمنُ ما في الشاشة ═══
//
// الشاشةُ تعرض ٢٩ مِزلاجاً، ولا أحدَ يقرأ ٢٩ مِزلاجاً ليعرف ماذا فعل. وأسطرُ
// الأثر تترجم الحالةَ إلى جملةٍ واحدةٍ يفهمها المالك: «أي كاشير يقفل بلا
// مصادقة والفرق يُسجَّل صفراً». فهي التي تجعل الإعدادَ قراراً لا مِزلاجاً.
//
// ونبرةُ السطر جزءٌ من المعنى لا زينة: «الإغلاق السريع مضاء» **خطرٌ**
// و«مطفأ» **سليم** — فالنبرةُ تُقاس كما يُقاس النصّ.
//
// ⚠️ ولا `Color` هنا ولا في النموذج: النبرةُ رمزٌ، وترجمتُها إلى لونٍ تقع في
// طبقة العرض. وإلّا صار `domain/models` يستورد `material`.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/quick_sale_policy.dart';

void main() {
  group('كلُّ خطوةٍ تعطي ثلاثةَ أسطرِ أثر', () {
    test('للخطوات الخمس جميعاً', () {
      for (final step in kQuickSaleSteps) {
        final lines = quickSaleImpact(step.id, const QuickSalePolicyValues({}));
        expect(lines.length, 3,
            reason: 'الخطوةُ «${step.id}» أعطت ${lines.length} سطراً — '
                'التصميمُ يرسم ثلاثةً لكلِّ خطوة.');
        expect(lines.every((l) => l.text.trim().isNotEmpty), isTrue);
      }
    });
  });

  group('النصُّ يتبع القيمةَ لا يثبت', () {
    test('«سؤال عن الكمية» يقلب جملةَ المسح', () {
      final off = quickSaleImpact('scan', const QuickSalePolicyValues({}));
      final on = quickSaleImpact(
          'scan', const QuickSalePolicyValues({'pos_ask_quantity_before_add': 'true'}));

      expect(off.first.text, contains('وحدة واحدة فوراً'));
      expect(on.first.text, contains('لوحة أرقام'));
      expect(off.first.text, isNot(on.first.text));
    });

    test('وسقفُ الخصم يظهر بالأرقام العربيّة داخلَ الجملة', () {
      final lines = quickSaleImpact(
          'cart', const QuickSalePolicyValues({'pos_manual_discount_cap': '25'}));

      expect(lines.first.text, contains('٢٥٪'),
          reason: 'الرقمُ يُعرض عربيّاً كبقيّةِ الواجهة — و«٢٥» لا «25».');
      expect(lines.first.text, contains('موافقة مدير'),
          reason: 'الافتراضُ أنّ ما فوق السقف يحتاج موافقة.');
    });

    test('وإطفاءُ الموافقة يبدّل عاقبةَ تجاوز السقف', () {
      final lines = quickSaleImpact(
          'cart',
          const QuickSalePolicyValues({'pos_discount_requires_manager': 'false'}));

      expect(lines.first.text, contains('يُرفض'),
          reason: 'بلا مسار موافقة يُرفض الخصمُ بدل أن يُصعَّد.');
    });
  });

  group('النبرةُ تحمل الحكم', () {
    test('«الإغلاق السريع» مضاءً خطرٌ ومطفأً سليم', () {
      final on = quickSaleImpact('shift', const QuickSalePolicyValues({}));
      final off = quickSaleImpact(
          'shift', const QuickSalePolicyValues({'pos_quick_close_enabled': 'false'}));

      expect(on.first.tone, QuickSaleImpactTone.danger,
          reason: 'الإغلاقُ السريعُ الطريقُ الوحيدُ بلا مصادقةٍ ويُصفّر '
              'الفرق — فظهورُه خطرٌ محاسبيٌّ لا خيارُ عرض.');
      expect(on.first.text, contains('بلا مصادقة'));

      expect(off.first.tone, QuickSaleImpactTone.good);
      expect(off.first.text, contains('مصادقة'));
    });

    test('وغيابُ كلِّ طرق المصادقة خطر', () {
      final none = quickSaleImpact(
          'shift', const QuickSalePolicyValues({'pos_close_auth_methods': ''}));
      // فارغٌ نصّاً ⇒ يعود للافتراض، فالطرقُ موجودة.
      expect(none.last.tone, QuickSaleImpactTone.good);

      final cleared = quickSaleImpact('shift',
          const QuickSalePolicyValues({'pos_close_auth_methods': 'لا-شيء'}));
      expect(cleared.last.tone, QuickSaleImpactTone.danger,
          reason: 'قيمةٌ لا تطابق أيَّ طريقةٍ معروفةٍ تعني صفرَ طرق — '
              'وهي الحالةُ التي يمنع فيها النظامُ إغلاقَ الوردية.');
      expect(cleared.last.text, contains('كلمة المرور'));
    });

    test('و«حذف السطر بلا مصادقة» خطرٌ لأنّه يمحو الأثر', () {
      final free = quickSaleImpact('cart', const QuickSalePolicyValues({}));
      expect(free[2].tone, QuickSaleImpactTone.danger);
      expect(free[2].text, contains('لا أثر'));

      final guarded = quickSaleImpact('cart',
          const QuickSalePolicyValues({'pos_delete_line_requires_auth': 'true'}));
      expect(guarded[2].tone, QuickSaleImpactTone.good);
    });
  });

  group('المسارُ السريعُ يُشتقّ من الطرق لا يُعلَن', () {
    test('طريقةٌ واحدةٌ مؤشَّرةٌ مع تخطّي الحوار ⇒ مسارٌ سريع', () {
      final fast = quickSaleImpact(
          'pay',
          const QuickSalePolicyValues({'pos_payment_methods_enabled': 'cash'}));

      expect(fast.first.tone, QuickSaleImpactTone.good);
      expect(fast.first.text, contains('مسار سريع'));
    });

    test('وطريقتان تُعيدان الحوارَ ويُذكر عددُهما عربيّاً', () {
      final dialog = quickSaleImpact(
          'pay',
          const QuickSalePolicyValues(
              {'pos_payment_methods_enabled': 'cash,card'}));

      expect(dialog.first.tone, QuickSaleImpactTone.neutral);
      expect(dialog.first.text, contains('٢ طرق'));
    });

    test('وإطفاءُ التخطّي يُلغي المسارَ السريعَ ولو بطريقةٍ واحدة', () {
      final noSkip = quickSaleImpact(
          'pay',
          const QuickSalePolicyValues({
            'pos_payment_methods_enabled': 'cash',
            'pos_skip_payment_dialog_single_method': 'false',
          }));

      expect(noSkip.first.text, isNot(contains('مسار سريع')));
    });
  });

  group('الطباعة', () {
    test('مطفأةً تقول إنّ الكاشير يطبع بنقرة', () {
      final off = quickSaleImpact('print', const QuickSalePolicyValues({}));
      expect(off.first.tone, QuickSaleImpactTone.neutral);
      expect(off.first.text, contains('بنقرة'));
    });

    test('ومضاءةً تذكر عددَ النسخ والقالب', () {
      final on = quickSaleImpact(
          'print',
          const QuickSalePolicyValues({
            'auto_print_receipt': 'true',
            'pos_receipt_copies': '1',
          }));

      expect(on.first.tone, QuickSaleImpactTone.good);
      expect(on.first.text, contains('نسختان'));
      expect(on.first.text, contains('thermal80_quick_sale'));
    });
  });
}
