import 'package:picpos_erp/core/i18n/tr.dart';
// ═══════════════════════════════════════════════════════════════════════════
// FEATURE VALIDATOR — applies the dependency graph to a raw policy
// ═══════════════════════════════════════════════════════════════════════════
//
// Third layer of the feature-flag system (data → rules → engine).
// Takes a base `FeaturePolicy` (usually built from a `BusinessProfile`) and
// a set of user-supplied overrides, and returns a `FeatureValidationResult`
// with:
//   - the final, fully-consistent policy,
//   - a log of applied rules ("kitchen was auto-enabled because tables
//     requires it"),
//   - a log of rejected overrides ("accounting_core cannot be disabled").
//
// The validator is DETERMINISTIC: rule evaluation iterates `FeatureKey.values`
// in declared order, and a fixed-point loop (max 3 passes) keeps applying
// rules until no pass produces a change. Same inputs → identical outputs.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

import 'feature_dependency_graph.dart';
import 'feature_key.dart';
import 'feature_policy.dart';

@immutable
class FeatureValidationResult {
  /// The final consistent policy after applying overrides + rules.
  final FeaturePolicy policy;

  /// Human-readable (Arabic) explanations of automatic rule applications.
  /// Surfaced in the developer-tools UI and in audit logs.
  final List<String> appliedRules;

  /// Overrides the validator refused to honour (hard-locked cores, etc.).
  final List<String> rejectedOverrides;

  const FeatureValidationResult({
    required this.policy,
    required this.appliedRules,
    required this.rejectedOverrides,
  });

  bool get hasChanges =>
      appliedRules.isNotEmpty || rejectedOverrides.isNotEmpty;
}

class FeatureValidator {
  const FeatureValidator._();

  /// Maximum fixed-point passes. Three is comfortably more than any
  /// dependency chain we currently model (the deepest is reservations →
  /// tables → (main + kitchen), depth 2). Higher would mask a cycle.
  static const int _maxPasses = 3;

  /// Validates + normalises a policy.
  ///
  /// [base] is the profile-default policy (no overrides applied yet).
  /// [overrides] maps a subset of feature keys to user-chosen values.
  /// A missing key in [overrides] means "inherit from base" — we never
  /// accept `null` as a third state.
  static FeatureValidationResult validate(
    FeaturePolicy base,
    Map<FeatureKey, bool> overrides,
  ) {
    final rules = <String>[];
    final rejects = <String>[];
    var policy = base;

    // Pass 0 — apply the overrides the user actually provided. Core
    // flags reject disable-attempts up front; enable-to-true is always
    // a no-op (cores are already true by `flag()`).
    for (final key in FeatureKey.values) {
      if (!overrides.containsKey(key)) continue;
      final desired = overrides[key]!;
      if (FeatureDependencyGraph.locked.contains(key) && !desired) {
        rejects.add(
          tr('رُفض تعطيل "{p0}": الميزة أساسية ولا يمكن إيقافها.', {'p0': key.settingKey}),
        );
        continue;
      }
      policy = policy.setFlag(key, desired);
    }

    // Passes 1..N — keep applying `requires` + `conflicts` until the
    // policy stops changing. Deterministic iteration order.
    for (var pass = 0; pass < _maxPasses; pass++) {
      final before = policy;

      // requires: A=true → each B in requires[A] must also be true.
      for (final key in FeatureKey.values) {
        if (!policy.flag(key)) continue;
        final deps = FeatureDependencyGraph.requires[key];
        if (deps == null) continue;
        for (final dep in deps) {
          if (!policy.flag(dep)) {
            policy = policy.setFlag(dep, true);
            rules.add(
              tr('تم تفعيل "{p0}" تلقائياً لأن "{p1}" يتطلبها.', {'p0': dep.settingKey, 'p1': key.settingKey}),
            );
          }
        }
      }

      // conflicts: within each group, if more than one flag is true,
      // keep the *last declared one that is on* (deterministic) and
      // disable the rest. "Last wins" is a convention — it maps to
      // "the most recently toggled override wins" in the UI where the
      // override map is ordered by insertion.
      for (final group in FeatureDependencyGraph.conflicts) {
        final onesOn = group.where(policy.flag).toList();
        if (onesOn.length <= 1) continue;
        // Disable everything except the last one (iteration order is
        // the Set's declaration order — Dart preserves it for constants).
        final keep = onesOn.last;
        for (final k in onesOn) {
          if (k == keep) continue;
          policy = policy.setFlag(k, false);
          rules.add(
            tr('تم تعطيل "{p0}" لأنها تتعارض مع "{p1}".', {'p0': k.settingKey, 'p1': keep.settingKey}),
          );
        }
      }

      if (policy == before) break;
    }

    return FeatureValidationResult(
      policy: policy,
      appliedRules: List.unmodifiable(rules),
      rejectedOverrides: List.unmodifiable(rejects),
    );
  }
}
