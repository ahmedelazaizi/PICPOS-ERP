// J4 — «ملف الموظف» (PicPos): صفحةٌ كاملةٌ بستّة تبويبات — البيانات
// الشخصية · الوظيفية · العقد والأجر · المستندات · السجل · الدور في النظام.
// الحفظُ واحدٌ للتبويبات الثلاثة الأولى (‏`saveEmployeeProfile` يسجّل
// الأحداثَ آليّاً)، والمستنداتُ والأدوارُ تُحفَظ فورَ كلّ إجراء.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/hr_employee_file.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_labels.dart';
import '../hr_picpos_providers.dart';
import '../widgets/hr_form_kit.dart';
import 'ef_attendance_tab.dart';
import 'ef_documents_tab.dart';
import 'ef_history_tab.dart';
import 'ef_leave_tab.dart';
import 'ef_job_tab.dart';
import 'ef_pay_tab.dart';
import 'ef_personal_tab.dart';
import 'ef_roles_tab.dart';
import 'employee_file_form.dart';

/// يفتح ملفَّ الموظف ([employeeId] null ⇒ موظفٌ جديد).
Future<void> openEmployeeFile(BuildContext context, {int? employeeId}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HrEmployeeFileScreen(employeeId: employeeId),
    ));

class HrEmployeeFileScreen extends ConsumerStatefulWidget {
  const HrEmployeeFileScreen({super.key, this.employeeId, this.initialTab = 0});
  final int? employeeId;
  final int initialTab;

  @override
  ConsumerState<HrEmployeeFileScreen> createState() =>
      _HrEmployeeFileScreenState();
}

class _HrEmployeeFileScreenState extends ConsumerState<HrEmployeeFileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 8, vsync: this, initialIndex: widget.initialTab);
  late int? _id = widget.employeeId;
  EmployeeFileForm? _form;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final id = _id;
    final profile = id == null ? null : await db.getEmployeeProfile(id);
    final allowances =
        id == null ? const <EmployeeAllowance>[] : await db.listEmployeeAllowances(id);
    if (!mounted) return;
    final old = _form;
    setState(() => _form = EmployeeFileForm(profile, allowances: allowances));
    old?.dispose();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _form?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final form = _form;
    if (form == null || _saving) return;
    if (form.name.text.trim().isEmpty) {
      _tabs.animateTo(0);
      AppToast.show(context, tr('اسم الموظف مطلوب.'), type: ToastType.error);
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ref.read(databaseProvider).saveEmployeeProfile(
            form.toProfile(),
            allowances: form.toAllowances(),
            actorUserId: ref.read(authProvider).user?.id,
          );
      _id = id;
      refreshHr(ref, id);
      await _load();
      if (mounted) AppToast.show(context, tr('تم حفظ ملف الموظف'));
    } catch (e, st) {
      if (!mounted) return;
      if (e is HrException) {
        AppToast.show(context, e.message, type: ToastType.error);
      } else {
        AppErrorHandler.handle(context, e, st);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = _form;
    final canManage =
        ref.watch(hasPermissionProvider(PermissionCodes.hrManage)).value ??
            false;
    final source = form?.source;
    // كودُ الموظف ومسمّاه وقسمُه بيانات — تُترجَم أجزاءً (‏`trData`) وتُعرض
    // سطراً فوق التبويبات، لا عنواناً فرعيّاً يمرّره الرأسُ كاملاً في `tr`.
    final meta = source == null
        ? null
        : [
            source.code,
            if (source.jobTitleName != null) trData(source.jobTitleName),
            if (source.departmentName != null) trData(source.departmentName),
          ].whereType<String>().join(' · ');
    return PicPosScreenScaffold(
      title: source == null ? tr('موظف جديد') : source.name,
      subtitle: source == null ? tr('ملف الموظف') : null,
      icon: PhosphorIconsBold.identificationCard,
      headerActions: [
        if (source != null) ...[
          HrPill(
            label: hrStatusLabel(source.status),
            color: hrStatusColor(context, source.status),
          ),
          const SizedBox(width: 10),
        ],
        FilledButton.icon(
          key: const Key('ef_save'),
          onPressed: form == null || _saving || !canManage ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(PhosphorIconsBold.floppyDisk, size: 16),
          label: Text(tr('حفظ')),
        ),
      ],
      subHeader: Container(
        decoration: BoxDecoration(
          color: context.picposCard,
          border: Border(bottom: BorderSide(color: context.picposHairline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (meta != null && meta.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 0),
                child: Text(
                  meta,
                  key: const Key('ef_meta'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.picposMuted),
                ),
              ),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: context.picposMuted,
              tabs: [
                for (final (key, icon, label) in [
                  ('personal', PhosphorIconsBold.user, tr('البيانات الشخصية')),
                  ('job', PhosphorIconsBold.briefcase, tr('البيانات الوظيفية')),
                  ('pay', PhosphorIconsBold.money, tr('العقد والأجر')),
                  ('documents', PhosphorIconsBold.files, tr('المستندات')),
                  ('attendance', PhosphorIconsBold.fingerprint, tr('الحضور')),
                  ('leave', PhosphorIconsBold.airplaneTilt, tr('الإجازات')),
                  ('history', PhosphorIconsBold.clockCounterClockwise,
                      tr('السجل')),
                  ('roles', PhosphorIconsBold.key, tr('الدور في النظام')),
                ])
                  Tab(
                    key: Key('ef_tab_$key'),
                    icon: Icon(icon, size: 18),
                    text: label,
                  ),
              ],
            ),
          ],
        ),
      ),
      body: form == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                EfPersonalTab(form: form),
                EfJobTab(form: form),
                EfPayTab(form: form),
                EfDocumentsTab(employeeId: _id),
                EfAttendanceTab(employeeId: _id, name: source?.name ?? ''),
                EfLeaveTab(employeeId: _id),
                EfHistoryTab(employeeId: _id),
                EfRolesTab(employeeId: _id),
              ],
            ),
    );
  }
}
