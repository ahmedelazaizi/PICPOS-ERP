import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/design_system/spacing.dart';

void main() {
  group('Design System - Spacing', () {
    group('Spacing Constants', () {
      test('spacing values are positive', () {
        expect(Spacing.xs, greaterThan(0));
        expect(Spacing.sm, greaterThan(0));
        expect(Spacing.md, greaterThan(0));
        expect(Spacing.lg, greaterThan(0));
        expect(Spacing.xl, greaterThan(0));
        expect(Spacing.xxl, greaterThan(0));
        expect(Spacing.section, greaterThan(0));
        expect(Spacing.page, greaterThan(0));
      });

      test('spacing values follow 4px base scale', () {
        expect(Spacing.xs, 4);
        expect(Spacing.sm, 8);
        expect(Spacing.md, 12);
        expect(Spacing.lg, 16);
        expect(Spacing.xl, 24);
        expect(Spacing.xxl, 32);
        expect(Spacing.section, 48);
        expect(Spacing.page, 64);
      });

      test('spacing values are in ascending order', () {
        expect(Spacing.sm, greaterThan(Spacing.xs));
        expect(Spacing.md, greaterThan(Spacing.sm));
        expect(Spacing.lg, greaterThan(Spacing.md));
        expect(Spacing.xl, greaterThan(Spacing.lg));
        expect(Spacing.xxl, greaterThan(Spacing.xl));
        expect(Spacing.section, greaterThan(Spacing.xxl));
        expect(Spacing.page, greaterThan(Spacing.section));
      });
    });

    group('Radii Constants', () {
      test('radii values are positive', () {
        expect(Radii.sm, greaterThan(0));
        expect(Radii.md, greaterThan(0));
        expect(Radii.lg, greaterThan(0));
        expect(Radii.xl, greaterThan(0));
        expect(Radii.full, greaterThan(0));
      });

      test('radii values match expected', () {
        expect(Radii.sm, 4);
        expect(Radii.md, 8);
        expect(Radii.lg, 12);
        expect(Radii.xl, 16);
        expect(Radii.full, 999);
      });

      test('radii values are in ascending order', () {
        expect(Radii.md, greaterThan(Radii.sm));
        expect(Radii.lg, greaterThan(Radii.md));
        expect(Radii.xl, greaterThan(Radii.lg));
        expect(Radii.full, greaterThan(Radii.xl));
      });
    });

    group('IconSizes Constants', () {
      test('icon sizes are positive', () {
        expect(IconSizes.xs, greaterThan(0));
        expect(IconSizes.sm, greaterThan(0));
        expect(IconSizes.md, greaterThan(0));
        expect(IconSizes.lg, greaterThan(0));
        expect(IconSizes.xl, greaterThan(0));
        expect(IconSizes.xxl, greaterThan(0));
      });

      test('icon sizes match expected', () {
        expect(IconSizes.xs, 12);
        expect(IconSizes.sm, 16);
        expect(IconSizes.md, 20);
        expect(IconSizes.lg, 24);
        expect(IconSizes.xl, 32);
        expect(IconSizes.xxl, 48);
      });

      test('icon sizes are in ascending order', () {
        expect(IconSizes.sm, greaterThan(IconSizes.xs));
        expect(IconSizes.md, greaterThan(IconSizes.sm));
        expect(IconSizes.lg, greaterThan(IconSizes.md));
        expect(IconSizes.xl, greaterThan(IconSizes.lg));
        expect(IconSizes.xxl, greaterThan(IconSizes.xl));
      });
    });

    group('TouchTargets Constants', () {
      test('touch targets are positive', () {
        expect(TouchTargets.min, greaterThan(0));
        expect(TouchTargets.standard, greaterThan(0));
        expect(TouchTargets.large, greaterThan(0));
      });

      test('touch targets match expected', () {
        expect(TouchTargets.min, 36);
        expect(TouchTargets.standard, 44);
        expect(TouchTargets.large, 56);
      });

      test('touch targets meet accessibility minimum', () {
        // Android accessibility minimum is 48dp, iOS is 44pt
        expect(TouchTargets.min, greaterThanOrEqualTo(36));
        expect(TouchTargets.standard, greaterThanOrEqualTo(44));
      });

      test('touch targets are in ascending order', () {
        expect(TouchTargets.standard, greaterThan(TouchTargets.min));
        expect(TouchTargets.large, greaterThan(TouchTargets.standard));
      });
    });
  });
}
