// test/unit/screen_permission_map_test.dart
//
// كل شاشة لازم تتربط بكود صلاحيتها هي.
//
// الخريطة كانت بتربط شاشات بأكواد عامة: العروض والطاولات والمطبخ ولوحة
// التحكم كلهم على `pos_access`، ومردودات البيع على `sales_view`. فالمدير
// يسحب `offers_view` وشاشة العروض تفضل ظاهرة لأنها مش مربوطة بيه أصلاً.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';

void main() {
  test('كل كود في الخريطة مسجّل في masterList', () {
    final master = PermissionCodes.masterList.map((m) => m['code']!).toSet();
    for (final entry in screenPermissionMap.entries) {
      expect(master.contains(entry.value), isTrue,
          reason: '${entry.key} مربوطة بكود غير مسجّل: ${entry.value}');
    }
  });

  test('الشاشات اللي ليها كود خاص متربطة بيه مش بكود عام', () {
    const expected = <ScreenId, String>{
      ScreenId.dashboard: 'dashboard_access',
      ScreenId.offers: 'offers_view',
      ScreenId.tables: 'tables_view',
      ScreenId.kitchen: 'kitchen_view',
      ScreenId.salesReturns: 'sales_return_view',
      ScreenId.purchaseReturns: 'purchases_return_view',
      ScreenId.manufacturing: 'manufacturing_view',
      ScreenId.fixedAssets: 'assets_view',
      ScreenId.loyalty: 'loyalty_view',
      ScreenId.distribution: 'distribution_view',
    };
    expected.forEach((screen, code) {
      expect(screenPermissionMap[screen], code,
          reason: '$screen لازم تتحكم بـ $code');
    });
  });

  test('كل مدخل قائمة متفق مع خريطة الشاشات', () {
    // ── ليه التعميم ──────────────────────────────────────────────────────
    // النسخة الأولى غطّت الشاشات اللي اتصلّحت بس (التمانية اللي كانت على
    // كود عام زي pos_access أو sales_view)، فسابت اختلاف «التحليلات»
    // يعدّي — ودي نفس العائلة بالظبط. الاختبار اللي بيغطي عيّنة بيثبّت
    // العيّنة، مش القاعدة. التعميم ده كشف اختلاف تاني من نفس العائلة على
    // شاشة «الفروع» (راجع تعليق Task 3d فوق عنصرها في auth_providers.dart).
    //
    // أي مدخل مالوش `ScreenId` مقابل بيتستثنى صراحة بسببه تحت — الاستثناء
    // المكتوب أحسن من اختبار بيعدّي على الفاضي.
    final mismatches = <String>[];
    for (final item in kAllNavItemDefs) {
      final screen = _screenForNavItem(item);
      if (screen == null) continue; // مستثنى بسبب مكتوب في _screenForNavItem
      final mapped = screenPermissionMap[screen];
      if (mapped == null) continue;
      if (item.permission != mapped) {
        mismatches.add('${item.label}: القائمة=${item.permission} '
            'الخريطة=$mapped');
      }
    }
    expect(mismatches, isEmpty,
        reason: 'مدخل بيظهر لناس ما يقدروش يفتحوا شاشته (أو العكس):\n'
            '${mismatches.join('\n')}');
  });
}

/// بيربط عنصر قائمة بالـ `ScreenId` المقابل له.
///
/// بيستخدم `ScreenId.fromIndex(item.index)` — بالظبط نفس المنطق اللي
/// `userNavItemsProvider` الحقيقي بيستخدمه فوق في auth_providers.dart —
/// مش مطابقة على `label` لأنه نص عرض عرضة يتغيّر من غير ما يبقى ده
/// المقصود.
///
/// بيرجّع `null` للمداخل اللي مالهاش شاشة مقابلة فعلاً (تفتح ديالوج أو
/// حوار مش route كامل مثلاً). دلوقتي الـ 47 مدخل كلهم في kAllNavItemDefs
/// بيرجّعوا شاشة موجودة في screenPermissionMap — يعني صفر استثناءات حالياً
/// — لكن السطر ده فاضل كحارس صريح لأي مدخل مستقبلي من النوع ده، عشان لو
/// حد ضاف مدخل بدون شاشة، الاختبار يفضل شغّال بدل ما يتقفل بلا داعي.
ScreenId? _screenForNavItem(NavItemDef item) => ScreenId.fromIndex(item.index);
