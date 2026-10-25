// ForceChangePasswordDialog on a client/mirror device (plan P2 / B.7.2): the
// change is made ON THE MAIN (changeOwnPassword), never written locally first,
// the minimum is 8, and an outage is reported - not hidden by a local write.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/auth_repository.dart';
import 'package:picpos_erp/presentation/widgets/dialogs/force_change_password_dialog.dart';

class _Repo implements IAuthRepository {
  final calls = <String>[];
  Object? failWith;
  @override
  Future<void> changeOwnPassword({
    required String username,
    String? currentPassword,
    String? cardCode,
    required String newPassword,
  }) async {
    calls.add('main:$username:$currentPassword:$cardCode:$newPassword');
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> updateUserPassword({
    required int userId,
    required String newPassword,
  }) async {
    calls.add('local:$userId:$newPassword');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Repo repo;
  String? captured;
  bool? popped;

  Future<void> open(WidgetTester t, {bool viaMain = true, String? card}) async {
    repo = _Repo();
    captured = null;
    popped = null;
    await t.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              popped = await showDialog<bool>(
                context: ctx,
                builder: (_) => ForceChangePasswordDialog(
                  userId: viaMain ? null : 7,
                  username: 'cashier1',
                  viaMain: viaMain,
                  currentPassword: card == null ? 'Temp#Init123' : null,
                  cardCode: card,
                  onPasswordChanged: (p) => captured = p,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  Future<void> submit(WidgetTester t, String a, String b) async {
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), a);
    await t.enterText(fields.at(1), b);
    await t.tap(find.byType(ElevatedButton));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 10)); // the success toast's timer
  }

  testWidgets('client: the change goes to the main with the in-memory current '
      'credential; nothing is written locally; the new password is handed '
      'back', (t) async {
    await open(t);
    await submit(t, 'Brand#New1234', 'Brand#New1234');
    expect(repo.calls, ['main:cashier1:Temp#Init123:null:Brand#New1234']);
    expect(captured, 'Brand#New1234');
    expect(popped, isTrue);
  });

  testWidgets('a card-only forced user proves identity with the card', (t) async {
    await open(t, card: 'CARD-9');
    await submit(t, 'Brand#New1234', 'Brand#New1234');
    expect(repo.calls, ['main:cashier1:null:CARD-9:Brand#New1234']);
  });

  testWidgets('8 characters minimum, and the two fields must match - '
      'neither reaches the main', (t) async {
    await open(t);
    await submit(t, 'short12', 'short12');
    expect(repo.calls, isEmpty);
    expect(find.textContaining('8'), findsWidgets);
    await submit(t, 'Brand#New1234', 'Different#New12');
    expect(repo.calls, isEmpty);
    expect(popped, isNull, reason: 'dialog still open');
  });

  testWidgets('an outage is shown and nothing is stored locally', (t) async {
    await open(t);
    repo.failWith = StateError('تغيير كلمة المرور يتطلب اتصالًا بالنظام الرئيسي.');
    await submit(t, 'Brand#New1234', 'Brand#New1234');
    expect(find.textContaining('يتطلب اتصالًا'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('local')), isEmpty);
    expect(captured, isNull);
    expect(popped, isNull);
  });

  testWidgets('standalone / main keeps the local change', (t) async {
    await open(t, viaMain: false);
    await submit(t, 'Brand#New1234', 'Brand#New1234');
    expect(repo.calls, ['local:7:Brand#New1234']);
    expect(popped, isTrue);
  });
}
