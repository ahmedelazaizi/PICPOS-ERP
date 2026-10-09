import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/settings_picpos/screens/cloud_sync_conflicts_screen.dart';
import 'package:ural_erp/services/cloud_sync/cloud_link_controller.dart';
import 'package:ural_erp/services/cloud_sync/cloud_sync_service.dart';

class _CloudFake implements CloudLinkController {
  _CloudFake(this.conflicts);
  final List<CloudConflictView> conflicts;
  final retried = <String>[];
  int syncs = 0;
  @override
  Future<void> retry(String globalId) async => retried.add(globalId);
  @override
  Future<CloudSyncRunResult?> syncNow({bool fullPush = false}) async {
    syncs++;
    return null;
  }
  @override
  Future<CloudLinkView> load({bool includeSecret = true}) async => CloudLinkView(
    enabled: true, url: '', linkId: '', hasSecret: false,
    intervalMinutes: 5, posted: 0, conflicts: conflicts,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final conflicts = [
    CloudConflictView(globalId: 'customer', kind: 'sales_invoice',
        cloudNumber: 'INV-1', reason: 'customer_not_found: abc',
        attempts: 2, retryRequested: false, updatedAt: DateTime(2026, 2, 3)),
    CloudConflictView(globalId: 'totals', kind: 'sales_invoice',
        cloudNumber: 'INV-2', reason: 'totals_mismatch: desktop 45.52 ≠ cloud 40.00',
        attempts: 1, retryRequested: false, updatedAt: DateTime(2026, 2, 4)),
    CloudConflictView(globalId: 'visit', kind: 'visit',
        reason: 'rep_not_found: xyz', attempts: 1,
        retryRequested: false, updatedAt: DateTime(2026, 2, 1)),
  ];

  testWidgets('kind and reason filters show Arabic explanations and retry syncs',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cloud = _CloudFake(conflicts);
    await tester.pumpWidget(ProviderScope(
      overrides: [cloudLinkControllerProvider.overrideWithValue(cloud)],
      child: MaterialApp(home: CloudSyncConflictsScreen(conflicts: conflicts)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة مبيعات (2)'), findsOneWidget);
    expect(find.text('زيارة عميل (1)'), findsOneWidget);
    expect(find.text('العميل غير موجود على هذا الجهاز'), findsOneWidget);
    expect(find.text('اختلاف الإجمالي بين الجهاز والسحابة'), findsOneWidget);
    await tester.tap(find.text('فاتورة مبيعات (2)'));
    await tester.pumpAndSettle();
    expect(find.text('rep_not_found: xyz'), findsNothing);
    await tester.tap(find.text('اختلاف الإجمالي بين الجهاز والسحابة (1)'));
    await tester.pumpAndSettle();
    expect(find.text('العميل غير موجود على هذا الجهاز'), findsNothing);
    await tester.tap(find.text('إعادة المحاولة').last);
    await tester.pumpAndSettle();
    expect(cloud.retried, ['totals']);
    expect(cloud.syncs, 1);
  });

  testWidgets('retry all confirms and syncs once for selected kind',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cloud = _CloudFake(conflicts);
    await tester.pumpWidget(ProviderScope(
      overrides: [cloudLinkControllerProvider.overrideWithValue(cloud)],
      child: MaterialApp(home: CloudSyncConflictsScreen(conflicts: conflicts)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فاتورة مبيعات (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إعادة محاولة الكل'));
    await tester.pumpAndSettle();
    expect(cloud.retried, isEmpty);
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();
    expect(cloud.retried, ['totals', 'customer']);
    expect(cloud.syncs, 1);
  });
}
