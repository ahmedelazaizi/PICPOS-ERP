// حارسُ العقد: إعدادُ عتادٍ لكلِّ جهازٍ لا تدهسه مزامنةُ الإعدادات.
//
// ═══ فئةُ العطب ═══
//
// `SettingSyncStrategy` تعمل بقائمةِ **منعٍ** لا قائمةِ سماح: كلُّ مفتاحٍ
// يصل من الخادم يُكتب في قاعدة الجهاز إلّا ما ورد في `devSpecificKeys`.
// فالإعدادُ الجديدُ عامٌّ بحكم الصمت — لا بقرار.
//
// وهذا صحيحٌ لأغلب سياسة البيع السريع (‏سقفُ الخصم وسياسةُ الإغلاق قراراتٌ
// مركزيّة)، وخطأٌ لاثنين:
//
//   • `pos_open_drawer_on_print` — خاصّيّةُ عتاد. نقطةُ بيعٍ **بلا درجٍ**
//     ترث «افتح الدرج» من فرعٍ عنده درج، فتنتظر عتاداً غيرَ موجود.
//   • `pos_receipt_template` — القالبُ يُحسَم بالفرع والطابعة واللغة،
//     وتثبيتُه مركزيّاً يتجاوز تلك السلسلة كلَّها.
//
// وسابقتُهما في نفس القائمة: `pos_receipt_printer` و`pos_cash_safe_id` —
// مفاتيحُ عتادٍ لكلِّ طرفيّة.
//
// ⚠️ **والتوقيتُ جزءٌ من العقد**: أُضيفا قبل أن يُوصَّلا في المحرّك عمداً.
// تغييرُ نطاقِ مفتاحٍ بعد انتشاره على أجهزةٍ حقيقيّةٍ يعني أنّ كلَّ جهازٍ
// يحمل سلفاً قيمةَ الخادم، فالإصلاحُ اللاحقُ لا يستعيد ما دُهس.
//
// ═══ ما يفعله هذا الملفّ ═══
//
// يقرأ مصدرَ الاستراتيجيّة ويثبّت أنّ المفتاحين مذكوران داخلَ
// `devSpecificKeys` نفسِها — لا في تعليقٍ ولا في موضعٍ آخرَ من الملفّ.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// قرارُ المالك 2026-08-29 — هذان لكلِّ جهاز.
const _perDeviceQuickSaleKeys = <String>{
  'pos_open_drawer_on_print',
  'pos_receipt_template',
};

/// مفاتيحُ نعلم يقيناً أنّها في القائمة سلفاً — **مرساةُ الحارس**.
///
/// ⚠️ بلا هذه المرساةِ يمرُّ الحارسُ أخضرَ لو فشل الاستخراجُ وأعاد نصّاً
/// فارغاً أو الملفَّ كلَّه: فحصُ «يحتوي» على نصٍّ خاطئٍ لا يُنبِّه بذاته.
const _knownPerDeviceKeys = <String>{
  'network_mode',
  'deployment_mode',
  'pos_cash_safe_id',
  'pos_receipt_printer',
};

void main() {
  group('مفاتيحُ العتاد لكلِّ جهازٍ في مزامنة الإعدادات', () {
    late String devKeysBlock;

    setUpAll(() {
      final source =
          File('lib/services/sync/strategies/setting_sync_strategy.dart')
              .readAsStringSync();

      // نقتطع كتلةَ القائمة وحدَها: مفتاحٌ مذكورٌ في تعليقٍ خارجَها لا يمنع
      // شيئاً، وفحصُ الملفِّ كلِّه كان سيقبله.
      final start = source.indexOf('kDeviceLocalSettingKeys = <String>[');
      expect(start, isNot(-1),
          reason: 'لم تُعثَر على `kDeviceLocalSettingKeys` — تغيّر شكلُ الملفّ');
      final end = source.indexOf('];', start);
      expect(end, isNot(-1), reason: 'كتلةُ المفاتيح غيرُ مغلقة');

      devKeysBlock = source.substring(start, end);
    });

    test('المرساةُ قائمة — الاستخراجُ يمسك القائمةَ فعلاً', () {
      for (final key in _knownPerDeviceKeys) {
        expect(devKeysBlock, contains("'$key'"),
            reason: 'المرساةُ `$key` غائبةٌ — الاستخراجُ لا يقرأ القائمة');
      }
    });

    test('والدرجُ والقالبُ لكلِّ جهازٍ لا عامّان', () {
      for (final key in _perDeviceQuickSaleKeys) {
        expect(
          devKeysBlock,
          contains("'$key'"),
          reason: 'المفتاحُ `$key` ليس في `devSpecificKeys` — سينتشر من '
              'الخادم إلى كلِّ نقاط البيع ويدهس إعدادَ الطرفيّة',
        );
      }
    });
  });
}
