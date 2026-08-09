// ═══════════════════════════════════════════════════════════════════════════
// حوارُ إنشاء التقرير كان يبني الأعمدةَ **ولا يمرّر فلتراً أبداً**.
// ═══════════════════════════════════════════════════════════════════════════
//
// السكيما توثّق عموداً للفلاتر منذ البداية، والمحرِّك يقرؤه — لكن الحوار كان
// يستدعي `createCustomReport` بالاسم والكيان والأعمدة وحدها. فلا سبيلَ في
// التطبيق كلِّه إلى بناء تقريرٍ مُصفّى.
//
// وهذا الاختبار يقطع المسارَ كاملاً بمستودعٍ **حقيقيّ** على قاعدةٍ في الذاكرة:
// حوار ⇒ ترميز ⇒ عمود `filters` ⇒ `executeReport` ⇒ الصفوف. فلا يثبت أن
// الحوار «مرّر شيئاً» بل أن ما مرّره **يُصفّي فعلاً**.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ‏`providers.dart` يُصدّر `database.dart` — واستيرادُه صراحةً ملاحظةُ تحليل.
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/data/repositories/reporting_repository_impl.dart';
import 'package:ural_erp/presentation/screens/report_builder_screen.dart';

void main() {
  late AppDatabase db;

  Future<void> product(String code, String name, double price) =>
      db.into(db.products).insert(ProductsCompanion.insert(
          code: code, name: name, salePrice: Value(price)));

  setUp(() async {
    db = AppDatabase.forTesting();
    await product('P1', 'قلم', 10);
    await product('P2', 'حاسوب', 5000);
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        reportingRepositoryProvider
            .overrideWithValue(ReportingRepositoryImpl(db)),
      ],
      child: const MaterialApp(home: ReportBuilderScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openDialogWithName(WidgetTester tester, String name) async {
    await tester.tap(find.text('جديد'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'اسم التقرير'), name);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'اسم المنتج'));
    await tester.pumpAndSettle();
  }

  testWidgets('بلا شروطٍ: التقريرُ يُحفظ بفلترٍ خالٍ ويُرجع كلَّ الصفوف',
      (tester) async {
    await pump(tester);
    await openDialogWithName(tester, 'كل الأصناف');
    await tester.tap(find.text('إنشاء'));
    await tester.pumpAndSettle();

    final saved = (await db.select(db.customReports).get()).single;
    expect(saved.filters, isNull,
        reason: 'حوارٌ بلا شروطٍ لا يكتب `[]` — فيبقى التقريرُ بلا فلتر');
    expect(await db.executeReport(saved.id), hasLength(2));
  });

  testWidgets('شرطٌ واحد: ما يُحفَظ يُصفّي فعلاً لا يُخزَّن وحسب',
      (tester) async {
    await pump(tester);
    await openDialogWithName(tester, 'الحواسيب');

    await tester.tap(find.text('الفلاتر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة شرط'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'القيمة'), 'حاسوب');
    await tester.tap(find.text('إنشاء'));
    await tester.pumpAndSettle();

    final saved = (await db.select(db.customReports).get()).single;
    expect(saved.filters, startsWith('['),
        reason: 'الصيغةُ المهيكلة لا نصُّ SQL خامّ');

    final rows = await db.executeReport(saved.id);
    expect(rows.map((r) => r['name']), ['حاسوب'],
        reason: 'التقريرُ المحفوظُ من الحوار يُصفّي — لا يرجع الصنفين');
  });

  testWidgets('شرطٌ بلا قيمة يُمنع عند الحفظ لا يُحفَظ فيُرفَض عند التشغيل',
      (tester) async {
    await pump(tester);
    await openDialogWithName(tester, 'ناقص');

    await tester.tap(find.text('الفلاتر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة شرط'));
    await tester.pumpAndSettle();

    // بلا كتابةِ قيمة
    await tester.tap(find.text('إنشاء'));
    await tester.pumpAndSettle();

    expect(await db.select(db.customReports).get(), isEmpty,
        reason: 'المحرِّك يرفض التقريرَ كلَّه لشرطٍ فاسد، فيُحفَظ تقريرٌ '
            'لا يُنتج صفاً أبداً ولا يقول لماذا');
    expect(find.text('إنشاء'), findsOneWidget, reason: 'الحوارُ يبقى مفتوحاً');

    // رسالةُ التنبيه تجدول مؤقّتاً لإخفائها؛ `pumpAndSettle` لا يستهلكه لأنه
    // لا يجدول إطاراً. وبلا استهلاكه يفشل الاختبارُ بـ«مؤقّتٌ معلّق» — فشلٌ
    // في التنظيف يُقرأ خطأً كفشلٍ في السلوك.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('تبديلُ الكيان يمسح شروطَ الكيان السابق', (tester) async {
    await pump(tester);
    await tester.tap(find.text('جديد'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('الفلاتر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة شرط'));
    await tester.pumpAndSettle();
    expect(find.text('الفلاتر (1)'), findsOneWidget);

    await tester.tap(find.text('الأصناف').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('العملاء/الموردين').last);
    await tester.pumpAndSettle();

    expect(find.text('الفلاتر (1)'), findsNothing,
        reason: 'حقلُ «الأصناف» ليس من حقول «الأطراف» — بقاؤه يُبطل '
            'التقريرَ كلَّه عند التشغيل');
  });
}
