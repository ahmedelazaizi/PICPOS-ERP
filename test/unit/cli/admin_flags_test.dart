import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/cli/admin_flags.dart';
import 'package:picpos_erp/services/activity_logger.dart';
import 'package:picpos_erp/services/audit_log.dart';

class _FakeLogger implements ActivityLogger {
  final actions = <String>[];
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #log) {
      actions.add(i.namedArguments[#action] as String);
      return Future<void>.value();
    }
    return super.noSuchMethod(i);
  }
}

void main() {
  late List<String> calls;
  late Directory dir;

  setUp(() {
    AuditLog.resetForTest();
    calls = [];
    dir = Directory.systemTemp.createTempSync('admin_flags_');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<List<String>> run(List<String> args, {required bool confirmed}) {
    var asked = false;
    return runAdminFlags(
      request: AdminFlagRequest.parse(args, const {}),
      confirm: () async {
        asked = true;
        return confirmed;
      },
      resetDevPassword: () async => calls.add('dev'),
      purgeUsers: () async => calls.add('purge'),
      resetAdminPassword: () async => calls.add('admin'),
      resetSetupWizard: () async => calls.add('wizard'),
    ).whenComplete(() {
      if (args.isEmpty) expect(asked, isFalse);
    });
  }

  test('no flags => nothing happens and no confirmation is requested', () async {
    expect(await run(const [], confirmed: true), isEmpty);
    expect(calls, isEmpty);
  });

  test('flag without confirmation => refused, no action, refusal audited',
      () async {
    expect(
        await run(['--purge-users', '--reset-admin-password'],
            confirmed: false),
        isEmpty);
    expect(calls, isEmpty);
    final logger = _FakeLogger();
    AuditLog.configure(logger);
    await Future<void>.delayed(Duration.zero);
    expect(logger.actions, ['admin_flag_refused']);
  });

  test('flag with confirmation => runs and audit survives late configure',
      () async {
    final done = await run(
        ['--reset-dev-password', '--purge-users', '--reset-admin-password'],
        confirmed: true);
    expect(calls, ['dev', 'purge', 'admin']);
    expect(done.length, 3);
    // AuditLog was not configured yet: events must be flushed on configure.
    final logger = _FakeLogger();
    AuditLog.configure(logger);
    await Future<void>.delayed(Duration.zero);
    expect(logger.actions, [
      'developer_password_reset_flag',
      'users_purged',
      'admin_password_reset',
    ]);
  });

  test('--reset-setup-wizard without confirmation => refused, data untouched',
      () async {
    expect(await run(['--reset-setup-wizard'], confirmed: false), isEmpty);
    expect(calls, isEmpty);
    final logger = _FakeLogger();
    AuditLog.configure(logger);
    await Future<void>.delayed(Duration.zero);
    expect(logger.actions, ['admin_flag_refused']);
  });

  test('--reset-setup-wizard with confirmation => runs and is audited',
      () async {
    expect(await run(['--reset-setup-wizard'], confirmed: true),
        ['reset-setup-wizard']);
    expect(calls, ['wizard']);
    final logger = _FakeLogger();
    AuditLog.configure(logger);
    await Future<void>.delayed(Duration.zero);
    expect(logger.actions, ['setup_wizard_reset']);
  });

  test('RESET_SETUP_WIZARD env is parsed like the CLI flag', () {
    final r = AdminFlagRequest.parse(
        const [], const {'PICPOS_RESET_SETUP_WIZARD': '1'});
    expect(r.resetSetupWizard, isTrue);
  });

  test('release build ignores the wizard flag even with a confirm file',
      () async {
    File('${dir.path}/$kRecoveryConfirmFileName').writeAsStringSync('ok');
    final r = AdminFlagRequest.parse(const ['--reset-setup-wizard'], const {},
        allowDevReset: false);
    final rEnv = AdminFlagRequest.parse(
        const [], const {'PICPOS_RESET_SETUP_WIZARD': '1'},
        allowDevReset: false);
    expect(r.resetSetupWizard, isFalse);
    expect(rEnv.resetSetupWizard, isFalse);
    final done = await runAdminFlags(
      request: r,
      confirm: () => consumeRecoveryConfirmation(dir),
      resetDevPassword: () async => calls.add('dev'),
      purgeUsers: () async => calls.add('purge'),
      resetAdminPassword: () async => calls.add('admin'),
      resetSetupWizard: () async => calls.add('wizard'),
    );
    expect(done, isEmpty);
    expect(calls, isEmpty);
  });

  test('release build ignores the dev-password flag', () {
    final r = AdminFlagRequest.parse(
        const ['--reset-dev-password'], const {},
        allowDevReset: false);
    expect(r.any, isFalse);
  });

  group('consumeRecoveryConfirmation', () {
    File mk() => File('${dir.path}/$kRecoveryConfirmFileName')
      ..writeAsStringSync('ok');

    test('missing file => false', () async {
      expect(await consumeRecoveryConfirmation(dir), isFalse);
    });

    test('fresh file => true once, then consumed', () async {
      final f = mk();
      expect(await consumeRecoveryConfirmation(dir), isTrue);
      expect(f.existsSync(), isFalse);
      expect(await consumeRecoveryConfirmation(dir), isFalse);
    });

    test('stale file => false and removed', () async {
      final f = mk();
      final later = DateTime.now().add(kRecoveryConfirmMaxAge * 2);
      expect(await consumeRecoveryConfirmation(dir, now: later), isFalse);
      expect(f.existsSync(), isFalse);
    });
  });
}
