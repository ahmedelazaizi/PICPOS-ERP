import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/database/database.dart' as db;
import 'package:ural_erp/data/providers/manufacturing_providers.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/domain/repositories/inventory_repository.dart';
import 'package:ural_erp/domain/repositories/reporting_repository.dart';
import 'package:ural_erp/presentation/reports_picpos/screens/consumption_report_picpos_screen.dart';
import 'package:ural_erp/presentation/reports_picpos/screens/delivery_report_picpos_screen.dart';
import 'package:ural_erp/presentation/reports_picpos/screens/expired_products_report_picpos_screen.dart';
import 'package:ural_erp/presentation/reports_picpos/screens/low_stock_report_picpos_screen.dart';
import 'package:ural_erp/presentation/reports_picpos/screens/near_expiry_report_picpos_screen.dart';
import 'package:ural_erp/presentation/reports_picpos/screens/reports_picpos_screen.dart';
import 'package:ural_erp/presentation/reports_picpos/screens/tax_report_picpos_screen.dart';

final _date = DateTime(2026, 5, 10, 12);

ProductEntity _product({int id = 1}) => ProductEntity(
      id: id,
      code: 'P-$id',
      name: 'منتج الاختبار $id',
      salePrice: 100,
      costPrice: 40,
      currentStock: 2,
      minStock: 7,
      warehouseId: 1,
    );

db.SalesInvoiceData _invoice({double tax = 14, double deliveryFee = 9}) =>
    db.SalesInvoiceData(
      id: 1,
      invoiceNumber: 'INV-1',
      warehouseId: 1,
      userId: 1,
      invoiceDate: _date,
      subtotal: 100,
      discount: 0,
      tax: tax,
      total: 114,
      paid: 114,
      paidUnallocated: 114,
      roundingAdjustment: 0,
      cashPaid: 114,
      bankPaid: 0,
      clickPaid: 0,
      paymentMethod: 'cash',
      saleType: 'sale',
      status: 'completed',
      deliveryStatus: 'delivered',
      deliveryFee: deliveryFee,
      isLocked: false,
      isDeleted: false,
      updatedAt: _date,
      rowVersion: 1,
      createdAt: _date,
    );

class _ExcelSpy {
  int calls = 0;
  List<List<dynamic>> rows = const [];

  Future<String?> exportReport({
    required String title,
    required List<String> headers,
    required List<List<dynamic>> rows,
    DateTime? periodFrom,
    DateTime? periodTo,
    int? branchId,
    Set<int>? scopedBranchIds,
  }) async {
    calls++;
    this.rows = rows;
    return 'test.xlsx';
  }
}

class _ReportingSpy implements IReportingRepository {
  _ReportingSpy({required this.delivery, required this.tax});

  final List<Map<String, dynamic>> delivery;
  final Map<String, dynamic> tax;

  @override
  Future<List<Map<String, dynamic>>> getDeliveryReport({
    required DateTime from,
    required DateTime to,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) async => delivery;

  @override
  Future<Map<String, dynamic>> getTaxReport(DateTime from, DateTime to,
          {int? costCenterId,
          List<int>? warehouseIds,
          int? branchId,
          Set<int>? allowedBranchIds}) async =>
      tax;

  @override
  Future<List<db.SalesInvoiceData>> getSalesByDateRange(
    DateTime start,
    DateTime end, {
    int? userId,
    List<int>? warehouseIds,
    int? costCenterId,
    Set<int>? allowedBranchIds,
    bool revenueOnly = false,
    bool excludeVoided = false,
  }) async => [_invoice()];

  @override
  Future<List<PurchaseInvoiceWithSupplier>>
      getPurchasesWithSupplierByDateRange(
    DateTime start,
    DateTime end, {
    List<int>? warehouseIds,
    int? costCenterId,
    Set<int>? allowedBranchIds,
  }) async => [];

  @override
  Future<List<Map<String, dynamic>>> getSalesTaxDetailByItem(
    DateTime from,
    DateTime to, {
    int? costCenterId,
    List<int>? warehouseIds,
    int? branchId,
    Set<int>? allowedBranchIds,
  }) async => [];

  @override
  Future<List<Map<String, dynamic>>> getSalesTaxByRate(
    DateTime from,
    DateTime to, {
    int? costCenterId,
    List<int>? warehouseIds,
    int? branchId,
    Set<int>? allowedBranchIds,
  }) async => [
        {'taxRate': 14.0, 'taxableBase': 100.0, 'taxAmount': 14.0},
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

List<dynamic> _base({
  Object? excel,
  IReportingRepository? reporting,
}) => [
      currentUserPermissionsProvider.overrideWith(
        (ref) async => [PermissionCodes.reportsExport],
      ),
      branchScopeProvider.overrideWith((ref) async => const BranchScope.fullAccess()),
      allProductsProvider.overrideWith((ref) => Stream.value([_product()])), 
      allCategoriesProvider.overrideWith((ref) => Stream.value(const <db.Category>[])),
      allWarehousesProvider.overrideWith((ref) => Stream.value(const <WarehouseData>[])),
      allRegionsProvider.overrideWith((ref) => Stream.value(const <RegionData>[])),
      branchListProvider.overrideWith((ref) async => const <db.Branche>[]),
      warehouseListProvider.overrideWith((ref) async => const <db.Warehouse>[]),
      allDeliveryPartiesProvider.overrideWith((ref) => Stream.value(const <Party>[])),
      if (excel != null) excelServiceProvider.overrideWithValue(excel),
      if (reporting != null)
        reportingRepositoryProvider.overrideWithValue(reporting),
    ];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required db.AppDatabase database,
  double width = 1280,
  List<dynamic> overrides = const [],
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...overrides,
      databaseProvider.overrideWithValue(database),
    ],
    child: _app(child),
  ));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 3),
    );

Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _seedConsumptionDatabase(db.AppDatabase database) async {
  final consumptionDate = DateTime.now();
  final rawId = await database.into(database.products).insert(
        db.ProductsCompanion.insert(code: 'RM-1', name: 'خام الاختبار'),
      );
  final invoiceId = await database.into(database.salesInvoices).insert(
        db.SalesInvoicesCompanion.insert(
          invoiceNumber: 'C-1',
          warehouseId: 1,
          userId: 1,
          invoiceDate: consumptionDate,
        ),
      );
  final itemId = await database.into(database.salesInvoiceItems).insert(
        db.SalesInvoiceItemsCompanion.insert(
          invoiceId: invoiceId,
          productId: rawId,
          quantity: 1,
          unitPrice: 1,
          total: 1,
        ),
      );
  final bomId = await database.into(database.billOfMaterials).insert(
        db.BillOfMaterialsCompanion.insert(
          finishedProductId: rawId,
          bomCode: 'B-1',
        ),
      );
  await database.into(database.saleBomConsumptions).insert(
        db.SaleBomConsumptionsCompanion.insert(
          saleInvoiceId: invoiceId,
          saleInvoiceItemId: itemId,
          bomId: bomId,
          rawMaterialId: rawId,
          consumedQty: 5,
          unitCostAtSale: 2,
          warehouseId: 1,
          globalId: 'consumption-test-1',
          createdAt: Value(consumptionDate),
        ),
      );
}

void main() {
  testWidgets('low stock renders KPI/table values, filters, and exports', (tester) async {
    final database = db.AppDatabase.forTesting();
    addTearDown(database.close);
    final spy = _ExcelSpy();
    await _pump(
      tester,
      const LowStockReportPicposScreen(),
      database: database,
      overrides: [
        ..._base(excel: spy),
        lowStockAlertProvider.overrideWith((ref) async => [_product()]),
      ],
    );
    await _settle(tester);
    expect(find.text('أصناف تحت الحد'), findsOneWidget);
    expect(find.text('منتج الاختبار 1'), findsOneWidget);
    expect(find.textContaining('5.00'), findsWidgets);
    await tester.enterText(find.byType(TextField).first, 'منتج الاختبار');
    await tester.pump();
    expect(find.text('منتج الاختبار 1'), findsOneWidget);
    await tester.tap(find.byTooltip('تصدير Excel'));
    await _drainToast(tester);
    expect(spy.calls, 1);
    expect(spy.rows.single[2], 2.0);
  });

  testWidgets('inventory alert screens show loading and empty states', (tester) async {
    final database = db.AppDatabase.forTesting();
    addTearDown(database.close);
    final lowCompleter = Completer<List<ProductEntity>>();
    await _pump(
      tester,
      const LowStockReportPicposScreen(),
      database: database,
      width: 800,
      overrides: [
        ..._base(),
        lowStockAlertProvider.overrideWith((ref) => lowCompleter.future),
      ],
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    lowCompleter.complete(const []);
    await _settle(tester);
    expect(find.text('لا توجد أصناف منخفضة المخزون'), findsOneWidget);

    await _pump(
      tester,
      const ExpiredProductsReportPicposScreen(),
      database: database,
      width: 800,
      overrides: [
        ..._base(),
        expiredProductsAlertProvider.overrideWith((ref) async => const []),
      ],
    );
    await _settle(tester);
    expect(find.text('لا توجد منتجات منتهية الصلاحية'), findsOneWidget);

    await _pump(
      tester,
      const NearExpiryReportPicposScreen(),
      database: database,
      width: 800,
      overrides: [
        ..._base(),
        nearExpiryAlertProvider.overrideWith((ref, days) async => const []),
      ],
    );
    await _settle(tester);
    expect(find.text('لا توجد منتجات قاربت على الانتهاء'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired and near-expiry exports use displayed rows and day filter', (tester) async {
    final database = db.AppDatabase.forTesting();
    addTearDown(database.close);
    final spy = _ExcelSpy();
    final batch = ProductBatchData(
      id: 1,
      productId: 1,
      batchNumber: 'B-1',
      expiryDate: _date.add(const Duration(days: 5)),
      quantity: 3,
      costPrice: 40,
      createdAt: _date,
    );
    await _pump(
      tester,
      const NearExpiryReportPicposScreen(),
      database: database,
      width: 1920,
      overrides: [
        ..._base(excel: spy),
        nearExpiryAlertProvider.overrideWith((ref, days) async => [batch]),
      ],
    );
    await _settle(tester);
    expect(find.text('3.00'), findsWidgets);
    await tester.tap(find.text('7 يوم'));
    await _settle(tester);
    expect(find.text('3.00'), findsWidgets);
    await tester.tap(find.byTooltip('تصدير Excel'));
    await _drainToast(tester);
    expect(spy.calls, 1);
    expect(spy.rows.single[2], 3.0);

    await _pump(
      tester,
      const ExpiredProductsReportPicposScreen(),
      database: database,
      overrides: [
        ..._base(excel: spy),
        expiredProductsAlertProvider.overrideWith((ref) async => [batch]),
      ],
    );
    await _settle(tester);
    expect(find.text('منتج الاختبار 1'), findsOneWidget);
    await tester.tap(find.byTooltip('تصدير Excel'));
    await _drainToast(tester);
    expect(spy.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delivery and tax numbers come from their reporting queries', (tester) async {
    final database = db.AppDatabase.forTesting();
    addTearDown(database.close);
    final spy = _ExcelSpy();
    final invoice = _invoice();
    final reporting = _ReportingSpy(
      delivery: [
        {'invoice': invoice, 'courier': null, 'company': null},
      ],
      tax: {
        'salesTax': 14.0,
        'purchaseTax': 4.0,
        'netTax': 10.0,
        'salesTotalExclTax': 100.0,
        'purchaseTotalExclTax': 20.0,
      },
    );
    await _pump(
      tester,
      const DeliveryReportPicposScreen(),
      database: database,
      width: 800,
      overrides: [..._base(excel: spy, reporting: reporting)],
    );
    await _settle(tester);
    expect(find.text('إجمالي العمليات'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.textContaining('9.000'), findsWidgets);
    await tester.tap(find.byTooltip('تصدير Excel'));
    await _drainToast(tester);
    expect(spy.calls, 1);

    await _pump(
      tester,
      const TaxReportPicposScreen(),
      database: database,
      width: 800,
      overrides: [..._base(excel: spy, reporting: reporting)],
    );
    await _settle(tester);
    expect(find.text('14.000 JOD'), findsWidgets);
    expect(find.text('10.000 JOD'), findsWidgets);
    await tester.tap(find.byTooltip('توضيح صافي الضريبة'));
    await tester.pump();
    expect(find.textContaining('صافي الضريبة ='), findsOneWidget);
    await tester.tap(find.byTooltip('تصدير Excel'));
    await _drainToast(tester);
    expect(spy.calls, 2);
    expect(salesTaxNet(14, 4), 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('consumption displays the total returned by the legacy query', (tester) async {
    final database = db.AppDatabase.forTesting();
    addTearDown(database.close);
    await tester.runAsync(() => _seedConsumptionDatabase(database));
    final spy = _ExcelSpy();
    await _pump(
      tester,
      const ConsumptionReportPicposScreen(),
      database: database,
      width: 800,
      overrides: [..._base(excel: spy)],
    );
    await _settle(tester);
    expect(find.textContaining('10.000'), findsWidgets,
        reason: '5 consumed units × cost 2 must equal 10');
    await tester.tap(find.byTooltip('تصدير Excel'));
    await _drainToast(tester);
    expect(spy.calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('inventory catalog actions navigate to screens, not dialogs', (tester) async {
    Widget? opened;
    final categories = buildPicposReportCatalog(
      actions: PicposReportActions(
        open: (builder) => opened = builder(),
        showLowStock: () {},
        showExpired: () {},
        showExpiring: () {},
        showArReconciliation: () {},
        showInventoryGlReconciliation: () {},
      ),
      eInvoicePlatform: null,
    );
    final inventory = categories.firstWhere((category) => category.id == 'inventory');
    for (final id in ['low_stock', 'expired_products', 'expiring_products']) {
      opened = null;
      inventory.mainReports.firstWhere((report) => report.id == id).action();
      expect(opened, isA<Widget>());
      expect(opened, isNot(isA<AlertDialog>()));
    }
  });
}
