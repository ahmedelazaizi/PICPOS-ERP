// توصيلُ شاشة الحجوزات — **خمسةُ مواضعَ يجب أن تتّفق**.
//
// ═══ العطبُ الذي يحرسه هذا الملفّ (وقع فعلاً) ═══
//
// «شاشةُ إغلاق الوردية لا تظهر في القائمة الجانبية» — بلاغُ المالك
// 2026-08-22. والشاشةُ كانت مبنيّةً ومُسجَّلةً في `screenPermissionMap`،
// لكنها **ساقطةٌ من نطاق ملفٍّ واحد** (`unified`). والحلقةُ في
// `userAllowedScreensProvider` تُرشِّح بنطاق الملفّ **قبل** فحص الصلاحية،
// فما ليس في النطاق يسقط حتى مع تجاوزِ مدير النظام.
//
// أي أنّ أربعةً من خمسةِ مواضعَ كانت صحيحةً والشاشةُ غيرُ موجودةٍ للمستخدم.
// فالحارسُ يقيس **الخمسةَ معاً** لا واحداً منها.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/enums/app_screen.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/navigation/screen_registry.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';

void main() {
  group('الحجوزاتُ موصولةٌ في كلّ موضع', () {
    test('١) لها معرِّفُ شاشة', () {
      expect(ScreenId.bookings.navigationIndex, 61);
    });

    test('٢) و`AppScreen` يحمل نفسَ الرقم', () {
      expect(AppScreen.bookings.value, ScreenId.bookings.navigationIndex,
          reason: 'الرقمان مصدرُ الحقيقة في نظامَين — وانحرافُهما يجعل '
              'التوجيهَ يفتح شاشةً غيرَ التي أذنت بها الصلاحية');
    });

    test('٣) ولها صلاحيةٌ في `screenPermissionMap`', () {
      expect(screenPermissionMap[ScreenId.bookings], isNotNull,
          reason: 'شاشةٌ بلا مدخلٍ هنا لا تُعرَض لأحد');
      expect(screenPermissionMap[ScreenId.bookings], isNotEmpty);
    });

    test('٤) وهي في نطاق المطعم والمقهى — من يحجز مواعيد', () {
      expect(ScreenRegistry.restaurant, contains(ScreenId.bookings));
      expect(ScreenRegistry.cafe, contains(ScreenId.bookings));
    });

    test('٥) وفي `unified` — أوسعُ النطاقات', () {
      expect(ScreenRegistry.unified, contains(ScreenId.bookings),
          reason: 'هذا بالضبط الموضعُ الذي سقطت منه شاشةُ إغلاق الوردية: '
              'أوسعُ نطاقٍ لا يُعقل أن ينقصه ما يحمله أضيقُ منه');
    });
  });

  group('ولا تكسر ما كان', () {
    test('إغلاقُ الورديّة ما زال في كلّ نطاقٍ يحمله', () {
      // ⚠️ حارسُ ارتداد: إضافةُ عنصرٍ إلى هذه القوائم تُحرَّر يدويّاً،
      // وحذفُ سطرٍ مجاورٍ سهوٌ وارد.
      for (final scope in [
        ScreenRegistry.restaurant,
        ScreenRegistry.unified,
        ScreenRegistry.lite,
      ]) {
        expect(scope, contains(ScreenId.shiftClose));
      }
    });

    // ⚠️ **قِيس قبل أن يُكتب**: أوّلُ صياغةٍ لهذا الحارس منعت أيَّ تكرارٍ
    // في `ScreenId` — وسقط فوراً على ٦٣ قيمةً بـ٦١ رقماً. والتكرارُ
    // **مقصودٌ وموثَّق**: `scalePlu` مرادفُ `pluManager` و`cycleCounting`
    // مرادفُ `fieldAudit` (‏«Alias for …» في المصدر). فمنعُ التكرار مطلقاً
    // كان سيُحمِّر على قرارَين صحيحَين — نفسُ فخّ الحارسِ المبنيِّ على
    // فرضيّةٍ لم تُقَس.
    //
    // فالحارسُ يثبّت **المرادفاتِ المعروفة** بأسمائها: تكرارٌ جديدٌ خارجَها
    // يُسقطه، وهو المقصود — رقمان متطابقان بلا قصدٍ يجعلان شاشةً تفتح مكانَ
    // أخرى.
    test('تكرارُ الأرقام محصورٌ في المرادفات الموثَّقة', () {
      final byIndex = <int, List<String>>{};
      for (final s in ScreenId.values) {
        byIndex.putIfAbsent(s.navigationIndex, () => []).add(s.name);
      }
      // ‏قوائمُ مرتّبةٌ لا مجموعات: مساواةُ `Set` في دارت بالهويّة لا
      // بالمحتوى، فـ`contains` تفشل على مجموعةٍ مطابقةٍ نصّاً.
      final duplicated = byIndex.entries
          .where((e) => e.value.length > 1)
          .map((e) => (e.value..sort()).join(','))
          .toList()
        ..sort();

      expect(duplicated, ['cycleCounting,fieldAudit', 'pluManager,scalePlu']);
    });

    test('لا رقمَ مكرّرٌ في `AppScreen`', () {
      final values = AppScreen.values.map((s) => s.value).toList();
      expect(values.toSet().length, values.length);
    });
  });
}
