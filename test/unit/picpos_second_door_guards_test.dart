// أبوابٌ ثانيةٌ لأفعالٍ محروسة — وصلُ الحراسة مقيسٌ لا مفترَض.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// النمطُ الذي تكرّر في هذا المستودع أربعَ مرّاتٍ في يومٍ واحد: فعلٌ له مدخلان،
// يُحرَس أحدُهما ويُنسى الآخر. والحارسُ البنيويُّ لا يراه لأن الكودَ **مذكورٌ**
// في المجلد — فيمرّ أخضر.
//
//   · «سند قبض» في ترويسة الخزينة بلا حراسة، وجارُه «سند صرف» محروس، ونفسُ
//     الحوار محروسٌ في لوحةٍ مرسومةٍ على **نفس الشاشة**.
//   · زرُّ «إضافة صنف» محروسٌ و**F5** يستدعي نفسَ الدالّة بلا مرورٍ بالحارس.
//   · «فاتورة جديدة» في المشتريات والمبيعات: الزرُّ والاختصارُ كلاهما بلا فحص.
//   · `onReprint` في حوار الفواتير السابقة يطبع بلا `pos_print`.
//
// ── لماذا تُقاس المصادرُ نصّاً ────────────────────────────────────────────
// اختبارُ ودجتٍ لهذه الشاشات يحتاج قاعدةَ بياناتٍ حيّةً وشجرةً كاملة، وتعليقُ
// الفتح في اختبارات الودجت مسألةٌ معروفةٌ في هذا المستودع. والمقيسُ هنا سؤالٌ
// بنيويٌّ لا سلوكيّ: **هل الفحصُ موصولٌ وقبل الفعل؟** والنصُّ يجيبه بدقّة.
//
// ⚠️ ويُقاس على الكود **بلا تعليقات**: أوّلُ صياغةٍ لاختبارٍ مشابهٍ سقطت
// حمراءَ لأن المرساةَ طوبقت في تعليقٍ قبل الفحص. التعليقُ ليس كوداً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نزعُ التعليقات وحدَها. السلاسلُ تُترك — ماسحٌ يدويٌّ لها قد يفقد التزامنَ
/// فيبتلع بقيةَ الملفّ، أي يُخفي حراسةً قائمة.
String stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '*') {
      i += 2;
      while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }
    out.write(src[i]);
    i++;
  }
  return out.toString();
}

String _code(String path) {
  final f = File(path);
  expect(f.existsSync(), isTrue, reason: 'الملفُّ «$path» اختفى');
  return stripComments(f.readAsStringSync());
}

/// موضعُ [needle]، ويفشل صراحةً إن غاب.
///
/// ⚠️ `indexOf` يرجع `-1` وهو «أصغرُ من» كلِّ شيء — فكان غيابُ المرساة يمرّ
/// أخضرَ في قياس الترتيب. وحارسٌ يمرّ لأن ما يقيسه غيرُ موجودٍ أخطرُ من غيابه.
int at(String haystack, String needle, {String? label}) {
  final i = haystack.indexOf(needle);
  expect(i, greaterThan(-1), reason: '${label ?? ''} «$needle» غير موجود');
  return i;
}

/// نافذةٌ تبدأ من توقيع الدالّة.
///
/// ⚠️ نافذةٌ ثابتةٌ لا فاصلٌ نصّيّ: التعليقاتُ مجرَّدةٌ سلفاً فلا تصلح فواصل،
/// وتوقيعُ الدالّة التالية يختلف شكلاً (`void` مقابل `Future<void>`). و٢٥٠٠
/// حرفاً تغطي مطلعَ أيّ دالّةٍ هنا بفارقٍ واسع — والفحصُ المطلوبُ يقع في
/// أوّل سطورها بحكم كونه فحصاً **قبل** الفعل.
String windowFrom(String src, String signature, [int chars = 2500]) {
  final start = at(src, signature);
  final end = start + chars;
  return src.substring(start, end > src.length ? src.length : end);
}

/// Extract one complete Future method so a growing method cannot hide its
/// dialog behind an arbitrary character window.
String functionBodyFrom(String src, String signature) {
  final start = at(src, signature);
  final next = src.indexOf('\n  Future<void>', start + signature.length);
  return src.substring(start, next < 0 ? src.length : next);
}

void main() {
  // ⚠️ **الحارسُ انتقل ولم يسقط — والمرساةُ تتبعه.**
  //
  // كان الزرّان في `headerActions` بملفّ الشاشة، فكان يكفي قياسُ «الحارسُ قبل
  // الزرّ» في ملفٍّ واحد. وقد نزلا إلى شبكةِ ٢×٢
  // (`treasury_actions_grid_picpos.dart`) كما يرسم التصميم، فصارت الخاصّيّةُ
  // موزّعةً على ملفَّين: الشاشةُ تمرّر الفعلَ، والشبكةُ تحرسه.
  //
  // ونُقلت المرساةُ **ولم تُخفَّف**: القياسُ الآن أقوى لأنه يضيف ما لم يكن
  // مقيساً — أن الحوارَ **لا يُفتح من بابٍ ثانٍ** خارج الفعل المحروس.
  group('سندُ القبض في شاشة الخزينة', () {
    const screenPath =
        'lib/presentation/treasury_picpos/screens/treasury_picpos_screen.dart';
    const gridPath =
        'lib/presentation/treasury_picpos/widgets/treasury_actions_grid_picpos.dart';

    test('لا بابَ ثانياً — الحوارُ يُفتح من الفعل المُمرَّر للشبكة وحدَه', () {
      // 🔴 **ومرساةٌ كسرها فوركٌ**: الصنفُ صار `ReceiptVoucherDialogPicpos`
      //    في `b71e7f2e`، والمرساةُ بقيت `ReceiptVoucherDialog(` — وهي ليست
      //    مقطعاً من الجديد (‏`Picpos` بين `Dialog` و`(`). وفحصُ **العدد**
      //    هو ما أسقطها صريحةً (‏٠ ≠ ١) بدل أن تمرّ خضراءَ بلا مقيس.
      final src = _code(screenPath);
      expect(
        'ReceiptVoucherDialogPicpos('.allMatches(src).length,
        1,
        reason: 'موضعٌ ثانٍ يفتح الحوارَ يتجاوز حارسَ الشبكة — وهي بالضبط '
            'فئةُ «البابِ الثاني» التي وُجد هذا الملفُّ لأجلها',
      );
      expect(
        at(src, 'TreasuryActionsGridPicpos('),
        lessThan(at(src, 'ReceiptVoucherDialogPicpos(')),
        reason: 'الفعلُ يُبنى داخلَ استدعاء الشبكة لا خارجَه',
      );
    });

    test('محروسٌ كجاره «سند صرف» — والفعلُ موصولٌ بـ`onGranted`', () {
      final src = _code(gridPath);
      final guard = at(src, 'PermissionCodes.treasuryReceiptsCreate');
      final action = at(src, 'onGranted: onReceipt');
      expect(guard, lessThan(action),
          reason: 'الحارسُ يجب أن يلفّ الزرَّ لا أن يأتي بعده. وكان الزرُّ '
              'مفتوحاً بينما جارُه «سند صرف» محروس.');

      // الجارُ الذي أثبت أن النيّةَ كانت الحراسة — يبقى محروساً هو الآخر.
      expect(at(src, 'PermissionCodes.treasuryPaymentsCreate'),
          lessThan(at(src, 'onGranted: onPayment')));
    });
  });

  group('«جديد» — الزرُّ والاختصارُ يمرّان بنفس الفحص', () {
    // القِمعُ واحدٌ في الثلاثة، فحراسةُ الدالّة تغطّي المدخلَين معاً.
    final cases = <String, List<String>>{
      'lib/presentation/products_picpos/screens/products_picpos_screen.dart': [
        'Future<void> _addProduct() async {',
        'PermissionCodes.productsAdd',
        'AddProductDialog.show',
      ],
      // 🔴 **ومرساةٌ ثانيةٌ كسرها تحويلُ التعديل** (‏`546e7d87`): كانت
      //    `createNewInvoice` فصارت `openPicPosInvoiceForm` تخدم الإنشاءَ
      //    والتعديلَ معاً. والخاصّيّةُ المحروسةُ قائمة، والمرساةُ تتبعها.
      'lib/presentation/purchases_picpos/screens/purchases_picpos_crud.dart': [
        'Future<void> openPicPosInvoiceForm({',
        'PermissionCodes.purchasesCreate',
        'showGeneralDialog(',
        // ⚠️ نافذةٌ أوسعُ لهذه وحدَها: الدالّةُ كبرت بتحميل أوامر الشراء
        //    والملءِ الأوّليّ، فصار الحوارُ عند ٢٨٠٤. والدالّةُ التاليةُ عند
        //    ٧٧٩٢ — فالنافذةُ تبقى **داخلَ** هذه الدالّة بفارقٍ واسع، ولا
        //    تلتقط `showGeneralDialog` من جارةٍ لها.
        '3200',
      ],
      'lib/presentation/sales_invoices_picpos/screens/sales_invoice_dialogs.dart':
          [
        'void _createNewInvoice({',
        'PermissionCodes.salesCreate',
        'salesInvoicesControllerProvider',
      ],
    };

    cases.forEach((path, spec) {
      final signature = spec[0], code = spec[1], action = spec[2];
      final window = spec.length > 3 ? int.parse(spec[3]) : 2500;
      test('${path.split('/').last} — الفحصُ قبل فتح الحوار', () {
        final source = _code(path);
        final body = path.endsWith('purchases_picpos_crud.dart')
            ? functionBodyFrom(source, signature)
            : windowFrom(source, signature, window);
        expect(at(body, code), lessThan(at(body, action)),
            reason: 'الفحصُ يجب أن يسبق فتحَ حوار الإنشاء. وبلا فحصٍ في '
                'الدالّة يتخطّى **F5** لفّةَ الزرّ كلياً.');
      });
    });

    test('وفاتورةُ المشتريات — الصلاحيةُ تتبع الفعلَ لا مدخلَه', () {
      // 🔴 بابٌ واحدٌ يخدم فعلَين: التحريرُ يعكس قيداً ويعيد ترحيلَه، فلا
      //    يحكمه إذنُ **الإنشاء**. وفحصُ `purchasesCreate` وحدَه كان سيفتح
      //    التحريرَ لمن لا يملكه — ثمّ يرفض المحرّكُ الحفظَ بعد ملءِ شاشة.
      final body = functionBodyFrom(
         _code(
             'lib/presentation/purchases_picpos/screens/purchases_picpos_crud.dart'),
         'Future<void> openPicPosInvoiceForm({',
       );
      expect(body.contains('PermissionCodes.purchasesEdit'), isTrue,
          reason: 'إذنُ التحرير لا يُفحَص — والبابُ واحدٌ للفعلَين');
      expect(at(body, 'PermissionCodes.purchasesEdit'),
          lessThan(at(body, 'showGeneralDialog(')),
          reason: 'الفحصُ بعد فتح الحوار — فلا يمنع شيئاً');
    });
  });

  group('إعادةُ طباعة فاتورةٍ سابقة', () {
    test('`onReprint` يفحص `pos_print` قبل الطباعة', () {
      final src = _code(
          'lib/presentation/pos_picpos/screens/picpos_pos_invoice_actions.dart');
      final body =
          windowFrom(src, 'Future<void> _showPreviousInvoices() async {');
      expect(at(body, 'PermissionCodes.posPrint'),
          lessThan(at(body, 'printInvoice(')),
          reason: 'الطباعةُ من حوار الفواتير السابقة كانت بلا فحص، بينما '
              'إعادةُ الطباعة في حوار «آخر فاتورة» محروسة.');
    });
  });
}
