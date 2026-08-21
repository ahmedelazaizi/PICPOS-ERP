// وردياتٌ متزامنةٌ لنفس المستخدم — أيَّ حالةٍ نمنع، وأيَّها نمرّر.
//
// ── طلبُ المالك (2026-08-14) ────────────────────────────────────────────────
// «إذا فُتحت ورديةٌ من جهاز، وأردتُ فتحَ وردية من جهازٍ آخر بنفس المستخدم —
// النظامُ ينبّه ولا يقبل، إلا بعد إغلاق المفتوحة.»
//
// ── التشخيصُ المقيس (وقد صحّح مستندَ التسليم) ───────────────────────────────
// المستندُ قال «لا فحصَ لورديةٍ مفتوحةٍ للمستخدم إطلاقاً». وهذا **خطأ**:
// `getCurrentOpenShift(userId)` موجودةٌ بالمستخدم، و`_ensureShiftOpen`
// يناديها ويرجع فوراً إن وجد وردية. والسيرفرُ نفسُه يرفض الازدواج منذ
// Feature 048 v130 ويرجع `duplicate: true`.
//
// الثقبُ الحقيقيُّ أضيقُ وأدقّ: نسخةُ PicPos **لا تسحب `shifts`** قبل
// الفحص، بينما نظيرُها في `app_main_screen.dart` تسحب. فالقاعدةُ المحليّةُ
// على الجهاز الثاني جاهلةٌ بوردية الأوّل ⇒ تُفتح ثانيةٌ صامتة، ولا أحدَ
// ينبّه الكاشير.
//
// ── ولماذا «قبل السحب / بعد السحب» هو المميِّز ────────────────────────────
// لا عمودَ يقول «أيُّ جهازٍ فتحها» بثقة: `posTerminalId` يبقى `null` حين لا
// تكون الطرفيّةُ مسجَّلةً (مقيسٌ في `treasury_dao.dart:346-360`)،
// و`originClientId` لا يُكتب في مسار الفتح أصلاً. فالمميِّزُ الأمين هو
// **متى ظهر الصفّ**: موجودٌ محلياً قبل السحب ⇒ ورديتي على هذا الجهاز
// (وإعادةُ تشغيلِ التطبيق يجب أن تكمّلها، لا أن تُمنع). ظهر بعد السحب فقط
// ⇒ جاء من طرفٍ آخر.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/shift_open_gate.dart';

void main() {
  group('الجهازُ الذي فتحها يكمّلها', () {
    test('ورديةٌ محليّةٌ قبل السحب ⇒ أكمِل بلا سؤال', () {
      // إعادةُ تشغيلِ التطبيق على نفس الجهاز: الصفُّ محليٌّ سلفاً.
      expect(
        decideShiftOpenGate(
          hasLocalOpenShift: true,
          hasOpenShiftAfterPull: true,
          isClient: true,
        ),
        equals(ShiftOpenGate.alreadyOpenHere),
      );
    });

    test('ولا يغيّرها كونُ التنصيبة مستقلّة', () {
      expect(
        decideShiftOpenGate(
          hasLocalOpenShift: true,
          hasOpenShiftAfterPull: false,
          isClient: false,
        ),
        equals(ShiftOpenGate.alreadyOpenHere),
      );
    });
  });

  group('المنعُ حين تكون مفتوحةً على طرفٍ آخر', () {
    test('لا شيءَ محلياً ثم يظهر بعد السحب ⇒ امنع ونبّه', () {
      expect(
        decideShiftOpenGate(
          hasLocalOpenShift: false,
          hasOpenShiftAfterPull: true,
          isClient: true,
        ),
        equals(ShiftOpenGate.openOnAnotherTerminal),
      );
    });
  });

  group('الفتحُ يمضي حين لا مانع', () {
    test('لا وردية قبل السحب ولا بعده', () {
      expect(
        decideShiftOpenGate(
          hasLocalOpenShift: false,
          hasOpenShiftAfterPull: false,
          isClient: true,
        ),
        equals(ShiftOpenGate.mayOpen),
      );
    });

    test('والتنصيبةُ المستقلّةُ لا تُمنع أبداً بحجّة السحب', () {
      // لا سيرفرَ ⇒ لا سحبَ ⇒ `hasOpenShiftAfterPull` بلا معنى. ولو مُرّرت
      // `true` سهواً وجب ألّا تمنع، وإلا لتعطّل تِلٌّ مستقلٌّ بلا سببٍ يفهمه
      // أحد.
      expect(
        decideShiftOpenGate(
          hasLocalOpenShift: false,
          hasOpenShiftAfterPull: true,
          isClient: false,
        ),
        equals(ShiftOpenGate.mayOpen),
      );
    });
  });
}
