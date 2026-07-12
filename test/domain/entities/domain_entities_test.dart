import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/safe_entity.dart';
import 'package:ural_erp/domain/entities/user_entity.dart';
import 'package:ural_erp/domain/entities/branch_entity.dart';
import 'package:ural_erp/domain/entities/category_entity.dart';
import 'package:ural_erp/domain/entities/warehouse_entity.dart';
import 'package:ural_erp/domain/entities/transaction_entity.dart';

void main() {
  group('SafeEntity', () {
    test('should create with required fields', () {
      const safe = SafeEntity(
        id: 1,
        name: 'خزينة رئيسية',
        type: 'cash',
        balance: 5000.0,
      );
      expect(safe.id, 1);
      expect(safe.name, 'خزينة رئيسية');
      expect(safe.isCash, true);
      expect(safe.isBank, false);
      expect(safe.balance, 5000.0);
      expect(safe.isDefault, false);
      expect(safe.isActive, true);
    });

    test('copyWith preserves unchanged fields', () {
      const safe = SafeEntity(
        id: 1,
        name: 'خزينة 1',
        type: 'cash',
        balance: 1000,
        isDefault: true,
      );
      final updated = safe.copyWith(balance: 2000);
      expect(updated.name, 'خزينة 1');
      expect(updated.balance, 2000);
      expect(updated.isDefault, true);
    });

    test('type helpers work correctly', () {
      const bankSafe = SafeEntity(
        id: 2,
        name: 'بنك',
        type: 'bank',
        balance: 10000,
      );
      expect(bankSafe.isBank, true);
      expect(bankSafe.isCash, false);
    });
  });

  group('UserEntity', () {
    test('should create with required fields', () {
      const user = UserEntity(
        id: 1,
        username: 'admin',
        displayName: 'مدير النظام',
      );
      expect(user.id, 1);
      expect(user.username, 'admin');
      expect(user.isActive, true);
      expect(user.isLocked, false);
      expect(user.permissions, isEmpty);
    });

    test('isAdmin recognizes admin role', () {
      const admin = UserEntity(
        id: 1,
        username: 'admin',
        displayName: 'Admin',
        roleName: 'مدير النظام',
      );
      expect(admin.isAdmin, true);
    });

    test('hasPermission bypasses for admin', () {
      const admin = UserEntity(
        id: 1,
        username: 'admin',
        displayName: 'Admin',
        roleName: 'admin',
      );
      expect(admin.hasPermission('any_permission'), true);
    });

    test('hasPermission checks list for non-admin', () {
      const user = UserEntity(
        id: 2,
        username: 'cashier',
        displayName: 'كاشير',
        roleName: 'cashier',
        permissions: ['pos_access', 'view_reports'],
      );
      expect(user.hasPermission('pos_access'), true);
      expect(user.hasPermission('manage_users'), false);
    });

    test('copyWith updates permissions', () {
      const user = UserEntity(
        id: 1,
        username: 'test',
        displayName: 'Test',
      );
      final updated =
          user.copyWith(permissions: ['pos_access', 'manage_products']);
      expect(updated.permissions.length, 2);
      expect(updated.id, 1);
    });
  });

  group('BranchEntity', () {
    test('should create with defaults', () {
      const branch = BranchEntity(id: 1, name: 'الفرع الرئيسي');
      expect(branch.isMain, false);
      expect(branch.isActive, true);
      expect(branch.address, isNull);
    });

    test('copyWith works', () {
      const branch = BranchEntity(id: 1, name: 'Branch');
      final updated = branch.copyWith(isMain: true, address: 'Cairo');
      expect(updated.isMain, true);
      expect(updated.address, 'Cairo');
    });
  });

  group('CategoryEntity', () {
    test('should create with defaults', () {
      const cat = CategoryEntity(id: 1, name: 'مشروبات');
      expect(cat.color, '#2563EB');
      expect(cat.sortOrder, 0);
      expect(cat.isRoot, true);
    });

    test('isRoot returns false when parentId is set', () {
      const child = CategoryEntity(id: 2, name: 'عصائر', parentId: 1);
      expect(child.isRoot, false);
    });
  });

  group('WarehouseEntity', () {
    test('should create with defaults', () {
      const wh = WarehouseEntity(id: 1, name: 'المخزن الرئيسي');
      expect(wh.isDefault, false);
      expect(wh.isActive, true);
      expect(wh.branchId, isNull);
    });
  });

  group('TransactionEntity', () {
    test('receipt has positive signed amount', () {
      final tx = TransactionEntity(
        id: 1,
        safeId: 1,
        transactionType: 'receipt',
        amount: 500,
        category: 'مبيعات',
        createdAt: DateTime.now(),
      );
      expect(tx.isReceipt, true);
      expect(tx.isPayment, false);
      expect(tx.signedAmount, 500);
    });

    test('payment has negative signed amount', () {
      final tx = TransactionEntity(
        id: 2,
        safeId: 1,
        transactionType: 'payment',
        amount: 300,
        category: 'مصروفات',
        createdAt: DateTime.now(),
      );
      expect(tx.isReceipt, false);
      expect(tx.isPayment, true);
      expect(tx.signedAmount, -300);
    });

    test('copyWith preserves fields', () {
      final tx = TransactionEntity(
        id: 1,
        safeId: 1,
        transactionType: 'receipt',
        amount: 100,
        category: 'أخرى',
        createdAt: DateTime(2026, 1, 1),
      );
      final updated = tx.copyWith(amount: 200);
      expect(updated.amount, 200);
      expect(updated.category, 'أخرى');
      expect(updated.safeId, 1);
    });
  });
}
