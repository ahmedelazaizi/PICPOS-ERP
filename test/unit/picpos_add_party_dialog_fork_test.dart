// فوركُ حوار «إضافة طرف» — حارسُ ما لا يُرى سقوطُه.
//
// ═══ لماذا حارسٌ على نسخةٍ ═══
//
// مقيسٌ في هذا المستودع: أُزيل حارسٌ من فورك الأصناف فسقط اختبارُ الفورك
// **وبقي اختبارُ الأصل أخضر**. والحوارُ هنا نُسخ من
// `screens/parties/party_dialogs.dart` وفيه قراراتُ **مسارِ بيانات** لا
// تجميل — فانحرافُ النسخة عطبٌ صامتٌ في بيانات عملاءَ وموردين.
//
// والقياسُ نصّيٌّ بالضرورة: فتحُ الحوار يحتاج قاعدةً حيّةً وشجرةً كاملة،
// وتعليقُ اختبارات الودجت عند فتح الشاشات مسألةٌ معروفةٌ هنا. والمقيسُ
// سؤالٌ بنيويّ: **هل القرارُ المكتوبُ ما زال مكتوباً؟**
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نزعُ التعليقات وحدَها — التعليقُ ليس كوداً.
///
/// ⚠️ ولولاه لمرَّ هذا الحارسُ على **شرحٍ** يذكر `isClientMode` بينما الكودُ
/// ينادي غيرَه. وهو عطبٌ وقع فعلاً في حارسٍ آخرَ بهذا المستودع.
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

void main() {
  const forkPath =
      'lib/presentation/parties_picpos/dialogs/add_party_dialog_picpos.dart';
  const screenPath =
      'lib/presentation/parties_picpos/screens/parties_picpos_screen.dart';

  String code(String path) {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: 'الملفُّ «$path» اختفى');
    return stripComments(f.readAsStringSync());
  }

  group('فوركُ حوار إضافة طرف', () {
    // 🔴 **القرارُ الذي يسقط بلا صوت.**
    //
    // `NetworkService.instance.isClient` **كاذبةٌ في وضع المرآة**، فأطرافُ
    // مديرِ المرآة لا تصل المركزَ أبداً (‏R9 / Feature 010 issue 6).
    // و`SyncInterceptor.isClientMode` صادقةٌ للعميل **والمرآة** معاً.
    //
    // فنسخةٌ تستعمل الأولى تعمل على المستقلّ والخادم وتفقد بياناتِ المرآة
    // صامتةً — ولا اختبارَ سلوكٍ محلّيٍّ يراها.
    test('يستعمل `SyncInterceptor.isClientMode` لا `NetworkService.isClient`',
        () {
      final src = code(forkPath);
      expect(src, contains('SyncInterceptor.isClientMode'),
          reason: 'بوّابةُ المزامنة يجب أن تشمل وضعَ المرآة');
      expect(src, isNot(contains('NetworkService.instance.isClient')),
          reason: 'هذه البوّابةُ تُسقط أطرافَ المرآة صامتةً');
    });

    // الأرقامُ العربيّةُ والفاصلةُ تُقبَل — BUG-U10/U14.
    test('يحلّل الأرقامَ بـ`NumberUtils.tryParseLocale`', () {
      final src = code(forkPath);
      expect(src, contains('NumberUtils.tryParseLocale'));
      expect(src, isNot(contains('double.parse(')),
          reason: 'التحليلُ الخامُّ يرفض «١٢٣٫٤٥» ويرمي');
    });

    // الكودُ الفارغُ يُمرَّر `null` ليولّده الـDAO — لا يُخترَع في الواجهة.
    test('الكودُ الفارغُ يصير `null` لا نصّاً فارغاً', () {
      final src = code(forkPath);
      expect(src, contains('enteredCode.isEmpty ? null : enteredCode'));
    });

    // فشلُ الحفظ **لا يغلق الحوار** — سببُه الشائع كودٌ مكرَّر، فإغلاقُه
    // يُضيّع ما كتبه المستخدمُ كلَّه.
    test('فشلُ الحفظ يُبقي الحوارَ مفتوحاً', () {
      final src = code(forkPath);
      final catchAt = src.indexOf('catch (e)');
      expect(catchAt, greaterThan(-1));
      final window = src.substring(
          catchAt, (catchAt + 400).clamp(0, src.length));
      expect(window, contains('saving = false'));
      expect(window, isNot(contains('Navigator.pop')),
          reason: 'إغلاقُ الحوار عند الفشل يُضيّع إدخالَ المستخدم');
    });

    // العملُ يُسجَّل في سجلّ النشاط بنوعِ كيانٍ تُرشِّح عليه شاشةُ العرض.
    test('يسجّل الإضافةَ بـ`entityType: party`', () {
      final src = code(forkPath);
      expect(src, contains("entityType: 'party'"));
      expect(src, contains('add_customer'));
      expect(src, contains('add_supplier'));
    });

    // والشاشةُ تنادي الفوركَ لا الأصل — وإلّا فالفوركُ ملفٌّ ميّت.
    test('شاشةُ PicPos تنادي الفوركَ لا الأصل', () {
      final src = code(screenPath);
      expect(src, contains('showAddPartyDialogPicpos('));
      expect(src, isNot(contains('showAddPartyDialog(context, ref)')),
          reason: 'نداءُ الأصل يُعيد الحوارَ القديمَ فوق شاشةٍ منسَّقة');
    });

    // والغلافُ هو ما تبدّل — فإن غاب فالفوركُ بلا سبب.
    test('يستعمل غلافَ PicPos لا `AlertDialog`', () {
      final src = code(forkPath);
      expect(src, contains('PicPosDialog('));
      expect(src, isNot(contains('AlertDialog(')));
    });
  });
}
