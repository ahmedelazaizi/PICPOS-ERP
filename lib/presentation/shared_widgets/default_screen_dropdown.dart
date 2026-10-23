// lib/presentation/shared_widgets/default_screen_dropdown.dart
//
// قائمةُ «الشاشة الافتراضية» المشتركة (حوارُ «الدور والإعدادات» في PicPos،
// وشاشةُ المستخدمين القديمة، وودجتُ المستخدمين في الإعدادات).
//
// كانت ثلاثَ نسخٍ يدويّةٍ غيرِ متطابقة بأربعة خياراتٍ؛ هذه تشتقّ العناصرَ من
// سجلّ الشاشات الفعليّ (‏`kAllNavItemDefs` — نفسُ ما يرسم الشريطَ الجانبيَّ)
// وتقطعه مع:
//   • نطاق المنتج/العلامة (‏`AppConfig.allowedScreenIds` ·
//     `navItemVisibleForBrand`)؛
//   • ما **يفتحه الدورُ المختار** فعلاً (‏`canOpenScreen` — القاعدةُ نفسُها
//     التي يطبّقها الشريطُ ومزوِّدُ الشاشات المسموحة)؛
// فلا تظهر شاشةٌ يفشل فتحُها عند الدخول. والقيمةُ المخزَّنة `ScreenId.name`.
//
// ملاحظة: ‏`buildAllScreens()` خاصٌّ بحالة الشاشة الرئيسية (امتدادٌ على
// `_MainScreenState`) فلا يُستدعى من خارجها؛ والتسمياتُ والأيقوناتُ نفسُها
// في `kAllNavItemDefs`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ural_erp/core/config/app_config.dart';
import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/navigation/default_screen_resolver.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/permissions/screen_visibility.dart';
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/e_invoicing_providers.dart';
import 'package:ural_erp/data/providers/repository_providers.dart';

/// شاشاتُ أدواتٍ لا يُعقل الهبوطُ عليها عند الدخول.
const _kNotLandingScreens = <ScreenId>{
  ScreenId.floorPlanDesigner,
  ScreenId.helpCenter,
  ScreenId.syncConflicts,
};

/// خيارٌ واحدٌ في القائمة.
class DefaultScreenOption {
  const DefaultScreenOption(this.id, this.label, this.icon);

  final ScreenId id;
  final String label;
  final IconData icon;

  /// القيمةُ المخزَّنة في `users.default_screen`.
  String get value => id.name;
}

/// الخياراتُ لدورٍ يملك [rolePermissions] (أو [bypass] لمدير النظام).
///
/// دالّةٌ خالصةٌ: [navItems] و[flavorAllowed] و[brandVisible] تُحقَن في
/// الاختبار، وافتراضيُّها السجلُّ الحيُّ.
List<DefaultScreenOption> defaultScreenOptions({
  required Iterable<String> rolePermissions,
  required bool bypass,
  bool eInvoiceAvailable = false,
  Iterable<NavItemDef>? navItems,
  Set<ScreenId>? flavorAllowed,
  bool Function(int index)? brandVisible,
}) {
  final items = navItems ?? kAllNavItemDefs;
  final allowedByFlavor = flavorAllowed ?? AppConfig.allowedScreenIds.toSet();
  final visible = brandVisible ?? navItemVisibleForBrand;
  final held = rolePermissions.toSet();
  final seen = <int>{};
  final out = <DefaultScreenOption>[];
  for (final item in items) {
    final id = ScreenId.fromIndex(item.index);
    if (id == null || !seen.add(item.index)) continue;
    if (!allowedByFlavor.contains(id) || !visible(item.index)) continue;
    if (_kNotLandingScreens.contains(id)) continue;
    // نفسُ الدالّة الوحيدة التي تستعملها القائمةُ ومزوّدُ الشاشات المسموحة
    // (بما فيها استثناءُ الفوترة الإلكترونية) — B-6.
    if (!screenVisibleToUser(held, id,
        primaryCode:
            resolveScreenPrimaryCode(screenPermissionMap, id, item.permission),
        bypass: bypass,
        eInvoicePlatformActive: eInvoiceAvailable)) {
      continue;
    }
    out.add(DefaultScreenOption(id, item.label, item.icon));
  }
  return out;
}

/// اسمُ الشاشة المخزَّنة للعرض (بطاقة المستخدم)، أو «غير محددة».
String defaultScreenLabel(String? stored) {
  final index = parseStoredScreen(stored);
  if (index == null) return tr('غير محددة');
  for (final item in kAllNavItemDefs) {
    if (item.index == index) return tr(item.label);
  }
  return tr('غير محددة');
}

/// قيمةُ القائمة المطبَّعة: `ScreenId.name` للمخزَّن (قديماً أو جديداً) إن كان
/// بين [options]، وإلّا `null` (فتُعرض «غير محددة» بدل assertion الـDropdown).
String? normalizeDefaultScreenValue(
  String? stored,
  List<DefaultScreenOption> options,
) {
  final index = parseStoredScreen(stored);
  if (index == null) return null;
  for (final o in options) {
    if (o.id.navigationIndex == index) return o.value;
  }
  return null;
}

class _RoleAccess {
  const _RoleAccess(this.permissions, this.bypass);
  final Set<String> permissions;
  final bool bypass;
}

final _roleAccessProvider =
    FutureProvider.autoDispose.family<_RoleAccess, int?>((ref, roleId) async {
  if (roleId == null) return const _RoleAccess({}, false);
  final repo = ref.read(authRepositoryProvider);
  final perms = await repo.getPermissionsForRole(roleId);
  var bypass = false;
  for (final r in await repo.getAllRoles()) {
    // مطابقةٌ لـ`hasSystemAdminBypass`: دورُ النظام المسمّى «مدير النظام» حصراً.
    if (r.id == roleId && r.isSystemRole && r.name == 'مدير النظام') {
      bypass = true;
    }
  }
  return _RoleAccess({for (final p in perms) p.code}, bypass);
});

class DefaultScreenDropdown extends ConsumerWidget {
  const DefaultScreenDropdown({
    super.key,
    required this.roleId,
    required this.value,
    required this.onChanged,
    this.decoration,
  });

  /// الدورُ المختار — تُشتقّ منه الشاشاتُ المسموحة.
  final int? roleId;

  /// القيمةُ المخزَّنة الحاليّة (قديمةً أو جديدة).
  final String? value;
  final ValueChanged<String?> onChanged;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(_roleAccessProvider(roleId)).value;
    final platform = ref.watch(activeEInvoicePlatformProvider).value;
    final options = access == null
        ? const <DefaultScreenOption>[]
        : defaultScreenOptions(
            rolePermissions: access.permissions,
            bypass: access.bypass,
            eInvoiceAvailable: platform != null,
          );
    final current = normalizeDefaultScreenValue(value, options);
    final hasUnavailable = access != null &&
        current == null &&
        parseStoredScreen(value) != null;
    return DropdownButtonFormField<String>(
      // يُعاد بناؤها عند تغيّر الدور أو القيمة (initialValue لا تتتبّع).
      key: ValueKey('default-screen-$roleId-$current-${options.length}'),
      isExpanded: true,
      decoration: (decoration ?? const InputDecoration()).copyWith(
        helperText:
            hasUnavailable ? tr('الشاشة الافتراضية غير متاحة لهذا الدور') : null,
      ),
      hint: Text(tr('غير محددة')),
      initialValue: current,
      items: [
        for (final o in options)
          DropdownMenuItem<String>(
            value: o.value,
            child: Row(
              children: [
                Icon(o.icon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr(o.label), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: access == null ? null : onChanged,
    );
  }
}
