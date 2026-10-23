// تركيبُ شاشة «المشتريات الخارجيّة» — الرسمُ والعرضُ وبابُ الأوراق.
//
// ═══ 🔴 ولا قاعدةَ حقيقيّةً داخلَ `testWidgets` ═══
//
// أوّلُ صياغةٍ لهذا الملفّ حقنت `AppDatabase.forTesting()` ورفعت الشاشةَ
// فوقها. و**النتيجةُ تعلّقٌ تامّ**: جسمُ `testWidgets` يعمل في منطقةٍ
// وهميّةِ الزمن، ومؤقّتاتُ drift لا يحرّكها أحدٌ فيها — فلا يكتمل استعلامٌ
// ولا ينتهي اختبار. وقد **جمّد سويّةَ الودجت كلَّها** (وحدةُ المعالجة ثابتةٌ
// عند نفس الرقم دقائقَ متّصلة) قبل أن يُقاس السبب.
//
// وهو نفسُ ما يوثّقه هذا المستودعُ في تعليق شاشات الودجت، ونفسُ سبب اعتماد
// `landed_cost_picpos_screen_test` على **مستودعٍ وهميّ**. فالمحقونُ هنا
// مستودعٌ وهميٌّ كذلك — وحسابُ الطبقات الأدنى مقيسٌ في
// `import_purchases_dao_test` على قاعدةٍ حقيقيّةٍ خارجَ منطقةٍ وهميّة.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/models/import_purchase_plan.dart';
import 'package:picpos_erp/domain/repositories/import_purchases_repository.dart';
import 'package:picpos_erp/presentation/import_purchases_picpos/screens/import_purchases_picpos_screen.dart';
import '../helpers/attachments_test_overrides.dart';

final _now = DateTime(2026, 9, 20);

ImportPurchaseDetailData _details() => ImportPurchaseDetailData(
      id: 1,
      purchaseInvoiceId: 11,
      customsDeclarationNo: 'C-4021',
      billOfLading: 'BL-77',
      countryOfOrigin: 'الصين',
      port: 'شنغهاي',
      letterOfCredit: 'LC-12',
      clearingAgentName: 'وكيل التخليص الدولي',
      createdAt: _now,
      rowVersion: 0,
    );

PurchaseInvoiceData _invoice() => PurchaseInvoiceData(
      id: 11,
      invoiceNumber: 'PUR-0001',
      supplierId: 5,
      warehouseId: 1,
      invoiceDate: _now,
      subtotal: 710,
      discount: 0,
      tax: 0,
      total: 710,
      paid: 0,
      paymentMethod: 'credit',
      status: 'pending',
      isLocked: false,
      currencyId: 3,
      exchangeRate: 0.71,
      isDeleted: false,
      updatedAt: _now,
      rowVersion: 0,
      createdAt: _now,
    );

ImportPurchaseRow _row({
  double landedApplied = 0,
  double landedDraft = 0,
}) =>
    (
      details: _details(),
      invoice: _invoice(),
      supplierName: 'مورد صيني',
      currencyCode: 'USD',
      clearingAgent: 'وكيل التخليص الدولي',
      landedApplied: landedApplied,
      landedDraft: landedDraft,
    );

class _FakeImportRepo implements ImportPurchasesRepository {
  _FakeImportRepo(this.rows);

  final List<ImportPurchaseRow> rows;
  final updates = <({int invoiceId, ImportDocumentFields fields})>[];

  @override
  Future<List<ImportPurchaseRow>> getRows({int limit = 500}) async => rows;

  @override
  Future<ImportPurchaseDetailData?> getForInvoice(int purchaseInvoiceId) async =>
      rows.isEmpty ? null : rows.first.details;

  @override
  Future<void> updateDetails({
    required int purchaseInvoiceId,
    required ImportDocumentFields fields,
  }) async {
    updates.add((invoiceId: purchaseInvoiceId, fields: fields));
  }
}

Future<_FakeImportRepo> _pump(
  WidgetTester tester, {
  List<ImportPurchaseRow>? rows,
  double width = 1440,
}) async {
  final repo = _FakeImportRepo(rows ?? [_row()]);
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        importPurchasesRepositoryProvider.overrideWithValue(repo),
        // بثُّ الفاتورة يقرأ القاعدةَ — ويُستبدَل ببثٍّ واحدٍ فلا يبقى
        // مؤقّتُ drift في المنطقة الوهميّة.
        purchaseInvoicesChangeProvider
            .overrideWith((ref) => Stream<int>.value(1)),
        // ⚠️ **تجاوزٌ متزامنٌ لا `async`.** `ensurePermission` تقرأ المزوّدَ
        //    بـ`ref.read(...).value`، ولا أحدَ يراقبه قبل النقرة — فالقراءةُ
        //    **باردة** وتُرجع `null` مع تجاوزٍ غيرِ متزامن، فتُفتَح نافذةُ
        //    «موافقة مدير» بدل الحوار المقصود.
        currentUserPermissionsProvider
            .overrideWith((ref) => const ['purchases_create', 'purchases_edit']),
        // وكلاءُ التخليص في حوار الأوراق — عبر مزوِّدهم لا عبر القاعدة.
        allSuppliersProvider.overrideWith((ref) => Stream.value(<Party>[])),
        // v176 / §٨ — حوارُ الأوراق يحمل لوحَ المرفقات.
        attachmentsRepositoryProvider
            .overrideWithValue(fakeAttachmentsRepo()),
      ],
      child: const MaterialApp(home: ImportPurchasesPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  return repo;
}

Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    testWidgets('الشاشةُ تُرسَم بلا فيضان عند عرض $w', (tester) async {
      await _pump(tester, width: width);
      expect(tester.takeException(), isNull,
          reason: 'شاشةُ المشتريات الخارجيّة فاضت عند $w');
      expect(find.text('المشتريات الخارجيّة'), findsWidgets);
      await _teardownTree(tester);
    });
  }

  testWidgets('وتعرض أوراقَ الفاتورة الموسومة', (tester) async {
    await _pump(tester);
    expect(find.text('C-4021'), findsOneWidget,
        reason: 'البيانُ الجمركيُّ لا يُعرَض');
    expect(find.textContaining('الصين'), findsWidgets);
    expect(find.text('وكيل التخليص الدولي'), findsOneWidget);
    await _teardownTree(tester);
  });

  testWidgets('🔴 والإجماليُّ محلّيٌّ — والعملةُ وصفٌ تحته لا وحدةٌ له',
      (tester) async {
    // المخزَّنُ محلّيٌّ دائماً (حُوِّل في النموذج مرّةً واحدة). وضربٌ ثانٍ
    // عند العرض كان يُظهر رقماً لم يدخل أيَّ دفتر.
    await _pump(tester);
    expect(find.text('710.000'), findsOneWidget);
    expect(find.textContaining('حُوِّلت من USD'), findsOneWidget);
    await _teardownTree(tester);
  });

  testWidgets('🔴 والمسوّدةُ لا تُجمَع مع المطبَّق', (tester) async {
    // ورقةٌ لم تُقيَّد تكلفةً لم تدخل الدفتر، وجمعُها يقرأ رقماً لم يقع.
    await _pump(tester, rows: [_row(landedApplied: 300, landedDraft: 50)]);
    expect(find.text('300.000'), findsOneWidget);
    expect(find.textContaining('مسوّدة 50.000'), findsOneWidget);
    await _teardownTree(tester);
  });

  testWidgets('وبلا فواتيرَ تُقال الحالةُ صراحةً — الوسمُ هو الفارق',
      (tester) async {
    await _pump(tester, rows: const []);
    expect(find.text('لا فواتيرَ استيرادٍ بعد'), findsOneWidget);
    await _teardownTree(tester);
  });

  testWidgets('🔴 والأوراقُ تُحرَّر بعد وصولها — بلا عملة', (tester) async {
    // البيانُ الجمركيُّ يُخلَّص **بعد** وصول البضاعة، فبابُ التحرير لازم.
    // والعملةُ ليست فيه: تبديلُ السعر بعد الترحيل يُبدّل **وصفَ** الصفِّ
    // ولا يُبدّل مبلغاً، فيصير المستندُ يقول سعراً لم يُحسَب به.
    final repo = await _pump(tester);

    await tester.tap(find.text('C-4021'));
    // الفتحُ سلسلةٌ غيرُ متزامنة: فحصُ الصلاحية ثمّ قراءةُ الوكلاء ثمّ
    // بناءُ الحوار — فإطاران لا يكفيان.
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import_papers_panel')), findsOneWidget);
    expect(find.byKey(const Key('import_currency')), findsNothing,
        reason: '🔴 العملةُ قابلةٌ للتحرير بعد الترحيل');

    await tester.enterText(find.byKey(const Key('import_customs')), 'C-9999');
    await tester.pump();
    await tester.tap(find.byKey(const Key('import_papers_save')));
    await tester.pumpAndSettle();

    expect(repo.updates, hasLength(1));
    expect(repo.updates.single.invoiceId, 11);
    expect(repo.updates.single.fields.customsDeclarationNo, 'C-9999');
    // وما لم يُمسَّ يبقى — التحريرُ ليس إعادةَ كتابةٍ من فراغ.
    expect(repo.updates.single.fields.port, 'شنغهاي');
    await tester.pump(const Duration(seconds: 6));
    await _teardownTree(tester);
  });

  testWidgets('وزرُّ «التكاليف المحمّلة» هنا ولا مدخلَ جانبيَّ له',
      (tester) async {
    // 🔴 قرارُ المالك 2026-09-18: «تعيش داخلها وحدَها». فهذه الشاشةُ هي
    //    المُبلِغُ الوحيد، وغيابُ الزرِّ يجعل المحرّكَ غيرَ قابلٍ للبلوغ.
    await _pump(tester);
    expect(find.byKey(const Key('import_open_landed')), findsOneWidget);
    await _teardownTree(tester);
  });
}
