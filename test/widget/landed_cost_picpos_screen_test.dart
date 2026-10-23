// test/widget/landed_cost_picpos_screen_test.dart
//
// تركيبُ شاشة «التكاليف المحمَّلة» بهويّة PicPos — بعرضَين.
//
// ⚠️ **العرضان ليسا احتياطاً.** الشاشةُ تضع عمودَين جنباً إلى جنبٍ (‏٤١٠px
// لبنود التكلفة + الباقي لطرقِ التوزيع وأثرِها)، وشريطَ ملخّصٍ يحمل أيقونةً
// ورقمَ ورقةٍ وشارةَ حالةٍ وأربعةَ أرقامٍ وزرَّ تطبيق. وهذا عينُ الحمل الذي
// فاض من قبل ٢٧٤px في `PicPosPageHeader` و١٤٣px في ربط الحسابات. فالحدُّ
// `< 1100` مقيسٌ لا مذوق، ويُقاس طرفاه.
//
// و«لم ينهر» غيرُ كافٍ: يُقاس أنّ الأرقامَ الأربعةَ وجدولَ التوزيع وبطاقةَ
// القيد تظهر فعلاً عند العرضَين.
//
// ⚠️ **وخانةُ فرق التقريب تُقاس على قيمةٍ غيرِ صفريّة.** الـDAO صار يقرّب
// ويُلقي الباقيَ على أكبر بندٍ فيستوي المجموعُ بالإجماليّ — لكنّ الخانةَ
// تبقى **محسوبةً من الصفوف** لا مكتوبةً صفراً، وهذا ما يجعلها تكشف الخللَ
// إن عاد. فالصفوفُ هنا مصنوعةٌ بفرقٍ مقصودٍ ٠٫٥٠ كي يُقاس أنّها تحسب فعلاً
// بدل أن تطبع ثابتاً.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/data/providers/repository_providers.dart';
import 'package:picpos_erp/domain/entities/invoice_entity.dart';
import 'package:picpos_erp/domain/repositories/landed_cost_repository.dart';
import 'package:picpos_erp/domain/repositories/purchases_repository.dart';
import 'package:picpos_erp/presentation/landed_cost_picpos/screens/landed_cost_picpos_screen.dart';

final _sheet = db.LandedCostSheetData(
  id: 1,
  purchaseInvoiceId: 7,
  sheetNumber: 'LC-2026-0042',
  totalAdditionalCost: 27600,
  allocationMethod: 'by_value',
  status: 'draft',
  createdAt: DateTime(2026, 8, 24),
  rowVersion: 0,
);

const _items = [
  db.LandedCostItemData(
    id: 1,
    sheetId: 1,
    costType: 'shipping',
    description: 'شحن بحري — حاوية ٤٠ قدم',
    amount: 12400,
    rowVersion: 0,
  ),
  db.LandedCostItemData(
    id: 2,
    sheetId: 1,
    costType: 'customs',
    description: 'رسوم جمركية وضريبة إفراج',
    amount: 15200,
    rowVersion: 0,
  ),
];

/// صفّا توزيعٍ مجموعُ ما وُزِّع فيهما **٢٧٥٩٩٫٥٠** مقابلَ إجماليِّ ورقةٍ
/// ٢٧٦٠٠ — أي فرقٌ غيرُ موزَّعٍ مقدارُه ٠٫٥٠. وهو مصنوعٌ عمداً كي تُقاس
/// خانةُ «فرقٌ غيرُ موزَّع» على قيمةٍ غيرِ صفريّة.
const _allocations = <Map<String, dynamic>>[
  {
    'product_name': 'سكر معبأ 1ك',
    'product_code': 'SKU-1042',
    'quantity': 400.0,
    'original_cost': 22.0,
    'allocated_amount': 8800.0,
    'new_unit_cost': 44.0,
  },
  {
    'product_name': 'زيت عافية 1ل',
    'product_code': 'SKU-1108',
    'quantity': 240.0,
    'original_cost': 68.0,
    'allocated_amount': 18799.5,
    'new_unit_cost': 146.33,
  },
];

class _FakeLandedCostRepo implements ILandedCostRepository {
  @override
  Future<List<db.LandedCostSheetData>> getLandedCostSheets({
    int? purchaseInvoiceId,
  }) async =>
      [_sheet];

  @override
  Future<List<db.LandedCostItemData>> getLandedCostItems(int sheetId) async =>
      _items;

  @override
  Future<List<Map<String, dynamic>>> getAllocationsWithDetails(
          int sheetId) async =>
      _allocations;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakePurchasesRepo implements PurchasesRepository {
  @override
  Future<InvoiceEntity?> getInvoiceById(int id) async => InvoiceEntity(
        id: id,
        invoiceNumber: 'PUR-2026-0418',
        type: InvoiceType.purchase,
        partyName: 'شركة الأناضول للأغذية',
        invoiceDate: DateTime(2026, 8, 24),
        lines: const [],
        subtotal: 0,
        discountAmount: 0,
        taxAmount: 0,
        total: 0,
        paid: 0,
        status: InvoiceStatus.paid,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  double width, {
  /// `purchases_create` يفتح الشاشةَ (‏`ScreenId.landedCost`)، و
  /// `landed_cost_apply` وحدَه هو ما يحرس زرَّ التطبيق.
  ///
  /// ⚠️ والمنحُ افتراضيٌّ عن قصد: زرُّ التطبيق جزءٌ من حِمل شريط الملخّص
  /// الذي تقيسه فحوصُ الفيضان أعلاه — فإخفاؤه كان سيخفّف الحملَ ويجعلها
  /// تقيس تخطيطاً غيرَ الذي يراه المستخدم.
  List<String> perms = const ['purchases_create', 'landed_cost_apply'],
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        landedCostRepositoryProvider.overrideWithValue(_FakeLandedCostRepo()),
        purchasesRepositoryProvider.overrideWithValue(_FakePurchasesRepo()),
        currentUserPermissionsProvider.overrideWith((ref) async => perms),
      ],
      child: const MaterialApp(home: LandedCostPicposScreen()),
    ),
  );
  // الحالةُ تُحمَّل في `Future.microtask` داخلَ `build()` للـNotifier،
  // فالإطارُ الأوّلُ يعرض المؤشّرَ والثاني يعرض القائمة.
  await tester.pump();
  await tester.pump();
}

/// يفتح تفصيلَ الورقة بالضغط على بطاقتها — زرُّ التطبيق في شريط الملخّص
/// داخلَ التفصيل لا في القائمة.
Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.descendant(
    of: find.byType(InkWell),
    matching: find.text('LC-2026-0042'),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    testWidgets('قائمةُ الأوراق تُرسَم بلا فيضان عند عرض $w', (tester) async {
      await _pump(tester, width);

      expect(tester.takeException(), isNull,
          reason: 'قائمةُ أوراق التحميل فاضت عند $w.');
      expect(find.text('التكاليف المحملة'), findsOneWidget);
      expect(find.text('LC-2026-0042'), findsOneWidget,
          reason: 'بطاقةُ الورقة لا تظهر في القائمة.');
    });

    testWidgets('تفصيلُ الورقة يُرسَم كاملاً بلا فيضان عند عرض $w',
        (tester) async {
      await _pump(tester, width);

      // ⚠️ اضغطِ البطاقةَ نفسَها لا أيَّ نصٍّ يحمل الرقم: `find.text(...).first`
      //    قد تصيب عنواناً آخرَ فلا يُفتَح شيءٌ ويشكو الفحصُ من غياب نصّ.
      await tester.tap(find.descendant(
        of: find.byType(InkWell),
        matching: find.text('LC-2026-0042'),
      ));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'تفصيلُ ورقة التحميل فاض عند $w — راجعْ حدَّ التكديس '
              '(‏العمودان ٤١٠ + الباقي) وشريطَ الملخّص.');

      // الأرقامُ الأربعةُ في شريط الملخّص.
      for (final label in [
        'قيمة الفاتورة الأصلية',
        'التكلفة الإضافية',
        'قيمة المخزون الجديدة',
        'نسبة التحميل',
      ]) {
        expect(find.text(label), findsOneWidget,
            reason: 'رقمُ «$label» غائبٌ عن شريط الملخّص عند $w.');
      }

      // بنودُ التكلفة وطرقُ التوزيع وجدولُ التوزيع وبطاقةُ القيد.
      expect(find.text('بنود التكلفة'), findsOneWidget);
      expect(find.text('طريقة التوزيع'), findsOneWidget);
      expect(find.text('جدول التوزيع على الأصناف'), findsOneWidget);
      expect(find.text('القيد الذي يُنشأ عند التطبيق'), findsOneWidget);
      expect(find.text('حالة الورقة'), findsOneWidget);

      // فاتورةُ الشراء تُقرأ لقطةً لا بثّاً — فاسمُها يصل.
      expect(find.textContaining('PUR-2026-0418'), findsOneWidget,
          reason: 'رقمُ فاتورة الشراء لا يصل — راجعْ `_sheetInvoiceProvider`.');
    });

    testWidgets('«بالوزن» معروضةٌ مقفولةً لا قابلةً للنقر عند عرض $w',
        (tester) async {
      await _pump(tester, width);
      await tester.tap(find.descendant(
        of: find.byType(InkWell),
        matching: find.text('LC-2026-0042'),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('بالوزن'), findsOneWidget,
          reason: 'الطريقةُ الرابعةُ غائبةٌ — والتصميمُ يعرضها مقفولةً '
              'كي يُعرَف أنّها مؤجَّلةٌ لا منسيّة.');
      expect(find.text('غير متاح — يحتاج وزناً مسجَّلاً لكل منتج'),
          findsOneWidget,
          reason: 'سببُ القفل غيرُ مكتوب — فتبدو الطريقةُ معطَّلةً بلا تفسير.');
    });
  }

  testWidgets('خانةُ فرق التقريب محسوبةٌ من الصفوف لا مطبوعةً ثابتاً',
      (tester) async {
    await _pump(tester, 1920);
    await tester.tap(find.descendant(
      of: find.byType(InkWell),
      matching: find.text('LC-2026-0042'),
    ));
    await tester.pump();
    await tester.pump();

    // المرساة: الخانةُ موجودةٌ فعلاً — فقياسُ قيمتها بعدَها له معنى.
    expect(find.text('فرق التقريب'), findsOneWidget,
        reason: 'خانةُ فرق التقريب غائبةٌ عن بطاقة الأثر.');

    // ٢٧٦٠٠ − ٢٧٥٩٩٫٥٠ = ٠٫٥٠. ولو كانت الخانةُ تطبع صفراً ثابتاً — على
    // اعتبار أنّ الـDAO صار يسوّي المجموع — لقرأت «0.00» هنا وسقط الفحص.
    expect(find.text('0.50'), findsOneWidget,
        reason: 'الفرقُ غيرُ محسوبٍ من مجموع ما وُزِّع فعلاً — راجعْ '
            '`_impactPanel`: القيمةُ يجب أن تأتي من الصفوف لا من ثابت.');

    // والقاعدةُ مكتوبةٌ للمستخدم في رأس الجدول — لأنّ الـDAO ينفّذها الآن.
    expect(find.textContaining('فرق التقريب يُحمَّل على أكبر بند'),
        findsOneWidget,
        reason: 'قاعدةُ التقريب غيرُ مكتوبةٍ في رأس جدول التوزيع.');
  });

  // ── حارسُ زرِّ التطبيق ────────────────────────────────────────────────────
  //
  // ⚠️ **فحصان لا واحد.** نداءُ `_pump` مرّتين في اختبارٍ واحدٍ لا يقيس
  //    المنع: `ProviderScope` يُعاد استعمالُ عنصره، و`PermissionGuard` يقرأ
  //    `permissionsAsync.value` الذي **يُبقي القيمةَ السابقة** عبر
  //    `copyWithPrevious` أثناء إعادة التحميل — سلوكٌ مقصودٌ وموثَّقٌ في
  //    الحارس (يمنع ومضةَ الأزرار عند كلّ `invalidate`). فالشجرةُ الثانيةُ
  //    كانت سترث صلاحيةَ الأولى ويمرّ النفيُ زوراً. لكلِّ حالةٍ شجرةٌ من
  //    الصفر — نفسُ ترتيب فحصَي `assets_depreciation`.

  testWidgets('المرساة: زرُّ التطبيق يظهر **مع** صلاحية landed_cost_apply',
      (tester) async {
    await _pump(tester, 1920);
    await _openSheet(tester);

    expect(find.text('تطبيق الورقة'), findsOneWidget,
        reason: 'الزرُّ غائبٌ حتّى مع الصلاحيّة — فنفيُ الفحص التالي '
            'سيقيس نمطَ البحث لا الحارس.');
  });

  testWidgets('🔴 وبلا صلاحية landed_cost_apply لا يظهر إطلاقاً',
      (tester) async {
    // `applyLandedCost` تمزج `products.costPrice` و`inventory_balances.
    // average_cost` وترحّل قيدَ يوميّةٍ متوازناً وتختم الورقةَ `applied` —
    // فإذنُ فتحِ الشاشة (`purchases_create`) لا يكفي لها.
    await _pump(tester, 1920, perms: const ['purchases_create']);
    await _openSheet(tester);

    // المرساةُ أوّلاً: التفصيلُ مفتوحٌ فعلاً — وإلّا لكان الغيابُ لأنّ
    // الشاشةَ ما زالت على القائمة، لا لأنّ الحارسَ عمل.
    expect(find.text('بنود التكلفة'), findsOneWidget,
        reason: 'تفصيلُ الورقة لم يُفتَح — فالنفيُ أدناه بلا معنى.');

    expect(find.text('تطبيق الورقة'), findsNothing,
        reason: 'زرُّ التطبيق ظهر لمستخدمٍ بلا `landed_cost_apply` — أي أنّ '
            'تكلفةَ كلِّ صنفٍ تُمزَج وقيدَ يوميّةٍ يُرحَّل بلا صلاحية.');
  });
}
