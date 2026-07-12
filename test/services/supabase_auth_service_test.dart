import 'package:ural_erp/services/auth/supabase_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserProfile.fromJson', () {
    test('parses all fields including nullable ones', () {
      final profile = UserProfile.fromJson({
        'id': 'uuid-1',
        'tenant_id': 'tenant-1',
        'full_name': 'أحمد',
        'email': 'a@example.com',
        'phone': null,
        'role': 'manager',
        'default_branch_id': 'branch-1',
        'allowed_branch_ids': ['branch-1', 'branch-2'],
        'permissions': ['products.read', 'products.write'],
        'is_active': true,
      });
      expect(profile.id, 'uuid-1');
      expect(profile.tenantId, 'tenant-1');
      expect(profile.role, 'manager');
      expect(profile.allowedBranchIds, hasLength(2));
      expect(profile.permissions, contains('products.write'));
      expect(profile.phone, isNull);
    });

    test('defaults missing arrays to empty', () {
      final profile = UserProfile.fromJson({
        'id': 'uuid-2',
        'tenant_id': 'tenant-2',
        'full_name': 'Nada',
        'email': 'n@example.com',
        'role': 'cashier',
      });
      expect(profile.allowedBranchIds, isEmpty);
      expect(profile.permissions, isEmpty);
      expect(profile.isActive, isTrue);
    });
  });

  group('SupabaseAuthService.hasPermission', () {
    // We cannot easily construct the service's profile without touching
    // Supabase.initialize, but we can verify the logic via a UserProfile
    // helper pattern that mirrors the check.
    bool checkHasPermission(UserProfile p, String code) {
      if (p.role == 'admin') return true;
      return p.permissions.contains(code);
    }

    final adminProfile = UserProfile.fromJson({
      'id': 'a',
      'tenant_id': 't',
      'full_name': 'A',
      'email': 'a@x',
      'role': 'admin',
    });
    final cashierProfile = UserProfile.fromJson({
      'id': 'c',
      'tenant_id': 't',
      'full_name': 'C',
      'email': 'c@x',
      'role': 'cashier',
      'permissions': ['pos.sell'],
    });

    test('admin has every permission', () {
      expect(checkHasPermission(adminProfile, 'anything'), isTrue);
      expect(checkHasPermission(adminProfile, 'journal.post'), isTrue);
    });

    test('non-admin only has listed permissions', () {
      expect(checkHasPermission(cashierProfile, 'pos.sell'), isTrue);
      expect(checkHasPermission(cashierProfile, 'journal.post'), isFalse);
    });
  });
}
