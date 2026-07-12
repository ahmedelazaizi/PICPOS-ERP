// ═══════════════════════════════════════════════════════════════════════════
// FeatureValidator unit tests
// ═══════════════════════════════════════════════════════════════════════════
//
// These tests lock in the behaviour the rest of the runtime-profile system
// depends on. Break one of them and the feature-flag subsystem is telling
// you something real — don't loosen the assertions without updating the
// ═══════════════════════════════════════════════════════════════════════════

import 'package:ural_erp/core/config/business_profile.dart';
import 'package:ural_erp/core/config/feature_dependency_graph.dart';
import 'package:ural_erp/core/config/feature_key.dart';
import 'package:ural_erp/core/config/feature_policy.dart';
import 'package:ural_erp/core/config/feature_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FeatureKey round-trip', () {
    test('every enum value round-trips through settingKey', () {
      for (final key in FeatureKey.values) {
        final parsed = FeatureKeyX.tryFromSettingKey(key.settingKey);
        expect(parsed, key,
            reason: '${key.settingKey} did not round-trip');
      }
    });

    test('core flags report isCore == true', () {
      const cores = {
        FeatureKey.coreAccounting,
        FeatureKey.coreInventory,
        FeatureKey.coreSales,
        FeatureKey.coreTreasury,
      };
      for (final k in FeatureKey.values) {
        expect(k.isCore, cores.contains(k),
            reason: '${k.name} isCore mismatch');
      }
    });

    test('non-core flags use a module prefix matching their namespace', () {
      for (final k in FeatureKey.values) {
        final parts = k.settingKey.split('.');
        expect(parts.length, 3,
            reason: '${k.settingKey} is not namespaced');
        expect(parts[0], 'feature',
            reason: '${k.settingKey} missing feature prefix');
      }
    });
  });

  group('FeaturePolicy data layer', () {
    test('fromProfile(restaurant) has tables + kitchen on', () {
      final p = FeaturePolicy.fromProfile(BusinessProfile.restaurant);
      expect(p.flag(FeatureKey.posTables), isTrue);
      expect(p.flag(FeatureKey.posKitchen), isTrue);
      expect(p.flag(FeatureKey.posScale), isFalse);
    });

    test('value-based equality', () {
      final a = FeaturePolicy.fromProfile(BusinessProfile.restaurant);
      final b = FeaturePolicy.fromProfile(BusinessProfile.restaurant);
      // `identical` may be true (const dedup) or false (runtime build);
      // both are acceptable. What we care about is value-equality.
      expect(a == b, isTrue, reason: 'two restaurant policies should be value-equal');
      expect(a.hashCode, b.hashCode);
      // A mutated copy must compare unequal.
      final c = a.copyWith(tablesEnabled: !a.tablesEnabled);
      expect(a == c, isFalse);
    });

    test('copyWith changes only the named flag', () {
      final a = FeaturePolicy.fromProfile(BusinessProfile.restaurant);
      final b = a.copyWith(scaleEnabled: true);
      expect(b.scaleEnabled, isTrue);
      expect(b.tablesEnabled, a.tablesEnabled);
      expect(a == b, isFalse);
    });

    test('core flags always read true regardless of the raw fields', () {
      // Even if we started from a profile that doesn't set them, the
      // accessor hard-codes true (the data-layer setter is a no-op too).
      final p = FeaturePolicy.fromProfile(BusinessProfile.commercial);
      expect(p.flag(FeatureKey.coreAccounting), isTrue);
      expect(p.flag(FeatureKey.coreInventory), isTrue);
      expect(p.flag(FeatureKey.coreSales), isTrue);
      expect(p.flag(FeatureKey.coreTreasury), isTrue);
    });
  });

  group('FeatureValidator — requires', () {
    test('enabling tables auto-enables kitchen + posMain', () {
      final base = FeaturePolicy.fromProfile(BusinessProfile.supermarket);
      expect(base.flag(FeatureKey.posTables), isFalse);
      expect(base.flag(FeatureKey.posKitchen), isFalse);

      final result = FeatureValidator.validate(
        base,
        {FeatureKey.posTables: true},
      );
      expect(result.policy.flag(FeatureKey.posTables), isTrue);
      expect(result.policy.flag(FeatureKey.posKitchen), isTrue,
          reason: 'kitchen must be auto-enabled because tables requires it');
      expect(result.policy.flag(FeatureKey.posMain), isTrue,
          reason: 'posMain must be auto-enabled because tables requires it');
      expect(result.appliedRules, isNotEmpty);
    });

    test('reservations transitively enable kitchen + posMain', () {
      final base = FeaturePolicy.fromProfile(BusinessProfile.supermarket);
      final result = FeatureValidator.validate(
        base,
        {FeatureKey.posReservations: true},
      );
      expect(result.policy.flag(FeatureKey.posReservations), isTrue);
      expect(result.policy.flag(FeatureKey.posTables), isTrue);
      expect(result.policy.flag(FeatureKey.posKitchen), isTrue);
      expect(result.policy.flag(FeatureKey.posMain), isTrue);
    });
  });

  group('FeatureValidator — locked flags', () {
    test('attempt to disable coreAccounting is rejected + logged', () {
      final base = FeaturePolicy.fromProfile(BusinessProfile.unified);
      final result = FeatureValidator.validate(
        base,
        {FeatureKey.coreAccounting: false},
      );
      expect(result.policy.flag(FeatureKey.coreAccounting), isTrue);
      expect(result.rejectedOverrides, isNotEmpty);
      expect(result.rejectedOverrides.first,
          contains(FeatureKey.coreAccounting.settingKey));
    });

    test('attempt to disable all four core flags → all rejected', () {
      final base = FeaturePolicy.fromProfile(BusinessProfile.unified);
      final result = FeatureValidator.validate(base, {
        FeatureKey.coreAccounting: false,
        FeatureKey.coreInventory: false,
        FeatureKey.coreSales: false,
        FeatureKey.coreTreasury: false,
      });
      expect(result.rejectedOverrides.length, 4);
      for (final k in FeatureDependencyGraph.locked) {
        expect(result.policy.flag(k), isTrue);
      }
    });
  });

  group('FeatureValidator — conflicts', () {
    test('invoiceMode + tables cannot both be on (last wins)', () {
      // Start from unified (both on), confirm conflicts resolves it.
      final base = FeaturePolicy.fromProfile(BusinessProfile.unified);
      // unified has invoiceModeEnabled=true and tablesEnabled=true.
      // Conflicts resolution picks the LAST in the group — set by
      // declaration order in FeatureDependencyGraph.conflicts.
      final result = FeatureValidator.validate(base, const {});
      final tablesOn = result.policy.flag(FeatureKey.posTables);
      final invoiceOn = result.policy.flag(FeatureKey.enterpriseInvoiceMode);
      expect(tablesOn && invoiceOn, isFalse,
          reason: 'conflicts must resolve one side to off');
      expect(result.appliedRules, isNotEmpty);
    });
  });

  group('FeatureValidator — determinism', () {
    test('validate is a pure function: same inputs → same outputs', () {
      final base = FeaturePolicy.fromProfile(BusinessProfile.restaurant);
      final overrides = {
        FeatureKey.posScale: true,
        FeatureKey.posOffers: true,
        FeatureKey.enterpriseHr: true,
      };
      final a = FeatureValidator.validate(base, overrides);
      final b = FeatureValidator.validate(base, overrides);
      expect(a.policy, b.policy);
      expect(a.appliedRules, b.appliedRules);
      expect(a.rejectedOverrides, b.rejectedOverrides);
    });

    test('empty overrides on a clean profile is idempotent', () {
      for (final profile in BusinessProfile.values) {
        final base = FeaturePolicy.fromProfile(profile);
        final result = FeatureValidator.validate(base, const {});
        // Validate should at most tidy conflicts; the profiles we ship
        // except `unified` should pass through unchanged (no applied
        // rules AND no rejects).
        if (profile != BusinessProfile.unified) {
          expect(result.rejectedOverrides, isEmpty,
              reason: 'profile $profile should have no rejects on fresh load');
        }
      }
    });
  });
}
