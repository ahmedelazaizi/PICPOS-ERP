// سياسةُ «البيع السريع» — §٤ من بلاغ المالك 2026-08-29.
//
// المصدرُ `invoice_templates/design/PicPos Quick Sale Settings.dc.html`.
//
// ═══ لماذا نموذجٌ خالصٌ في `domain/models` ═══
//
// الشاشةُ تعرض ٢٩ إعداداً في خمسِ خطوات، ولكلٍّ مفتاحٌ في القاعدة وقيمةٌ
// افتراضيّةٌ ومجموعةُ خيارات. وضعُ ذلك في ملفّ الواجهة يجعل الرقمَ الافتراضيَّ
// والمفتاحَ غيرَ قابلَين للقياس إلّا بضخِّ الشاشة. وهنا يُقاسان مباشرة.
//
// ═══ الفخُّ الذي يحرسه هذا الملفّ ═══
//
// ⚠️ **إعدادٌ يُحفَظ ولا يُقرأ = ميزةٌ ميّتةٌ صامتة.** المديرُ يطفئ «البيع
// بالسالب» فيظنّه ممنوعاً وهو يمرّ. ولهذا يحمل كلُّ صفٍّ حالةَ إنفاذٍ صريحةً،
// وقائمةُ غيرِ المنفَّذ **تتقلّص ولا تكبر** — على نفس عقد
// `PermissionEnforcementRegistry.picposParityGaps`.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/quick_sale_policy.dart';

void main() {
  group('بنيةُ سياسة البيع السريع', () {
    test('خمسُ خطواتٍ بمفاتيح التصميم وترتيبِه', () {
      expect(
        kQuickSaleSteps.map((s) => s.id).toList(),
        const ['scan', 'cart', 'pay', 'print', 'shift'],
      );
      expect(
        kQuickSaleSteps.map((s) => s.label).toList(),
        const ['مسح الصنف', 'السلة', 'الدفع', 'الطباعة', 'الوردية'],
      );
    });

    test('وتسعةٌ وعشرون صفّاً موزّعةً ٧+٧+٥+٦+٤', () {
      expect(
        kQuickSaleSteps.map((s) => s.rows.length).toList(),
        const [7, 7, 5, 6, 4],
      );
      expect(kQuickSaleRows.length, 29);
    });

    test('ولا مفتاحَ مكرّرٌ ولا فارغ', () {
      final keys = kQuickSaleRows.map((r) => r.settingKey).toList();
      expect(keys.toSet().length, keys.length,
          reason: 'مفتاحان متطابقان يعني أنّ صفّاً يدهس صفّاً آخرَ عند الحفظ.');
      expect(keys.every((k) => k.isNotEmpty), isTrue);
    });
  });

  group('الارتباطُ بما هو مشحونٌ فعلاً', () {
    // ⚠️ هذه المفاتيحُ **موجودةٌ ومنفَّذةٌ** في المستودع قبل هذا البند، فلا
    // يجوز أن يخترع هذا البندُ لها مفاتيحَ جديدةً بجوارها: إعدادان لنفس
    // المعنى ينفصلان عند أوّل حفظ، ويبقى المحرّكُ يقرأ القديمَ بينما الشاشةُ
    // تكتب الجديد.
    test('الصفوفُ التي لها مفتاحٌ قائمٌ ترتبط به لا تخترع بديلاً', () {
      String keyOf(String id) =>
          kQuickSaleRows.firstWhere((r) => r.id == id).settingKey;

      expect(keyOf('merge'), 'pos_prevent_item_stacking');
      expect(keyOf('autoprint'), 'auto_print_receipt');
      expect(keyOf('quickclose'), 'pos_quick_close_enabled');
    });

    // ⚠️ **«البيع بالسالب» ثلاثيٌّ في التصميم وثنائيٌّ في المحرّك.**
    // `enable_negative_sales` مِزلاجٌ مشحونٌ يقرأه
    // `sales_transaction_orchestrator` في كلِّ بيعة. والتصميمُ يريد
    // «منع · تحذير · السماح».
    //
    // فلو ربطنا الصفَّ بالمِزلاج وحدَه ضاع الخيارُ الثالث، ولو اخترعنا
    // مفتاحاً ثلاثيّاً وحدَه لبقي المحرّكُ يقرأ القديمَ ولم يتغيّر شيء.
    // فالصفُّ يحمل الاثنين: مفتاحُه الثلاثيُّ مصدرُ العرض، ومرآتُه الثنائيّةُ
    // تُكتب معه في نفس الحفظ فيبقى المحرّكُ صحيحاً.
    test('و«البيع بالسالب» يكتب مرآتَه الثنائيّة مع مفتاحه الثلاثيّ', () {
      final row = kQuickSaleRows.firstWhere((r) => r.id == 'negstock');

      expect(row.options.length, 3);
      expect(row.mirrorKey, 'enable_negative_sales',
          reason: 'بلا المرآة يبقى المحرّكُ يقرأ القيمةَ القديمةَ مهما '
              'بدّل المديرُ الشاشة.');

      // منع ⇒ لا يُسمح؛ تحذير والسماح ⇒ يُسمح (يفترقان في التنبيه لا المنع).
      expect(row.mirrorFor!(0), 'false');
      expect(row.mirrorFor!(1), 'true');
      expect(row.mirrorFor!(2), 'true');
    });

    test('و«تجميع الصنف» معكوسُ «منع التراكم» لا مرادفُه', () {
      final merge = kQuickSaleRows.firstWhere((r) => r.id == 'merge');
      expect(merge.invertedBinding, isTrue,
          reason: 'المفتاحُ المشحونُ `pos_prevent_item_stacking` يعني '
              '**المنعَ**، وعنوانُ التصميم «تجميع الصنف المتكرر» يعني '
              'السماح. فحفظُ القيمة كما هي يقلب الإعدادَ رأساً على عقب.');
    });
  });

  group('سجلُّ ما لم يُنفَّذ بعد', () {
    test('كلُّ صفٍّ غيرِ منفَّذٍ مسجَّلٌ بسببٍ صريح', () {
      for (final row in kQuickSaleRows) {
        if (row.enforced) continue;
        expect(
          row.notEnforcedReason,
          isNotNull,
          reason: 'الصفُّ «${row.id}» غيرُ منفَّذٍ وبلا سببٍ مكتوب. '
              'إعدادٌ يُحفَظ ولا يُقرأ ميزةٌ ميّتةٌ صامتة — فليُكتب سببُه '
              'كي يُرى في المراجعة.',
        );
        expect(row.notEnforcedReason, isNotEmpty);
      }
    });

    test('وما وُصف بأنه منفَّذٌ لا يحمل سبباً', () {
      for (final row in kQuickSaleRows.where((r) => r.enforced)) {
        expect(row.notEnforcedReason, isNull,
            reason: 'الصفُّ «${row.id}» منفَّذٌ ومعه سببُ عدمِ إنفاذ — '
                'تناقضٌ يعني أنّ أحدَهما لم يُحدَّث.');
      }
    });
  });

  _valuesSuite();

  group('الخياراتُ والافتراضات', () {
    test('صفوفُ الاختيار تحمل خياراتٍ وافتراضاً داخلَ مداها', () {
      for (final row in kQuickSaleRows) {
        if (row.kind == QuickSaleControl.toggle) {
          expect(row.options, isEmpty);
          expect(row.defaultIndex, anyOf(0, 1),
              reason: 'المِزلاجُ صفرٌ أو واحد — «${row.id}».');
          continue;
        }
        if (row.kind == QuickSaleControl.number) continue;

        expect(row.options, isNotEmpty,
            reason: 'الصفُّ «${row.id}» من نوع ${row.kind} بلا خيارات.');
        expect(row.defaultIndex, lessThan(row.options.length),
            reason: 'افتراضُ «${row.id}» خارجَ مدى خياراته — '
                'يسقط عند أوّل قراءة.');
        expect(row.defaultIndex, greaterThanOrEqualTo(0));
      }
    });

    test('وسقفُ الخصم رقمٌ بمدىً ووحدة', () {
      final cap = kQuickSaleRows.firstWhere((r) => r.id == 'disccap');
      expect(cap.kind, QuickSaleControl.number);
      expect(cap.min, 0);
      expect(cap.max, 50);
      expect(cap.defaultNumber, 15);
      expect(cap.unit, '٪');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// فكُّ القيم وحفظُها — الموضعُ الذي يقع فيه العطبُ الصامت
// ═══════════════════════════════════════════════════════════════════════════
//
// ثلاثةُ مزالقَ مقيسة:
//   ١. **العكس**: `pos_prevent_item_stacking` يعني المنعَ، والعنوانُ يعني
//      السماح. خطأٌ هنا يقلب الإعدادَ لكلِّ كاشير.
//   ٢. **الافتراض عند الغياب**: قاعدةٌ نظيفةٌ لا تحمل المفتاح، فالقراءةُ
//      يجب أن تعطي افتراضَ التصميم لا صفراً.
//   ٣. **القيمةُ الفاسدة**: نصٌّ ليس رقماً في القاعدة يجب ألّا يُسقط الشاشة.
void _valuesSuite() {
  group('فكُّ القيم', () {
    test('قاعدةٌ فارغةٌ تعطي افتراضاتِ التصميم', () {
      const v = QuickSalePolicyValues({});

      expect(v.isOn(_row('focus')), isTrue);
      expect(v.isOn(_row('askqty')), isFalse);
      expect(v.indexOf(_row('negstock')), 1);
      expect(v.indexOf(_row('mgrlimit')), 2);
      expect(v.numberOf(_row('disccap')), 15);
    });

    test('و«تجميع الصنف» يُفكُّ معكوساً عن مفتاحه المشحون', () {
      // المفتاحُ يعني «امنع التراكم». فـ`true` تعني **لا** تجميع.
      const on = QuickSalePolicyValues({'pos_prevent_item_stacking': 'false'});
      const off = QuickSalePolicyValues({'pos_prevent_item_stacking': 'true'});

      expect(on.isOn(_row('merge')), isTrue);
      expect(off.isOn(_row('merge')), isFalse);
    });

    test('وقيمةٌ فاسدةٌ تعود للافتراض بلا انهيار', () {
      const v = QuickSalePolicyValues({
        'pos_manual_discount_cap': 'ليست رقماً',
        'pos_negative_stock_policy': '٩٩',
      });

      expect(v.numberOf(_row('disccap')), 15);
      expect(v.indexOf(_row('negstock')), 1,
          reason: 'فهرسٌ خارجَ المدى يجب أن يعود للافتراض لا أن يُسقط '
              'الشاشةَ عند أوّل بناء.');
    });
  });

  group('حفظُ القيم', () {
    test('المِزلاجُ المعكوسُ يُكتب معكوساً', () {
      final w = QuickSalePolicyValues.write(_row('merge'), 1);
      expect(w, {'pos_prevent_item_stacking': 'false'});
    });

    test('و«البيع بالسالب» يكتب مفتاحَه ومرآتَه معاً', () {
      expect(QuickSalePolicyValues.write(_row('negstock'), 0), {
        'pos_negative_stock_policy': '0',
        'enable_negative_sales': 'false',
      });
      expect(QuickSalePolicyValues.write(_row('negstock'), 2), {
        'pos_negative_stock_policy': '2',
        'enable_negative_sales': 'true',
      });
    });

    test('والمِزلاجُ العاديُّ نصٌّ منطقيٌّ لا فهرس', () {
      expect(QuickSalePolicyValues.write(_row('quickclose'), 0),
          {'pos_quick_close_enabled': 'false'});
    });
  });

  group('الاختيارُ المتعدّد', () {
    test('يحفظ الترتيبَ لا المجموعةَ وحدَها', () {
      final pick = kQuickSalePicks.firstWhere((p) => p.id == 'methods');
      final w = QuickSalePolicyValues.writePick(pick, ['card', 'cash']);
      expect(w, {'pos_enabled_payment_methods': 'card,cash'});

      const v = QuickSalePolicyValues(
          {'pos_enabled_payment_methods': 'card,cash'});
      expect(v.pickOf(pick), ['card', 'cash'],
          reason: 'الترتيبُ هو ترتيبُ الأزرار على شاشة الكاشير — '
              'فكُّه كمجموعةٍ يفقد المعنى.');
    });

    test('وغيابُ المفتاح يعطي المؤشَّرَ افتراضاً بترتيب التصميم', () {
      final pick = kQuickSalePicks.firstWhere((p) => p.id == 'methods');
      const v = QuickSalePolicyValues({});
      expect(v.pickOf(pick), ['cash', 'card', 'click', 'credit'],
          reason: '«دفع متعدّد» مطفأٌ افتراضاً في التصميم.');
    });
  });
}

QuickSaleRow _row(String id) => kQuickSaleRows.firstWhere((r) => r.id == id);
