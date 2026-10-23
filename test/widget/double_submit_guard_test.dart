// E-3: ضغطتان سريعتان على «حفظ» لا تُنشئان سجلّاً مرّتين.
//
// الإنشاءُ يُعلَّق على Completer حتى يبقى الحفظُ "في الطيران" أثناء الضغطة
// الثانية — وهذا هو الظرف الحقيقيّ: خدمةٌ بطيئةٌ + يدٌ سريعة.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/accounting_repository.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/presentation/screens/parties/providers/party_groups_controller.dart'
    show activePartyGroupsProvider;
import 'package:ural_erp/presentation/bookings_picpos/widgets/new_booking_panel.dart';
import 'package:ural_erp/presentation/parties_picpos/dialogs/add_party_dialog_picpos.dart';
import 'package:ural_erp/presentation/screens/tables_screen.dart'
    show showTableReservationDialog;
import 'package:ural_erp/services/booking_actions_service.dart';
import 'package:ural_erp/services/table_session_service.dart';

class _FakeBookingActions implements BookingActionsService {
  int calls = 0;
  final gate = Completer<int>();

  @override
  Future<int> create({
    required String customerName,
    String? customerPhone,
    int? partyId,
    required int serviceId,
    int? resourceId,
    required DateTime startsAt,
    double depositAmount = 0,
    String? notes,
    int? branchId,
    required int? userId,
    required String userName,
  }) {
    calls++;
    return gate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeSession implements TableSessionService {
  int calls = 0;
  final gate = Completer<void>();

  @override
  Future<void> reserveTable({
    required int tableId,
    required String customerName,
    String? customerPhone,
    int? partyId,
    required DateTime reservationTime,
    required int partySize,
    String? notes,
    required int? userId,
    required String userName,
  }) {
    calls++;
    return gate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeAccounting implements IAccountingRepository {
  @override
  Future<List<CostCenter>> getActiveCostCenters() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeParties implements IPartiesRepository {
  int inserts = 0;
  final gate = Completer<int>();

  @override
  Future<int> insertParty(PartiesCompanion party) {
    inserts++;
    return gate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// لا يُستعمل `pumpAndSettle` حيث تدور مؤشّراتُ تحميلٍ بلا نهاية.
Future<void> _pumpFrames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// بلا `customers_view` يُعرض نموذجُ الضيف مباشرةً؛ وإلّا يُدخَل منه.
Future<void> _enterGuest(WidgetTester tester, String name) async {
  final query = find.byKey(const ValueKey('customer_picker_query'));
  if (query.evaluate().isNotEmpty) {
    await tester.enterText(query, name);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('customer_result_guest')));
    await _pumpFrames(tester);
  }
  await tester.enterText(
      find.byKey(const ValueKey('customer_guest_name')), name);
  await _pumpFrames(tester);
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<void> bigScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('لوحُ الحجز الجديد: نقرتان سريعتان ⇒ إنشاءٌ واحد', (tester) async {
    await bigScreen(tester);
    final fake = _FakeBookingActions();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          bookingActionsServiceProvider.overrideWithValue(fake),
          currentUserPermissionsProvider
              .overrideWith((ref) => const ['bookings_add']),
          bookingServicesProvider.overrideWith(
            (ref) => Stream.value([
              BookingService(
                id: 1,
                name: 'قصّ شعر',
                durationMinutes: 45,
                bufferMinutes: 0,
                price: 500,
                colorHex: '#0250D3',
                isActive: true,
                sortOrder: 0,
                createdAt: DateTime(2026, 1, 1),
                rowVersion: 0,
              ),
            ]),
          ),
          bookingResourcesProvider
              .overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showNewBookingPanel(context,
                    onDay: DateTime.now().add(const Duration(days: 3))),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('افتح'));
    await _pumpFrames(tester);

    await tester.tap(find.byType(DropdownButton<int>).first);
    await _pumpFrames(tester);
    await tester.tap(find.text('قصّ شعر').last);
    await _pumpFrames(tester);
    await _enterGuest(tester, 'سارة');

    final save = find.widgetWithText(ElevatedButton, 'حفظ الحجز');
    expect(tester.widget<ElevatedButton>(save).onPressed, isNotNull,
        reason: 'الحفظُ لا يزال ممنوعاً — التجهيزةُ ناقصة');

    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.calls, 1, reason: 'الضغطةُ الثانية أنشأت حجزاً مكرّراً');
    expect(tester.widget<ElevatedButton>(save).onPressed, isNull,
        reason: 'الزرُّ يبقى معطَّلاً أثناء الحفظ');

    fake.gate.complete(1);
    await _pumpFrames(tester);
    expect(fake.calls, 1);
    await _finish(tester);
  });

  testWidgets('حوارُ حجز الطاولة: نقرتان سريعتان ⇒ حجزٌ واحد', (tester) async {
    await bigScreen(tester);
    final fake = _FakeSession();
    final table = RestaurantTable(
      id: 5,
      sectionId: 1,
      name: 'T5',
      capacity: 4,
      status: 'available',
      x: 0,
      y: 0,
      shape: 'square',
      lastStatusAt: DateTime(2026, 10, 18),
      isActive: true,
      createdAt: DateTime(2026, 10, 18),
      rowVersion: 0,
      rotation: 0,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          tableSessionServiceProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showTableReservationDialog(context, ref, table),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('افتح'));
    await _pumpFrames(tester);
    await _enterGuest(tester, 'خالد');

    final confirm = find.widgetWithText(ElevatedButton, 'تأكيد الحجز');
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.calls, 1, reason: 'الضغطةُ الثانية أنشأت حجزاً مكرّراً');

    fake.gate.complete();
    await _pumpFrames(tester);
    expect(fake.calls, 1);
    await _finish(tester);
  });

  testWidgets('إضافة عميلٍ سريعة: نقرتان سريعتان ⇒ إدراجٌ واحد', (tester) async {
    await bigScreen(tester);
    final fake = _FakeParties();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partiesRepositoryProvider.overrideWithValue(fake),
          accountingRepositoryProvider.overrideWithValue(_FakeAccounting()),
          allBranchesProvider.overrideWith((ref) => Stream.value(const [])),
          activePartyGroupsProvider
              .overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showAddPartyDialogPicpos(context, ref,
                    initialName: 'منى'),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('افتح'));
    await _pumpFrames(tester);

    final save = find.widgetWithText(ElevatedButton, 'حفظ');
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.inserts, 1, reason: 'الضغطةُ الثانية أنشأت عميلاً مكرّراً');

    fake.gate.complete(7);
    await _pumpFrames(tester);
    expect(fake.inserts, 1);
    await _finish(tester);
  });
}