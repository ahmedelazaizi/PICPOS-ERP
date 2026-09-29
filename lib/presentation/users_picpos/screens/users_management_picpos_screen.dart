import 'package:ural_erp/core/i18n/tr.dart';
// منطق منسوخ من users_management_screen.dart (monolith) — أي إصلاح منطقي
// يتصلّح في المصدر أولاً ثم يُنقل بـ patch لهذا الملف (مصيدة النسخ §٥.٨). لا
// يُنسخ أبداً من D:\URAL-ERP.
//
// الشاشة الأصل (lib/presentation/screens/users_management_screen.dart)
// مونوليث 869 سطر بلا `part` files. الفورك هنا ينسخ منطق الـ State كاملاً
// حرفياً بلا أي تعديل منطقي: تعيين الدور/الشاشة الافتراضية/حد الخصم الأقصى،
// تفعيل/تعطيل المستخدم، قفل/فك القفل، الحذف (تعطيل+قفل ناعم)، شارة الفرع،
// ألوان/أيقونات الأدوار، وقائمة المستخدمين بالكامل (`_buildUsersList` عبر
// `ExpansionTile` لكل مستخدم بكل ما فيها من حقول وأزرار). يتغيّر بس اسم الكلاس
// وطبقة العرض الخارجية (PicPosScreenScaffold بدل Scaffold+AppBar يدوي؛ زر
// إضافة مستخدم انتقل من AppBar actions إلى headerActions).
//
// REUSE (import لا نسخ): `allUsersProvider`/`allRolesProvider`/
// `allUserBranchNamesProvider`/`authProvider`/`authRepositoryProvider`/
// `currentUserPermissionsProvider`/`activityLoggerProvider` من
// data/providers/providers.dart، `ClientWriteInterceptor`، توابع
// bootstrap_admin (isBootstrapAdmin وحارس منع تعديل/قفل/حذف مدير النظام
// الجذري)، `SecurityAlertsPanel`، وحوارات settings/widgets/ كما هي
// (AddUserDialog/EditUserDialog/ResetPasswordDialog/SetPinDialog/
// BranchAccessDialog/WarehouseAccessDialog).
//
// FULL PARITY مع الأصل: لوحة تنبيهات الأمان (للمدير فقط)، قائمة المستخدمين
// القابلة للتوسيع (ExpansionTile) بكل شاراتها (الدور/معطل/الفرع)، تعيين
// الدور (مع بوابة الموافقة الثنائية Spec 063 وحارس bootstrap admin)، الشاشة
// الافتراضية، حد الخصم الأقصى، تفعيل/تعطيل، قفل/فك القفل (بتأكيد)، إعادة
// كلمة المرور، تعيين/تغيير PIN، حذف (ناعم)، صلاحيات الفروع والمخازن (أو شارة
// «مدير النظام» لمستخدم #1)، وإضافة مستخدم جديد.
//
// راجع lib/presentation/screens/users_management_screen.dart (الأصل).

import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
// 063 (D1-005): dual-approval gate for user-role changes.
import 'package:ural_erp/services/dual_approval_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/auth/bootstrap_admin.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';

import '../../../data/providers/providers.dart';
import '../../widgets/enhanced_components.dart';
import '../../../services/client_write_interceptor.dart';
import '../../widgets/dialogs/app_confirm_dialog.dart';
import '../../screens/settings/widgets/add_user_dialog.dart';
import '../../screens/settings/widgets/edit_user_dialog.dart';
import '../../screens/settings/widgets/reset_password_dialog.dart';
import '../../screens/settings/widgets/security_alerts_panel.dart';
import '../../screens/settings/widgets/set_pin_dialog.dart';
import '../../screens/settings/widgets/branch_access_dialog.dart';
import '../../screens/settings/widgets/warehouse_access_dialog.dart';
import '../../picpos_shell/picpos_danger_confirm.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';

/// شاشة إدارة المستخدمين بهوية PicPos. تُختار في مواقع الـ
/// `Navigator.push` (فورك التقارير/الإعدادات) بدلاً من app_main_screen، لأن
/// الشاشة الأصلية أساساً ليست في الراوتر. تعيد استخدام نفس
/// `allUsersProvider`/`allRolesProvider`/`allUserBranchNamesProvider` وبقية
/// المزوّدات والحوارات من UralCash — فقط طبقة العرض الخارجية تبدّلت لـ
/// picpos_shell (هيدر PicPosScreenScaffold بدل Scaffold+AppBar).
bool _isAdmin(List<String> p) => p.contains('system_admin') || p.contains('*');

/// فتحُ شاشة إدارة المستخدمين (`users_manage`).
///
/// ── لماذا الفحصُ في الشاشة لا في مداخلها ────────────────────────────────
/// كانت الشاشةُ بلا أيّ فحصٍ داخليّ، وحمايتُها كلُّها على المداخل: لفّةٌ في
/// شاشة الإعدادات، ومدخلٌ في كتالوج التقارير **نُسي فيه `permission:`** —
/// فمن يملك `reports_view` وحدَه كان يبلغ الشاشةَ ويُسنِد لنفسه دورَ مدير
/// النظام (‏أُغلق 2026-08-13).
///
/// وحراسةُ المداخل وحدَها هي بعينها فئةُ العطب التي طاردناها اليومَ كلَّه:
/// بابٌ يُحرَس وبابٌ يُنسى. فالفحصُ هنا نقطةٌ واحدةٌ يمرّ بها كلُّ مدخلٍ
/// حاليٍّ ومستقبليّ.
@visibleForTesting
bool canManageUsersCodes(List<String> permissions) =>
    _isAdmin(permissions) || permissions.contains(PermissionCodes.usersManage);

/// إسنادُ دورٍ لمستخدم (`roles_manage`) — **لا** `users_manage`.
///
/// منحُ دورٍ قرارُ صلاحياتٍ لا تحريرُ سجلّ مستخدم، وهو المسارُ الذي يصنع
/// مديرَ نظامٍ جديداً. فمن يدير الحساباتِ لا يصعّد نفسَه بالضرورة.
///
/// ⚠️ وكان حارسُه الوحيدُ `DualApprovalService` (سبيك ٠٦٣) وهو **مطفأٌ
/// افتراضياً** بإعداد، فلم يكن ثمّة فحصٌ فعليٌّ إطلاقاً.
@visibleForTesting
bool canAssignUserRoleCodes(List<String> permissions) =>
    _isAdmin(permissions) || permissions.contains(PermissionCodes.rolesManage);

class UsersManagementPicposScreen extends ConsumerStatefulWidget {
  const UsersManagementPicposScreen({super.key});

  @override
  ConsumerState<UsersManagementPicposScreen> createState() =>
      _UsersManagementPicposScreenState();
}

class _UsersManagementPicposScreenState
    extends ConsumerState<UsersManagementPicposScreen> {
  @override
  Widget build(BuildContext context) {
    // ── بوّابةُ الشاشة ────────────────────────────────────────────────────
    // ⚠️ `.value` لا `asData?.value`: الثاني يرجع `null` في **كلّ** إعادة
    // تحميلٍ لا في الأولى وحدَها، فكان سيفتح الشاشةَ لحظةَ كلّ تحديث. نفسُ
    // العطب الذي أُصلح في `PermissionGuard` (‏4f774fd3).
    // وبلا قيمةٍ بعد ⇒ **يُغلَق**: لا تُعرض الشاشةُ «تفاؤلاً» ريثما تُقرأ.
    final perms = ref.watch(currentUserPermissionsProvider).value;
    if (perms == null || !canManageUsersCodes(perms)) {
      return _deniedScaffold(
        perms == null
            ? tr('جارٍ التحقّق من الصلاحية…')
            : tr('ليس لديك صلاحية «إدارة المستخدمين».'),
      );
    }

    final usersAsync = ref.watch(allUsersProvider);
    final rolesAsync = ref.watch(allRolesProvider);
    final branchNamesAsync = ref.watch(allUserBranchNamesProvider);
    final theme = Theme.of(context);

    return PicPosScreenScaffold(
      title: tr('المستخدمون'),
      subtitle: tr('إدارة حسابات المستخدمين والصلاحيات'),
      icon: PhosphorIconsBold.users,
      headerActions: [
        IconButton(
          icon: const Icon(PhosphorIconsBold.userPlus),
          onPressed: () => _showAddUserDialog(),
          tooltip: tr('إضافة مستخدم'),
        ),
      ],
      body: usersAsync.when(
        data: (users) => rolesAsync.when(
          data: (roles) => Column(
            children: [
              // Feature 004 (US2) — surface unresolved cross-branch password
              // collision alerts to the System Admin only. The panel hides
              // itself when there are no alerts.
              if (ref.watch(authProvider).isAdmin) const SecurityAlertsPanel(),
              Expanded(
                child: _buildUsersList(
                  users,
                  roles,
                  theme,
                  branchNamesAsync.value ?? {},
                ),
              ),
            ],
          ),
          loading: () => Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 4),
          ),
          error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
        ),
        loading: () => Padding(
          padding: const EdgeInsets.all(16),
          child: ShimmerLoading.list(itemCount: 4),
        ),
        error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // شبكةُ بطاقاتِ المستخدمين — تصميم `isUsers`
  //
  // ⚠️ **حلّت محلَّ `ListView` من `ExpansionTile`، ولم تُسقط قدرةً واحدة.**
  // البطاقةُ في التصميم تحمل زرَّين ونقاطاً؛ والشاشةُ كانت تحمل **ثمانيةَ
  // إجراءاتٍ** (تعديل · تفعيل/تعطيل · قفل/فتح · كلمة مرور · PIN · الفروع ·
  // المخازن · حذف) **وثلاثةَ محرّراتٍ داخل الطيّ** (الدور · الشاشة
  // الافتراضية · حدّ الخصم).
  //
  // فالزرّان الظاهران هما الأكثرُ استعمالاً، والستّةُ الباقيةُ تحت النقاط،
  // والمحرّراتُ الثلاثةُ انتقلت **بجسمها الحرفيّ** إلى حوارٍ يفتحه بندُ
  // «الدور والإعدادات» — لا نسخةٍ مُعاد كتابتها. حذفُ إجراءٍ إداريٍّ لأن
  // مخطّطاً لا يرسمه ليس إعادةَ تصميم.
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildUsersList(
    List<UserWithRole> users,
    List<Role> roles,
    ThemeData theme,
    Map<int, List<String>> userBranchNames,
  ) {
    if (users.isEmpty) {
      return  EmptyStateWidget(
        icon: PhosphorIconsBold.users,
        message: tr('لا توجد مستخدمين'),
        description: tr('أضف أول مستخدم للنظام'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          < 720 => 1,
          < 1100 => 2,
          _ => 3,
        };
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 11,
            mainAxisSpacing: 11,
            // ارتفاعٌ صريحٌ: البطاقةُ ثابتةُ المحتوى (رأسٌ + ثلاثةُ سطورٍ +
            // صفُّ أزرار)، والنسبةُ المحسوبةُ من العرض كانت تقصّها في العمود
            // الضيّق — نفسُ عطبِ بطاقاتِ العدّادات المقيس.
            mainAxisExtent: 196,
          ),
          itemCount: users.length,
          itemBuilder: (context, index) => _buildUserCard(
            users[index],
            roles,
            theme,
            userBranchNames,
          ),
        );
      },
    );
  }

  Widget _buildUserCard(
    UserWithRole userWithRole,
    List<Role> roles,
    ThemeData theme,
    Map<int, List<String>> userBranchNames,
  ) {
    final user = userWithRole.user;
    final role = userWithRole.role;
    final tint = user.isActive ? _getRoleColor(role?.name) : Colors.grey;
    final tintBg = tint.withValues(alpha: 31 / 255);

    // شارةُ الحالة: المقفولُ أخصُّ من المعطَّل، والمعطَّلُ أخصُّ من النشط —
    // فمستخدمٌ معطَّلٌ ومقفولٌ يُعرَض «مقفول» لأنه العائقُ الأقربُ للحلّ.
    final (String stLabel, Color stColor) = user.isLocked
        ? (tr('مقفول'), Colors.orange)
        : (!user.isActive ? (tr('معطل'), AppColors.error) : (tr('نشط'), AppColors.success));

    final branches = userBranchNames[user.id] ?? const <String>[];
    final branchLabel = branches.isEmpty ? tr('كل الفروع') : branches.join(tr('، '));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tintBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _initialsOf(user.displayName),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: tint,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    Text(
                      '@${user.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: stColor.withValues(alpha: 31 / 255),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  stLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: stColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          _userMetaLine(
            PhosphorIconsBold.shieldCheck,
            role?.name ?? tr('بلا دور'),
            tint,
            bold: true,
          ),
          const SizedBox(height: 6),
          _userMetaLine(
            PhosphorIconsBold.buildings,
            branchLabel,
            AppColors.textMuted,
          ),
          const SizedBox(height: 6),
          _userMetaLine(
            PhosphorIconsBold.house,
            tr('الشاشة الافتراضية: {p0}', {'p0': _homeScreenLabel(user.defaultScreen)}),
            AppColors.textMuted,
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _userCardButton(
                  theme,
                  key: Key('user-edit-${user.id}'),
                  icon: PhosphorIconsBold.pencilSimple,
                  iconColor: AppColors.warning,
                  label: tr('تعديل البيانات'),
                  onPressed: () => _showEditUserDialog(user),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _userCardButton(
                  theme,
                  key: Key('user-password-${user.id}'),
                  icon: PhosphorIconsBold.key,
                  iconColor: AppColors.primary,
                  label: tr('كلمة المرور'),
                  onPressed: () => _showResetPasswordDialog(user),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 32,
                height: 32,
                child: PopupMenuButton<String>(
                  key: Key('user-more-${user.id}'),
                  tooltip: tr('المزيد'),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  icon: const Icon(
                    PhosphorIconsBold.dotsThreeVertical,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                  onSelected: (v) => _onUserMenu(v, userWithRole, roles),
                  itemBuilder: (_) => [
                     PopupMenuItem(
                      value: 'settings',
                      child: Text(tr('الدور والإعدادات'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(user.isActive ? tr('تعطيل') : tr('تفعيل'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      value: 'lock',
                      child: Text(user.isLocked ? tr('فتح القفل') : tr('قفل'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                     PopupMenuItem(
                      value: 'pin',
                      child: Text(tr('تعيين PIN'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                     PopupMenuItem(
                      value: 'branches',
                      child:
                          Text(tr('إدارة الفروع'), style: const TextStyle(fontSize: 12)),
                    ),
                     PopupMenuItem(
                      value: 'warehouses',
                      child: Text(tr('إدارة المخازن'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                     PopupMenuItem(
                      value: 'delete',
                      child: Text(tr('حذف'),
                          style: const TextStyle(fontSize: 12, color: AppColors.error)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _userMetaLine(
    IconData icon,
    String text,
    Color color, {
    bool bold = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: bold ? null : AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _userCardButton(
    ThemeData theme, {
    required Key key,
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 32,
      child: OutlinedButton.icon(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon, size: 13, color: iconColor),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: theme.textTheme.bodyMedium?.color,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          side: BorderSide(color: theme.dividerColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
          ),
        ),
      ),
    );
  }

  /// أوّلُ حرفٍ من أوّل كلمتَين — القطعُ بـ`runes` لا بـ`[0]` كي لا يُشطر
  /// زوجٌ بديلٌ نصفَ محرف.
  String _initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return tr('؟');
    return words
        .take(2)
        .map((w) => String.fromCharCodes(w.runes.take(1)))
        .join();
  }

  /// تسميةُ الشاشة الافتراضية — نفسُ خيارات القائمة المنسدلة في حوار
  /// الإعدادات، فلا يختلف الوصفُ عن المحرِّر.
  String _homeScreenLabel(String? screen) {
    switch (screen) {
      case 'pos':
        return tr('البيع السريع');
      case 'dashboard':
        return tr('لوحة القيادة');
      case 'products':
        return tr('المنتجات');
      case 'inventory':
        return tr('المخزون');
      default:
        return 'غير محددة';
    }
  }

  /// ⚠️ **القفلُ يؤكَّد قبل تنفيذه** — و`_toggleUserLock` لا تؤكّد داخلها.
  ///
  /// كان التأكيدُ في **المستدعي** (زرُّ القفل في جسم الطيّ)، فنقلُ الإجراء
  /// إلى قائمة النقاط أسقطه أوّلَ مرّة: نقرةٌ واحدةٌ كانت تمنع مستخدماً من
  /// الدخول بلا سؤال. النصُّ والأيقونةُ واللونُ منقولةٌ حرفيّاً عن الأصل.
  ///
  /// (‏`_deleteUser` تؤكّد داخلها، و`_toggleUserActive` لم تكن تؤكّد أصلاً —
  /// قِيس كلاهما قبل النقل ولم يُغيَّر سلوكُهما.)
  Future<void> _confirmToggleLock(User user) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: user.isLocked ? tr('فك قفل المستخدم') : tr('قفل المستخدم'),
      message: user.isLocked
          ? tr('هل أنت متأكد من فك قفل المستخدم {p0}؟', {'p0': user.displayName})
          : tr('هل أنت متأكد من قفل المستخدم {p0}؟ لن يتمكن من تسجيل الدخول.', {'p0': user.displayName}),
      confirmLabel: user.isLocked ? tr('فك القفل') : tr('قفل'),
      icon: user.isLocked ? PhosphorIconsBold.lockOpen : PhosphorIconsBold.lock,
      color: user.isLocked ? AppColors.info : Colors.orange,
    );
    if (confirmed) await _toggleUserLock(user);
  }

  void _onUserMenu(String action, UserWithRole uwr, List<Role> roles) {
    final user = uwr.user;
    switch (action) {
      case 'settings':
        _showUserSettingsDialog(uwr, roles);
      case 'toggle':
        _toggleUserActive(user);
      case 'lock':
        _confirmToggleLock(user);
      case 'pin':
        _showSetPinDialog(user);
      case 'branches':
        _showBranchAccessDialog(user);
      case 'warehouses':
        _showWarehouseAccessDialog(user);
      case 'delete':
        _deleteUser(user);
    }
  }

  /// حوارُ «الدور والإعدادات» — يحمل **جسمَ الطيّ السابق حرفيّاً**.
  ///
  /// لم يُعد بناؤه: محرّرُ الدور فيه حارسُ المسؤول الجذر (Spec 061) وحدُّ
  /// الخصم والشاشةُ الافتراضية، وإعادةُ كتابتها كانت ستُسقط حارساً بصمت.
  void _showUserSettingsDialog(UserWithRole userWithRole, List<Role> roles) {
    final user = userWithRole.user;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('الدور والإعدادات — {p0}', {'p0': user.displayName})),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: _buildUserSettingsBody(user, roles),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:  Text(tr('إغلاق')),
          ),
        ],
      ),
    );
  }

  Widget _buildUserSettingsBody(User user, List<Role> roles) {
    return Padding(
      padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Role Assignment
                     Text(
                      tr('تعيين الدور:'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    // Spec 061 (D1-003): role dropdown disabled for the
                    // bootstrap admin — admin's role assignment is immutable.
                    Tooltip(
                      message: isBootstrapAdmin(user.id, username: user.username)
                          ? bootstrapAdminRoleGuardMessage
                          : '',
                      child: DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(PhosphorIconsLight.shieldCheck),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        initialValue: user.roleId,
                        items: roles
                            .map(
                              (role) => DropdownMenuItem(
                                value: role.id,
                                child: Text(role.name),
                              ),
                            )
                            .toList(),
                        onChanged: isBootstrapAdmin(user.id,
                                username: user.username)
                            ? null
                            : (roleId) => _updateUserRole(user.id, roleId),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Default Screen
                     Text(
                      tr('الشاشة الافتراضية:'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(PhosphorIconsLight.monitor),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      initialValue: user.defaultScreen,
                      items:  [
                        DropdownMenuItem(
                          value: 'pos',
                          child: Text(tr('البيع السريع')),
                        ),
                        DropdownMenuItem(
                          value: 'dashboard',
                          child: Text(tr('لوحة القيادة')),
                        ),
                        DropdownMenuItem(
                          value: 'products',
                          child: Text(tr('المنتجات')),
                        ),
                        DropdownMenuItem(
                          value: 'inventory',
                          child: Text(tr('المخزون')),
                        ),
                      ],
                      onChanged: (screen) =>
                          _updateDefaultScreen(user.id, screen),
                    ),
                    const SizedBox(height: 16),

                    // Max Discount Percent
                     Text(
                      tr('حد الخصم الأقصى (%):'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue:
                                user.maxDiscountPercent?.toStringAsFixed(0) ??
                                '',
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(
                                PhosphorIconsLight.percent,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              hintText: tr('بلا حد'),
                              suffixText: '%',
                              helperText: user.maxDiscountPercent != null
                                  ? tr('الحد الحالي: {p0}%', {'p0': user.maxDiscountPercent!.toStringAsFixed(0)})
                                  : tr('لا يوجد حد - اتركه فارغاً لعدم التحديد'),
                            ),
                            onFieldSubmitted: (val) =>
                                _updateMaxDiscount(user.id, val),
                          ),
                        ),
                        if (user.maxDiscountPercent != null)
                          IconButton(
                            icon: const Icon(
                              PhosphorIconsBold.x,
                              color: AppColors.error,
                              size: 18,
                            ),
                            tooltip: tr('إزالة الحد'),
                            onPressed: () => _updateMaxDiscount(user.id, ''),
                          ),
                      ],
                    ),
                  ],
                ),
    );
  }


  /// شاشةُ المنع — بنفس الترويسة كي يعرف المستخدمُ أين هو ويرجع، لا صفحةً
  /// بيضاءَ تُقرأ عطلاً. والرسالةُ تسمّي الصلاحيةَ الناقصةَ كي يعرف المديرُ
  /// ما يمنحه بدل أن يجرّب.
  Widget _deniedScaffold(String message) => PicPosScreenScaffold(
        title: tr('المستخدمون'),
        subtitle: tr('إدارة حسابات المستخدمين والصلاحيات'),
        icon: PhosphorIconsBold.users,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsBold.lockKey,
                    size: 48, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _showAddUserDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const AddUserDialog(),
    );

    if (result == true) {
      ref.invalidate(allUsersProvider);
      ref.invalidate(allUserBranchNamesProvider);
    }
  }

  Future<void> _showEditUserDialog(dynamic user) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditUserDialog(user: user),
    );
    if (result == true) {
      ref.invalidate(allUsersProvider);
      if (!mounted) return;
      AppToast.show(context, tr('تم حفظ التعديلات'), type: ToastType.success);
    }
  }

  // _addUser logic is now handled in AddUserDialog

  Future<void> _updateUserRole(int userId, int? roleId) async {
    if (roleId == null) return;
    // ── `roles_manage` — الفحصُ **قبل** الموافقة الثنائية ─────────────────
    // إسنادُ الدور هو مسارُ صناعةِ مديرِ نظامٍ جديد. وحارسُه الوحيدُ كان
    // `DualApprovalService` أدناه وهو **مطفأٌ افتراضياً** بإعداد
    // (`requireApprovalForOp` يرجع `true` بلا حوارٍ حين تكون الرايةُ مطفأة)،
    // فلم يكن ثمّة فحصٌ فعليٌّ إطلاقاً. (مقيسٌ 2026-08-13)
    //
    // والترتيبُ مقصود: لا يُستدعى مُوافقٌ ثانٍ لعمليةٍ سترفض أصلاً.
    final perms =
        ref.read(currentUserPermissionsProvider).value ?? const <String>[];
    if (!canAssignUserRoleCodes(perms)) {
      if (mounted) {
        AppToast.show(context, tr('ليس لديك صلاحية «إدارة صلاحيات الأدوار»'),
            type: ToastType.error);
      }
      return;
    }
    // 063 (D1-005): dual-approval gate (settings-flag gated; OFF by
    // default = no dialog).
    final approved = await DualApprovalService.requireApprovalForOp(
      context,
      ref,
      operation: DualApprovalOperation.userRoleChange,
      details: tr('تغيير دور المستخدم #{userId}', {'userId': userId}),
    );
    if (!approved) {
      if (mounted) {
        AppToast.show(context, tr('الموافقة الثنائية مرفوضة — لم يتم تغيير الدور'), type: ToastType.warning);
      }
      return;
    }
    // Route through interceptor in client mode
    final intercepted = await ClientWriteInterceptor.updateUser(userId, {
      'roleId': roleId,
    });
    if (!intercepted) {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.assignRoleToUser(userId, roleId);
    }
    // #Forensic Log: Role change
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserEdit(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        'User#$userId',
        tr('تغيير الدور'),
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
    // Invalidate permission providers so UI reflects the new role immediately
    ref.invalidate(currentUserPermissionsProvider);
    ref.invalidate(userNavItemsProvider);
    ref.invalidate(userAllowedScreensProvider);

    if (!mounted) return;
    AppToast.show(context, tr('تم تحديث الدور'), type: ToastType.success);
  }

  Future<void> _updateDefaultScreen(int userId, String? screen) async {
    if (screen == null) return;
    // Route through interceptor in client mode
    final intercepted = await ClientWriteInterceptor.updateUser(userId, {
      'defaultScreen': screen,
    });
    if (!intercepted) {
      final authRepo = ref.read(authRepositoryProvider);
      // Get current user to preserve other info or use a dedicated method
      final userWithRole = await authRepo.getUserById(userId);
      if (userWithRole != null) {
        await authRepo.updateUserInfo(
          userId: userId,
          displayName: userWithRole.user.displayName,
          roleId: userWithRole.user.roleId,
          maxDiscountPercent: userWithRole.user.maxDiscountPercent,
          discountLimitIsPercent: userWithRole.user.discountLimitIsPercent,
          cardCode: userWithRole.user.cardCode,
          defaultScreen: screen,
        );
      }
    }
    // #Forensic Log: Default screen change
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserEdit(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        'User#$userId',
        tr('تغيير الشاشة الافتراضية'),
        newValue: screen,
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
    if (!mounted) return;
    AppToast.show(
      context,
      tr('تم تحديث الشاشة الافتراضية'),
      type: ToastType.success,
    );
  }

  Future<void> _updateMaxDiscount(int userId, String value) async {
    final maxDiscount = value.isEmpty ? null : double.tryParse(value);

    if (value.isNotEmpty && maxDiscount == null) {
      AppToast.show(context, tr('يرجى إدخال رقم صحيح'), type: ToastType.error);
      return;
    }

    if (maxDiscount != null && (maxDiscount < 0 || maxDiscount > 100)) {
      AppToast.show(
        context,
        tr('يجب أن تكون النسبة بين 0 و 100'),
        type: ToastType.error,
      );
      return;
    }

    // Route through interceptor in client mode
    final intercepted = await ClientWriteInterceptor.updateUser(userId, {
      'maxDiscountPercent': maxDiscount,
    });
    if (!intercepted) {
      final authRepo = ref.read(authRepositoryProvider);
      final userWithRole = await authRepo.getUserById(userId);
      if (userWithRole != null) {
        await authRepo.updateUserInfo(
          userId: userId,
          displayName: userWithRole.user.displayName,
          roleId: userWithRole.user.roleId,
          maxDiscountPercent: maxDiscount,
          discountLimitIsPercent: userWithRole.user.discountLimitIsPercent,
          cardCode: userWithRole.user.cardCode,
          defaultScreen: userWithRole.user.defaultScreen,
        );
      }
    }
    // #Forensic Log: Max discount change
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserEdit(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        'User#$userId',
        tr('تغيير حد الخصم'),
        newValue: maxDiscount?.toStringAsFixed(0) ?? tr('بدون حد'),
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
    if (!mounted) return;
    AppToast.show(
      context,
      maxDiscount != null
          ? tr('تم تحديد حد الخصم: {p0}%', {'p0': maxDiscount.toStringAsFixed(0)})
          : tr('تم إزالة حد الخصم'),
      type: ToastType.success,
    );
    // Refresh the list
    ref.invalidate(allUsersProvider);
  }

  Future<void> _toggleUserActive(User user) async {
    final newActive = !user.isActive;
    // Spec 061 (D1-003): refuse to deactivate the bootstrap admin row.
    if (isBootstrapAdmin(user.id, username: user.username) && !newActive) {
      AppToast.show(context, bootstrapAdminGuardMessage,
          type: ToastType.error);
      return;
    }
    // Route through interceptor in client mode
    final intercepted = await ClientWriteInterceptor.updateUser(user.id, {
      'isActive': newActive,
    });
    if (!intercepted) {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.toggleUserActive(userId: user.id, isActive: newActive);
    }
    // #Forensic Log: User activate/deactivate
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserToggleActive(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        user.displayName,
        newActive,
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
    if (!mounted) return;
    AppToast.show(
      context,
      user.isActive ? tr('تم تعطيل المستخدم') : tr('تم تفعيل المستخدم'),
      type: ToastType.success,
    );
  }

  Future<void> _toggleUserLock(User user) async {
    final newLocked = !user.isLocked;
    // Spec 061 (D1-003): refuse to lock the bootstrap admin row.
    if (isBootstrapAdmin(user.id, username: user.username) && newLocked) {
      AppToast.show(context, bootstrapAdminGuardMessage,
          type: ToastType.error);
      return;
    }
    // Route through interceptor in client mode
    final intercepted = await ClientWriteInterceptor.updateUser(user.id, {
      'isLocked': newLocked,
    });
    if (!intercepted) {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.setUserLocked(user.id, newLocked);
    }
    // #Forensic Log: User lock/unlock
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserToggleLock(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        user.displayName,
        newLocked,
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
    if (!mounted) return;
    AppToast.show(
      context,
      user.isLocked ? tr('تم فك قفل المستخدم') : tr('تم قفل المستخدم'),
      type: ToastType.success,
    );
  }

  Future<void> _deleteUser(User user) async {
    // Spec 061 (D1-003): refuse to delete the bootstrap admin row — block
    // BEFORE the confirmation dialog appears so the operator isn't even
    // invited to attempt it.
    if (isBootstrapAdmin(user.id, username: user.username)) {
      AppToast.show(context, bootstrapAdminGuardMessage,
          type: ToastType.error);
      return;
    }
    // ⚠️ **العنوانُ يقول ما يحدث فعلاً.** هذا حذفٌ ناعم: الصفُّ يبقى
    //    و`isActive`/`isLocked` وحدَهما يتبدّلان (انظر أسفلَه). فكتابةُ
    //    «سيُحذف» فوقَ أثرٍ لا يحذف تضليلٌ في أخطرِ موضع — ومن ظنّ الحساب
    //    ممحوّاً استغرب بقاءَ اسمه في السجلّ وظنّه عطباً.
    final confirmed = await showPicPosDangerConfirm(
      context,
      icon: PhosphorIconsBold.userMinus,
      title: tr('تعطيل المستخدم'),
      subtitle: user.displayName,
      message: 'يُقفَل الحساب فلا يستطيع صاحبُه الدخول. وحركاتُه السابقة '
          'تبقى مسجّلةً باسمه كما هي.',
      actionLabel: tr('تعطيل الحساب'),
      willDeleteLabel: tr('سيحدث'),
      willDelete:  [
        tr('تعطيل الحساب فلا يظهر في قوائم المستخدمين النشطين'),
        tr('قفلُه فلا يُقبَل منه تسجيلُ دخول'),
      ],
      willRemainLabel: tr('يبقى كما هو'),
      willRemain:  [
        tr('فواتيره وحركاته السابقة'),
        tr('أثرُه في سجلّ العمليات'),
        tr('الورديات المغلقة باسمه'),
      ],
    );
    if (!confirmed) return;

    // Soft delete: deactivate + lock
    final intercepted = await ClientWriteInterceptor.updateUser(user.id, {
      'isActive': false,
      'isLocked': true,
    });
    if (!intercepted) {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.toggleUserActive(userId: user.id, isActive: false);
      await authRepo.setUserLocked(user.id, true);
    }
    // #Forensic Log: User delete
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserToggleActive(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        user.displayName,
        false,
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
    if (!mounted) return;
    AppToast.show(context, tr('تم تعطيل الحساب وقفله'), type: ToastType.success);
    ref.invalidate(allUsersProvider);
    ref.invalidate(allUserBranchNamesProvider);
  }

  Future<void> _showResetPasswordDialog(User user) async {
    await showDialog(
      context: context,
      builder: (context) => ResetPasswordDialog(user: user),
    );
  }

  Future<void> _showSetPinDialog(User user) async {
    await showDialog(
      context: context,
      builder: (context) => SetPinDialog(user: user),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // N3: BRANCH & WAREHOUSE ACCESS DIALOGS
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _showBranchAccessDialog(User user) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => BranchAccessDialog(user: user),
    );
    if (result == true) {
      ref.invalidate(allUserBranchNamesProvider);
    }
  }

  Future<void> _showWarehouseAccessDialog(User user) async {
    await showDialog(
      context: context,
      builder: (context) => WarehouseAccessDialog(user: user),
    );
  }

  // ignore: unused_element
  Widget _buildBranchBadge(int userId, Map<int, List<String>> userBranchNames) {
    final branches = userBranchNames[userId];
    if (branches == null) return const SizedBox.shrink();

    final String label;
    if (branches.isEmpty) {
      // Empty list = full access (admin/system role)
      label = tr('كل الفروع');
    } else {
      label = branches.join(tr('، '));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsBold.buildings, size: 11, color: Colors.teal),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.teal,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String? roleName) {
    if (roleName == 'مدير النظام') return Colors.purple;
    if (roleName == 'مدير') return Colors.blue;
    if (roleName == 'كاشير') return Colors.green;
    return Colors.grey;
  }

  // ignore: unused_element
  IconData _getRoleIcon(String? roleName) {
    if (roleName == 'مدير النظام') return PhosphorIconsBold.shieldCheck;
    if (roleName == 'مدير') return PhosphorIconsBold.userGear;
    if (roleName == 'كاشير') return PhosphorIconsBold.cashRegister;
    return PhosphorIconsBold.user;
  }
}
