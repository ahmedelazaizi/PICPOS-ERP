import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:picpos_erp/services/mirror_state.dart';
import 'package:picpos_erp/services/network_service.dart';

/// MM.A foundation tests — exercises the persistence + lifecycle of
/// MirrorState and confirms NetworkMode.mirror is reachable through the
/// existing enum/getter machinery.
///
/// Behavior under test only — does NOT exercise the wizard UI (that
/// requires a full Riverpod + DB harness; left to a widget test once
/// MM.B's badge component lands and we have a smaller surface to drive).
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Reset both singletons to a clean baseline so each test starts from
    // the same in-memory state. The test-only setters bypass prefs so
    // they're safe to call without re-running loadSettings afterwards.
    MirrorState.instance.debugSetForTests();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
  });

  group('NetworkMode.mirror enum', () {
    test('mirror value is present in the enum and persistable', () {
      expect(NetworkMode.values, contains(NetworkMode.mirror));
      // name() is what loadSettings persists/reads from SharedPreferences,
      // so a stable string here is part of the storage contract.
      expect(NetworkMode.mirror.name, equals('mirror'));
    });

    test('isMirror getter mirrors the enum value', () {
      NetworkService.instance.debugSetModeForTests(NetworkMode.mirror);
      expect(NetworkService.instance.isMirror, isTrue);
      expect(NetworkService.instance.isClient, isFalse);
      expect(NetworkService.instance.isServer, isFalse);
      expect(NetworkService.instance.isStandalone, isFalse);
    });

    test('NetworkService.loadSettings restores mirror mode from prefs', () async {
      SharedPreferences.setMockInitialValues({'network_mode': 'mirror'});
      await NetworkService.instance.loadSettings();
      expect(NetworkService.instance.mode, NetworkMode.mirror);
      expect(NetworkService.instance.isMirror, isTrue);
    });
  });

  group('MirrorState — fresh install', () {
    test('loadSettings on empty prefs yields all-null state', () async {
      await MirrorState.instance.loadSettings();
      expect(MirrorState.instance.serverDisplayName, isNull);
      expect(MirrorState.instance.lastHandshakeAt, isNull);
      expect(MirrorState.instance.adminUserId, isNull);
      expect(MirrorState.instance.isConfigured, isFalse);
    });
  });

  group('MirrorState.setPaired', () {
    test('persists display name + handshake without adminUserId', () async {
      await MirrorState.instance.setPaired(
        serverDisplayName: '192.168.1.10:8080',
      );
      expect(MirrorState.instance.serverDisplayName, '192.168.1.10:8080');
      expect(MirrorState.instance.lastHandshakeAt, isNotNull);
      expect(MirrorState.instance.adminUserId, isNull);
      expect(MirrorState.instance.isConfigured, isTrue,
          reason: 'MM.A gate is name+handshake — adminUserId is MM.C');
    });

    test('persists adminUserId when supplied', () async {
      await MirrorState.instance.setPaired(
        serverDisplayName: 'hq.example.com:8080',
        adminUserId: 7,
      );
      expect(MirrorState.instance.adminUserId, 7);
    });

    test('survives a load cycle through SharedPreferences', () async {
      await MirrorState.instance.setPaired(
        serverDisplayName: 'hq.example.com:8080',
        adminUserId: 7,
      );
      // Wipe the in-memory state but leave prefs intact, then reload.
      MirrorState.instance.debugSetForTests();
      expect(MirrorState.instance.isConfigured, isFalse);

      await MirrorState.instance.loadSettings();
      expect(MirrorState.instance.serverDisplayName, 'hq.example.com:8080');
      expect(MirrorState.instance.adminUserId, 7);
      expect(MirrorState.instance.lastHandshakeAt, isNotNull);
      expect(MirrorState.instance.isConfigured, isTrue);
    });
  });

  group('MirrorState.markHandshake', () {
    test('updates lastHandshakeAt without touching identity fields', () async {
      await MirrorState.instance.setPaired(
        serverDisplayName: 'hq.local:8080',
        adminUserId: 1,
      );
      final firstStamp = MirrorState.instance.lastHandshakeAt!;

      // Wait a moment so the next stamp is strictly after the first.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await MirrorState.instance.markHandshake();

      expect(
        MirrorState.instance.lastHandshakeAt!.isAfter(firstStamp),
        isTrue,
        reason: 'markHandshake must move the timestamp forward',
      );
      expect(MirrorState.instance.serverDisplayName, 'hq.local:8080');
      expect(MirrorState.instance.adminUserId, 1);
    });
  });

  group('MirrorState.clear', () {
    test('wipes both in-memory state and prefs', () async {
      await MirrorState.instance.setPaired(
        serverDisplayName: 'hq.local:8080',
        adminUserId: 1,
      );
      expect(MirrorState.instance.isConfigured, isTrue);

      await MirrorState.instance.clear();
      expect(MirrorState.instance.serverDisplayName, isNull);
      expect(MirrorState.instance.adminUserId, isNull);
      expect(MirrorState.instance.lastHandshakeAt, isNull);
      expect(MirrorState.instance.isConfigured, isFalse);

      // Confirm the wipe persisted: a fresh load also sees nothing.
      MirrorState.instance.debugSetForTests();
      await MirrorState.instance.loadSettings();
      expect(MirrorState.instance.isConfigured, isFalse);
    });
  });

  group('MirrorState.isConfigured', () {
    test('false when display name is empty', () {
      MirrorState.instance.debugSetForTests(
        serverDisplayName: '',
        lastHandshakeAt: DateTime.now().toUtc(),
      );
      expect(MirrorState.instance.isConfigured, isFalse,
          reason: 'empty string is not a valid identity');
    });

    test('false when handshake is missing', () {
      MirrorState.instance.debugSetForTests(
        serverDisplayName: 'hq.local:8080',
        lastHandshakeAt: null,
      );
      expect(MirrorState.instance.isConfigured, isFalse);
    });

    test('true when name + handshake set, regardless of adminUserId', () {
      MirrorState.instance.debugSetForTests(
        serverDisplayName: 'hq.local:8080',
        lastHandshakeAt: DateTime.now().toUtc(),
      );
      expect(MirrorState.instance.isConfigured, isTrue);
    });
  });
}
