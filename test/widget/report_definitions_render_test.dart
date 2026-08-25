// التعريفاتُ السبعةُ تُركَّب على قاعدةٍ حقيقيّة.
//
// ═══ لماذا لا يكفي اختبارُ العارض وحدَه ═══
//
// `report_view_picpos_test` يقيس العارضَ بمحمِّلٍ وهميّ — فيمسك التخطيطَ
// والشارةَ والإخفاق، ولا يمسّ التعريفاتِ نفسَها. وثلاثةُ أعطابٍ تعيش
// حصراً في التعريف ولا يراها التحليل:
//
//  ‏١) **صفُّ المجاميع أقصرُ من الأعمدة.** `PicPosDataTable` يؤكّد تساويَهما
//     في `assert` — أي أنّه ينفجر في التشغيل لا في التحليل. سبعةُ جداولَ
//     هنا لكلٍّ صفُّ مجاميعَ مكتوبٌ بيد.
//  ‏٢) **SQL يرمي.** عمودٌ باسمٍ خاطئٍ أو ضمٌّ ناقصٌ لا يظهر إلّا عند
//     التنفيذ — والعارضُ يبتلعه في بطاقة «تعذّر حسابُ التقرير»، فيبدو
//     التقريرُ «يعمل» وهو لا يعمل. ولذلك يشترط الفحصُ **غيابَ** تلك
//     البطاقة صراحةً.
//  ‏٣) **فيضُ التخطيط بمحتوىً حقيقيّ** — أسماءٌ عربيّةٌ طويلةٌ وأرقامٌ
//     بعملة، لا نصوصٌ قصيرةٌ مصنوعةٌ للاختبار.
//
// ⚠️ ولا `db.close()` في التفكيك — يعلّق في المنطقة الوهميّة بانتظار
// مؤقّت drift.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/reports_picpos/screens/report_definitions_picpos.dart';
import 'package:ural_erp/presentation/reports_picpos/screens/report_view_picpos_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await _seed(db);
  });

  // ⚠️ بلا `db.close()` عمداً — انظر رأسَ الملفّ.

  Future<void> open(
    WidgetTester tester,
    PicPosReportDefinition def,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          branchScopeProvider
              .overrideWith((_) async => const BranchScope.fullAccess()),
        ],
        child: MaterialApp(home: ReportViewPicposScreen(definition: def)),
      ),
    );
    await tester.pumpAndSettle();
  }

  final defs = <String, PicPosReportDefinition Function()>{
    'هامش الربح': profitMarginReport,
    'سلوك العملاء': () => partyBehaviorReport(suppliers: false),
    'سلوك الموردين': () => partyBehaviorReport(suppliers: true),
    'تقسيم RFM': customerSegmentsReport,
    'اتجاه المبيعات': salesTrendReport,
    'دوران المخزون': inventoryTurnoverReport,
    'نشاط المستخدمين': userActivityReport,
  };

  for (final entry in defs.entries) {
    for (final w in const {'عريض': Size(1500, 950), 'ضيّق': Size(760, 900)}
        .entries) {
      testWidgets('«${entry.key}» تُركَّب على عرضٍ ${w.key}', (tester) async {
        await open(tester, entry.value(), w.value);
        expect(tester.takeException(), isNull);
        // ⚠️ الفحصُ الذي يمنع «يبدو أنّه يعمل»: بطاقةُ الإخفاق غائبة.
        expect(find.text('تعذّر حسابُ التقرير'), findsNothing,
            reason: 'الاستعلامُ رمى — والعارضُ ابتلعه في بطاقة');
        // والدوّارةُ انتهت.
        expect(find.byType(CircularProgressIndicator), findsNothing);
      });
    }
  }

  testWidgets('الأرقامُ من القاعدة لا من التصميم', (tester) async {
    await open(tester, partyBehaviorReport(suppliers: false),
        const Size(1500, 950));
    // العميلُ المزروعُ وحدَه — لا «٤٢٠ عميلاً» من نصّ التصميم.
    expect(find.text('مطعم النيل'), findsWidgets);
    expect(find.text('٤٢٠'), findsNothing,
        reason: 'رقمٌ من التصميم تسرّب إلى الشاشة');
  });
}

Future<void> _seed(AppDatabase db) async {
  final wh = await db
      .into(db.warehouses)
      .insert(WarehousesCompanion.insert(name: 'المخزن الرئيسي'));
  final user = await db.into(db.users).insert(
        UsersCompanion.insert(
          username: 'cashier',
          passwordHash: 'x',
          displayName: 'كاشير الوردية الأولى',
        ),
      );
  final cat = await db
      .into(db.categories)
      .insert(CategoriesCompanion.insert(name: 'مخبوزات ومعجّنات'));
  final unit =
      await db.into(db.units).insert(UnitsCompanion.insert(name: 'قطعة', symbol: 'ق'));
  final product = await db.into(db.products).insert(
        ProductsCompanion.insert(
          code: 'P-001',
          name: 'خبز بلدي مدعّم كبير',
          categoryId: Value(cat),
          unitId: Value(unit),
          warehouseId: Value(wh),
          salePrice: const Value(10),
          costPrice: const Value(6),
          minStock: const Value(50),
          currentStock: const Value(4),
        ),
      );
  final customer = await db
      .into(db.parties)
      .insert(PartiesCompanion.insert(name: 'مطعم النيل'));
  final supplier = await db.into(db.parties).insert(
        PartiesCompanion.insert(
          name: 'مورّد الألبان المتّحد',
          isSupplier: const Value(true),
        ),
      );

  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day, 12);

  final invoice = await db.into(db.salesInvoices).insert(
        SalesInvoicesCompanion.insert(
          invoiceNumber: 'S-1',
          warehouseId: wh,
          userId: user,
          invoiceDate: day,
          customerId: Value(customer),
          subtotal: const Value(100),
          total: const Value(110),
          paid: const Value(60),
          tax: const Value(10),
        ),
      );
  await db.into(db.salesInvoiceItems).insert(
        SalesInvoiceItemsCompanion.insert(
          invoiceId: invoice,
          productId: product,
          quantity: 10,
          unitPrice: 10,
          total: 110,
          taxAmount: const Value(10),
          costPrice: const Value(6),
          quantityInBase: const Value(1),
        ),
      );
  await db.into(db.purchaseInvoices).insert(
        PurchaseInvoicesCompanion.insert(
          invoiceNumber: 'P-1',
          supplierId: supplier,
          warehouseId: wh,
          invoiceDate: day,
          subtotal: const Value(300),
          total: const Value(300),
          paid: const Value(120),
        ),
      );
  await db.into(db.activityLogs).insert(
        ActivityLogsCompanion.insert(
          userId: Value(user),
          userName: 'كاشير الوردية الأولى',
          action: 'sale',
          entityType: 'sales_invoice',
          description: 'بيعٌ نقديّ',
          createdAt: Value(day),
        ),
      );
}
