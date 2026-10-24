// RESET-001 (users/login/sync plan P0): an admin password reset issued from a
// client/mirror device must reach the HOST (POST /api/users/<id>/password) —
// never silently succeed locally, never park the plaintext password in the
// outbox, and never rely on PUT /api/users/<id> {password} (the host ignores it).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/services/auth/remote_password_reset.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';

import '../helpers/mirror_peer_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => I18nCatalog.setCatalog(const {}));

  group('resetPasswordOnMain (fake port)', () {
    test('sends exactly one request with the id and the new password', () async {
      final calls = <(int, String)>[];
      await resetPasswordOnMain(
        userId: 7,
        password: 'New#Pass12345',
        send: (id, pw) async => calls.add((id, pw)),
      );
      expect(calls, [(7, 'New#Pass12345')]);
    });

    for (final (name, error) in <(String, Object)>[
      ('SocketException', const SocketException('refused')),
      ('TimeoutException', TimeoutException('slow')),
      ('http.ClientException', http.ClientException('reset')),
    ]) {
      test('$name -> RemotePasswordResetException (online required)', () async {
        await expectLater(
          resetPasswordOnMain(
              userId: 1, password: 'x', send: (_, _) async => throw error),
          throwsA(isA<RemotePasswordResetException>()
              .having((e) => e.cause, 'cause', same(error))),
        );
      });
    }

    test('a host rejection (403/400) is rethrown UNCHANGED, not disguised as '
        '"offline"', () async {
      final rejection = Exception('Server error (403): users_manage required');
      await expectLater(
        resetPasswordOnMain(
            userId: 1, password: 'x', send: (_, _) async => throw rejection),
        throwsA(same(rejection)),
      );
    });
  });

  group('ClientWriteInterceptor.resetUserPasswordOnline', () {
    late Peers p;
    setUp(() async => p = await createPeers());
    tearDown(() async => p.dispose());

    test('standalone/server device: not intercepted (false), nothing sent',
        () async {
      expect(SyncInterceptor.isClientMode, isFalse);
      expect(
          await ClientWriteInterceptor.resetUserPasswordOnline(
              p.cashierId, 'New#Pass12345'),
          isFalse);
    });

    test('client with an unreachable host: refused AND nothing is queued '
        '(no plaintext in the outbox)', () async {
      p.asClient();
      ClientWriteInterceptor.initialize(p.client);
      await expectLater(
          ClientWriteInterceptor.resetUserPasswordOnline(
              p.cashierId, 'New#Pass12345'),
          throwsA(isA<Object>()));
      final n = await p.client
          .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
          .getSingle();
      expect(n.read<int>('n'), 0);
      // and the local credential is untouched
      expect(await p.canLogin(p.client, 'cashier1', 'New#Pass12345'), isFalse);
    });

    test('mirror with an unreachable host: refused, nothing queued', () async {
      p.asMirror();
      ClientWriteInterceptor.initialize(p.client);
      await expectLater(
          ClientWriteInterceptor.resetUserPasswordOnline(
              p.cashierId, 'New#Pass12345'),
          throwsA(isA<Object>()));
      final n = await p.client
          .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
          .getSingle();
      expect(n.read<int>('n'), 0);
    });
  });

  test('the reset dialog uses the online-only host route and no longer sends '
      '{password} through PUT /api/users/<id>', () {
    final src = File(
            'lib/presentation/screens/settings/widgets/reset_password_dialog.dart')
        .readAsStringSync();
    expect(src, contains('ClientWriteInterceptor.resetUserPasswordOnline('));
    expect(RegExp(r"updateUser\([^)]*'password'", dotAll: true).hasMatch(src),
        isFalse);
  });
}
