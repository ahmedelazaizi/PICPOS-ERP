import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/data/providers/quick_sale_policy_providers.dart';
import 'package:picpos_erp/domain/models/quick_sale_policy.dart';
import 'package:picpos_erp/presentation/pos/providers/pos_closing_controller.dart';
import 'package:picpos_erp/presentation/pos/providers/pos_notification_provider.dart';
import 'package:picpos_erp/presentation/shift_close_picpos/widgets/picpos_cashier_closing_dialog.dart';

void main() {
  for (final accepted in [false, true]) {
    testWidgets(
      'AUD-F01 close result $accepted controls dialog, success toast, and sign-out',
      (tester) async {
        final auth = _TestAuthNotifier();
        final closing = _TestClosingController(accepted);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => auth),
              currentUserPermissionsProvider.overrideWith((ref) async => []),
              quickSalePolicyProvider.overrideWith(
                (ref) async => const QuickSalePolicyValues({
                  'pos_shift_diff_threshold': '3',
                }),
              ),
              posClosingControllerProvider.overrideWith(() => closing),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const PicposCashierClosingDialog(),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('إغلاق سريع'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('تأكيد إغلاق الوردية'));
        await tester.pumpAndSettle();
        expect(closing.closeCalls, 1);

        if (accepted) {
          expect(find.byType(PicposCashierClosingDialog), findsNothing);
          final notifications = ProviderScope.containerOf(
            tester.element(find.byType(MaterialApp)),
            listen: false,
          ).read(posNotificationsProvider);
          expect(
            notifications.any((entry) => entry.message.contains('تم إغلاق الوردية')),
            isTrue,
          );
          expect(auth.signedOut, isTrue);
        } else {
          expect(find.byType(PicposCashierClosingDialog), findsOneWidget);
          expect(
            find.text(
              'رُفض إغلاق الوردية لأن فرق النقد يتجاوز الحد المسموح. عدّل النقدي الفعلي ثم أعد المحاولة.',
            ),
            findsOneWidget,
          );
          expect(auth.signedOut, isFalse);
        }
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      },
    );
  }
}

class _TestClosingController extends PosClosingController {
  _TestClosingController(this.accepted);

  final bool accepted;
  int closeCalls = 0;

  @override
  PosClosingState build() => PosClosingState(
        isLoading: false,
        aggregates: ShiftClosingAggregates(
          openingBalance: accepted ? 0 : 100,
        ),
      );

  @override
  Future<bool> handleClosing({
    String password = '',
    String cardCode = '',
    bool overrideVariance = false,
    String? varianceReason,
    bool printReport = true,
  }) async {
    closeCalls++;
    return accepted;
  }
}

class _TestAuthNotifier extends AuthNotifier {
  bool signedOut = false;

  @override
  AuthState build() => const AuthState();

  @override
  void logout() {
    signedOut = true;
  }
}
