// حارسُ العقد: **ورقةُ المعاينة لا تحمل رقماً، والفرعُ لا يُختار.**
//
// ═══ ما يُحرَس هنا ولماذا ═══
//
// ‏١) 🔴 **رقمُ الفاتورة يُولَّد داخلَ معاملة الحفظ** (‏Spec 066:
//    `generateInvoiceNumber` والإدراجُ التابعُ له في نفس الدالّة). فقبل
//    الحفظ لا رقمَ موجود.
//
//    ومعاينةٌ تطبع رقماً مخمَّناً تُخرج ورقةً **تبدو مستنداً ضريبيّاً** برقمٍ
//    قد يذهب لفاتورة عميلٍ آخر: يعاين المستخدمُ «INV-1043» ويطبعها ويسلّمها،
//    ثمّ يُحفَظ مستندُه «INV-1044» — ونسختان ورقيّتان بنفس الرقم عند عميلَين.
//    ولا شيءَ في النظام يمسك ذلك: الورقةُ خرجت ولا أثرَ لها.
//
// ‏٢) **ولا سطرَ في سجلّ النشاط**: السجلُّ يربط الطباعةَ بمستندٍ (`entityId`)
//    ولا مستندَ هنا. وصفٌّ بلا معرِّفٍ يوهم بطباعة فاتورةٍ حُفظت.
//
// ‏٣) 🔴 **و«الفرع» يُعرَض ولا يُختار**: `createSalesInvoice` و
//    `createPurchaseInvoice` كلاهما يشتقّ `branchId` من
//    `warehouses.branch_id` حين لا يمرّره المنادي — وهذه الشاشةُ لا تمرّره.
//    فمنتقٍ كان يَعِد بما لا يقع.
//
// ‏٤) **وتاريخُ الاستحقاق مرآةٌ**: الشاشةُ تنادي عينَ الدالّة التي يناديها
//    `PartyDao.resolveInvoiceDueDate` وقتَ الحفظ — ومرآةٌ تحسب بنفسها ليست
//    مرآة.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r`.
String _code(String path) => [
      for (final line in File(path).readAsStringSync().split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

int _count(String haystack, String needle) {
  var n = 0;
  var i = haystack.indexOf(needle);
  while (i != -1) {
    n++;
    i = haystack.indexOf(needle, i + needle.length);
  }
  return n;
}

const _printing = 'lib/services/printing_service.dart';
const _form = 'lib/presentation/invoice_form_picpos/picpos_invoice_form.dart';
const _money = 'lib/presentation/invoice_form_picpos/picpos_invoice_money.dart';
const _draft = 'lib/domain/models/picpos_invoice_draft.dart';
const _salesWire =
    'lib/presentation/sales_invoices_picpos/screens/sales_invoice_dialogs.dart';
const _purchWire =
    'lib/presentation/purchases_picpos/screens/purchases_picpos_crud.dart';

/// جسمُ تنفيذِ المعاينة وحدَه — لا الواجهةُ ولا ما بعدها.
String _previewBody() {
  final code = _code(_printing);
  final start = code.indexOf('Future<bool> previewSalesInvoiceA4({',
      code.indexOf('class PrintingServiceImpl'));
  expect(start, greaterThan(0), reason: 'تنفيذُ المعاينة اختفى أو تغيّر اسمُه');
  final end = code.indexOf('Future<bool> printSalesInvoiceA4(', start);
  expect(end, greaterThan(start));
  return code.substring(start, end);
}

void main() {
  test('🔴 ورقةُ المعاينة بلا رقمِ مستند', () {
    final body = _previewBody();
    expect(body.contains("invoiceNumber: '—'"), isTrue,
        reason: '🔴 رقمٌ مخمَّنٌ على ورقةٍ تبدو مستنداً ضريبيّاً — وقد يذهب '
            'لفاتورة عميلٍ آخر');
    expect(body.contains('invoiceId'), isFalse,
        reason: 'لا مستندَ هنا، فلا معرِّفَ يُقرأ');
  });

  test('وموسومةٌ «غير محفوظة» في عنوانها', () {
    expect(_previewBody().contains('غير محفوظة'), isTrue,
        reason: 'ورقةٌ بلا وسمٍ تُقرأ فاتورةً صدرت');
  });

  test('🔴 ولا تُسجَّل في سجلّ النشاط', () {
    expect(_previewBody().contains('_logPrint('), isFalse,
        reason: '🔴 صفٌّ بلا `entityId` يوهم بطباعة فاتورةٍ حُفظت');
    // ومرساةٌ: المسارُ الحقيقيُّ **يسجّل** — فالفرقُ مقصودٌ لا نسيان.
    expect(_count(_code(_printing), '_logPrint('), greaterThan(1),
        reason: 'السجلُّ اختفى من المسار الحقيقيِّ أيضاً — فالفحصُ أعلاه '
            'صار بلا معنى');
  });

  test('🔴 و«الفرع» يُعرَض ولا يُختار', () {
    final form = _code(_form);
    final at = form.indexOf("label: 'الفرع',");
    expect(at, greaterThan(0), reason: 'حقلُ الفرع لا يُبنى أصلاً');
    // من التسمية حتى نهاية الحقل — والحقلُ التالي يبدأ بـ`label: 'المخزن'`.
    final field = form.substring(at, form.indexOf("label: 'المخزن',", at));
    expect(field.contains('onTap'), isFalse,
        reason: '🔴 منتقي فرعٍ يَعِد بما لا يقع: يختار المستخدمُ فرعاً ويُختَم '
            'المستندُ على فرع المخزن');
    expect(field.contains('lockSimple'), isTrue,
        reason: 'حقلٌ مقفولٌ بلا قفلٍ يُقرأ «معطوب»');
    expect(field.contains('branchName'), isTrue,
        reason: 'الفرعُ لا يُقرأ من المخزن — فمن أين؟');
  });

  test('والمخزنُ يحمل فرعَه في الطرفين', () {
    expect(_code(_draft).contains('class PicPosWarehouseOption'), isTrue);
    for (final f in [_salesWire, _purchWire]) {
      expect(_code(f).contains('PicPosWarehouseOption('), isTrue,
          reason: 'المنادي $f يمرّر مخزناً بلا فرع — فيبقى الحقلُ فارغاً '
              'على كلّ فاتورة');
      // 🔴 **والقيمةُ تُشتقّ من صفّ المخزن — لا وجودُ المفتاح.**
      //
      //    أوّلُ صيغةٍ لهذا الفحص اكتفت بـ`contains('branchName:')`، **ونجت
      //    منها** طفرةُ `branchName: null`: المفتاحُ باقٍ والحقلُ يقول
      //    «غير مخصّص لفرع» على كلّ فاتورة — وهو نصٌّ مشروعٌ تماماً لمخزنٍ
      //    عامّ، فلا شيءَ يبدو معطوباً.
      expect(_code(f).contains('branchNames[w.branchId]'), isTrue,
          reason: 'اسمُ الفرع لا يُقرأ من صفّ المخزن في $f — فيقول الحقلُ '
              '«غير مخصّص لفرع» على كلّ فاتورة');
    }
  });

  test('🔴 وتاريخُ الاستحقاق مرآةٌ لا حسابٌ ثانٍ', () {
    final form = _code(_form);
    expect(form.contains('resolveDueDateFromTerms('), isTrue,
        reason: 'الشاشةُ تحسب الاستحقاقَ بنفسها — ومرآةٌ تحسب بنفسها ليست '
            'مرآة: يقرأ المستخدمُ تاريخاً ويُختَم على المستند غيرُه');
    // ⚠️ **الجسمُ وحدَه لا الملفُّ كلُّه**: `Duration(days: 365)` في حدود
    //    منتقي التاريخ استعمالٌ مشروعٌ تماماً، وفحصٌ على الملفّ يسقط عليه.
    final at = form.indexOf('DateTime? get _dueDate');
    expect(at, greaterThan(0), reason: 'مرآةُ الاستحقاق اختفت');
    final body = form.substring(at, form.indexOf(';', at));
    expect(body.contains('resolveDueDateFromTerms('), isTrue);
    expect(body.contains('Duration('), isFalse,
        reason: '🔴 حسابُ مهلةٍ بيده — فما يُقرأ على الشاشة غيرُ ما يُختَم '
            'على المستند');
    expect(body.contains('paymentTermsDays'), isTrue,
        reason: 'المرآةُ لا تقرأ مهلةَ الطرف أصلاً');
  });

  test('وزرُّ المعاينة يتبع الرابطَ لا النمط', () {
    expect(_code(_money).contains('state.widget.onPreviewA4 != null'), isTrue,
        reason: 'زرٌّ يُعرَض بلا ما ينفّذه أسوأُ من غيابه');
  });

  test('🔴 و«تفاصيل إضافية» لا تُبنى', () {
    // التصميمُ يضع صفّاً مطويّاً باسمها، ومحتواه «ملاحظات ومرفقات». والملاحظاتُ
    // حقلٌ قائمٌ يُحفَظ فعلاً، والمرفقاتُ مؤجَّلةٌ بقرار مالكٍ مستقلّ — فصفٌّ
    // ثالثٌ يحمل ما هو معروضٌ سلفاً وما لا يُبنى ضجيج.
    for (final f in [_form, _money]) {
      expect(_code(f).contains('تفاصيل إضافية'), isFalse,
          reason: 'صفٌّ مطويٌّ يَعِد بمرفقاتٍ لا بنيةَ لها في $f');
    }
  });
}
