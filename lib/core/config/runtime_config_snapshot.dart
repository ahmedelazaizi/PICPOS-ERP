// ═══════════════════════════════════════════════════════════════════════════
// RUNTIME CONFIG SNAPSHOT — immutable picture of the active configuration
// ═══════════════════════════════════════════════════════════════════════════
//
// A value object capturing "what is this install running with RIGHT NOW":
//   - the business profile
//   - the (validated) feature policy
//   - the deployment mode (standalone / server / client)
//   - the capture timestamp
//
// The snapshot is auto-attached to audit events and unhandled-exception
// reports so support can tell two installs apart at a glance. It also
// feeds the "عن النظام" diagnostics page and powers `runtime_config_hash`
// (sha1 over the JSON form) which the settings layer stores back into
// the DB on every mutation.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

import 'business_profile.dart';
import 'feature_key.dart';
import 'feature_policy.dart';

/// Deployment modes are still defined in `NetworkService` today — we
/// mirror the enum here as a thin shim so `RuntimeConfigSnapshot` does
/// not depend on the network service layer. Phase B moves the canonical
/// enum here and the network service imports from this file.
///
/// Spec 097: `mirror` is the 4th first-class mode (admin-elevated client
/// acting as remote HQ console). Surfaced in Dev Tools' mode toggle and
/// kept in lock-step with `NetworkMode.mirror` via `ConfigService.changeMode`.
enum DeploymentMode { standalone, server, client, mirror }

extension DeploymentModeX on DeploymentMode {
  String get key {
    switch (this) {
      case DeploymentMode.standalone: return 'standalone';
      case DeploymentMode.server:     return 'server';
      case DeploymentMode.client:     return 'client';
      case DeploymentMode.mirror:     return 'mirror';
    }
  }

  static DeploymentMode fromKey(String? key) {
    switch (key) {
      case 'server': return DeploymentMode.server;
      case 'client': return DeploymentMode.client;
      case 'mirror': return DeploymentMode.mirror;
      default:       return DeploymentMode.standalone;
    }
  }
}

@immutable
class RuntimeConfigSnapshot {
  final BusinessProfile profile;
  final FeaturePolicy features;
  final DeploymentMode mode;
  final DateTime capturedAt;

  const RuntimeConfigSnapshot({
    required this.profile,
    required this.features,
    required this.mode,
    required this.capturedAt,
  });

  factory RuntimeConfigSnapshot.build({
    required BusinessProfile profile,
    required FeaturePolicy features,
    required DeploymentMode mode,
    DateTime? at,
  }) =>
      RuntimeConfigSnapshot(
        profile: profile,
        features: features,
        mode: mode,
        capturedAt: at ?? DateTime.now(),
      );

  /// Canonical JSON shape. Ordering is stable so the sha1 of this output
  /// is reproducible — critical for `runtime_config_hash`.
  Map<String, dynamic> toJson() {
    final flags = <String, bool>{};
    // Sort by enum declaration order (deterministic).
    for (final k in FeatureKey.values) {
      flags[k.settingKey] = features.flag(k);
    }
    return {
      'profile': profile.name,
      'mode': mode.key,
      'features': flags,
      'capturedAt': capturedAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is RuntimeConfigSnapshot &&
      other.profile == profile &&
      other.features == features &&
      other.mode == mode &&
      other.capturedAt == capturedAt;

  @override
  int get hashCode => Object.hash(profile, features, mode, capturedAt);
}
