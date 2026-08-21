// ═══════════════════════════════════════════════════════════════════════════
// BUSINESS PROFILE PROVIDER — Riverpod-side runtime profile + features
// ═══════════════════════════════════════════════════════════════════════════
//
// This is the bridge between persisted settings and the UI. The widget
// tree mounts a `FeaturesBridge` at the root that:
//
//   1. Synchronously hydrates `AppConfig._featuresNotifier` from the
//      current providers on first build.
//   2. Listens to `featureFlagsProvider` and propagates every change
//      back into `AppConfig`. The 905+ legacy `AppConfig.features.xxx`
//      call sites then return the latest value on next rebuild.
//
// All MUTATIONS go through `ConfigService`, which is the single legal
// entry point — notifiers expose `applyFromService(...)` only, never
// raw `state =` mutation. This keeps hash recomputation + audit
// emission + lock-checks in one place.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/providers.dart';
import '../../data/repositories/settings_repository_cached.dart';
import 'brand.dart';
import 'industry_tables_policy.dart';
import '../../services/admin_password_service.dart';
import '../../services/audit_log.dart';
import '../../services/developer_auth_service.dart';
import '../../services/network_service.dart';
import '../logging/diagnostic_logger.dart';
import 'app_config.dart';
import 'feature_key.dart';
import 'feature_validator.dart';
import 'runtime_config_snapshot.dart';

// ─── Settings repository (cached) ──────────────────────────────────────

/// The cached settings facade. `main.dart` overrides this with a
/// preloaded instance via `ProviderScope(overrides: ...)`. If the
/// override is missing we still build a fresh one — every read just
/// pays a cold DB hit until the cache warms.
final settingsRepositoryCachedProvider =
    Provider<SettingsRepositoryCached>((ref) {
  return SettingsRepositoryCached(ref.watch(databaseProvider));
});

// ─── Profile + overrides + mode notifiers ──────────────────────────────

class BusinessProfileNotifier extends Notifier<BusinessProfile> {
  @override
  BusinessProfile build() {
    final repo = ref.watch(settingsRepositoryCachedProvider);
    final raw = repo.get('business_profile');
    if (raw == null || raw.isEmpty) return AppConfig.profile;
    for (final p in BusinessProfile.values) {
      if (p.name == raw) return p;
    }
    return AppConfig.profile;
  }

  /// Internal — only `ConfigService` should call this. Bypassing it
  /// will skip audit + hash + DB persistence.
  void applyFromService(BusinessProfile p) {
    state = p;
  }
}

class FeatureOverridesNotifier extends Notifier<Map<FeatureKey, bool>> {
  @override
  Map<FeatureKey, bool> build() {
    final repo = ref.watch(settingsRepositoryCachedProvider);
    final out = <FeatureKey, bool>{};
    repo.entriesWithPrefix('feature.').forEach((k, v) {
      if (v == null || v.isEmpty) return;
      final key = FeatureKeyX.tryFromSettingKey(k);
      if (key == null) return;
      out[key] = v == 'true';
    });
    return out;
  }

  void applyFromService(FeatureKey key, bool value) {
    state = {...state, key: value};
  }

  void clearOverride(FeatureKey key) {
    final next = Map<FeatureKey, bool>.from(state)..remove(key);
    state = next;
  }
}

class DeploymentModeNotifier extends Notifier<DeploymentMode> {
  @override
  DeploymentMode build() {
    final repo = ref.watch(settingsRepositoryCachedProvider);
    return DeploymentModeX.fromKey(repo.get('deployment_mode'));
  }

  void applyFromService(DeploymentMode m) {
    state = m;
  }
}

final businessProfileProvider =
    NotifierProvider<BusinessProfileNotifier, BusinessProfile>(
  BusinessProfileNotifier.new,
);

final featureOverridesProvider = NotifierProvider<FeatureOverridesNotifier,
    Map<FeatureKey, bool>>(
  FeatureOverridesNotifier.new,
);

final deploymentModeProvider =
    NotifierProvider<DeploymentModeNotifier, DeploymentMode>(
  DeploymentModeNotifier.new,
);

// ─── Computed providers ────────────────────────────────────────────────

/// Broadcast bus for validator auto-correction events. The
/// developer-tools screen subscribes; the rest of the app ignores.
final featureCorrectionBus =
    StreamController<FeatureValidationResult>.broadcast();

final featureFlagsProvider = Provider<FeaturePolicy>((ref) {
  final profile = ref.watch(businessProfileProvider);
  var overrides = ref.watch(featureOverridesProvider);

  // ── «نوع النشاط التجاري» يحكم رايةَ الطاولات في PicPos ──────────────────
  //
  // العطبُ المقيس 2026-08-15: الإعداداتُ تعرض «مطعم (طاولات وصالات)»
  // واختيارُه لا يُظهر شيئاً — `industry_mode` منفصلٌ تماماً عن البروفايل
  // وعن السياسة، وقارئوه ثلاثةٌ لا رابعَ لهم وليس فيهم PicPos.
  //
  // وقرارُ المالك: وصلُ الضابط القائم لا مفتاحٌ ثانٍ بجواره.
  //
  // ⚠️ يُحقن **تجاوزاً** لا يُفرض بعد التصديق: كي تجري عليه قواعدُ
  // `FeatureDependencyGraph` (‏`posTables` يستلزم `posMain`+`posKitchen`،
  // ويستبعد `enterpriseInvoiceMode`) بدل تخطّيها.
  //
  // ⚠️ والقراءةُ من المستودع المخزَّن **مباشرةً** لا من `industryModeProvider`:
  // ذاك يبني حالتَه بـ`supermarket` ثم يحمّل من القاعدة لاحقاً، فمراقبتُه
  // كانت ستُظهر التنقّلَ بلا طاولاتٍ لحظةً ثم يقفز — ووميضٌ في شريط التنقّل
  // يُقرأ عطباً.
  overrides = withIndustryTablesOverride(
    overrides,
    ref.watch(settingsRepositoryCachedProvider).get('industry_mode'),
    isPicPos: Brand.isPicPos,
  );

  final result = FeatureValidator.validate(
    FeaturePolicy.fromProfile(profile),
    overrides,
  );
  if (result.hasChanges) {
    featureCorrectionBus.add(result);
  }
  return result.policy;
});

final runtimeConfigSnapshotProvider = Provider<RuntimeConfigSnapshot>((ref) {
  return RuntimeConfigSnapshot.build(
    profile: ref.watch(businessProfileProvider),
    features: ref.watch(featureFlagsProvider),
    mode: ref.watch(deploymentModeProvider),
  );
});

/// Hash computed centrally from the combined snapshot — single source of
/// truth, never recomputed by individual notifiers.
final runtimeConfigHashProvider = Provider<String>((ref) {
  final snapshot = ref.watch(runtimeConfigSnapshotProvider);
  return sha1.convert(utf8.encode(jsonEncode(snapshot.toJson()))).toString();
});

// ─── Config lock — re-entrancy guard for critical operations ───────────

class ConfigLockNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void _set(bool value) {
    state = value;
  }
}

final configLockProvider =
    NotifierProvider<ConfigLockNotifier, bool>(ConfigLockNotifier.new);

/// Transactional wrapper for critical operations (shift close, full
/// sync, fiscal year close…). Throws on nested invocation so callers
/// cannot accidentally deadlock the system by holding the lock twice.
Future<T> runWithConfigLock<T>(Ref ref, Future<T> Function() fn) async {
  final notifier = ref.read(configLockProvider.notifier);
  if (notifier.state) {
    throw StateError(
      'Config lock is already held — nested critical operation?',
    );
  }
  notifier._set(true);
  try {
    return await fn();
  } finally {
    notifier._set(false);
  }
}

// ─── Developer auth + session ──────────────────────────────────────────

final developerAuthServiceProvider = Provider<DeveloperAuthService>((ref) {
  return DeveloperAuthService(ref.watch(settingsRepositoryCachedProvider));
});

final adminPasswordServiceProvider = Provider<AdminPasswordService>((ref) {
  return AdminPasswordService(ref.watch(settingsRepositoryCachedProvider));
});

class DeveloperSession {
  final bool unlocked;
  final DateTime? expiresAt;
  const DeveloperSession({this.unlocked = false, this.expiresAt});

  bool get isActive {
    if (!unlocked || expiresAt == null) return false;
    return DateTime.now().isBefore(expiresAt!);
  }
}

class DeveloperSessionNotifier extends Notifier<DeveloperSession> {
  /// Sliding window length — every successful auth or developer-tools
  /// mutation extends the session to `now + window`.
  static const Duration window = Duration(minutes: 10);

  @override
  DeveloperSession build() => const DeveloperSession();

  void unlock() {
    state = DeveloperSession(
      unlocked: true,
      expiresAt: DateTime.now().add(window),
    );
  }

  void extend() {
    if (!state.isActive) return;
    state = DeveloperSession(
      unlocked: true,
      expiresAt: DateTime.now().add(window),
    );
  }

  void clear() {
    state = const DeveloperSession();
  }
}

final developerSessionProvider =
    NotifierProvider<DeveloperSessionNotifier, DeveloperSession>(
  DeveloperSessionNotifier.new,
);

// ─── ConfigService — single mutation entry-point ───────────────────────

class ConfigService {
  final SettingsRepositoryCached _settings;
  final Ref _ref;

  ConfigService(this._settings, this._ref);

  Future<void> changeProfile(BusinessProfile next) async {
    _assertUnlocked();
    final from = _ref.read(businessProfileProvider);
    if (from == next) return;
    await _settings.save('business_profile', next.name);
    _ref.read(businessProfileProvider.notifier).applyFromService(next);
    await _persistHashAndAudit(
      'profile_changed',
      level: AuditLevel.critical,
      payload: {'from': from.name, 'to': next.name},
    );
    _ref.read(developerSessionProvider.notifier).extend();
  }

  Future<void> setOverride(FeatureKey key, bool value) async {
    _assertUnlocked();
    await _settings.save(key.settingKey, value.toString());
    _ref
        .read(featureOverridesProvider.notifier)
        .applyFromService(key, value);
    await _persistHashAndAudit(
      'feature_override_changed',
      level: AuditLevel.info,
      payload: {'key': key.settingKey, 'value': value},
    );
    _ref.read(developerSessionProvider.notifier).extend();
  }

  Future<void> clearOverride(FeatureKey key) async {
    _assertUnlocked();
    await _settings.remove(key.settingKey);
    _ref.read(featureOverridesProvider.notifier).clearOverride(key);
    await _persistHashAndAudit(
      'feature_override_cleared',
      level: AuditLevel.info,
      payload: {'key': key.settingKey},
    );
    _ref.read(developerSessionProvider.notifier).extend();
  }

  Future<void> changeMode(DeploymentMode next) async {
    _assertUnlocked();
    final from = _ref.read(deploymentModeProvider);
    if (from == next) {
      unawaited(DiagnosticLogger.log('MODE-CHANGE',
          'no-op: from=${from.key} == next=${next.key}'));
      return;
    }
    final beforeNs = NetworkService.instance.mode;
    unawaited(DiagnosticLogger.log('MODE-CHANGE',
        'BEGIN from=${from.key} → next=${next.key} '
        'beforeNetworkMode=${beforeNs.name}'));

    await _settings.save('deployment_mode', next.key);
    unawaited(DiagnosticLogger.log('MODE-CHANGE',
        'wrote deployment_mode=${next.key}'));

    // Spec 097: `deployment_mode` (DeploymentMode) and `network_mode`
    // (NetworkMode, Spec 089 canonical store) must stay in lock-step.
    // Without this, flipping mode from Dev Tools would update the UI-
    // facing enum but leave the network layer (and Spec 089's reconcile)
    // looking at a stale `network_mode` value. The mirror mode case is
    // the motivating one — its behaviour depends on NetworkMode.mirror,
    // not DeploymentMode.mirror.
    final db = _ref.read(databaseProvider);
    final targetNetworkMode = _toNetworkMode(next);
    try {
      await NetworkService.instance.setMode(targetNetworkMode, db: db);
      final afterNs = NetworkService.instance.mode;
      unawaited(DiagnosticLogger.log('MODE-CHANGE',
          'setMode returned: target=${targetNetworkMode.name} '
          'afterNetworkMode=${afterNs.name} '
          '(${afterNs == targetNetworkMode ? "OK" : "MISMATCH — bug!"})'));
    } catch (e, st) {
      unawaited(DiagnosticLogger.log('MODE-CHANGE',
          '❌ setMode threw: $e\n$st'));
      rethrow;
    }

    _ref.read(deploymentModeProvider.notifier).applyFromService(next);
    await _persistHashAndAudit(
      'mode_changed',
      level: AuditLevel.critical,
      payload: {'from': from.key, 'to': next.key},
    );
    _ref.read(developerSessionProvider.notifier).extend();
    unawaited(DiagnosticLogger.log('MODE-CHANGE',
        '✓ END from=${from.key} → next=${next.key} '
        'finalNetworkMode=${NetworkService.instance.mode.name}'));
  }

  NetworkMode _toNetworkMode(DeploymentMode m) {
    switch (m) {
      case DeploymentMode.standalone: return NetworkMode.standalone;
      case DeploymentMode.server:     return NetworkMode.server;
      case DeploymentMode.client:     return NetworkMode.client;
      case DeploymentMode.mirror:     return NetworkMode.mirror;
    }
  }

  Future<void> resetWizard() async {
    _assertUnlocked();
    await _settings.save('setup_completed', '');
    await _settings.save('setup_in_progress', 'true');
    await AuditLog.record(
      'wizard_reset',
      level: AuditLevel.critical,
    );
    _ref.read(developerSessionProvider.notifier).extend();
  }

  // ─── Spec B3 — Setup Wizard exit-path hardening ───────────────────────
  //
  // The Setup Wizard has two exit paths, `_finishSetup()` and
  // `_skipSetup()`. Both must leave `businessProfileProvider` /
  // `deploymentModeProvider` / the developer-password gate reading
  // correctly from THIS live `SettingsRepositoryCached` instance — the
  // same one `settingsRepositoryCachedProvider` hands to Dev Tools.
  //
  // Originally this existed as a "Phase C2 hot-fix" duplicated inside
  // `_finishSetup()` only, wrapped in a `try/catch` that swallowed
  // failures into a bare `debugPrint` — invisible in a Release build.
  // `_skipSetup()` had no equivalent at all. Extracted here so:
  //   1. Both exit paths call the SAME code (no more drifting copies).
  //   2. It has a direct unit-test surface (via `configServiceProvider`
  //      + a `ProviderContainer`) that doesn't require mounting the
  //      wizard's widget tree.
  //   3. Failure is reported (return value + diagnostic log), not
  //      silently swallowed — callers must surface it to the user.
  Future<bool> rehydrateRuntimeConfigCache({required String exitPath}) async {
    try {
      await _settings.preload(<String>[
        'setup_completed',
        'setup_in_progress',
        'business_profile',
        'deployment_mode',
        'developer_password_salt',
        'developer_password_hash',
        'feature_schema_version',
        'runtime_config_hash',
        ...FeatureKey.values.map((k) => k.settingKey),
      ]);
      // Force the notifiers to rebuild from the fresh cache. Without
      // this, `BusinessProfileNotifier.build()`'s initial read still
      // wins and the navigation looks like the compile-time default.
      _ref.invalidate(businessProfileProvider);
      _ref.invalidate(featureOverridesProvider);
      _ref.invalidate(deploymentModeProvider);
      return true;
    } catch (e, st) {
      await DiagnosticLogger.logError(
        'SETUP-WIZARD',
        'runtime cache rehydrate ($exitPath)',
        e,
        st,
      );
      return false;
    }
  }

  void _assertUnlocked() {
    if (_ref.read(configLockProvider)) {
      throw StateError(
        'لا يمكن تغيير الإعدادات أثناء عملية حرجة (إغلاق وردية / مزامنة)',
      );
    }
  }

  Future<void> _persistHashAndAudit(
    String event, {
    required AuditLevel level,
    Map<String, dynamic>? payload,
  }) async {
    final hash = _ref.read(runtimeConfigHashProvider);
    await _settings.save('runtime_config_hash', hash);
    await AuditLog.record(
      event,
      level: level,
      payload: {...?payload, 'hash': hash},
    );
  }
}

final configServiceProvider = Provider<ConfigService>((ref) {
  return ConfigService(ref.watch(settingsRepositoryCachedProvider), ref);
});

// ─── FeaturesBridge — syncs Riverpod into AppConfig ────────────────────

/// Mount this widget exactly ONCE at the root of the app. It listens to
/// `featureFlagsProvider` and `businessProfileProvider` and pushes every
/// change into `AppConfig` so the legacy static getters reflect runtime
/// state.
///
/// IMPORTANT: the AppConfig sync runs in `addPostFrameCallback`, NOT
/// directly in `build`. Mutating a `ValueNotifier` during `build()` is a
/// Flutter footgun — even if no widget is currently listening, future
/// `ValueListenableBuilder` consumers would get "setState during build"
/// errors. Deferring by one frame keeps the bridge correct AND safe.
class FeaturesBridge extends ConsumerWidget {
  final Widget child;
  const FeaturesBridge({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(featureFlagsProvider);
    final profile = ref.watch(businessProfileProvider);

    // Spec 029 / US5 — eager-load the install-wide negative-sales toggle
    // so the POS cart guard (cart_controller.addItem) never reads a
    // still-loading null when the cashier types into the cart on a cold
    // session. Cluster 024 / Issue 8 papered over this race by latching
    // `allowNegativeSale=true` onto the new product row at quick-add
    // time — but that latch defeated subsequent global-toggle flips.
    // We removed the latch; closing the race here keeps the cart guard's
    // dynamic OR-of-flags semantically correct.
    //
    // `ref.watch` triggers the FutureProvider's first read on the first
    // build; subsequent reads are cached. We don't render anything based
    // on the value — the Consumer's only job is to make sure the
    // provider has been touched before the POS screen mounts.
    ref.watch(enableNegativeSalesProvider);

    // Defer the side-effect to AFTER the current frame settles. The
    // value-equality short-circuit inside `updateFeatures` /
    // `updateProfile` makes repeated no-op posts free.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppConfig.updateFeatures(policy);
      AppConfig.updateProfile(profile);
    });
    return child;
  }
}
