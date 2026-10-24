// تحقّقُ خطواتِ الإعداد الأول — دوالُّ خالصة تُرجع [FirstRunIssue] (‏رمزاً) لا نصّاً:
// هذا الدليلُ بلا Flutter فلا `tr()` فيه، وطبقةُ العرض تحوّل الرمزَ إلى رسالةٍ
// مترجَمة (‏`first_run_issue_text.dart`). الرسائلُ مقتبسةٌ من النموذج §0.4
// **دون** تحقّقات التفعيل [ملغى — قرار المالك 2].
library;

import 'first_run_currency.dart';
import 'first_run_draft.dart';
import 'first_run_path.dart';
import 'first_run_steps.dart';

/// أدنى طولٍ لكلمة مرور المسؤول ولكلمات مستخدمي الفروع الأولية (‏E11).
const int kFirstRunPasswordMin = 8;

/// أدنى طولٍ لكلمة مرور المطوّر (‏كما في المعالج القديم).
const int kFirstRunDeveloperPasswordMin = 4;

/// أقصى طولٍ لرمز الفرع — حدُّ عمود `branches.code`.
const int kFirstRunBranchCodeMax = 10;

/// اسمُ دخول المسؤول — للقراءة فقط في المعالج (‏B20 / E12 / SEC-001).
const String kFirstRunAdminUsername = 'admin';

enum FirstRunIssue {
  companyNameRequired,
  currencyRequired,
  currencyUnsupported,
  fiscalYearInvalid,
  branchNameRequired,
  warehouseRequired,
  branchCodeTooLong,
  branchRowsIncomplete,
  branchCodesDuplicate,
  adminPasswordShort,
  adminPasswordMismatch,
  developerPasswordShort,
  developerPasswordMismatch,
  userRowsIncomplete,
  usernamesDuplicate,
  userScopeInvalid,
  tablesCountInvalid,
  endpointRequired,
  portInvalid,
  deviceNameRequired,
  linkNotVerified,
  storageNotChecked,
  serverNotProvisioned,
  firstSyncPending,
  accountNotVerified,
  pgHostRequired,
  pgPortInvalid,
  pgDatabaseRequired,
  pgUserRequired,
  userPasswordShort,
  userPasswordWeak,
  userPasswordDuplicate,
  offlineDaysInvalid,
  branchNotSelected,
  mirrorAdminRequired,
}

/// مدد السماح المقبولة للدخول دون اتصال (أيام) — النموذج §0.3.
const List<int> kFirstRunOfflineDays = [1, 3, 7, 14, 30];

/// سببُ فشل أوّل خطوةٍ في [validateAll].
class FirstRunStepIssue {
  const FirstRunStepIssue(this.step, this.issue);
  final FirstRunStep step;
  final FirstRunIssue issue;
}

String _norm(String s) => s.trim().toUpperCase();

/// أوّلُ مشكلةٍ في [step]، أو `null` إن صحّت.
FirstRunIssue? validateStep(
  FirstRunStep step,
  FirstRunDraft d,
  FirstRunSecrets s,
) {
  switch (step) {
    case FirstRunStep.mode:
    case FirstRunStep.review:
    case FirstRunStep.success:
      return null;
    case FirstRunStep.company:
      return _company(d);
    case FirstRunStep.storage:
      if (d.path == FirstRunPath.hq) return _postgres(d);
      return d.checks.storageChecked ? null : FirstRunIssue.storageNotChecked;
    case FirstRunStep.users:
      return _users(d, s);
    case FirstRunStep.prep:
      if (d.pack.hasTables && d.serviceType.tables) {
        final n = int.tryParse(d.tablesCount.trim());
        if (!RegExp(r'^\d+$').hasMatch(d.tablesCount.trim()) ||
            n == null ||
            n > 1000) {
          return FirstRunIssue.tablesCountInvalid;
        }
      }
      return null;
    case FirstRunStep.link:
      if (d.endpoint.trim().isEmpty) return FirstRunIssue.endpointRequired;
      final port = int.tryParse(d.port.trim());
      if (port == null || port < 1 || port > 65535) {
        return FirstRunIssue.portInvalid;
      }
      if (d.path == FirstRunPath.mirror) {
        if (d.accountUsername.trim().isEmpty) {
          return FirstRunIssue.mirrorAdminRequired;
        }
      } else if (d.deviceName.trim().isEmpty) {
        return FirstRunIssue.deviceNameRequired;
      }
      return d.checks.linked ? null : FirstRunIssue.linkNotVerified;
    case FirstRunStep.firstSync:
      if (!d.checks.firstSyncDone) return FirstRunIssue.firstSyncPending;
      return d.selectedBranchId == null ? FirstRunIssue.branchNotSelected : null;
    case FirstRunStep.account:
      return d.checks.accountVerified ? null : FirstRunIssue.accountNotVerified;
  }
}

FirstRunIssue? _postgres(FirstRunDraft d) {
  if (d.pgHost.trim().isEmpty) return FirstRunIssue.pgHostRequired;
  final port = int.tryParse(d.pgPort.trim());
  if (port == null || port < 1 || port > 65535) {
    return FirstRunIssue.pgPortInvalid;
  }
  if (d.pgDatabase.trim().isEmpty) return FirstRunIssue.pgDatabaseRequired;
  if (d.pgUser.trim().isEmpty) return FirstRunIssue.pgUserRequired;
  return d.checks.provisioned ? null : FirstRunIssue.serverNotProvisioned;
}

FirstRunIssue? _company(FirstRunDraft d) {
  if (d.companyName.trim().isEmpty) return FirstRunIssue.companyNameRequired;
  if (d.currency.isEmpty) return FirstRunIssue.currencyRequired;
  if (!kFirstRunCurrencies.contains(d.currency)) {
    return FirstRunIssue.currencyUnsupported;
  }
  if (d.fiscalYear < 2000 || d.fiscalYear > 9999) {
    return FirstRunIssue.fiscalYearInvalid;
  }
  if (d.branchName.trim().isEmpty) return FirstRunIssue.branchNameRequired;
  if (d.warehouseName.trim().isEmpty) return FirstRunIssue.warehouseRequired;
  if (d.branchCode.trim().length > kFirstRunBranchCodeMax) {
    return FirstRunIssue.branchCodeTooLong;
  }
  if (d.path == FirstRunPath.hq) {
    final seen = <String>{};
    for (final b in d.branches) {
      if (b.code.trim().isEmpty || b.name.trim().isEmpty) {
        return FirstRunIssue.branchRowsIncomplete;
      }
      if (b.code.trim().length > kFirstRunBranchCodeMax) {
        return FirstRunIssue.branchCodeTooLong;
      }
      if (!seen.add(_norm(b.code))) return FirstRunIssue.branchCodesDuplicate;
    }
  }
  return null;
}

FirstRunIssue? _users(FirstRunDraft d, FirstRunSecrets s) {
  final p = s.adminPassword;
  if (p.length < kFirstRunPasswordMin) return FirstRunIssue.adminPasswordShort;
  if (p != s.adminPasswordConfirm) return FirstRunIssue.adminPasswordMismatch;
  final dev = s.developerPassword.trim();
  if (dev.length < kFirstRunDeveloperPasswordMin) {
    return FirstRunIssue.developerPasswordShort;
  }
  if (dev != s.developerPasswordConfirm.trim()) {
    return FirstRunIssue.developerPasswordMismatch;
  }
  if (d.path == FirstRunPath.hq) {
    if (!kFirstRunOfflineDays.contains(d.offlineDays)) {
      return FirstRunIssue.offlineDaysInvalid;
    }
    final names = <String>{kFirstRunAdminUsername};
    // الخادمُ يرفض كلمتين متطابقتين لمستخدمين مختلفين (‏DuplicatePasswordException).
    final passwords = <String>{p};
    final scopes = <String>{
      'HQ',
      'ALL',
      for (final b in d.branches) _norm(b.code),
    };
    for (final u in d.hqUsers) {
      if (u.name.trim().isEmpty ||
          u.username.trim().isEmpty ||
          u.roleId == null) {
        return FirstRunIssue.userRowsIncomplete;
      }
      if (!names.add(u.username.trim().toLowerCase())) {
        return FirstRunIssue.usernamesDuplicate;
      }
      if (!scopes.contains(_norm(u.scope))) {
        return FirstRunIssue.userScopeInvalid;
      }
      final pw = s.userPasswords[u.rowId] ?? '';
      if (pw.length < kFirstRunPasswordMin) return FirstRunIssue.userPasswordShort;
      final lower = pw.toLowerCase();
      if (lower == kFirstRunAdminUsername ||
          lower == u.username.trim().toLowerCase()) {
        return FirstRunIssue.userPasswordWeak;
      }
      if (!passwords.add(pw)) return FirstRunIssue.userPasswordDuplicate;
    }
  }
  return null;
}

/// أوّلُ خطوةٍ فاشلةٍ في مسار [d] (‏ما عدا المراجعة)، أو `null` إن صحّ كلُّه.
/// «التالي» في المراجعة يعيد هذا التحقّق ويقفز إلى الخطوة الفاشلة.
FirstRunStepIssue? validateAll(FirstRunDraft d, FirstRunSecrets s) {
  for (final step in stepsFor(d.path)) {
    final issue = validateStep(step, d, s);
    if (issue != null) return FirstRunStepIssue(step, issue);
  }
  return null;
}
