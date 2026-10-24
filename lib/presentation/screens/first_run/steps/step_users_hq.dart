// الخطوة ٤ (مقرّ) — المستخدمون والصلاحيات: المسؤول الأول وكلمةُ المطوّر (كما في
// المستقل) ثم جدولُ مستخدمي الفروع (الاسم · اسم الدخول · الدور من الأدوار
// المزروعة · نطاق الفرع · كلمةٌ أوليّة ≥ 8 يُجبَر المستخدمُ على تغييرها) وسياسةُ
// الدخول دون اتصال. كلماتُ المرور في الذاكرة فقط بمفتاح `rowId`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../domain/models/first_run/first_run_draft.dart';
import '../../../../domain/models/first_run/first_run_validation.dart';
import '../../../picpos_shell/picpos_surface.dart';
import '../first_run_controller.dart';
import '../first_run_providers.dart';
import '../widgets/first_run_callout.dart';
import '../widgets/first_run_field.dart';
import 'step_users_local.dart';

class StepUsersHq extends ConsumerWidget {
  const StepUsersHq({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(firstRunControllerProvider.select((s) => s.draft));
    final secrets = ref.watch(firstRunControllerProvider.select((s) => s.secrets));
    final ctl = ref.read(firstRunControllerProvider.notifier);
    final roles = ref.watch(firstRunRolesProvider).value ?? const [];

    void setUsers(List<FirstRunUserRow> rows) =>
        ctl.update((x) => x.copyWith(hqUsers: rows));

    void edit(int i, FirstRunUserRow Function(FirstRunUserRow r) f) {
      final rows = [...d.hqUsers];
      rows[i] = f(rows[i]);
      setUsers(rows);
    }

    final scopes = <(String, String)>[
      ('HQ', tr('المقر الرئيسي')),
      ('ALL', tr('جميع الفروع')),
      for (final b in d.branches)
        if (b.code.trim().isNotEmpty)
          (b.code.trim().toUpperCase(), '${b.code.trim()} — ${b.name.trim()}'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StepUsersLocal(),
        const SizedBox(height: 22),
        Text(
          tr('مستخدمو الفروع — إعداد أولي'),
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: context.picposText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tr('اختياري. كلمة المرور الأولية يُجبَر المستخدم على تغييرها عند أول دخول.'),
          style: TextStyle(fontSize: 12, color: context.picposMuted),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < d.hqUsers.length; i++)
          _UserCard(
            index: i,
            row: d.hqUsers[i],
            password: secrets.userPasswords[d.hqUsers[i].rowId] ?? '',
            roles: roles,
            scopes: scopes,
            onChange: (f) => edit(i, f),
            onPassword: (v) => ctl.updateSecrets((s) => s.copyWith(
                  userPasswords: {...s.userPasswords, d.hqUsers[i].rowId: v},
                )),
            onDelete: () {
              final rows = [...d.hqUsers]..removeAt(i);
              ctl.updateSecrets((s) => s.copyWith(
                    userPasswords: {...s.userPasswords}..remove(d.hqUsers[i].rowId),
                  ));
              setUsers(rows);
            },
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const Key('first_run_hq_user_add'),
            onPressed: () {
              final nextId = d.hqUsers.fold<int>(0, (m, u) => u.rowId > m ? u.rowId : m) + 1;
              setUsers([...d.hqUsers, FirstRunUserRow(name: '', username: '', rowId: nextId)]);
            },
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: Text(tr('إضافة مستخدم')),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          tr('سياسة الدخول دون اتصال للفروع'),
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: context.picposText,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButton<int>(
          key: const Key('first_run_offline_days'),
          value: kFirstRunOfflineDays.contains(d.offlineDays) ? d.offlineDays : null,
          items: [
            for (final n in kFirstRunOfflineDays)
              DropdownMenuItem(
                value: n,
                child: Text(tr('{p0} يوم بعد آخر تحقق ناجح', {'p0': n})),
              ),
          ],
          onChanged: (v) {
            if (v != null) ctl.update((x) => x.copyWith(offlineDays: v));
          },
        ),
        const SizedBox(height: 10),
        FirstRunCallout(
          title: tr('بعد انتهاء المدة يُطلب اتصال بالرئيسي لتجديد التحقق.'),
          body: tr('تُستعمل آخر صلاحيات متزامنة ضمن المدة المعتمدة.'),
          icon: Icons.schedule_outlined,
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.index,
    required this.row,
    required this.password,
    required this.roles,
    required this.scopes,
    required this.onChange,
    required this.onPassword,
    required this.onDelete,
  });

  final int index;
  final FirstRunUserRow row;
  final String password;
  final List<FirstRunRoleOption> roles;
  final List<(String, String)> scopes;
  final void Function(FirstRunUserRow Function(FirstRunUserRow r)) onChange;
  final ValueChanged<String> onPassword;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scopeValue = scopes.any((s) => s.$1 == row.scope.toUpperCase())
        ? row.scope.toUpperCase()
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.picposHairline),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FirstRunField(
                  key: Key('first_run_hq_user_name_$index'),
                  label: tr('الموظف'),
                  value: row.name,
                  onChanged: (v) => onChange((r) => r.copyWith(name: v)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FirstRunField(
                  key: Key('first_run_hq_user_username_$index'),
                  label: tr('اسم الدخول'),
                  value: row.username,
                  ltr: true,
                  onChanged: (v) => onChange((r) => r.copyWith(username: v)),
                ),
              ),
              IconButton(
                key: Key('first_run_hq_user_delete_$index'),
                tooltip: tr('حذف'),
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _Select<int>(
                  key: Key('first_run_hq_user_role_$index'),
                  label: tr('الدور'),
                  value: roles.any((r) => r.id == row.roleId) ? row.roleId : null,
                  items: [
                    for (final r in roles) DropdownMenuItem(value: r.id, child: Text(r.name)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    final role = roles.firstWhere((r) => r.id == v);
                    onChange((r) => r.copyWith(roleId: v, roleName: role.name));
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Select<String>(
                  key: Key('first_run_hq_user_scope_$index'),
                  label: tr('نطاق الفرع'),
                  value: scopeValue,
                  items: [
                    for (final s in scopes) DropdownMenuItem(value: s.$1, child: Text(s.$2)),
                  ],
                  onChanged: (v) {
                    if (v != null) onChange((r) => r.copyWith(scope: v));
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FirstRunField(
                  key: Key('first_run_hq_user_password_$index'),
                  label: tr('كلمة المرور الأولية'),
                  value: password,
                  obscure: true,
                  ltr: true,
                  onChanged: onPassword,
                ),
              ),
            ],
          ),
          SwitchListTile(
            key: Key('first_run_hq_user_force_$index'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(tr('يُلزم بتغيير كلمة المرور عند أول دخول')),
            subtitle: Text(tr('الخادم لا يمنح جلسة لحساب ملزم بالتغيير؛ عند تعطيله يعتمد جهاز الفرع الحساب مباشرة في الإعداد.')),
            value: row.forceChange,
            onChanged: (v) => onChange((r) => r.copyWith(forceChange: v)),
          ),
        ],
      ),
    );
  }
}

/// قائمةٌ منسدلةٌ متحكَّمٌ بها (‏تتبع قيمةَ المسودّة عند تغيّرها من الخارج).
class _Select<T> extends StatelessWidget {
  const _Select({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          isDense: true,
          value: value,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
