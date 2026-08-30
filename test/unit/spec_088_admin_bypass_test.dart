// ═══════════════════════════════════════════════════════════════════════════
// SPEC 088 USR-1 — Server-side bootstrap-admin permission bypass (source pins)
// ═══════════════════════════════════════════════════════════════════════════
//
// Field bug: on a mirror device, admin (userId=1) hit 403 from the central
// server's per-user permission middleware on calls like /api/branches
// (POST), /api/shifts (open) etc. — even though Spec 086 added matrix
// safety-net entries. The matrix path is best-effort; future codes can be
// added without re-running grantMissingDefaults() in time. The durable
// fix is a server-side bypass that short-circuits the permission check
// when the caller is the bootstrap admin (userId=1, per Spec 061).
//
// These pins ensure:
//   1. The bypass uses the canonical isBootstrapAdmin predicate.
//   2. The bypass runs AFTER the 401 (missing X-User-Id) guard and BEFORE
//      the userHasPermission DB lookup — so admin's missing matrix rows
//      never matter.
//   3. The one-shot PERMS-WARN log line is wired so field operators can
//      grep for "bootstrap admin bypass engaged" after rollout.
//
// See specs/088-mirror-hotfix-pack/contracts/permission-bypass.md.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spec 088 USR-1 — bootstrap-admin server bypass', () {
    final src =
        File('lib/services/api/api_user_context.dart').readAsStringSync();

    test('imports the canonical isBootstrapAdmin predicate', () {
      expect(src, contains("import '../../core/auth/bootstrap_admin.dart'"),
          reason:
              'USR-1 must reuse the Spec 061 canonical predicate. Inlining '
              '`userId == 1` would silently miss the username-fallback case '
              'and split the invariant across two source files.');
    });

    test('imports DiagnosticLogger for PERMS-WARN line', () {
      expect(src,
          contains("import '../../core/logging/diagnostic_logger.dart'"),
          reason:
              'The one-shot PERMS-WARN line is the only way the field can '
              'confirm the bypass is engaged on a deployed build.');
    });

    test('bypass runs BEFORE the userHasPermission DB lookup', () {
      final bypassIdx = src.indexOf('isBootstrapAdmin(userId)');
      final lookupIdx = src.indexOf('db.userHasPermission(userId, code)');
      expect(bypassIdx, isNot(-1),
          reason: 'isBootstrapAdmin guard must exist inside requirePermission.');
      expect(lookupIdx, isNot(-1));
      expect(bypassIdx < lookupIdx, isTrue,
          reason: 'Ordering matters: the bypass must short-circuit BEFORE '
              'the DB lookup, otherwise admin with no matrix rows still '
              'returns 403 (the exact field bug).');
    });

    test('bypass runs AFTER the 401 missing-session guard', () {
      final missingIdx = src.indexOf('Missing or invalid X-Session-Token');
      final bypassIdx = src.indexOf('isBootstrapAdmin(userId)');
      expect(missingIdx, isNot(-1),
          reason: 'الرسالةُ تسمّي `X-Session-Token` — الترويسةَ التي تُقرأ '
              'فعلاً. و`X-User-Id` لم تعد تُقرأ منذ توكن الجلسة الموقَّع.');
      expect(bypassIdx, isNot(-1));
      expect(missingIdx < bypassIdx, isTrue,
          reason: 'Order: the 401 guard for a missing session must still run '
              'first. Otherwise a request with no verified identity would '
              'crash on the null check inside isBootstrapAdmin.');
    });

    // ⚠️ كان هنا حارسٌ اسمُه «per-user-perms-disabled path is preserved»
    // يشترط وجودَ السطر `if (!await isPerUserPermsEnabled(db)) return null`
    // نصّاً. وهو **يثبّت العطب**: ذلك السطرُ كان يُعطّل ١٠٤ بوّاباتِ صلاحيّةٍ
    // على كلِّ تنصيبةٍ في الميدان، لأنّ المفتاحَ لا يُزرع في أيِّ بذرةٍ أو
    // هجرةٍ أو خريطةِ افتراضات. حُذف السطرُ ومعه هذا الحارس، وحلَّ محلَّه
    // نقيضُه: لا شرطَ يسبق البوّابة.
    test('لا شرطَ يسبق البوّابة — لا مفتاحَ ولا قراءةَ إعداد', () {
      // ⚠️ **الفحصُ على الكود لا على النصّ الخام.** أوّلُ صياغتَين لهذا
      // الحارس سقطتا على **تعليقٍ** يشرح لماذا حُذف المفتاح: الحارسُ يقرأ
      // التعليقاتِ كما يقرأ الكود، فذِكرُ الاسم في شرحٍ يُقرأ استعمالاً.
      final codeOnly = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      final start = codeOnly.indexOf('Future<Response?> requirePermission(');
      expect(start, isNot(-1),
          reason: 'مرساةٌ — تجريدُ التعليقات لم يُفرِغ الملفَّ ولا الدالّة.');
      final block = codeOnly.substring(start, start + 900);

      // مرساةٌ ثانية: الكتلةُ المقتطعةُ تحوي فعلاً جسمَ الدالّة.
      expect(block, contains('userIdOf(request)'),
          reason: 'مرساةٌ — لولاها لمرّت التوكيداتُ التاليةُ على نصٍّ فارغ.');

      expect(block, isNot(contains('isPerUserPermsEnabled')),
          reason: 'عودةُ المفتاح تعني عودةَ ١٠٤ بوّاباتٍ معطَّلةٍ افتراضاً.');
      expect(codeOnly, isNot(contains('server_per_user_perms_enabled')),
          reason: 'المفتاحُ محذوفٌ من الطبقة كلِّها، لا من نداءٍ واحد.');
    });

    test('one-shot bypass-logged flag exists', () {
      expect(src, contains('static bool _bootstrapBypassLogged = false'),
          reason: 'Without the static flag the PERMS-WARN line would fire '
              'on every admin request, drowning the diagnostic log. The '
              'flag flips on first fire and silences subsequent calls.');
      expect(src, contains('_bootstrapBypassLogged = true'),
          reason: 'The flag must actually be flipped after the first emit.');
    });

    test('PERMS-WARN line carries the canonical text field operators grep for',
        () {
      expect(src, contains("'bootstrap admin bypass engaged (userId="),
          reason: 'The exact phrase is the contract — quickstart.md '
              'instructs field operators to grep for it after a smoke '
              'build. Changing the wording silently breaks the smoke.');
    });
  });
}
