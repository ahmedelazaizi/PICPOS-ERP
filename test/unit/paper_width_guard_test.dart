// رفضُ ربطِ قالبٍ أعرضَ من طابعته.
//
// ── العطبُ الذي يمنعه ─────────────────────────────────────────────────────
// قالبُ A4 على طابعةٍ ٨٠مم **يُقصّ صامتاً اليوم**: لا رسالةَ ولا سجلّ، فقط
// نصفُ فاتورةٍ يخرج من الطابعة. والمستخدمُ لا يربط القالبَ الخطأ عمداً — بل
// يختار من قائمةٍ لا تقول له إنّ العرضين لا يلتقيان.
//
// ── ولماذا اتّجاهٌ واحدٌ يُرفض والآخرُ يُحذَّر ────────────────────────────
// الأعرضُ من الطابعة **يفقد بياناً** — عمودُ الإجمالي هو آخرُ ما يُقصّ، فيخرج
// المطبوعُ صحيحَ الشكل ناقصَ الرقم. وهذا يُرفض.
// والأضيقُ يطبع كاملاً ويترك هامشاً أبيضَ — قبحٌ لا فقدُ بيان. فيُحذَّر منه
// ولا يُمنع، وإلا مُنع مستخدمٌ يطبع إيصالَ ٥٨مم على طابعةِ ٨٠ عن قصد.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/printing/paper_compatibility.dart';

void main() {
  group('الأعرضُ من الطابعة يُرفض', () {
    test('A4 على طابعةٍ ٨٠مم', () {
      final v = checkPaperFit(templateWidthMm: 210, printerWidthMm: 80);
      expect(v.isRejected, isTrue);
      expect(v.reason, isNotEmpty, reason: 'الرفضُ الصامتُ عطبٌ ثانٍ لا علاج');
    });

    test('٨٠مم على طابعةِ ٥٨مم', () {
      expect(
        checkPaperFit(templateWidthMm: 80, printerWidthMm: 58).isRejected,
        isTrue,
      );
    });
  });

  group('المطابقُ يمرّ', () {
    test('٨٠ على ٨٠', () {
      final v = checkPaperFit(templateWidthMm: 80, printerWidthMm: 80);
      expect(v.isOk, isTrue);
      expect(v.isRejected, isFalse);
      expect(v.isWarning, isFalse);
    });

    test('وفرقٌ تحت التسامح يمرّ — المساحةُ المطبوعةُ ليست عرضَ الورق', () {
      // طابعةُ ٨٠مم مساحتُها المطبوعةُ ٧٢مم شائعاً؛ فرقُ مليمترين لا يعني
      // عدمَ توافق.
      expect(
        checkPaperFit(templateWidthMm: 80, printerWidthMm: 78.5).isOk,
        isTrue,
      );
    });
  });

  group('الأضيقُ يُحذَّر ولا يُمنع', () {
    test('٥٨ على طابعةِ ٨٠', () {
      final v = checkPaperFit(templateWidthMm: 58, printerWidthMm: 80);
      expect(v.isWarning, isTrue);
      expect(v.isRejected, isFalse,
          reason: 'الطباعةُ صحيحةٌ بهامشٍ أبيض — المنعُ هنا يعطّل استعمالاً مشروعاً');
      expect(v.reason, isNotEmpty);
    });
  });

  group('عرضُ طابعةٍ مجهولٌ لا يمنع', () {
    test('null يمرّ', () {
      // طابعةٌ لم يُسجَّل عرضُها ليست طابعةً غيرَ متوافقة. المنعُ على
      // المجهول يقفل الربطَ على كلِّ طابعةٍ لم تُعرَّف بعد.
      expect(checkPaperFit(templateWidthMm: 210, printerWidthMm: null).isOk,
          isTrue);
    });

    test('وصفرٌ يمرّ كذلك', () {
      expect(
        checkPaperFit(templateWidthMm: 210, printerWidthMm: 0).isOk,
        isTrue,
      );
    });
  });

  test('الرسالةُ تذكر الرقمين — «غيرُ متوافق» وحدَها لا تُصلِح شيئاً', () {
    final v = checkPaperFit(templateWidthMm: 210, printerWidthMm: 80);
    expect(v.reason, contains('210'));
    expect(v.reason, contains('80'));
  });
}
