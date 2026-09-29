import 'package:ural_erp/core/i18n/tr.dart';
// Spec 078 — تقريرُ جاهزيّة صلاحيّات الخادم.
//
// ── لماذا لم يعد ديالوجَ تبديل ───────────────────────────────────────────
// كان يكتب المفتاحَ `server_per_user_perms_enabled` الذي يحكم بوّاباتِ
// الصلاحيّة الـ١٠٤ على الخادم. والمفتاحُ **لم يكن يُزرع في أيِّ تنصيب**
// (‏لا بذرةٌ ولا هجرةٌ ولا خريطةُ افتراضات)، وهذا الديالوجُ كاتبُه الوحيد —
// فكلُّ تنصيبةٍ لم يفتحها مشغِّلٌ يدوياً كانت تعمل بلا أيِّ فحصِ صلاحيّةٍ
// على الخادم. صار الفحصُ يُنفَّذ بلا شرط (`ApiUserCtx.requirePermission`)،
// فالمفتاحُ حُذف ومعه التبديل.
//
// وبقيت الأداةُ الحقيقيّة: **استطلاعُ المنح الناقصة ومنحُها**. وهي التي
// تُشغَّل قبل الطرح لتكشف دوراً ينقصه كودٌ فيُرفَض عملُه في الميدان.
//
// Visibility of the entry tile in settings_screen.dart is gated on
// PermissionCodes.rolesManage (the most relevant existing perm).

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/database/database.dart';
import '../../../../services/role_grant_preflight_service.dart';

class ServerPermsToggleDialog extends StatefulWidget {
  const ServerPermsToggleDialog({
    super.key,
    required this.db,
  });

  final AppDatabase db;

  static Future<bool?> show({
    required BuildContext context,
    required AppDatabase db,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ServerPermsToggleDialog(db: db),
    );
  }

  @override
  State<ServerPermsToggleDialog> createState() =>
      _ServerPermsToggleDialogState();
}

class _ServerPermsToggleDialogState extends State<ServerPermsToggleDialog> {
  late final RoleGrantPreflightService _svc;
  RolePreflightReport? _report;
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _svc = RoleGrantPreflightService(widget.db);
    _runPreflight();
  }

  Future<void> _runPreflight() async {
    setState(() => _loading = true);
    try {
      final report = await _svc.scanMissingGrants();
      if (mounted) setState(() => _report = report);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _grantDefaults() async {
    setState(() => _saving = true);
    try {
      final count = await _svc.grantMissingDefaults();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(count == 0
                ? tr('لم يكن هناك صلاحيات ناقصة لمنحها')
                : tr('تم منح {count} صلاحية للأدوار المعروفة', {'count': count})),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _runPreflight();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: _buildReportMode(),
    );
  }

  Widget _buildReportMode() {
    final report = _report;
    return AlertDialog(
      title:  Text(tr('جاهزية صلاحيات السيرفر')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _warningBanner(),
              const SizedBox(height: 16),
               Text(
                tr('فحص جاهزية الأدوار'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (report == null)
                const SizedBox.shrink()
              else
                _buildReportBody(report),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child:  Text(tr('إغلاق')),
        ),
        FilledButton(
          onPressed: _saving ? null : _runPreflight,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              :  Text(tr('إعادة الفحص')),
        ),
      ],
    );
  }

  Widget _warningBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child:  Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(PhosphorIconsBold.warning, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr('فحصُ الصلاحيات على السيرفر **مُفعَّلٌ دائماً** — السيرفر يرفض أي عملية يقوم بها مستخدم لا يملك صلاحيتها (مثلاً: كاشير يحاول حذف فاتورة بدون صلاحية sales_delete). الفحصُ أدناه يكشف الأدوارَ التي ينقصها منحٌ فيُرفَض عملُها في الميدان — شغّله بعد أي تعديل على الأدوار.'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportBody(RolePreflightReport report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (report.knownRolesAreReady)
          _readyChip()
        else
          _gapsList(report),
        if (report.customRolesPresent.isNotEmpty) ...[
          const SizedBox(height: 12),
          _customRolesNote(report.customRolesPresent),
        ],
      ],
    );
  }

  Widget _readyChip() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child:  Row(
        children: [
          const Icon(PhosphorIconsBold.checkCircle, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('كل الأدوار المعروفة جاهزة للتشغيل'),
              style: const TextStyle(color: AppColors.success),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gapsList(RolePreflightReport report) {
    final roleCount = report.missingByKnownRole.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.warning, color: AppColors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('{roleCount} دور يحتاج صلاحيات إضافية ({p0} صلاحية ناقصة)', {'roleCount': roleCount, 'p0': report.totalMissingPairs}),
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...report.missingByKnownRole.entries.map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.key,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 12),
                  child: Text(
                    e.value.join(tr('، ')),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : _grantDefaults,
          icon: const Icon(PhosphorIconsBold.shieldPlus, size: 18),
          label:  Text(tr('امنح الصلاحيات الناقصة تلقائياً (الأدوار المعروفة)')),
        ),
      ],
    );
  }

  Widget _customRolesNote(List<String> customRoles) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Row(
            children: [
              const Icon(PhosphorIconsBold.info, color: AppColors.info, size: 18),
              const SizedBox(width: 6),
              Text(
                tr('أدوار مخصّصة (يلزم منحها الصلاحيات يدوياً)'),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 24),
            child: Text(
              customRoles.join(tr('، ')),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 6),
           Padding(
            padding: const EdgeInsetsDirectional.only(start: 24),
            child: Text(
              tr('هذه الأدوار خارج المصفوفة الافتراضية. تأكد من منحها الصلاحيات المناسبة من شاشة "إدارة صلاحيات الأدوار" قبل التفعيل، وإلا سيواجه مستخدموها أخطاء 403.'),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
