// شاشةُ سجلّ السندات — خ‑٩.
//
// ═══ ما يُقاس ═══
//
// ‏١) **المدخلُ يفتح السجلَّ لا الاستمارة.** كان يفتحها مباشرةً، فلا
//    سبيلَ لمطالعة سندٍ محفوظٍ ولا مرساةً لمرفقاته (§٨).
//
// ‏٢) 🔴 **و«جديد» يدفع الاستمارةَ ثمّ يعود منها.** الدفعُ هو ما يُحيي
//    `Navigator.maybePop` في الاستمارة — وبلا ذلك يبقى السندُ المحفوظُ
//    على الشاشة ويُكتَب مرّتين (راجع
//    `voucher_screen_finishes_its_save_test`).
//
// ‏٣) 🔴 **وسندُ الشيك يُوسَم ولا يُجمَع مع النقد.** هو مستندٌ **بلا أثرٍ
//    ماليّ**: قيدُه يقع على الورقة التجاريّة. وجمعُه في مجموعٍ واحدٍ
//    يُظهر في الخزنة مالاً لم يدخلها.
//
// ‏٤) **ومدى «اليوم» يشمل سنداتِ اليوم.** `created_at` يحمل الساعةَ،
//    و`to = اليوم 00:00` يُسقطها كلَّها — عطبٌ يبدو «لا بيانات».
//
// ⚠️ ولا `AppDatabase` حقيقيّةٌ هنا: المزوِّدُ متجاوَزٌ، وبلا ذلك يتعلّق
//    `pumpAndSettle` على قاعدةٍ تُفتَح.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/document_record_providers.dart';
import 'package:ural_erp/domain/models/document_record.dart';
import 'package:ural_erp/presentation/treasury_picpos/screens/voucher_records_picpos_screen.dart';

VoucherRecord _rec({
  required int id,
  required String number,
  required double amount,
  bool cheque = false,
  String? party,
  DateTime? at,
}) =>
    VoucherRecord(
      id: id,
      voucherNumber: number,
      date: at ?? DateTime.now(),
      amount: amount,
      discount: 0,
      category: 'customer_payment',
      isCheque: cheque,
      safeId: 1,
      safeName: 'خزنة رئيسية',
      partyId: 9,
      partyName: party ?? 'عميل الجنوب',
      description: 'تحصيل',
    );

/// مفتاحُ الملّاح — يُقرأ به `canPop` بعد الدفع.
final _nav = GlobalKey<NavigatorState>();

/// يلتقط المرشِّحاتِ التي وصلت المزوِّدَ — فالمقيسُ ما طُلب لا ما رُسم.
class _Seen {
  DocumentRecordFilter? filter;
  VoucherDirection? direction;
}

Future<void> _pump(
  WidgetTester tester, {
  required List<VoucherRecord> rows,
  _Seen? seen,
  VoucherDirection direction = VoucherDirection.receipt,
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
        voucherRecordsProvider.overrideWith((ref, key) {
          seen?.direction = key.$1;
          seen?.filter = key.$2;
          return Stream.value(rows);
        }),
        currentUserPermissionsProvider
            .overrideWith((ref) async => const ['treasury_view']),
      ],
      child: MaterialApp(
        navigatorKey: _nav,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: VoucherRecordsPicPosScreen(direction: direction),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('مرساةٌ — المدخلُ يفتح السجلَّ لا الاستمارة', (tester) async {
    await _pump(tester, rows: [_rec(id: 1, number: 'RV-1', amount: 100)]);

    expect(find.text('RV-1'), findsOneWidget,
        reason: 'السجلُّ لم يُرسَم — أو المدخلُ ما زال يفتح الاستمارة');
    expect(find.byKey(const Key('voucher_records_new')), findsOneWidget,
        reason: 'لا زرَّ «جديد» ⇒ لا سبيلَ لإنشاء سندٍ إطلاقاً');
    // والاستمارةُ ليست معروضةً قبل الضغط.
    expect(find.byKey(const Key('voucher_amount')), findsNothing);
  });

  testWidgets('🔴 و«جديد» يدفع الاستمارةَ فوقه — لا يستبدلها به',
      (tester) async {
    await _pump(tester, rows: [_rec(id: 1, number: 'RV-1', amount: 100)]);

    await tester.tap(find.byKey(const Key('voucher_records_new')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voucher_amount')), findsOneWidget,
        reason: '🔴 «جديد» لا يفتح الاستمارة');

    // 🔴 **والدفعُ هو المقيس**: بلا مسارٍ فوق السجلّ تعود
    //    `Navigator.maybePop` في الاستمارة عديمةَ الأثر، فيبقى السندُ
    //    المحفوظُ على الشاشة ويُكتَب مرّتين.
    //
    // ⚠️ **ولا يُقاس ببقاء السجلّ في الشجرة**: `Overlay` لا يبني ما تحت
    //    أوّلِ مسارٍ معتم، فالسجلُّ يغيب عن الشجرة **في الحالتين** —
    //    المدفوعةِ والمستبدَلة. والفاصلُ `canPop`.
    expect(_nav.currentState!.canPop(), isTrue,
        reason: '🔴 لا مسارَ تحت الاستمارة ⇒ صارت هي الجذرَ، و«رجوع» '
            'و«الإغلاق بعد الحفظ» يموتان معاً');

    // وعودةٌ تُعيد السجلَّ — لا شاشةً بيضاء.
    _nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(VoucherRecordsPicPosScreen), findsOneWidget);
    expect(find.text('RV-1'), findsOneWidget);
  });

  testWidgets('🔴 وسندُ الشيك يُوسَم ولا يدخل مجموعَ النقد', (tester) async {
    await _pump(tester, rows: [
      _rec(id: 1, number: 'RV-1', amount: 100),
      _rec(id: 2, number: 'RV-2', amount: 900, cheque: true),
    ]);

    // ⚠️ **بالعدد لا بـ`findsWidgets`**: «شيك» اسمُ شريحةِ المرشِّح أيضاً،
    //    فطفرةٌ تحذف وسمَ الصفّ تُبقي الشريحةَ — ومرّت خضراءَ فعلاً (‏S5).
    //    فالمنتظَرُ اثنان: الشريحةُ ووسمُ الصفّ الواحد.
    expect(find.text('شيك'), findsNWidgets(2),
        reason: '🔴 لا وسمَ للشيك على صفّه — فيُقرأ نقداً دخل الخزنة');
    expect(find.text('نقديّ'), findsNWidgets(2));

    // 🔴 المجموعُ ١٠٠ لا ١٠٠٠: سندُ الشيك مستندٌ بلا أثرٍ ماليّ.
    final totals = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(totals.any((t) => t.contains('1,000')), isFalse,
        reason: '🔴 جُمع الشيكُ مع النقد — فالخزنةُ تُظهر مالاً لم يدخلها');
    expect(totals.any((t) => t.startsWith('100')), isTrue,
        reason: 'مجموعُ النقد غاب — فالشريطُ بلا رقمٍ يُقرأ');
  });

  testWidgets('🔴 ومدى «إلى اليوم» يشمل سنداتِ اليوم', (tester) async {
    final seen = _Seen();
    await _pump(tester, rows: const [], seen: seen);

    final to = seen.filter!.to!;
    expect(to.hour, 23,
        reason: '🔴 `to` عند أوّل اليوم ⇒ كلُّ سندات اليوم تسقط من سجلّ '
            'اليوم، والشاشةُ تقول «لا سندات» وهي كاذبة');
    expect(to.minute, 59);
    expect(seen.direction, VoucherDirection.receipt);
  });

  testWidgets('والاتّجاهُ يصل المزوِّدَ — صرفاً لا قبضاً', (tester) async {
    final seen = _Seen();
    await _pump(
      tester,
      rows: const [],
      seen: seen,
      direction: VoucherDirection.payment,
    );
    expect(seen.direction, VoucherDirection.payment,
        reason: 'شاشةُ الصرف تقرأ سجلَّ القبض');
    expect(find.text('سند صرف'), findsWidgets);
  });

  testWidgets('والبحثُ يصل المزوِّدَ لا يُرشَّح في الذاكرة', (tester) async {
    // ترشيحٌ في الذاكرة يبحث في **المحمَّل** وحدَه (٥٠٠ صفّاً بحدّ
    // الاستعلام)، فسندٌ أقدمُ لا يظهر مهما كُتب في الخانة.
    final seen = _Seen();
    await _pump(tester, rows: const [], seen: seen);

    await tester.enterText(
        find.byKey(const Key('voucher_records_search')), 'الجنوب');
    await tester.pumpAndSettle();

    expect(seen.filter!.search, 'الجنوب',
        reason: 'البحثُ لم يصل الاستعلامَ — فهو يرشّح الصفحةَ المحمَّلةَ '
            'وحدَها ويُخفي ما وراءها');
  });

  testWidgets('وفتحُ صفٍّ يعرض المستندَ للقراءة', (tester) async {
    await _pump(tester, rows: [_rec(id: 1, number: 'RV-1', amount: 100)]);

    await tester.tap(find.text('RV-1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voucher_document_view')), findsOneWidget,
        reason: 'فتحُ صفٍّ لا يعرض شيئاً — وهو نصفُ خ‑٩');
    expect(find.text('خزنة رئيسية'), findsWidgets);
  });

  testWidgets('وسجلٌّ فارغٌ يقول ذلك ولا يبدو معطوباً', (tester) async {
    await _pump(tester, rows: const []);
    expect(find.text('لا سنداتٍ في هذا المدى'), findsOneWidget);
  });

  // ═══════════════════════════════════════════════════════════════════
  group('والمدخلُ موصولٌ بالسجلّ فعلاً', () {
    // ⚠️ **يُقاس على `app_main_screen` لا على الشاشة**: كلُّ ما فوقَه
    //    يمرّ أخضرَ ولو بقي `ScreenConfig` يبني الاستمارةَ مباشرةً —
    //    فالشاشةُ سليمةٌ ولا أحدَ يفتحها.
    String config(String screen) {
      final src = File('lib/app_main_screen.dart').readAsStringSync();
      final at = src.indexOf('appScreen: AppScreen.$screen,');
      expect(at, greaterThan(0), reason: 'لا إعدادَ لـ$screen');
      return src.substring(at, src.indexOf('label:', at));
    }

    test('سندُ القبض يبني السجلَّ باتّجاه القبض', () {
      final body = config('receiptVoucher');
      expect(body, contains('VoucherRecordsPicPosScreen('),
          reason: 'المدخلُ ما زال يفتح الاستمارةَ مباشرةً');
      expect(body, contains('VoucherDirection.receipt'),
          reason: 'بلا اتّجاهٍ مثبَّتٍ ⇒ سجلُّ الصرف تحت اسم «سند قبض»');
    });

    test('وسندُ الصرف باتّجاه الصرف', () {
      final body = config('paymentVoucher');
      expect(body, contains('VoucherRecordsPicPosScreen('));
      expect(body, contains('VoucherDirection.payment'));
    });
  });
}
