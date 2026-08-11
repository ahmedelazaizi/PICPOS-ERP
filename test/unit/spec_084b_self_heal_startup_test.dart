// ═══════════════════════════════════════════════════════════════════════════
// SPEC 084b — Self-heal startup grant for matrix defaults
// ═══════════════════════════════════════════════════════════════════════════
//
// Pins:
//   1. The startup hook in `_syncPermissionsAndAccounts` calls
//      RoleGrantPreflightService.grantMissingDefaults() — without this
//      call, matrix additions don't propagate to existing installs.
//   2. The call is gated on the !isClient branch — clients pull
//      role_permissions from the server and must NOT self-heal locally.
//   3. The call is non-fatal — wrapped in try/catch so a self-heal
//      failure (e.g. transient DB lock) doesn't block app startup.
//   4. The semantics are idempotent at the service layer
//      (`grantMissingDefaults` returns 0 on the second call once the
//      first one applied everything).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spec 084b — startup hook source pins', () {
    late String src;

    setUpAll(() {
      src = File('lib/data/database/database_startup.dart').readAsStringSync();
    });

    test('startup calls RoleGrantPreflightService.grantMissingDefaultsOnce',
        () {
      expect(
          src,
          contains(
              'RoleGrantPreflightService(this).grantMissingDefaultsOnce()'),
          reason: 'Without this call, matrix updates (Spec 084 onward) '
              'never propagate to existing installs and operators have '
              'to remember the "Grant defaults" button after every upgrade.');
    });

    // بلاغٌ ميدانيّ 2026-08-11: «مع تحديد الصلاحيات للمستخدم لا تنطبق
    // للمستخدم» — الدورُ كاشير، أُعِدّ من حساب المدير، ثم خروجٌ ودخول.
    //
    // النداءُ **العاري** كان يُدرج كلَّ ما تمنحه المصفوفةُ وينقص الدور، وهو
    // يرى النزعَ نقصاً فيردّه. فيُحفظ قرارُ المشغّل صحيحاً ثم يُنقض عند أوّل
    // إقلاع. والفرقُ بين الاسمين حرفان — يمرّان في المراجعة بلا انتباه،
    // ولذلك حارسٌ عليهما.
    test('ولا يُنادى العاري من الإقلاع — يدوس نزعَ المشغّل', () {
      final bare = RegExp(
          r'RoleGrantPreflightService\(this\)\.grantMissingDefaults\(\)');
      expect(bare.hasMatch(src), isFalse,
          reason: 'النداءُ العاري يُعيد في كلّ إقلاعٍ ما نزعه المشغّل من '
              'شاشة الصلاحيات. المسيَّجُ بالبصمة (`…Once`) يُبقي ترقياتِ '
              'المصفوفة تصل ولا يدوس قراراً صريحاً.');
    });

    test('self-heal lives in the !isClient branch (server-only)', () {
      // The self-heal call must appear AFTER the server-mode
      // syncAllPermissions invocation and within the same scope. Tie
      // it to the awaited syncAllPermissions and verify the grantMissing
      // call appears within a bounded window after it.
      final syncIdx = src.indexOf('await syncAllPermissions();');
      expect(syncIdx, isNot(-1),
          reason: 'Could not locate the server-mode syncAllPermissions '
              'call — structure changed; update this guard.');
      // 1500 chars covers the syncAllPermissions try block + comment +
      // self-heal try block comfortably.
      final scope = src.substring(
          syncIdx, (syncIdx + 1500).clamp(0, src.length));
      expect(scope, contains('grantMissingDefaults'),
          reason: 'Self-heal must run only when isClient is false; '
              'a client running this would corrupt the server-authoritative '
              'role_permissions state on the mirror.');
    });

    test('self-heal is non-fatal (wrapped in try/catch)', () {
      // Pin the exact try/catch shape so a future refactor that drops
      // the catch (and accidentally lets exceptions bubble up to block
      // startup) fails here.
      final selfHealStart = src.indexOf(
          'await RoleGrantPreflightService(this).grantMissingDefaultsOnce()');
      expect(selfHealStart, isNot(-1));

      // Walk backwards: there must be a `try {` within ~200 chars before.
      final pre = src.substring(
          (selfHealStart - 200).clamp(0, selfHealStart), selfHealStart);
      expect(pre, contains('try {'),
          reason: 'The self-heal call must be inside a try block — a '
              'transient DB lock on the grants table must not block '
              'app boot.');

      // And a `} catch (` within ~500 chars after.
      final post =
          src.substring(selfHealStart, (selfHealStart + 500).clamp(0, src.length));
      expect(post, contains('} catch ('),
          reason: 'No matching catch — exceptions would bubble through '
              'beforeOpen and the app would refuse to start.');
    });

    test('a count > 0 is surfaced to the diagnostic log', () {
      // Support needs to see "self-heal applied N grants" in the log so
      // they can correlate "upgraded to +147 → cashier started working
      // without any operator click" with the grant event.
      expect(src, contains('GRANT-SELFHEAL'),
          reason: 'Log tag missing — first-boot self-heal would be '
              'invisible to support.');
      expect(src, contains('applied \$inserted missing matrix grants'),
          reason: 'Diagnostic message template missing — the support log '
              'must record the count so an operator complaint of '
              '"cashier still 403\'s" can be cross-checked against '
              'whether self-heal ran.');
    });
  });
}
