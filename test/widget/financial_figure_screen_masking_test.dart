import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/widgets/permission_guard.dart';

void main() {
  Future<void> pumpFigure(
    WidgetTester tester, {
    required String permission,
    required List<String> permissions,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => permissions),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PermissionMaskedText(
              permission: permission,
              text: '12,000',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('loyalty figure is masked without loyalty_view', (tester) async {
    await pumpFigure(
      tester,
      permission: PermissionCodes.loyaltyView,
      permissions: const [],
    );
    expect(find.text('12,000'), findsNothing);
    expect(find.text(kMaskedValuePlaceholder), findsOneWidget);
  });

  testWidgets('asset figure is visible with assets_view', (tester) async {
    await pumpFigure(
      tester,
      permission: PermissionCodes.assetsView,
      permissions: const [PermissionCodes.assetsView],
    );
    expect(find.text('12,000'), findsOneWidget);
  });
}
