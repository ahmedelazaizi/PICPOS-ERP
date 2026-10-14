import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/providers/manufacturing_providers.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/reporting_repository.dart';
import 'package:ural_erp/presentation/screens/reports/sales_by_classification_report.dart';

class _DelayedReportingRepository implements IReportingRepository {
  final List<Completer<List<SalesByCategoryRow>>> categoryRequests = [];
  final List<Completer<List<SalesBySaleTypeRow>>> saleTypeRequests = [];
  Set<int>? categoryAllowedBranchIds;
  Set<int>? saleTypeAllowedBranchIds;

  @override
  Future<List<SalesByCategoryRow>> getSalesByCategory({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) {
    categoryAllowedBranchIds = allowedBranchIds;
    final request = Completer<List<SalesByCategoryRow>>();
    categoryRequests.add(request);
    return request.future;
  }

  @override
  Future<List<SalesBySaleTypeRow>> getSalesBySaleType({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) {
    saleTypeAllowedBranchIds = allowedBranchIds;
    final request = Completer<List<SalesBySaleTypeRow>>();
    saleTypeRequests.add(request);
    return request.future;
  }

  @override
  Future<List<SalesInvoiceSummaryRow>> getSalesInvoicesBySaleType({
    required String saleType,
    required DateTime from,
    required DateTime to,
    Set<int>? allowedBranchIds,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'category content survives secondary failure without widening branch scope',
    (tester) async {
      final repository = _DelayedReportingRepository();
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            branchScopeProvider.overrideWithValue(
              const AsyncData(
                BranchScope(allowedBranchIds: {7}, primaryBranchId: 7),
              ),
            ),
            activeBranchIdProvider.overrideWithValue(
              const AsyncData<int?>(null),
            ),
            currentUserPermissionsProvider.overrideWithValue(
              const AsyncData([PermissionCodes.reportsOrderType]),
            ),
            allRegionsProvider.overrideWith(
              (ref) => Stream.value(const <RegionData>[]),
            ),
            branchListProvider.overrideWith((ref) async => const <Branche>[]),
            warehouseListProvider.overrideWith(
              (ref) async => const <Warehouse>[],
            ),
            reportingRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            supportedLocales: [Locale('ar'), Locale('en')],
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: SalesByClassificationReport(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(repository.categoryAllowedBranchIds, {7});
      expect(repository.saleTypeAllowedBranchIds, {7});
      expect(find.text('ألبان'), findsNothing);

      repository.saleTypeRequests[0].completeError(
        StateError('secondary query failed'),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);

      repository.categoryRequests[0].complete(const [
        SalesByCategoryRow(category: 'ألبان', quantity: 2, total: 30),
      ]);
      await tester.pump();
      await tester.pump();

      expect(find.text('ألبان'), findsOneWidget);
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();
      expect(find.textContaining('secondary query failed'), findsOneWidget);
    },
  );

  testWidgets('late older filter responses cannot replace the latest report', (
    tester,
  ) async {
    final repository = _DelayedReportingRepository();
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          branchScopeProvider.overrideWithValue(
            const AsyncData(
              BranchScope(allowedBranchIds: {7}, primaryBranchId: 7),
            ),
          ),
          activeBranchIdProvider.overrideWithValue(const AsyncData<int?>(null)),
          currentUserPermissionsProvider.overrideWithValue(
            const AsyncData([PermissionCodes.reportsOrderType]),
          ),
          allRegionsProvider.overrideWith(
            (ref) => Stream.value(const <RegionData>[]),
          ),
          branchListProvider.overrideWith((ref) async => const <Branche>[]),
          warehouseListProvider.overrideWith(
            (ref) async => const <Warehouse>[],
          ),
          reportingRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          locale: Locale('ar'),
          supportedLocales: [Locale('ar'), Locale('en')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: SalesByClassificationReport(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('اليوم').first);
    await tester.pump();
    await tester.pump();

    repository.categoryRequests[1].complete(const [
      SalesByCategoryRow(category: 'Latest category', quantity: 1, total: 5),
    ]);
    repository.saleTypeRequests[1].complete(const [
      SalesBySaleTypeRow(type: 'latest-type', count: 1, total: 10),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Latest category'), findsOneWidget);

    repository.categoryRequests[0].complete(const [
      SalesByCategoryRow(category: 'Stale category', quantity: 9, total: 90),
    ]);
    repository.saleTypeRequests[0].completeError(
      StateError('stale secondary failure'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Latest category'), findsOneWidget);
    expect(find.text('Stale category'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();
    expect(find.text('latest-type'), findsOneWidget);
    expect(find.textContaining('stale secondary failure'), findsNothing);
  });
}
