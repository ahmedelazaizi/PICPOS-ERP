// AUTHZ-001 (audit 2026-10-23): the manager-override dialog must not accept the
// requester's OWN password, nor a holder of only a conditional (`cond:`) grant.
// Covers the table gates (`tables_merge`, ...) that route through it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/manager_approval_rules.dart';
import 'package:ural_erp/data/database/database.dart' as db;
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/auth_repository.dart';
import 'package:ural_erp/presentation/widgets/permission_guard.dart';
import 'package:ural_erp/services/login_rate_limiter.dart';
import 'package:ural_erp/services/manager_approval_cache.dart';

db.User _user(int id, String name) => db.User(
      id: id,
      username: name,
      passwordHash: '',
      passwordSalt: '',
      displayName: name,
      defaultScreen: '0',
      isLocked: false,
      isActive: true,
      discountLimitIsPercent: true,
      forcePasswordChange: false,
      createdAt: DateTime(2026, 1, 1),
      rowVersion: 1,
    );

/// The requester is user 10 (a cashier holding `tables_merge` conditionally).
class _Cashier extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        userWithRole: db.UserWithRole(user: _user(10, 'cashier')),
      );
}

class _Repo implements IAuthRepository {
  _Repo(this.byPassword, this.perms);
  final Map<String, int> byPassword; // password → user id
  final Map<int, List<String>> perms;

  @override
  Future<db.UserWithRole?> authenticateByPasswordOrCard(String input) async {
    final id = byPassword[input];
    return id == null
        ? null
        : db.UserWithRole(user: _user(id, 'u$id'));
  }

  @override
  Future<List<String>> getUserPermissionCodes(int userId) async =>
      perms[userId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  group('ManagerApprovalRules.canApprove (pure)', () {
    bool ok(int approver, List<String> perms,
            {int? requester = 10, String code = 'tables_merge'}) =>
        ManagerApprovalRules.canApprove(
          approverId: approver,
          requesterId: requester,
          approverPermissions: perms,
          permission: code,
        );

    test('requester can never approve themselves', () {
      expect(ok(10, ['tables_merge']), isFalse);
      expect(ok(10, ['system_admin']), isFalse);
    });
    test('another conditional holder cannot approve', () {
      expect(ok(11, ['tables_merge', 'cond:tables_merge']), isFalse);
    });
    test('another unconditional holder can approve', () {
      expect(ok(11, ['tables_merge']), isTrue);
    });
    test('system admin approves non-critical, not critical ops', () {
      expect(ok(1, ['system_admin']), isTrue);
      expect(ok(1, ['*']), isTrue);
    });
    test('holder without the code cannot approve', () {
      expect(ok(11, ['tables_split']), isFalse);
    });
  });

  group('override dialog (widget)', () {
    Future<bool?> run(
      WidgetTester tester, {
      required String typed,
      required Map<String, int> passwords,
      required Map<int, List<String>> perms,
    }) async {
      ManagerApprovalCache.instance.clear();
      bool? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(_Cashier.new),
            authRepositoryProvider
                .overrideWithValue(_Repo(passwords, perms)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async => result = await requestManagerApproval(
                    ctx,
                    actionName: 'دمج',
                    permission: 'tables_merge',
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), typed);
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('own password (conditional holder) is denied', (tester) async {
      await run(tester, typed: 'mine', passwords: {
        'mine': 10
      }, perms: {
        10: ['tables_merge', 'cond:tables_merge']
      });
      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget,
          reason: 'dialog must stay open');
      expect(ManagerApprovalCache.instance.consume('tables_merge'), isFalse);
    });

    testWidgets('own password even with an unconditional grant is denied',
        (tester) async {
      await run(tester, typed: 'mine', passwords: {
        'mine': 10
      }, perms: {
        10: ['tables_merge']
      });
      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);
      expect(ManagerApprovalCache.instance.consume('tables_merge'), isFalse);
    });

    testWidgets('another conditional holder is denied', (tester) async {
      await run(tester, typed: 'peer', passwords: {
        'peer': 11
      }, perms: {
        11: ['tables_merge', 'cond:tables_merge']
      });
      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);
      expect(ManagerApprovalCache.instance.consume('tables_merge'), isFalse);
    });

    testWidgets('a different unconditional holder approves', (tester) async {
      await run(tester, typed: 'boss', passwords: {
        'boss': 12
      }, perms: {
        12: ['tables_merge']
      });
      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
      expect(ManagerApprovalCache.instance.consume('tables_merge'), isTrue);
    });

    testWidgets('a system admin (another user) approves', (tester) async {
      await run(tester, typed: 'root', passwords: {
        'root': 1
      }, perms: {
        1: ['system_admin']
      });
      expect(find.text('تصريح المسؤول مطلوب'), findsNothing);
    });

    testWidgets('SEC-009: 5 wrong passwords lock the dialog even for the right one',
        (tester) async {
      LoginRateLimiter.reset();
      ManagerApprovalCache.instance.clear();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(_Cashier.new),
            authRepositoryProvider.overrideWithValue(_Repo({
              'boss': 12
            }, {
              12: ['tables_merge']
            })),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => requestManagerApproval(ctx,
                      actionName: 'دمج', permission: 'tables_merge'),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      for (var i = 0; i < LoginRateLimiter.maxAttempts; i++) {
        await tester.enterText(find.byType(TextField), 'wrong$i');
        await tester.tap(find.text('تأكيد'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), 'boss');
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();

      expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget,
          reason: 'locked: even the correct password must not approve');
      expect(ManagerApprovalCache.instance.consume('tables_merge'), isFalse);
      LoginRateLimiter.reset();
    });  });
}
