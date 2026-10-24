// أقسامُ المراجعة الخاصة بالمقرّ والفرع والمرآة (‏عنوان/قيمة بروابط «تعديل»).
// لا تُعرض كلماتُ المرور ولا رمزُ الإقران — «••••••••» فقط للمسؤول.
import 'package:flutter/material.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../domain/models/first_run/first_run_draft.dart';
import '../../../../domain/models/first_run/first_run_path.dart';
import '../../../../domain/models/first_run/first_run_steps.dart';
import '../../../../domain/models/first_run/first_run_validation.dart';
import '../widgets/first_run_summary.dart';

String _scopeName(String scope) => switch (scope.toUpperCase()) {
      'HQ' => tr('المقر الرئيسي'),
      'ALL' => tr('جميع الفروع'),
      final code => code,
    };

/// أقسامٌ إضافيّةٌ لمسار المقرّ بعد أقسام الشركة المشتركة.
List<Widget> reviewHqSections(FirstRunDraft d, void Function(FirstRunStep) edit) {
  return [
    FirstRunSummarySection(
      title: tr('الفروع'),
      onEdit: () => edit(FirstRunStep.company),
      rows: [
        (tr('الفرع الرئيسي'), d.branchName.trim()),
        for (final b in d.branches) (b.code.trim(), b.name.trim()),
      ],
    ),
    FirstRunSummarySection(
      title: tr('قاعدة بيانات الخادم'),
      editKey: const Key('first_run_edit_storage'),
      onEdit: () => edit(FirstRunStep.storage),
      rows: [
        (tr('الخادم'), '${d.pgHost.trim()}:${d.pgPort.trim()}'),
        (tr('القاعدة'), d.pgDatabase.trim()),
        (tr('المستخدم'), d.pgUser.trim()),
      ],
    ),
    FirstRunSummarySection(
      title: tr('المستخدمون والصلاحيات'),
      onEdit: () => edit(FirstRunStep.users),
      rows: [
        (tr('المسؤول'), kFirstRunAdminUsername),
        (tr('كلمة المرور'), '••••••••'),
        for (final u in d.hqUsers)
          (
            u.username.trim(),
            '${u.roleName ?? '—'} / ${_scopeName(u.scope)}',
          ),
        (
          tr('الدخول دون اتصال'),
          tr('{p0} يوم بعد آخر تحقق ناجح', {'p0': d.offlineDays})
        ),
      ],
    ),
  ];
}

/// مراجعةُ الفرع: الربط ثم الفرع والحساب. لا بياناتِ شركةٍ تُكتب من هذا الجهاز.
List<Widget> reviewBranchSections(
  FirstRunDraft d,
  void Function(FirstRunStep) edit,
) {
  return [
    FirstRunSummarySection(
      title: tr('الربط بالرئيسي'),
      onEdit: () => edit(FirstRunStep.link),
      rows: [
        (tr('نوع النسخة'), tr('فرع تابع للسيرفر الرئيسي')),
        (tr('السيرفر'), '${d.endpoint.trim()}:${d.port.trim()}'),
        (tr('اسم الجهاز'), d.deviceName.trim()),
        (
          tr('دور الجهاز'),
          d.branchRole == BranchDeviceRole.first
              ? tr('أول جهاز في الفرع')
              : tr('جهاز إضافي داخل الفرع')
        ),
      ],
    ),
    FirstRunSummarySection(
      title: tr('الفرع والحساب'),
      onEdit: () => edit(FirstRunStep.firstSync),
      rows: [
        (tr('الفرع'), '${d.selectedBranchName} (${d.selectedBranchCode})'),
        (tr('المزامنة الأولى'), tr('تمت')),
        (tr('الحساب المعتمد'), d.accountUsername.trim()),
      ],
    ),
  ];
}

List<Widget> reviewMirrorSections(
  FirstRunDraft d,
  void Function(FirstRunStep) edit,
) {
  return [
    FirstRunSummarySection(
      title: tr('الربط بالرئيسي'),
      onEdit: () => edit(FirstRunStep.link),
      rows: [
        (tr('نوع النسخة'), tr('نسخة مرآة للسيرفر الرئيسي')),
        (tr('السيرفر'), '${d.endpoint.trim()}:${d.port.trim()}'),
        (tr('مدير الرئيسي'), d.accountUsername.trim()),
      ],
    ),
  ];
}

bool reviewIsCompanyPath(FirstRunPath p) =>
    p == FirstRunPath.standalone || p == FirstRunPath.hq;
