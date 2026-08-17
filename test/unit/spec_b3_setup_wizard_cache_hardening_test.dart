// Spec B3 — Setup Wizard exit-path hardening.
//
// Bug report: developer tools settings "تظهر وتختفي" (appear then
// disappear) and wizard actions error out. Diagnosis
// (.superpowers/sdd/2026-08-16-quick-return-plan-one/devtools-diagnosis.md):
// the Setup Wizard's `_finishSetup()` wrote `business_profile`,
// `deployment_mode` and the developer password through the UNCACHED
// settings repo, while Dev Tools (and `businessProfileProvider` /
// `deploymentModeProvider` / `DeveloperAuthService`) all read from the
// LIVE `SettingsRepositoryCached` instance warmed at boot. A manual
// "Phase C2 hot-fix" patched the cache back up after `_finishSetup()`
// only — wrapped in a `try/catch` that swallowed failures into a bare
// `debugPrint` — and `_skipSetup()` had no equivalent at all.
//
// Owner decision 2026-08-17: hardening must apply on EITHER exit path,
// extracted into ONE shared function, with failure made visible instead
// of silently swallowed.
//
// This file exercises the extracted, shared function directly —
// `ConfigService.rehydrateRuntimeConfigCache` (business_profile_provider.dart)
// — against a real (in-memory) Drift database via a bare `ProviderContainer`.
// The Setup Wizard screen itself is not mounted: it pulls in NetworkService,
// MirrorState, SyncService and friends, which makes it an expensive and
// fragile thing to boot inside a widget test (see
// `.claude/…/widget-test-screen-hang-cause.md` — drift timers + db.close()
// deadlock fake_async). A directly-tested extracted function is the
// documented fallback for exactly this situation.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// `app_config.dart` re-exports `business_profile.dart` — no direct import
// needed for `BusinessProfile` here (same convention as
// `setup_wizard_screen.dart`, see the comment at its own import block).
import 'package:ural_erp/core/config/app_config.dart';
import 'package:ural_erp/core/config/business_profile_provider.dart';
import 'package:ural_erp/core/config/runtime_config_snapshot.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/providers/providers.dart';

void main() {
  group('ConfigService.rehydrateRuntimeConfigCache (Spec B3)', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting();
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
      ]);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test(
        'after a direct DB write via the live cache, all three critical '
        'keys read correctly from the live cache/providers '
        '(reproduces the fixed _finishSetup path)', () async {
      // Warm the providers with their compile-time defaults FIRST — this
      // mirrors main.dart's real boot order: providers are read (via
      // FeaturesBridge etc.) using the cache warmed at startup, BEFORE
      // the wizard ever runs.
      expect(container.read(businessProfileProvider), AppConfig.profile);
      expect(container.read(deploymentModeProvider), DeploymentMode.standalone);

      // A non-default profile so the assertion below can't pass by
      // accident of matching the compile-time default.
      final chosenProfile = BusinessProfile.values
          .firstWhere((p) => p != AppConfig.profile);

      // Simulate what `_finishSetup()` now does: write straight through
      // the SAME live cached repo `settingsRepositoryCachedProvider`
      // hands out (not the plain uncached repo).
      final cache = container.read(settingsRepositoryCachedProvider);
      await cache.save('business_profile', chosenProfile.name);
      await cache.save('deployment_mode', DeploymentMode.server.key);
      await cache.save('developer_password_salt', 'unit-test-salt');
      await cache.save('developer_password_hash', 'unit-test-hash');

      final configService = container.read(configServiceProvider);
      final ok = await configService.rehydrateRuntimeConfigCache(
        exitPath: 'test-finish',
      );
      expect(ok, isTrue);

      // The three keys — read from the LIVE providers/cache, exactly how
      // Dev Tools reads them.
      expect(container.read(businessProfileProvider), chosenProfile);
      expect(container.read(deploymentModeProvider), DeploymentMode.server);
      expect(cache.get('developer_password_salt'), 'unit-test-salt');
      expect(cache.get('developer_password_hash'), 'unit-test-hash');
    });

    test(
        'after skip-setup-style DB state (nothing written for the three '
        'keys), the live cache/providers agree with the DB — compiled '
        'defaults, no stale leftovers', () async {
      // `_skipSetup()` never writes business_profile/deployment_mode/
      // developer password (by design). Warm the providers first (their
      // defaults), write only `setup_completed` — as `_skipSetup()` does
      // — then rehydrate and confirm the three keys are STILL correctly
      // reporting the compiled defaults, not some earlier-read stale
      // value.
      container.read(businessProfileProvider);
      container.read(deploymentModeProvider);

      final settingsRepo = container.read(settingsRepositoryProvider);
      await settingsRepo.saveSetting('setup_completed', 'true');

      final configService = container.read(configServiceProvider);
      final ok = await configService.rehydrateRuntimeConfigCache(
        exitPath: 'test-skip',
      );
      expect(ok, isTrue);

      expect(container.read(businessProfileProvider), AppConfig.profile);
      expect(container.read(deploymentModeProvider), DeploymentMode.standalone);
      final cache = container.read(settingsRepositoryCachedProvider);
      expect(cache.get('developer_password_salt'), anyOf(isNull, isEmpty));
      expect(cache.get('setup_completed'), 'true');
    });

    test('a rehydrate failure is reported — NOT silently swallowed',
        () async {
      DiagnosticLogger.enableTestMode();
      final configService = container.read(configServiceProvider);

      // Force the underlying preload to fail deterministically: drop the
      // `settings` table so every `getSettingValue` call inside
      // `preload` throws a real SQL error. (A plain `db.close()` was
      // tried first and turned out NOT to make the next query fail
      // reliably — drift's close does not guarantee the following read
      // observes it synchronously.)
      await db.customStatement('DROP TABLE settings');

      final ok = await configService.rehydrateRuntimeConfigCache(
        exitPath: 'test-fail',
      );

      expect(ok, isFalse,
          reason: 'Callers key their user-facing warning off this '
              'return value — it must be false on failure, not just '
              'a swallowed exception.');
      expect(
        DiagnosticLogger.testLog.any(
          (line) =>
              line.contains('SETUP-WIZARD') && line.contains('test-fail'),
        ),
        isTrue,
        reason: 'Failure must land in the diagnostic log — a bare '
            'debugPrint (the previous behaviour) is invisible in a '
            'Release build, which is exactly how this bug went '
            'unnoticed.',
      );
    });
  });
}
