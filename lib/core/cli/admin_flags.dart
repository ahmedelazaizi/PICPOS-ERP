// أعلام الاسترداد الحساسة لسطر الأوامر/البيئة (S-05 / S-11):
//   --reset-dev-password · --reset-admin-password · --purge-users ·
//   --reset-setup-wizard
// (وما يقابلها من متغيرات `<PREFIX>_RESET_DEV_PASSWORD` … `_PURGE_USERS`).
//
// كانت تُنفَّذ بلا أي شرط، ولا يُكتب لها تدقيق. الآن:
//   1. لا تُنفَّذ إلا مع «إثبات حضور» على الجهاز: ملف تأكيد محلي حديث
//      (`recovery_confirm.txt` في مجلد البيانات، عمره ≤ 15 دقيقة) يُستهلك
//      (يُحذف) عند أول استخدام. تفعيله عن بُعد بوسيط/متغير بيئة وحده لا يكفي.
//   2. كل تنفيذ أو رفض يُسجَّل حدث تدقيق critical (يُخزَّن مؤقتاً داخل
//      AuditLog إن لم تكن مهيّأة بعد ويُفرَّغ عند configure).
import 'dart:io';

import 'package:picpos_erp/core/config/support_env.dart';
import 'package:picpos_erp/services/audit_log.dart';

/// اسم ملف التأكيد المحلي الذي ينشئه الفني بيده في مجلد البيانات.
const String kRecoveryConfirmFileName = 'recovery_confirm.txt';

/// أقصى عمر مقبول لملف التأكيد.
const Duration kRecoveryConfirmMaxAge = Duration(minutes: 15);

/// الأعلام المطلوبة فعلاً في [args]/[env] (الترتيب = ترتيب التنفيذ).
class AdminFlagRequest {
  const AdminFlagRequest({
    required this.resetDevPassword,
    required this.purgeUsers,
    required this.resetAdminPassword,
    this.resetSetupWizard = false,
  });

  /// [allowDevReset]=false (بناء الإصدار، ISS-SEC-02) يتجاهل علمَي كلمة المطوّر ومعالج الإعداد.
  factory AdminFlagRequest.parse(List<String> args, Map<String, String> env,
          {bool allowDevReset = true}) =>
      AdminFlagRequest(
        resetDevPassword: allowDevReset &&
            (args.contains('--reset-dev-password') ||
                supportEnvFlag(env, 'RESET_DEV_PASSWORD')),
        purgeUsers:
            args.contains('--purge-users') || supportEnvFlag(env, 'PURGE_USERS'),
        resetAdminPassword: args.contains('--reset-admin-password') ||
            supportEnvFlag(env, 'RESET_ADMIN_PASSWORD'),
        // مُعطَّل في بناء الإصدار كعلم كلمة المطوّر (قرار المالك).
        resetSetupWizard: allowDevReset &&
            (args.contains('--reset-setup-wizard') ||
                supportEnvFlag(env, 'RESET_SETUP_WIZARD')),
      );

  final bool resetDevPassword;
  final bool purgeUsers;
  final bool resetAdminPassword;
  final bool resetSetupWizard;

  bool get any =>
      resetDevPassword || purgeUsers || resetAdminPassword || resetSetupWizard;
}

/// يتحقق من ملف التأكيد في [dir] ويستهلكه (يحذفه). `true` فقط إن وُجد وحديث.
/// الملف القديم يُحذف أيضاً كي لا يبقى صالحاً لاحقاً.
Future<bool> consumeRecoveryConfirmation(
  Directory dir, {
  DateTime? now,
}) async {
  try {
    final f = File('${dir.path}${Platform.pathSeparator}$kRecoveryConfirmFileName');
    if (!await f.exists()) return false;
    final age = (now ?? DateTime.now()).difference(await f.lastModified());
    await f.delete();
    return !age.isNegative && age <= kRecoveryConfirmMaxAge;
  } catch (_) {
    return false;
  }
}

/// ينفّذ الأعلام المطلوبة إن وُجد تأكيد. بلا أعلام لا يفعل شيئاً (ولا يستدعي
/// [confirm]). عند غياب التأكيد يرفض الكل ولا يستدعي أي إجراء.
/// يعيد أسماء الأعلام المنفّذة.
Future<List<String>> runAdminFlags({
  required AdminFlagRequest request,
  required Future<bool> Function() confirm,
  required Future<void> Function() resetDevPassword,
  required Future<void> Function() purgeUsers,
  required Future<void> Function() resetAdminPassword,
  required Future<void> Function() resetSetupWizard,
}) async {
  if (!request.any) return const [];

  final requested = <String>[
    if (request.resetDevPassword) 'reset-dev-password',
    if (request.purgeUsers) 'purge-users',
    if (request.resetAdminPassword) 'reset-admin-password',
    if (request.resetSetupWizard) 'reset-setup-wizard',
  ];

  if (!await confirm()) {
    await AuditLog.record(
      'admin_flag_refused',
      level: AuditLevel.critical,
      payload: {'flags': requested, 'reason': 'no_local_confirmation'},
    );
    stderr.writeln('[RECOVERY] refused $requested: create a fresh '
        '$kRecoveryConfirmFileName in the data folder and retry.');
    return const [];
  }

  final done = <String>[];
  Future<void> run(String name, String event, Future<void> Function() act) async {
    try {
      await act();
      done.add(name);
      await AuditLog.record(event,
          level: AuditLevel.critical, payload: {'flag': name, 'ok': true});
    } catch (e) {
      await AuditLog.record(event,
          level: AuditLevel.critical,
          payload: {'flag': name, 'ok': false, 'error': e.toString()});
    }
  }

  if (request.resetDevPassword) {
    // `DeveloperAuthService.clear()` يسجّل أيضاً `developer_password_reset`؛
    // هذا الحدث يوثّق أن السبب علم الاسترداد ونتيجته.
    await run('reset-dev-password', 'developer_password_reset_flag',
        resetDevPassword);
  }
  if (request.purgeUsers) {
    await run('purge-users', 'users_purged', purgeUsers);
  }
  if (request.resetAdminPassword) {
    await run('reset-admin-password', 'admin_password_reset', resetAdminPassword);
  }
  if (request.resetSetupWizard) {
    await run('reset-setup-wizard', 'setup_wizard_reset', resetSetupWizard);
  }
  return done;
}
