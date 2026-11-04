// زرُّ «مرتجع» في `PosPreviousInvoicesDialog` (بند ٧ من
// docs/plans/2026-10-30-study-pos-quicksale.md):
//  • يظهر فقط عند تمرير `onReturn` (الشاشةُ القديمة لا تتأثّر)،
//  • يحترم `showReturnButtonInPOSProvider`،
//  • لا يظهر لفاتورة مرتجعٍ أو مرتجعةٍ كلّياً،
//  • يمرّر الفاتورةَ المختارة بعينها.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/data/providers/repository_providers.dart';
import 'package:picpos_erp/data/providers/settings_providers.dart';
import 'package:picpos_erp/domain/repositories/auth_repository.dart';
import 'package:picpos_erp/domain/repositories/sales_repository.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/presentation/pos/widgets/pos_previous_invoices_dialog.dart';

db.SalesInvoiceData _invoice(
  int id, {
  String saleType = 'default',
  String status = 'completed',
}) =>
    db.SalesInvoiceData(
      id: id,
      invoiceNumber: 'POS-$id',
      warehouseId: 1,
      userId: 1,
      invoiceDate: DateTime(2026, 1, 1),
      subtotal: 100,
      discount: 0,
      tax: 0,
      total: 100,
      paid: 100,
      paidUnallocated: 100,
      roundingAdjustment: 0,
      cashPaid: 100,
      bankPaid: 0,
      clickPaid: 0,
      paymentMethod: 'cash',
      saleType: saleType,
      status: status,
      deliveryFee: 0,
      isLocked: true,
      isDeleted: false,
      updatedAt: DateTime(2026, 1, 1),
      rowVersion: 1,
      createdAt: DateTime(2026, 1, 1),
    );

class _Auth extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        userWithRole: db.UserWithRole(
          user: db.User(
            id: 1,
            username: 'tester',
            passwordHash: '',
            passwordSalt: '',
            displayName: 'كاشير',
            defaultScreen: '0',
            isLocked: false,
            isActive: true,
            discountLimitIsPercent: true,
            forcePasswordChange: false,
            createdAt: DateTime(2026, 1, 1),
            rowVersion: 1,
          ),
        ),
      );
}

class _Sales implements SalesRepository {
  _Sales(this.rows);
  final List<db.SalesInvoiceData> rows;
  @override
  Stream<List<db.SalesInvoiceData>> watchTodaySalesForUser(int userId) =>
      Stream.value(rows);
  @override
  Stream<List<db.SalesInvoiceData>> watchTodaySales() => Stream.value(rows);
  @override
  Stream<List<db.SalesInvoiceData>> watchSalesSince(DateTime from,
          {int? userId}) =>
      Stream.value(rows);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Treasury implements ITreasuryRepository {
  @override
  Future<ShiftData?> getCurrentOpenShift(int userId) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AuthRepo implements IAuthRepository {
  @override
  Stream<List<db.UserWithRole>> watchAllUsers() => Stream.value(const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  required List<db.SalesInvoiceData> rows,
  void Function(db.SalesInvoiceData)? onReturn,
  bool showReturnSetting = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_Auth.new),
        salesRepositoryProvider.overrideWithValue(_Sales(rows)),
        treasuryRepositoryProvider.overrideWithValue(_Treasury()),
        authRepositoryProvider.overrideWithValue(_AuthRepo()),
        showReturnButtonInPOSProvider
            .overrideWith((ref) async => showReturnSetting),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PosPreviousInvoicesDialog(
            onEdit: (_) {},
            onReprint: (_) {},
            onPrintKitchen: (_) {},
            onReturn: onReturn,
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  Finder returnBtn(int id) => find.byKey(ValueKey('previous_invoice_return_$id'));

  testWidgets('مع onReturn: الزرُّ يظهر ويمرّر الفاتورةَ المختارة', (tester) async {
    db.SalesInvoiceData? got;
    await _pump(tester,
        rows: [_invoice(1), _invoice(2)], onReturn: (inv) => got = inv);

    expect(returnBtn(1), findsOneWidget);
    expect(returnBtn(2), findsOneWidget);
    await tester.tap(returnBtn(2));
    expect(got?.id, 2);
  });

  testWidgets('بلا onReturn: لا زرَّ (الشاشةُ القديمة لا تتأثّر)', (tester) async {
    await _pump(tester, rows: [_invoice(1)]);
    expect(find.byTooltip('إعادة طباعة'), findsOneWidget); // الصفُّ مرسوم
    expect(returnBtn(1), findsNothing);
    expect(find.byTooltip('مرتجع'), findsNothing);
  });

  testWidgets('إعداد show_return_button_pos=false يُخفي الزرَّ', (tester) async {
    await _pump(tester,
        rows: [_invoice(1)], onReturn: (_) {}, showReturnSetting: false);
    expect(find.byTooltip('إعادة طباعة'), findsOneWidget);
    expect(returnBtn(1), findsNothing);
  });

  testWidgets('لا زرَّ لفاتورة مرتجعٍ ولا لمرتجعةٍ كلّياً', (tester) async {
    await _pump(tester, rows: [
      _invoice(1),
      _invoice(2, saleType: 'return'),
      _invoice(3, status: 'returned'),
    ], onReturn: (_) {});
    expect(returnBtn(1), findsOneWidget);
    expect(returnBtn(2), findsNothing);
    expect(returnBtn(3), findsNothing);
  });

  test('canReturnFromPreviousInvoices', () {
    expect(canReturnFromPreviousInvoices(_invoice(1)), isTrue);
    expect(canReturnFromPreviousInvoices(_invoice(1, status: 'partial_return')),
        isTrue);
    expect(canReturnFromPreviousInvoices(_invoice(1, saleType: 'return')),
        isFalse);
    expect(canReturnFromPreviousInvoices(_invoice(1, status: 'returned')),
        isFalse);
  });
}
