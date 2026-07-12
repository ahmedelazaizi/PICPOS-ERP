// ═══════════════════════════════════════════════════════════════════════════
// DEPLOYMENT MODE COMMITTER TESTS — Spec 125 (T019)
// ═══════════════════════════════════════════════════════════════════════════
//
// Focused unit tests on the committer's public API surface. Full integration
// (pairing + first-sync end-to-end) is exercised by the manual smoke matrix
// in quickstart.md and the wizard widget tests in Phase 3.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/deployment/commit_result.dart';
import 'package:ural_erp/services/deployment/setup_contract.dart';
import 'package:ural_erp/services/network_service.dart';

void main() {
  group('SetupContract construction', () {
    test('StandaloneContract has correct targetMode + displayName', () {
      const c = StandaloneContract();
      expect(c.targetMode, NetworkMode.standalone);
      expect(c.displayNameAr, 'مستقل');
    });

    test('ServerContract carries port', () {
      const c = ServerContract(port: 8080);
      expect(c.targetMode, NetworkMode.server);
      expect(c.port, 8080);
      expect(c.displayNameAr, 'سيرفر');
    });

    test('ClientContract carries credentials + server addr', () {
      const c = ClientContract(
        serverHost: '192.168.1.10',
        serverPort: 8080,
        adminUsername: 'admin',
        adminPassword: 'pw',
      );
      expect(c.targetMode, NetworkMode.client);
      expect(c.serverHost, '192.168.1.10');
      expect(c.serverPort, 8080);
      expect(c.adminUsername, 'admin');
      expect(c.displayNameAr, 'عميل');
    });

    test('MirrorContract is structurally distinct from ClientContract', () {
      const m = MirrorContract(
        serverHost: 'h',
        serverPort: 1,
        adminUsername: 'u',
        adminPassword: 'p',
      );
      expect(m.targetMode, NetworkMode.mirror);
      expect(m.displayNameAr, 'مرآة');
      // Sealed switch must distinguish:
      const SetupContract any = m;
      final tag = switch (any) {
        StandaloneContract() => 'S',
        ServerContract() => 'V',
        ClientContract() => 'C',
        MirrorContract() => 'M',
      };
      expect(tag, 'M');
    });
  });

  group('CommitResult sealed hierarchy', () {
    test('CommitOk and CommitFailed are distinguishable in switch', () {
      const CommitResult ok = CommitOk(
        mode: NetworkMode.mirror,
        totalDuration: Duration(milliseconds: 100),
      );
      const CommitResult fail = CommitFailed(
        failedAtStep: CommitStep.pairing,
        reasonAr: 'فشل',
        reasonCode: 'X',
      );

      String classify(CommitResult r) => switch (r) {
            CommitOk() => 'ok',
            CommitFailed() => 'fail',
          };
      expect(classify(ok), 'ok');
      expect(classify(fail), 'fail');
    });

    test('CommitFailed.reasonAr is Arabic + reasonCode is upper-snake', () {
      const f = CommitFailed(
        failedAtStep: CommitStep.firstSync,
        reasonAr: 'تعذّرت المزامنة',
        reasonCode: 'FIRSTSYNC_FAILED',
      );
      expect(f.reasonAr.contains('تعذّر'), isTrue);
      expect(f.reasonCode, matches(RegExp(r'^[A-Z_]+$')));
    });
  });

  group('CommitStep coverage', () {
    test('all 7 documented steps exist', () {
      expect(CommitStep.values.length, 7);
      expect(CommitStep.values, contains(CommitStep.preCheck));
      expect(CommitStep.values, contains(CommitStep.pairing));
      expect(CommitStep.values, contains(CommitStep.firstSync));
      expect(CommitStep.values, contains(CommitStep.startHttpServer));
      expect(CommitStep.values, contains(CommitStep.startHeartbeat));
      expect(CommitStep.values, contains(CommitStep.seedMasterData));
      expect(CommitStep.values, contains(CommitStep.finalDbCommit));
    });
  });
}
