// J4 — تبويبُ «الدور في النظام»: من مكانٍ واحدٍ يُربط الموظفُ بمستخدم
// دخولٍ واحد (ربطُ موجودٍ أو إنشاءُ جديدٍ بدورٍ مقترَحٍ من وسومه، وتغييرُ
// الدور، وإعادةُ تعيين كلمة المرور)، وتُضبط وسومُ أدواره (مندوب · كاشير ·
// محاسب · أمين مخزن)، ولوحةُ المندوب لمن يحمل وسمَه.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_labels.dart';
import '../hr_picpos_providers.dart';
import '../widgets/hr_form_kit.dart';
import 'ef_rep_panel.dart';

class EfRolesTab extends ConsumerWidget {
  const EfRolesTab({super.key, required this.employeeId});
  final int? employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = employeeId;
    if (id == null) {
      return PicPosEmptyState(
        icon: PhosphorIconsBold.key,
        title: tr('احفظ الموظف أولاً'),
        hint: tr('يُربط الموظف بمستخدم النظام وأدواره بعد حفظ ملفه'),
      );
    }
    final profile = ref.watch(hrProfileProvider(id)).value;
    if (profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final canManage =
        ref.watch(hasPermissionProvider(PermissionCodes.hrManage)).value ??
            false;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        HrSection(
          title: tr('أدوار الموظف'),
          icon: PhosphorIconsBold.tag,
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final tag in HrRoleTag.values)
              FilterChip(
                key: Key('ef_tag_$tag'),
                avatar: Icon(hrRoleTagIcon(tag), size: 15),
                label: Text(hrRoleTagLabel(tag)),
                selected: profile.roleTags.contains(tag),
                onSelected: !canManage
                    ? null
                    : (on) => _run(context, ref, id, () {
                          final tags = {...profile.roleTags};
                          on ? tags.add(tag) : tags.remove(tag);
                          return ref.read(databaseProvider).setEmployeeRoleTags(
                              id, tags,
                              actorUserId: ref.read(authProvider).user?.id);
                        }),
              ),
          ]),
        ),
        EfUserPanel(profile: profile),
        if (profile.isRep) EfRepPanel(profile: profile, canManage: canManage),
      ],
    );
  }
}

/// ينفّذ [action] ثمّ يُحدّث ملفَّ الموظف، ويعرض الخطأ برسالته.
Future<bool> _run(BuildContext context, WidgetRef ref, int employeeId,
    Future<void> Function() action,
    {String? success}) async {
  try {
    await action();
    refreshHr(ref, employeeId);
    if (success != null && context.mounted) {
      AppToast.show(context, success);
    }
    return true;
  } catch (e, st) {
    if (context.mounted) {
      if (e is HrException) {
        AppToast.show(context, e.message, type: ToastType.error);
      } else {
        AppErrorHandler.handle(context, e, st);
      }
    }
    return false;
  }
}

/// «مستخدم النظام» — رابطٌ واحدٌ بين الموظف ومستخدم دخول.
class EfUserPanel extends ConsumerWidget {
  const EfUserPanel({super.key, required this.profile});
  final EmployeeProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canUsers =
        ref.watch(hasPermissionProvider(PermissionCodes.usersManage)).value ??
            false;
    final roles = ref.watch(hrRolesProvider).value ?? const <Role>[];
    final id = profile.id!;
    final userId = profile.userId;
    return HrSection(
      title: tr('مستخدم النظام'),
      icon: PhosphorIconsBold.key,
      child: userId == null
          ? _Unlinked(profile: profile, canUsers: canUsers)
          : FutureBuilder<UserWithRole?>(
              future: ref.read(authRepositoryProvider).getUserById(userId),
              builder: (context, snap) {
                final u = snap.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HrInfoLine(
                        icon: PhosphorIconsBold.user,
                        label: tr('اسم الدخول'),
                        value: profile.username ?? '—'),
                    HrInfoLine(
                        icon: PhosphorIconsBold.shieldCheck,
                        label: tr('الدور'),
                        value: u?.role == null ? '—' : trData(u!.role!.name)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                        key: const Key('ef_user_role'),
                        onPressed: !canUsers || u == null
                            ? null
                            : () => _changeRole(context, ref, u, roles),
                        icon: const Icon(PhosphorIconsBold.shieldCheck,
                            size: 16),
                        label: Text(tr('تغيير الدور')),
                      ),
                      OutlinedButton.icon(
                        key: const Key('ef_user_reset_password'),
                        onPressed: !canUsers
                            ? null
                            : () => _resetPassword(context, ref, userId),
                        icon: const Icon(PhosphorIconsBold.password, size: 16),
                        label: Text(tr('إعادة تعيين كلمة المرور')),
                      ),
                      OutlinedButton.icon(
                        key: const Key('ef_user_unlink'),
                        onPressed: !canUsers
                            ? null
                            : () async {
                                final ok = await showPicPosConfirm(context,
                                    icon: PhosphorIconsBold.linkBreak,
                                    title: tr('فك ربط المستخدم'),
                                    message: tr(
                                        'يبقى المستخدم «{p0}» في النظام دون ربط بهذا الموظف.',
                                        {'p0': profile.username ?? ''}),
                                    danger: true);
                                if (!ok || !context.mounted) return;
                                await _run(context, ref, id,
                                    () => ref
                                        .read(databaseProvider)
                                        .linkEmployeeUser(
                                            employeeId: id,
                                            userId: null,
                                            actorUserId: ref
                                                .read(authProvider)
                                                .user
                                                ?.id));
                              },
                        icon: const Icon(PhosphorIconsBold.linkBreak, size: 16),
                        label: Text(tr('فك الربط')),
                      ),
                    ]),
                  ],
                );
              },
            ),
    );
  }

  Future<void> _changeRole(BuildContext context, WidgetRef ref,
      UserWithRole u, List<Role> roles) async {
    int? roleId = u.user.roleId;
    final picked = await showDialog<int?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => PicPosDialog(
          icon: PhosphorIconsBold.shieldCheck,
          title: tr('تغيير الدور'),
          width: 520,
          onCancel: () => Navigator.pop(ctx),
          primaryAction: PicPosDialogAction(
            label: tr('حفظ'),
            icon: PhosphorIconsBold.check,
            onPressed: () => Navigator.pop(ctx, roleId ?? -1),
          ),
          body: [
            HrDropdown<int>(
              label: tr('الدور'),
              value: roleId,
              items: {for (final r in roles) r.id: trData(r.name)},
              onChanged: (v) => setState(() => roleId = v),
            ),
          ],
        ),
      ),
    );
    if (picked == null || picked < 0 || !context.mounted) return;
    await _run(context, ref, profile.id!,
        () => ref.read(authRepositoryProvider).assignRoleToUser(u.user.id, picked),
        success: tr('تم تغيير الدور'));
  }

  Future<void> _resetPassword(
      BuildContext context, WidgetRef ref, int userId) async {
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => PicPosDialog(
        icon: PhosphorIconsBold.password,
        title: tr('إعادة تعيين كلمة المرور'),
        width: 520,
        onCancel: () => Navigator.pop(ctx, false),
        primaryAction: PicPosDialogAction(
          label: tr('حفظ'),
          icon: PhosphorIconsBold.check,
          onPressed: () => Navigator.pop(ctx, true),
        ),
        body: [
          HrTextField(
            fieldKey: const Key('ef_new_password'),
            label: tr('كلمة المرور الجديدة'),
            controller: password,
            required: true,
          ),
        ],
      ),
    );
    if (ok != true || password.text.trim().length < 4 || !context.mounted) {
      if (ok == true && context.mounted) {
        AppToast.show(context, tr('كلمة المرور 4 أحرف على الأقل'),
            type: ToastType.error);
      }
      return;
    }
    await _run(
        context,
        ref,
        profile.id!,
        () => ref.read(authRepositoryProvider).updateUserPassword(
            userId: userId, newPassword: password.text.trim()),
        success: tr('تم تغيير كلمة المرور'));
  }
}

/// موظفٌ بلا مستخدم: ربطُ مستخدمٍ قائمٍ أو إنشاءُ مستخدمٍ جديد.
class _Unlinked extends ConsumerStatefulWidget {
  const _Unlinked({required this.profile, required this.canUsers});
  final EmployeeProfile profile;
  final bool canUsers;

  @override
  ConsumerState<_Unlinked> createState() => _UnlinkedState();
}

class _UnlinkedState extends ConsumerState<_Unlinked> {
  int? _existing;
  int? _roleId;
  int? _warehouseId;
  bool _roleSuggested = false;
  late final _username = TextEditingController(
      text: (widget.profile.code ?? '').toLowerCase().replaceAll('-', ''));
  final _password = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _suggestRole() async {
    if (_roleSuggested) return;
    _roleSuggested = true;
    final db = ref.read(databaseProvider);
    for (final tag in HrRoleTag.values) {
      if (!widget.profile.roleTags.contains(tag)) continue;
      final id = await db.suggestedRoleIdForTag(tag);
      if (id != null) {
        if (mounted) setState(() => _roleId = id);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final id = p.id!;
    final users = ref.watch(hrLinkableUsersProvider(id)).value ?? const [];
    final roles = ref.watch(hrRolesProvider).value ?? const <Role>[];
    final warehouses =
        ref.watch(hrRepAssetsProvider(id)).value?.warehouses ?? const [];
    _suggestRole();
    final keeper = p.roleTags.contains(HrRoleTag.warehouseKeeper);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('الموظف غير مرتبط بمستخدم دخول. اربطه بمستخدم قائم أو أنشئ له مستخدماً.'),
            style: TextStyle(fontSize: 12.5, color: context.picposMuted)),
        const SizedBox(height: 12),
        HrFieldGrid(wide: const {0}, children: [
          HrDropdown<int>(
            fieldKey: const Key('ef_link_user'),
            label: tr('ربط مستخدم قائم'),
            value: _existing,
            emptyLabel: tr('اختر مستخدماً'),
            items: {
              for (final u in users) u.id: '${u.displayName} (${u.username})',
            },
            onChanged: (v) => setState(() => _existing = v),
          ),
          Align(
            alignment: AlignmentDirectional.bottomStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 22),
              child: FilledButton.icon(
                key: const Key('ef_link_user_save'),
                onPressed: !widget.canUsers || _existing == null
                    ? null
                    : () => _run(
                        context,
                        ref,
                        id,
                        () => ref.read(databaseProvider).linkEmployeeUser(
                            employeeId: id,
                            userId: _existing,
                            actorUserId: ref.read(authProvider).user?.id),
                        success: tr('تم ربط المستخدم')),
                icon: const Icon(PhosphorIconsBold.link, size: 16),
                label: Text(tr('ربط')),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Divider(color: context.picposHairline, height: 1),
        const SizedBox(height: 14),
        Text(tr('إنشاء مستخدم جديد للموظف'),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.picposText)),
        const SizedBox(height: 10),
        HrFieldGrid(children: [
          HrTextField(
            fieldKey: const Key('ef_new_username'),
            label: tr('اسم الدخول'),
            controller: _username,
            required: true,
            textDirection: TextDirection.ltr,
          ),
          HrTextField(
            fieldKey: const Key('ef_new_user_password'),
            label: tr('كلمة المرور'),
            controller: _password,
            required: true,
          ),
          HrDropdown<int>(
            fieldKey: const Key('ef_new_user_role'),
            label: tr('الدور'),
            value: _roleId,
            emptyLabel: tr('اختر دوراً'),
            items: {for (final r in roles) r.id: trData(r.name)},
            onChanged: (v) => setState(() => _roleId = v),
          ),
          if (keeper)
            HrDropdown<int>(
              label: tr('المخزن المسموح'),
              value: _warehouseId,
              emptyLabel: tr('كل المخازن'),
              items: {for (final w in warehouses) w.id: trData(w.name)},
              onChanged: (v) => setState(() => _warehouseId = v),
            ),
        ]),
        const SizedBox(height: 10),
        Text(
          p.branchId == null
              ? tr('سيُنشأ المستخدم بلا تقييد فرع.')
              : tr('سيُقيَّد المستخدم بفرع الموظف «{p0}».',
                  {'p0': trData(p.branchName ?? '')}),
          style: TextStyle(fontSize: 12, color: context.picposMuted),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            key: const Key('ef_create_user'),
            onPressed: !widget.canUsers ? null : () => _create(context),
            icon: const Icon(PhosphorIconsBold.userPlus, size: 16),
            label: Text(tr('إنشاء وربط')),
          ),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final p = widget.profile;
    final username = _username.text.trim();
    final password = _password.text.trim();
    if (username.length < 3 || password.length < 4 || _roleId == null) {
      AppToast.show(
          context,
          tr('أدخل اسم دخول (3 أحرف على الأقل) وكلمة مرور (4 أحرف) واختر الدور'),
          type: ToastType.error);
      return;
    }
    final repo = ref.read(authRepositoryProvider);
    final db = ref.read(databaseProvider);
    await _run(context, ref, p.id!, () async {
      if (await repo.getUserByUsername(username) != null) {
        throw HrException('اسم الدخول «{p0}» مستخدم.', {'p0': username});
      }
      final userId = await repo.createUser(
        username: username,
        password: password,
        displayName: p.name,
        roleId: _roleId,
      );
      if (p.branchId != null) {
        await repo.setUserBranchAccess(userId, [p.branchId!]);
      }
      if (_warehouseId != null) {
        await db.setUserWarehouseAccess(userId, [_warehouseId!]);
      }
      await db.linkEmployeeUser(
          employeeId: p.id!,
          userId: userId,
          actorUserId: ref.read(authProvider).user?.id);
    }, success: tr('تم إنشاء المستخدم وربطه بالموظف'));
  }
}
