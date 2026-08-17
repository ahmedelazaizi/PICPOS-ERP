// ═══════════════════════════════════════════════════════════════════════════
// نطاقُ الفرع في فاتورةِ المشتريات — نقلُ Spec 103 من مسارِ المبيعات
// ═══════════════════════════════════════════════════════════════════════════
//
// `PurchaseInvoiceForm` كان بيحمّل كلَّ المخازن بلا ترشيح، وده مش «حقلٌ فيه
// خيارٌ زايد» — لأن فرعَ الفاتورة **يُشتقُّ من مخزنها** لا يُختار:
//
//     purchase_dao.dart:589-594
//       final wh = await getWarehouseById(params.warehouseId);
//       resolvedBranchId = wh?.branchId;
//
// وقائمةُ الفواتير بتقصّ على `branchId.isIn(allowed) | isNull` (سطر ١٥٠)،
// فاختيارُ مخزنِ فرعٍ آخر بيخلّي الفاتورةَ **تختفي من قائمةِ فرعها**.
//
// المسارُ المرجعيُّ المنقولُ عنه: sales_invoice_dialogs.dart:٤٣٦-٤٤٥ (Spec 103)
// — `isClientMode` ثم `client_branch_id` ثم `where(branchId == …)`، ومعه
// احتياطٌ مقصود: لو الترشيحُ طلع فاضياً تفضل القائمةُ الكاملةُ ظاهرةً بدل ما
// نسلّم المستخدمَ قائمةً خاوية.
//
// ⚠️ وصفةُ فتحِ الشاشة في اختبار (test/widget/_support/screen_smoke.dart):
// فكّك الشجرةَ وادفع إطاراً بزمنٍ موجب، و**لا تُغلق القاعدة** — إغلاقُها
// بينتظر مؤقّتَ drift في المنطقة الوهمية فما بيرجعش.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/screens/purchase_invoices/widgets/purchase_invoice_form.dart';

class _ClientModeInterceptor implements SyncInterceptor {
  @override
  bool get isClientModeImpl => true;
  @override
  bool get isMirrorModeImpl => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
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
  late int hqBranchId;
  late int tantaBranchId;
  late int tantaWarehouseId;
  late int tantaCostCenterId;

  setUp(() async {
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
  });

  tearDown(() async {
    // ما نسيبش الجهازَ في وضع «عميل» للاختبارات اللي بعدها.
    SyncInterceptor.instance = null;
    SharedPreferences.setMockInitialValues({});
    // ⚠️ بلا `db.close()` — مقصود، انظر رأسَ الملف.
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    PurchaseInvoiceData? editInvoice,
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
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

  void enterClientMode(int branchId) {
    SyncInterceptor.instance = _ClientModeInterceptor();
    SharedPreferences.setMockInitialValues({'client_branch_id': branchId});
  }

  group('ترشيحُ المخازن بفرعِ العميل', () {
    testWidgets('وضعُ العميل — مخازنُ الفرعِ وحدَها', (tester) async {
      enterClientMode(tantaBranchId);

      await pumpForm(tester);

      expect(warehouseNames(tester), ['مخزن طنطا'],
          reason: 'مخزنُ فرعٍ آخر يجعل الفاتورةَ تغيب عن قائمةِ فرعها');

      await disposeTree(tester);
    });

    testWidgets('فرعٌ بلا مخازن — تبقى القائمةُ الكاملة (احتياطُ Spec 103)',
        (tester) async {
      // فرعٌ ثالثٌ لا مخزنَ له.
      final emptyBranchId = await db.into(db.branches).insert(
            BranchesCompanion.insert(
              name: 'فرعٌ بلا مخازن',
              globalId: const Value('gid-branch-empty'),
            ),
          );
      enterClientMode(emptyBranchId);

      await pumpForm(tester);

      expect(warehouseNames(tester), containsAll(['المخزن الرئيسي', 'مخزن طنطا']),
          reason: 'قائمةٌ خاويةٌ أسوأُ من قائمةٍ واسعة — الاحتياطُ مقصود');

      await disposeTree(tester);
    });

    testWidgets('الوضعُ المستقل — بلا ترشيح', (tester) async {
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
      final hqWarehouseId =
          (await db.select(db.warehouses).get()).first.id;
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

      enterClientMode(tantaBranchId);

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
      enterClientMode(tantaBranchId);

      await pumpForm(tester);

      expect(dropdownFor(tester, 'المخزن').value, tantaWarehouseId,
          reason: 'بلا انتقاءٍ مسبقٍ يصل `null` للمستودع فيحوّله `?? 1` '
              'إلى مخزنِ فرعٍ آخر بلا أيِّ إشعار');

      await disposeTree(tester);
    });

    testWidgets('مركزُ التكلفةِ يُشتقُّ من المخزنِ المنتقى', (tester) async {
      enterClientMode(tantaBranchId);

      await pumpForm(tester);

      expect(dropdownFor(tester, 'مركز التكلفة').value, tantaCostCenterId,
          reason: 'نفسُ اشتقاقِ SalesInvoiceForm — مركزُ التكلفةِ يتبع المخزن');

      await disposeTree(tester);
    });

    testWidgets('بلا مخازنَ أصلاً — الزرُّ يرفض بدل أن يخترع مخزناً',
        (tester) async {
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
