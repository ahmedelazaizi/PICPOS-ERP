// B-3: صلاحياتُ الطاولات المشروطة (`cond:<code>`) لا تتخطّى موافقةَ المدير.
//
// المشروطُ يضع في القائمة الكودَ **و** علامتَه؛ فالفحصُ بـ`contains` وحدَه كان
// يُمرّر tables_add_items / tables_checkout / tables_merge بلا موافقة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/tables/table_action_gate.dart';

void main() {
  const codes = [
    PermissionCodes.tablesAddItems,
    PermissionCodes.tablesCheckout,
    PermissionCodes.tablesMerge,
  ];

  group('tableActionGate (خالصة)', () {
    for (final c in codes) {
      test('$c: مشروط ⇒ يحتاج موافقة', () {
        expect(
            tableActionGate([c, PermissionCodes.conditionalMarker(c)], c),
            TableActionGate.needsApproval);
      });
      test('$c: عادي ⇒ مسموح', () {
        expect(tableActionGate([c], c), TableActionGate.allowed);
      });
      test('$c: غائب ⇒ مرفوض', () {
        expect(tableActionGate(const <String>[], c), TableActionGate.denied);
        expect(tableActionGate(const ['tables_view'], c),
            TableActionGate.denied);
      });
    }

    test('مدير النظام يمرّ', () {
      expect(tableActionGate(const ['system_admin'], PermissionCodes.tablesMerge),
          TableActionGate.allowed);
    });
  });

  Future<List<bool>> pumpGate(WidgetTester tester, List<String> perms) async {
    final results = <bool>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) => perms),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    results.add(await ensureTableAction(
                      ref,
                      context,
                      PermissionCodes.tablesMerge,
                      'دمج الطاولات',
                    ));
                  },
                  child: const Text('نفّذ'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('tables_merge مشروط ⇒ يُطلب حوارُ موافقة ولا يمرّ', (tester) async {
    final results = await pumpGate(tester, [
      PermissionCodes.tablesMerge,
      PermissionCodes.conditionalMarker(PermissionCodes.tablesMerge),
    ]);
    await tester.tap(find.text('نفّذ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(results, isEmpty, reason: 'رجعت النتيجةُ بلا حوار موافقة');
    expect(find.byType(Dialog), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('tables_merge عادي ⇒ يمرّ بلا حوار', (tester) async {
    final results = await pumpGate(tester, [PermissionCodes.tablesMerge]);
    await tester.tap(find.text('نفّذ'));
    await tester.pumpAndSettle();

    expect(results, [true]);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('بلا الكود ⇒ مرفوض بلا حوار موافقة', (tester) async {
    final results = await pumpGate(tester, const <String>[]);
    await tester.tap(find.text('نفّذ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(results, [false]);
    expect(find.byType(Dialog), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}