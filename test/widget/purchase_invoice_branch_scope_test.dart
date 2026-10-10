// ═══════════════════════════════════════════════════════════════════════════
// نطاقُ الفرع في فاتورةِ المشتريات — على مستوى الشاشة
// ═══════════════════════════════════════════════════════════════════════════
//
// `PurchaseInvoiceForm` كان يحمّل كلَّ المخازن بلا ترشيح، وده مش «حقلٌ فيه
// خيارٌ زايد» — لأن فرعَ الفاتورة **يُشتقُّ من مخزنها** لا يُختار:
//
//     purchase_dao.dart:589-594
//       final wh = await getWarehouseById(params.warehouseId);
//       resolvedBranchId = wh?.branchId;
//
// وقائمةُ الفواتير بتقصّ على `branchId.isIn(allowed) | isNull` (سطر ١٥٠)،
// فاختيارُ مخزنِ فرعٍ آخر بيخلّي الفاتورةَ **تختفي من قائمةِ فرعها**.
//
// والنطاقُ مصدرُه `branchScopeProvider` (يحسم الأوضاعَ الأربعة) — فالحصرُ
// يقع هنا على جهازٍ **مستقلّ** أيضاً متى كان المستخدمُ مخصَّصاً لفرع، وهو
// ما كان يفوت النموذجَ حين كان يقرأ `client_branch_id` وحدَه.
//
// وقياسُ الاشتقاقِ والسياساتِ في الأوضاع الأربعة مكانُه
// `test/data/providers/assignable_scope_test.dart`؛ هنا نقيس **الشاشة**.
//
// ⚠️ وصفةُ فتحِ الشاشة في اختبار (test/widget/_support/screen_smoke.dart):
// فكّك الشجرةَ وادفع إطاراً بزمنٍ موجب، و**لا تُغلق القاعدة**. ومعها
// `DiagnosticLogger.enableTestMode()` — `branchScopeProvider` يسجّل في كلّ
// نداء، وكتابةُ الملفّ تنتظر قناةَ `path_provider` فتتعلّق في الزمن الوهمي.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/purchase_invoices/widgets/purchase_invoice_form.dart';
import 'package:ural_erp/services/mirror_state.dart';
import 'package:ural_erp/services/network_service.dart';

UserWithRole _cashier({required int userId, required int roleId}) {
  final role = Role(
    id: roleId,
    name: 'كاشير',
    isSystemRole: false,
    createdAt: DateTime(2026),
    rowVersion: 0,
  );
  final user = User(
    id: userId,
    username: 'cashier',
    passwordHash: 'h',
    passwordSalt: 's',
    displayName: 'كاشير',
    roleId: roleId,
    defaultScreen: 'pos',
    isLocked: false,
    isActive: true,
    discountLimitIsPercent: true,
    forcePasswordChange: false,
    createdAt: DateTime(2026),
    rowVersion: 0,
  );
  return UserWithRole(user: user, role: role);
}

/// آخرُ نداءٍ وصل لـ`onSave` — `null` يعني الزرَّ رفض الحفظ.
Map<String, Object?>? _lastSave;

Future<void> _captureSave({
  required int? partyId,
  required String invoiceNumber,
  required String supplierInvoiceNumber,
  required DateTime date,
  required double total,
  required double discount,
  required double tax,
  required double netAmount,
  required double paidAmount,
  required String notes,
  required List<Map<String, dynamic>> items,
  required int? warehouseId,
  required int? costCenterId,
  required bool isDraft,
  required String paymentMethod,
  int? safeId,
  bool printAfterSave = false,
}) async {
  _lastSave = {'warehouseId': warehouseId, 'costCenterId': costCenterId};
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  // ignore: unused_local_variable
  late int hqBranchId;
  late int tantaBranchId;
  late int tantaWarehouseId;
  late int tantaCostCenterId;
  late int cashierId;
  late int cashierRoleId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DiagnosticLogger.enableTestMode();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    MirrorState.instance.debugSetForTests();
    ElevationSnapshot.isCrossBranchElevated = false;

    _lastSave = null;
    db = AppDatabase.forTesting();

    // البذرةُ بتزرع «المخزن الرئيسي» على الفرع الافتراضي — هو ده مخزنُ
    // «فرعٍ آخر» في هذا الاختبار.
    final seeded = await db.select(db.warehouses).get();
    hqBranchId = seeded.first.branchId!;

    tantaCostCenterId = await db.into(db.costCenters).insert(
          CostCentersCompanion.insert(
            code: 'CC-TANTA',
            name: 'مركز تكلفة طنطا',
            globalId: const Value('gid-cc-tanta'),
          ),
        );
    tantaBranchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'فرع طنطا',
            globalId: const Value('gid-branch-tanta'),
          ),
        );
    tantaWarehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
            name: 'مخزن طنطا',
            branchId: Value(tantaBranchId),
            costCenterId: Value(tantaCostCenterId),
            globalId: const Value('gid-wh-tanta'),
          ),
        );

    cashierRoleId =
        await db.into(db.roles).insert(RolesCompanion.insert(name: 'كاشير'));
    cashierId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'cashier',
            passwordHash: 'h',
            passwordSalt: const Value('s'),
            displayName: 'كاشير',
            roleId: Value(cashierRoleId),
          ),
        );

    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    SharedPreferences.setMockInitialValues({});
    // ⚠️ بلا `db.close()` — مقصود، انظر رأسَ الملفّ.
  });

  /// يربط الكاشيرَ بفرعٍ ثم يسجّل دخولَه — النطاقُ يأتي من هنا لا من ربطِ
  /// الجهاز، فيقع الحصرُ في الأوضاع الأربعة كلِّها.
  Future<void> loginCashierScopedTo(int branchId) async {
    await db.into(db.userBranchAccess).insert(
          UserBranchAccessCompanion.insert(userId: cashierId, branchId: branchId),
        );
    container.read(authProvider);
    container
        .read(authProvider.notifier)
        .login(_cashier(userId: cashierId, roleId: cashierRoleId));
  }

  Future<void> pumpForm(
    WidgetTester tester, {
    PurchaseInvoiceData? editInvoice,
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: PurchaseInvoiceForm(
            editInvoice: editInvoice,
            onSave: _captureSave,
          ),
        ),
      ),
    ));
    // إطارٌ للبناء وإطارٌ لِما بعد `_loadInitialData`.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// القائمةُ المنسدلةُ الداخلية — `DropdownButtonFormField` ما بيعرّضش
  /// `items`، فبنقرأ `DropdownButton` اللي جوّاه.
  DropdownButton<int> dropdownFor(WidgetTester tester, String label) {
    final field = find.ancestor(
      of: find.text(label),
      matching: find.byType(DropdownButtonFormField<int>),
    );
    return tester.widget<DropdownButton<int>>(
      find.descendant(of: field, matching: find.byType(DropdownButton<int>)),
    );
  }

  List<String> warehouseNames(WidgetTester tester) =>
      dropdownFor(tester, 'المخزن')
          .items!
          .map((i) => ((i.child as Text).data)!)
          .toList();

  group('ترشيحُ المخازن بنطاقِ الفرع', () {
    testWidgets('كاشيرُ فرعِ طنطا — مخازنُ فرعِه وحدَها', (tester) async {
      await loginCashierScopedTo(tantaBranchId);

      await pumpForm(tester);

      expect(warehouseNames(tester), ['مخزن طنطا'],
          reason: 'مخزنُ فرعٍ آخر يجعل الفاتورةَ تغيب عن قائمةِ فرعها');

      await disposeTree(tester);
    });

    testWidgets('فرعٌ بلا مخازن — تبقى القائمةُ الكاملة على جهازٍ مستقلّ',
        (tester) async {
      final emptyBranchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'فرعٌ بلا مخازن',
              globalId: const Value('gid-branch-empty'),
            ),
          );
      await loginCashierScopedTo(emptyBranchId);

      await pumpForm(tester);

      expect(warehouseNames(tester), containsAll(['المخزن الرئيسي', 'مخزن طنطا']),
          reason: 'محلٌّ بجهازٍ واحدٍ ما ينفعش يقف — سابقةُ المالك 2026-08-04');

      await disposeTree(tester);
    });

    testWidgets('مستخدمٌ بلا حصرِ فروع — بلا ترشيح', (tester) async {
      // بلا تسجيلِ دخول ⇒ `branchScopeProvider` يرجع `fullAccess`.
      await pumpForm(tester);

      expect(warehouseNames(tester),
          containsAll(['المخزن الرئيسي', 'مخزن طنطا']));

      await disposeTree(tester);
    });

    testWidgets('تعديلُ فاتورةٍ مخزنُها خارجَ الفرع — يبقى في القائمة',
        (tester) async {
      final supplierId = await db.into(db.parties).insert(
            PartiesCompanion.insert(
              name: 'مورد الاختبار',
              isSupplier: const Value(true),
              globalId: const Value('gid-party-supplier'),
            ),
          );
      final hqWarehouseId = (await db.select(db.warehouses).get()).first.id;
      final invoiceId = await db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: 'PINV-1',
              supplierId: supplierId,
              warehouseId: hqWarehouseId,
              invoiceDate: DateTime(2026, 8, 1),
              globalId: const Value('gid-pinv-1'),
            ),
          );
      final invoice = await (db.select(db.purchaseInvoices)
            ..where((t) => t.id.equals(invoiceId)))
          .getSingle();

      await loginCashierScopedTo(tantaBranchId);

      await pumpForm(tester, editInvoice: invoice);

      // قائمةٌ لا تحوي قيمتَها المنتقاةَ = انهيارُ `DropdownButton`، وحذفُ
      // المخزنِ صامتاً = إعادةُ توطينِ الفاتورةِ على فرعٍ آخر عند الحفظ.
      expect(warehouseNames(tester), contains('المخزن الرئيسي'));
      expect(dropdownFor(tester, 'المخزن').value, hqWarehouseId);

      await disposeTree(tester);
    });
  });

  group('المخزنُ الافتراضيُّ — سدُّ `warehouseId ?? 1`', () {
    testWidgets('فاتورةٌ جديدة — مخزنُ الفرعِ منتقىً سلفاً', (tester) async {
      await loginCashierScopedTo(tantaBranchId);

      await pumpForm(tester);

      expect(dropdownFor(tester, 'المخزن').value, tantaWarehouseId,
          reason: 'بلا انتقاءٍ مسبقٍ يصل `null` للمستودع فيحوّله `?? 1` '
              'إلى مخزنِ فرعٍ آخر بلا أيِّ إشعار');

      await disposeTree(tester);
    });

    testWidgets('مركزُ التكلفةِ يُشتقُّ من المخزنِ المنتقى', (tester) async {
      await loginCashierScopedTo(tantaBranchId);

      await pumpForm(tester);

      expect(dropdownFor(tester, 'مركز التكلفة').value, tantaCostCenterId,
          reason: 'نفسُ اشتقاقِ SalesInvoiceForm — مركزُ التكلفةِ يتبع المخزن');

      await disposeTree(tester);
    });

    testWidgets('بلا مخازنَ أصلاً — الزرُّ يرفض بدل أن يخترع مخزناً',
        (tester) async {
      // v195 — مواقعُ المخزن (bins) أبناءٌ له؛ تُمسح أولاً وإلا سقط الحذفُ بـ787.
      await db.customStatement('DELETE FROM location_stock');
      await db.customStatement('DELETE FROM warehouse_locations');
      await db.delete(db.warehouses).go();

      await pumpForm(tester);
      await tester.tap(find.text('حفظ الفاتورة'));
      await tester.pump();

      expect(_lastSave, isNull, reason: 'رفضٌ صريحٌ أوضحُ من فرعٍ خاطئٍ صامت');
      // نصٌّ كاملٌ لا `textContaining('المخزن')` — عنوانُ القائمةِ المنسدلة
      // نفسُه «المخزن»، فالمطابقةُ الجزئيةُ كانت تنجح بلا أيِّ رسالة.
      expect(find.text('يجب اختيار المخزن قبل حفظ الفاتورة'), findsOneWidget,
          reason: 'الرسالةُ لازم تسمّي الحقلَ الناقصَ بعينه');

      // مؤقّتُ إخفاءِ الـtoast (٢٫٥ث) لازم يُطلَق قبل تفكيكِ الشجرة.
      await tester.pump(const Duration(seconds: 3));
      await disposeTree(tester);
    });
  });
}
