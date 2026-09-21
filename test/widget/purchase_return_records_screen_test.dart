// شاشةُ سجلّ مردودات المشتريات — خ‑٩.
//
// ═══ ما يُقاس، ولماذا هو تصحيحٌ لا إضافة ═══
//
// المدخلُ كان يفتح **شاشةَ إنشاءٍ**، ولمطالعةِ ما مضى **حوارٌ** خلف زرٍّ
// في ترويستها. وذاك الحوارُ يقرأ `purchase_invoices` لا `purchase_returns`:
//
//   • فالصفُّ **فاتورةٌ لا مردود** — ثلاثةُ مردوداتٍ على فاتورةٍ صفٌّ واحد؛
//   • ومداه على **تاريخ الفاتورة** — فمردودُ اليوم على فاتورةٍ قديمةٍ غائب؛
//   • ولا `id` مردودٍ يُفتَح — فمرفقاتُ §٨ بلا مرساة.
//
// ولذلك يُقاس هنا أنّ الصفَّ **مردودٌ بعينه**، وأنّ المدى يصل الاستعلامَ
// شاملاً آخرَ اليوم، وأنّ فتحَ صفٍّ يعرض المستندَ.
//
// ⚠️ **وضريبةُ المدخلات المردودة تُجمَع صراحةً**: هي الحقلُ الذي وُجد
//    `purchase_returns` لأجله، وسجلٌّ بلا مجموعِها يترك الدوريّةَ
//    الضريبيّةَ بلا رقمٍ يُراجَع.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/attachments_test_overrides.dart';

import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/data/providers/document_record_providers.dart';
import 'package:ural_erp/domain/models/document_record.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_attachments_panel.dart';
import 'package:ural_erp/presentation/purchase_returns_picpos/screens/purchase_return_records_picpos_screen.dart';

PurchaseReturnRecord _rec({
  required int id,
  required double total,
  double tax = 0,
  String method = 'credit',
  String? invoice,
  String? supplier,
  String? reason,
  DateTime? at,
}) =>
    PurchaseReturnRecord(
      id: id,
      originalInvoiceId: 30,
      returnDate: at ?? DateTime.now(),
      subtotal: total - tax,
      tax: tax,
      total: total,
      refundMethod: method,
      isFullReturn: false,
      originalInvoiceNumber: invoice ?? 'PI-30',
      supplierId: 4,
      supplierName: supplier ?? 'مورد الشمال',
      reason: reason,
    );

class _Seen {
  DocumentRecordFilter? filter;
}

Future<void> _pump(
  WidgetTester tester, {
  required List<PurchaseReturnRecord> rows,
  _Seen? seen,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        purchaseReturnRecordsProvider.overrideWith((ref, filter) {
          seen?.filter = filter;
          return Stream.value(rows);
        }),
        // ⚠️ **إلزاميّ**: حوارُ المستند يحمل `PicPosAttachmentsPanel`،
        //    واللوحُ يصل `databaseProvider` فتُفتَح قاعدةٌ حقيقيّةٌ ولا
        //    يستقرّ `pumpAndSettle`. راجع رأسَ `attachments_test_overrides`.
        attachmentsRepositoryProvider.overrideWithValue(fakeAttachmentsRepo()),
        currentUserPermissionsProvider
            .overrideWith((ref) async => const ['purchases_return_view']),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: PurchaseReturnRecordsPicPosScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('مرساةٌ — المدخلُ يفتح السجلَّ وفيه زرُّ «جديد»',
      (tester) async {
    await _pump(tester, rows: [_rec(id: 1, total: 120, tax: 20)]);

    expect(find.text('PI-30'), findsOneWidget,
        reason: 'السجلُّ لم يُرسَم — أو المدخلُ ما زال يفتح شاشةَ الإنشاء');
    expect(find.byKey(const Key('return_records_new')), findsOneWidget);
  });

  testWidgets('🔴 وثلاثةُ مردوداتٍ على فاتورةٍ ثلاثةُ صفوفٍ لا صفٌّ واحد',
      (tester) async {
    // 🔴 عينُ عطب الحوار القديم: الصفُّ فاتورةٌ لا مردود، فيُجمَع الثلاثةُ
    //    في سطرٍ واحدٍ ولا سبيلَ لفتح واحدٍ بعينه.
    await _pump(tester, rows: [
      _rec(id: 1, total: 10),
      _rec(id: 2, total: 20),
      _rec(id: 3, total: 30),
    ]);

    expect(find.text('PI-30'), findsNWidgets(3),
        reason: '🔴 المردوداتُ مطويّةٌ على فاتورتها — فلا واحدَ منها يُفتَح');
  });

  testWidgets('🔴 وضريبةُ المدخلات المردودة مجموعةٌ على حدة', (tester) async {
    await _pump(tester, rows: [
      _rec(id: 1, total: 120, tax: 20),
      _rec(id: 2, total: 60, tax: 10),
    ]);

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(texts.any((t) => t.startsWith('30')), isTrue,
        reason: '🔴 لا مجموعَ للضريبة — والدوريّةُ الضريبيّةُ بلا رقمٍ '
            'يُراجَع، وهي الحقلُ الذي وُجد الجدولُ لأجله');
    expect(texts.any((t) => t.startsWith('180')), isTrue,
        reason: 'مجموعُ الإجماليّ غاب');
  });

  testWidgets('🔴 ومدى «إلى اليوم» يشمل مردوداتِ اليوم', (tester) async {
    final seen = _Seen();
    await _pump(tester, rows: const [], seen: seen);

    expect(seen.filter!.to!.hour, 23,
        reason: '🔴 `to` عند أوّل اليوم ⇒ مردوداتُ اليوم تسقط من سجلّ اليوم');
    expect(seen.filter!.to!.minute, 59);
  });

  testWidgets('والبحثُ يصل الاستعلامَ لا يُرشَّح في الذاكرة', (tester) async {
    final seen = _Seen();
    await _pump(tester, rows: const [], seen: seen);

    await tester.enterText(
        find.byKey(const Key('return_records_search')), 'الشمال');
    await tester.pumpAndSettle();

    expect(seen.filter!.search, 'الشمال',
        reason: 'البحثُ يرشّح الصفحةَ المحمَّلةَ وحدَها ويُخفي ما وراءها');
  });

  testWidgets('وفتحُ صفٍّ يعرض المستندَ للقراءة', (tester) async {
    await _pump(tester,
        rows: [_rec(id: 1, total: 120, tax: 20, reason: 'تالف')]);

    await tester.tap(find.text('PI-30'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('return_document_view')), findsOneWidget,
        reason: 'فتحُ صفٍّ لا يعرض شيئاً — وهو نصفُ خ‑٩');
    expect(find.text('تالف'), findsWidgets);
    expect(find.text('ضريبةُ المدخلات المردودة'), findsOneWidget);

    // 🔴 **ولوحُ المرفقات فيه** (خ‑١٠): إشعارُ الخصم ورقةُ **المردود** لا
    //    ورقةُ الفاتورة الأصل، ووضعُها على الأمّ يخلط مستندَين في ملفّ.
    expect(find.byKey(const Key('attachments_panel')), findsOneWidget,
        reason: '🔴 المردودُ يُعرَض بلا مرفقاته');

    // 🔴 **والمرساةُ المردودُ نفسُه لا فاتورتُه الأصل.** نجت طفرةٌ تُبدّلها
    //    (‏D4): كلُّ ما فوقَها يمرّ أخضرَ واللوحُ حاضرٌ — وهو يقرأ ويكتب
    //    على **المستند الخطأ**. وإشعارُ الخصم ورقةُ المردود، ووضعُها على
    //    الأمّ يخلط مستندَين في ملفٍّ واحدٍ ويُظهر مرفقَ مردودٍ على مردودٍ
    //    آخرَ من نفس الفاتورة.
    final panel = tester.widget<PicPosAttachmentsPanel>(
        find.byType(PicPosAttachmentsPanel));
    expect(panel.entityId, 1,
        reason: '🔴 اللوحُ مرسًى على غير المردود — راجع أعلاه');
    expect(panel.entityType, 'purchase_return');
  });

  testWidgets('وسجلٌّ فارغٌ يقول ذلك ولا يبدو معطوباً', (tester) async {
    await _pump(tester, rows: const []);
    expect(find.text('لا مردوداتٍ في هذا المدى'), findsOneWidget);
  });

  // ═══════════════════════════════════════════════════════════════════
  group('والمدخلُ موصولٌ بالسجلّ فعلاً', () {
    // ⚠️ يُقاس على `app_main_screen`: كلُّ ما فوقَه يمرّ أخضرَ ولو بقي
    //    `ScreenConfig` يبني شاشةَ الإنشاء — فالسجلُّ سليمٌ ولا أحدَ يفتحه.
    test('🔴 و«جديد» **يدفع** شاشةَ الإنشاء لا يستبدلها به', () {
      // 🔴 الدفعُ لا التبديل: `pushReplacement` يجعل شاشةَ الإنشاء هي
      //    الجذرَ، فيموت «رجوع» ولا يعود المستخدمُ إلى سجلٍّ فيه مردودُه.
      //
      // ⚠️ **ويُقاس بنيويّاً هنا وسلوكيّاً في نظيره**
      //    (`voucher_records_screen_test`): شاشةُ الإنشاء تفتح قاعدةً
      //    **حقيقيّةً عند `initState`** (‏`loadInvoices` وتوابعُه)، فتركيبُها
      //    في اختبار ودجتٍ يُسقطه بـ«A Timer is still pending» من مؤقّتات
      //    drift — لا بفشلِ العقد. وتجاوزُ شجرةِ مزوّديها كلِّها لقياس سطرٍ
      //    واحدٍ كلفةٌ بلا عائد.
      final src = File(
              'lib/presentation/purchase_returns_picpos/screens/purchase_return_records_picpos_screen.dart')
          .readAsStringSync();
      expect(src, contains('Navigator.of(context).push('),
          reason: '🔴 لم يعد يدفع — راجع أعلاه');
      expect(src, isNot(contains('pushReplacement')),
          reason: '🔴 استُبدل السجلُّ بشاشة الإنشاء ⇒ «رجوع» ميّت');
      expect(src, contains('PurchaseReturnsPicposScreen()'),
          reason: 'زرُّ «جديد» لا يفتح شاشةَ الإنشاء القائمة');
    });

    test('ذراعُ PicPos تبني السجلَّ', () {
      final src = File('lib/app_main_screen.dart').readAsStringSync();
      final at = src.indexOf('appScreen: AppScreen.purchaseReturns,');
      expect(at, greaterThan(0));
      final body = src.substring(at, src.indexOf('label:', at));
      expect(body, contains('PurchaseReturnRecordsPicPosScreen()'),
          reason: 'المدخلُ ما زال يفتح شاشةَ الإنشاء مباشرةً');

      // ⚠️ **وذراعُ UralCash لا تتبدّل** (ح‑٣): العملُ عليها موقوفٌ،
      //    والسجلُّ مبنيٌّ على قشرة PicPos.
      expect(body, contains('PurchaseReturnsScreen()'),
          reason: 'سقطت ذراعُ UralCash — وشاشتُها فقدت بابَها');
      expect(body, contains('Brand.isPicPos'));
    });
  });
}
