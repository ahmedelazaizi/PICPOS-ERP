// ═══════════════════════════════════════════════════════════════════════════
// SPEC 097 — `ConfigService.changeMode` propagates to BOTH settings keys
// ═══════════════════════════════════════════════════════════════════════════
//
// Architectural pin: before Spec 097, `changeMode` only persisted
// `deployment_mode` (UI-facing DeploymentMode enum). The canonical
// `network_mode` (Spec 089 SoT, used by NetworkService + sync interceptors)
// was written only by the Setup Wizard. Flipping mode from Dev Tools
// silently left the network layer on a stale mode value.
//
// These source pins enforce the lock-step contract: `changeMode` must
// write the deployment_mode setting AND call `NetworkService.setMode`
// with a translated NetworkMode value, in the same method.
//
// See specs/SESSION-HANDOFF-2026-05-26.md and
// `project_spec_097_design.md`.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/config/runtime_config_snapshot.dart';

void main() {
  group('Spec 097 — DeploymentMode enum has mirror', () {
    test('enum has exactly 4 values including mirror', () {
      expect(DeploymentMode.values.length, 4,
          reason: 'mirror is the 4th first-class mode.');
      expect(DeploymentMode.values, contains(DeploymentMode.mirror));
    });

    test('key getter round-trips mirror', () {
      expect(DeploymentMode.mirror.key, 'mirror');
      expect(DeploymentModeX.fromKey('mirror'), DeploymentMode.mirror);
    });

    test('fromKey is exhaustive — every enum value round-trips', () {
      for (final mode in DeploymentMode.values) {
        expect(DeploymentModeX.fromKey(mode.key), mode,
            reason: 'fromKey(${mode.key}) must round-trip.');
      }
    });
  });

  group('Spec 097 — ConfigService.changeMode wiring', () {
    final src = File('lib/core/config/business_profile_provider.dart')
        .readAsStringSync();

    test('imports NetworkService', () {
      expect(src, contains("import '../../services/network_service.dart'"),
          reason: 'changeMode must call NetworkService.setMode to keep '
              'deployment_mode and network_mode in lock-step.');
    });

    test('changeMode saves deployment_mode AND calls NetworkService.setMode',
        () {
      final start = src.indexOf('Future<void> changeMode(');
      expect(start, isNot(-1));
      // Look at the body up to the next top-level method definition.
      // Window grew to 2400 to accommodate the MODE-CHANGE diagnostic
      // logging added after the smoke surfaced a propagation bug.
      final body = src.substring(start, start + 2400);

      expect(body, contains("_settings.save('deployment_mode'"),
          reason: 'deployment_mode (DeploymentMode enum) must be persisted.');
      expect(body, contains('NetworkService.instance.setMode('),
          reason:
              'Spec 097: network_mode (NetworkMode enum, Spec 089 canonical) '
              'must be propagated in the SAME call so the two stores cannot '
              'drift apart.');
      expect(body, contains('_toNetworkMode(next)'),
          reason:
              'The DeploymentMode → NetworkMode mapper must be threaded '
              'through so mirror in the UI maps to NetworkMode.mirror.');
      expect(body, contains('databaseProvider'),
          reason:
              'setMode requires a DB handle (Spec 089 atomic) — the Ref '
              'lookup must happen inside changeMode.');
    });

    test('_toNetworkMode covers all 4 DeploymentMode values', () {
      final start = src.indexOf('NetworkMode _toNetworkMode(');
      expect(start, isNot(-1),
          reason: 'The mapper helper must exist next to changeMode.');
      final body = src.substring(start, start + 600);

      expect(body, contains('DeploymentMode.standalone'));
      expect(body, contains('DeploymentMode.server'));
      expect(body, contains('DeploymentMode.client'));
      expect(body, contains('DeploymentMode.mirror'),
          reason:
              'Without the mirror case the switch is non-exhaustive — '
              'analyzer would catch this, but the pin is here so the '
              'failure mode is documented.');
      expect(body, contains('NetworkMode.mirror'));
    });
  });
}
