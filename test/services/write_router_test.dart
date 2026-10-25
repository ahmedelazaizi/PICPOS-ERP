import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:picpos_erp/services/mirror_branch_context.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';
import 'package:picpos_erp/services/write_router.dart';

/// MM.C unit tests for the routing helpers — WriteRouter behaviour and
/// MirrorOfflineException identity. The full _tryOrQueue path requires
/// stubbing ServerProxy + AppDatabase so it lives in a follow-up
/// integration test; this file pins down the pure-logic gates that
/// determine mirror-mode behaviour everywhere else in the codebase.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    MirrorState.instance.debugSetForTests();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
  });

  group('WriteRouter.isMirrorActive', () {
    test('false in standalone mode regardless of MirrorState', () {
      MirrorState.instance.debugSetForTests(
        serverDisplayName: 'hq.local:8080',
        lastHandshakeAt: DateTime.now().toUtc(),
      );
      expect(WriteRouter.isMirrorActive, isFalse);
    });

    test('false in client mode regardless of MirrorState', () {
      NetworkService.instance.debugSetModeForTests(NetworkMode.client);
      MirrorState.instance.debugSetForTests(
        serverDisplayName: 'hq.local:8080',
        lastHandshakeAt: DateTime.now().toUtc(),
      );
      expect(WriteRouter.isMirrorActive, isFalse,
          reason: 'client mode uses outbox, not the mirror no-outbox path');
    });

    test('false in mirror mode when MirrorState is not configured', () {
      NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
      // No display name + no handshake → isConfigured is false.
      expect(WriteRouter.isMirrorActive, isFalse,
          reason: 'intermediate state — wizard not finished');
    });

    test('true only when mode==mirror AND state is configured', () {
      NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
      MirrorState.instance.debugSetForTests(
        serverDisplayName: 'hq.local:8080',
        lastHandshakeAt: DateTime.now().toUtc(),
      );
      expect(WriteRouter.isMirrorActive, isTrue);
    });
  });

  group('WriteRouter.stampBranchContext (M2)', () {
    setUp(() => MirrorBranchContext.instance.reset());
    tearDown(() => MirrorBranchContext.instance.reset());

    test('no-op until a current branch is known', () {
      final payload = <String, dynamic>{'name': 'X'};
      WriteRouter.stampBranchContext(payload);
      expect(payload, {'name': 'X'});
    });

    test('never stamps the acting user (the main takes it from the session)',
        () {
      MirrorState.instance.debugSetForTests(
        serverDisplayName: 'hq.local:8080',
        lastHandshakeAt: DateTime.now().toUtc(),
        adminUserId: 42, // the legacy pairing admin must NOT leak into writes
      );
      MirrorBranchContext.instance.debugSet(
          branches: const [MirrorBranch(id: 2, name: 'B2')], current: 2);
      final payload = <String, dynamic>{'name': 'X'};
      WriteRouter.stampBranchContext(payload);
      expect(payload.containsKey('actorUserId'), isFalse);
      expect(payload.containsKey('userId'), isFalse);
      expect(payload['branchId'], 2);
    });

    test('a payload that already has a branch key is left alone (even null)',
        () {
      MirrorBranchContext.instance.debugSet(
          branches: const [MirrorBranch(id: 2, name: 'B2')], current: 2);
      final own = <String, dynamic>{'branchId': 7};
      final none = <String, dynamic>{'branchId': null, 'name': 'warehouse'};
      WriteRouter.stampBranchContext(own);
      WriteRouter.stampBranchContext(none);
      expect(own['branchId'], 7);
      expect(none['branchId'], isNull);
    });
  });
  group('MirrorOfflineException', () {
    test('preserves the underlying network error in toString', () {
      final ex = MirrorOfflineException('SocketException: refused');
      expect(ex.detail, 'SocketException: refused');
      expect(ex.toString(), contains('SocketException: refused'));
      expect(ex.toString(), contains('فقد الاتصال'),
          reason: 'Arabic-localised user-facing message');
    });

    test('is an Exception so callers can catch it generically', () {
      expect(MirrorOfflineException('x'), isA<Exception>());
    });
  });

  group('MirrorAdminVerification factories', () {
    test('success carries userId + display + role and isSuccess', () {
      final v = MirrorAdminVerification.success(
        userId: 7,
        displayName: 'مدير النظام',
        roleName: 'admin',
      );
      expect(v.outcome, MirrorAdminVerificationOutcome.ok);
      expect(v.userId, 7);
      expect(v.displayName, 'مدير النظام');
      expect(v.roleName, 'admin');
      expect(v.isSuccess, isTrue);
    });

    test('invalidCredentials and notAdmin are non-success', () {
      expect(MirrorAdminVerification.invalidCredentials().isSuccess, isFalse);
      expect(MirrorAdminVerification.notAdmin().isSuccess, isFalse);
      expect(
        MirrorAdminVerification.invalidCredentials().outcome,
        MirrorAdminVerificationOutcome.invalidCredentials,
      );
      expect(
        MirrorAdminVerification.notAdmin().outcome,
        MirrorAdminVerificationOutcome.notAdmin,
      );
    });

    test('failed carries the underlying error detail', () {
      final v = MirrorAdminVerification.failed('DNS lookup failed');
      expect(v.isSuccess, isFalse);
      expect(v.outcome, MirrorAdminVerificationOutcome.error);
      expect(v.errorDetail, 'DNS lookup failed');
    });
  });
}
