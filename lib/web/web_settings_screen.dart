// «الإعدادات» — نسخة ويب مصغّرة (م3-9).
//
// شاشة الإعدادات الكاملة (`settings_picpos_screen.dart`) تسحب بالاستيراد
// إعداداتِ POS ونقاط البيع والطاولات وقوالب الطباعة (محظورة في مسار الويب)، وكلُّها
// إعداداتُ أجهزةٍ محلية لا معنى لها في متصفح. فتُترجَم للويب نسخةٌ مصغّرة تحمل
// ما له معنى عن بُعد: إدارة المستخدمين، ومصفوفة الصلاحيات، والانتقال للفروع.
//
// الأمان الفعلي (الصلاحيات) على الخادم؛ هذه واجهةٌ فقط.
import 'package:flutter/material.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../core/navigation/screen_id.dart';
import '../presentation/settings_picpos/widgets/permissions_matrix_picpos.dart';

class WebSettingsScreen extends StatelessWidget {
  const WebSettingsScreen({super.key, required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(tr('الإعدادات'), style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          tr('نسخة الويب تعرض إعدادات الإدارة عن بُعد. إعدادات الأجهزة (الطابعات، '
          'نقاط البيع، الشبكة، قوالب الطباعة) تُدار من تطبيق سطح المكتب.'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.people_alt_outlined),
                title: Text(tr('المستخدمون')),
                subtitle: Text(tr('إضافة المستخدمين وإسناد الأدوار والفروع')),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => onNavigate(ScreenId.users.navigationIndex),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.grid_view_outlined),
                title: Text(tr('مصفوفة الصلاحيات')),
                subtitle: Text(tr('عرض وتعديل صلاحيات الأدوار')),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => showPermissionsMatrixPicpos(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.apartment_outlined),
                title: Text(tr('الفروع والمنشآت')),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => onNavigate(ScreenId.branches.navigationIndex),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
