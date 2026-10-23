// بطاقاتُ إعدادات خدمات الضيف — بلاغُ المالك 2026-09-12:
// «معرفتنيش ازاى هظبط الاعداد بتاعهم وهم اصلا مش ظاهرين».
//
// ⚠️ **والحارسُ البنيويُّ لا يكفي هنا.** ذاك يُثبت أنّ الرايةَ **تُكتَب** في
// مكانٍ ما من الشيفرة؛ وهذا يُثبت أنّ المستخدمَ يرى مفتاحاً ويقلبه فتتغيّر
// القيمةُ في القاعدة فعلاً. وبينهما مسافةٌ وقع فيها العطبُ الأصليُّ نفسُه:
// رايةُ طلبِ الضيف كان لها قارئٌ ومسارٌ كاملٌ و**صفرُ كُتّاب**.
//
// ═══ ⚠️ زمنُ الاختبار وهميٌّ — ومن هنا جاء تعليقُ ثلاثين دقيقة ═══
//
// `testWidgets` يعمل في `FakeAsync`: المؤقّتاتُ تتقدّم بالدفع، أمّا العملُ
// غيرُ المتزامن **الحقيقيُّ** (‏استعلامُ drift) فلا يكتمل ما دام أحدٌ ينتظره
// داخل المنطقة. فأوّلُ صياغةٍ انتظرت `getSettingValue` في جسم الاختبار
// واستعملت `pumpAndSettle`، فعلّقت عشرَ دقائقَ لكلّ حالةٍ وسقطت ثمانيةٌ
// بـ«did not complete» — **والسببُ ليس في الودجت ولا في القاعدة**.
//
// والعلاجُ شقّان:
//   • **القراءةُ تُثبَّت**: المزوّداتُ تُستبدَل بقيمٍ تُحَلُّ تزامنيّاً
//     (`overrideWith` تُرجع قيمةً لا `Future`)، فالرسمُ لا ينتظر شيئاً.
//   • **الكتابةُ تُقاس في `runAsync`**: هناك وحدَه يجري الزمنُ حقيقيّاً
//     فتكتمل كتابةُ drift ويُقرأ أثرُها.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/feature_settings_providers.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/settings_picpos/screens/guest_services_settings_picpos.dart';
import 'package:picpos_erp/services/api/table_bill_token.dart';

late AppDatabase _db;

/// يبني البطاقةَ بقيمِ قراءةٍ مُثبَتة.
///
/// ⚠️ و`databaseProvider` يبقى القاعدةَ الحقيقيّة: الكتابةُ هي المقيسة،
/// فاستبدالُها بمزيّفٍ كان يجعل الاختبارَ يقيس نفسَه.
Future<void> _pumpTableBill(
  WidgetTester tester, {
  bool qr = false,
  bool guest = false,
  String? publicBase,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(_db),
        tableBillQrEnabledProvider.overrideWith((ref) => qr),
        tableBillGuestOrderEnabledProvider.overrideWith((ref) => guest),
        tableBillPublicBaseUrlProvider.overrideWith((ref) => publicBase),
      ],
      child: const _Host(child: TableBillSettingsCard()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpWhatsApp(WidgetTester tester, {String code = ''}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(_db),
        whatsAppCountryCodeProvider.overrideWith((ref) => code),
      ],
      child: const _Host(child: WhatsAppSettingsCard()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _Host extends StatelessWidget {
  const _Host({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(width: 600, child: child),
            ),
          ),
        ),
      );
}

/// يُمهِل الزمنَ الحقيقيَّ حتى تكتمل كتابةُ drift، ثمّ يقرأ أثرَها.
///
/// ⚠️ ويستنزف مؤقّتَ التنبيه بعدها: `AppToast` يجدول مؤقّتاً حتى يختفي،
/// والإطارُ يرمي «A Timer is still pending even after the widget tree was
/// disposed» — إخفاقٌ **بعد** نجاحِ ما يقيسه الاختبار، فيبدو العطبُ في
/// الحفظ وهو في التنظيف.
Future<String?> _readAfterWrite(WidgetTester tester, String key) async {
  String? out;
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    out = await _db.getSettingValue(key);
  });
  await tester.pump(const Duration(seconds: 6));
  return out;
}

void main() {
  // ⚠️ **قاعدةٌ واحدةٌ للملفّ كلِّه — و`setUp` كان يُنشئ واحدةً لكلّ حالة.**
  // وdrift يقولها بنصّها: «It looks like you've created the database class
  // AppDatabase multiple times. When these two databases use the same
  // QueryExecutor, race conditions will occur». والنتيجةُ هنا لم تكن فساداً
  // بل **تعليقاً**: أوّلُ حالةٍ تمرّ ثمّ تقف البقيّةُ عند أوّل استعلام.
  //
  // ولا تُغلَق القاعدةُ: `close()` ينتظر مؤقّتَ drift في المنطقة الوهميّة
  // فيعلّق الاختبار — مصيدةٌ مسجَّلةٌ في هذا المستودع.
  setUpAll(() => _db = AppDatabase.forTesting());

  // والعزلُ بمسحِ المفاتيح الأربعة وحدَها: مسحُ الجدول كلِّه يُسقط ما بذره
  // `beforeOpen` من إعداداتِ إقلاع.
  setUp(() async {
    for (final k in const [
      kTableBillQrEnabledKey,
      kTableBillGuestOrderEnabledKey,
      kTableBillPublicBaseUrlKey,
      kWhatsAppCountryCodeKey,
    ]) {
      await _db.customStatement('DELETE FROM settings WHERE key = ?', [k]);
    }
  });

  // ⚠️ **وحالتان لا واحدة.** أوّلُ صياغةٍ ضخّت البطاقةَ مرّتَين في نفس
  // الحالة بقيمتَين — و`ProviderScope` المضخوخُ ثانيةً يحتفظ بحاوِيه، فلا
  // تُعاد قراءةُ الاستبدال. فبدا المفتاحُ «لا يعكس القيمة» وهو سليم.
  testWidgets('مرساةٌ — البطاقةُ تُرسَم ومفتاحُها مطفأٌ افتراضاً',
      (tester) async {
    await _pumpTableBill(tester);
    expect(find.text('رمز حساب الطاولة'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
  });

  testWidgets('والمفتاحُ يعكس القيمةَ المحفوظة', (tester) async {
    await _pumpTableBill(tester, qr: true);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue,
        reason: 'المفتاحُ لا يعكس القيمةَ المحفوظة — فالعرضُ يكذب');
  });

  testWidgets('وقلبُ المفتاح يكتب الرايةَ في القاعدة', (tester) async {
    await _pumpTableBill(tester);
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(await _readAfterWrite(tester, kTableBillQrEnabledKey), 'true');
  });

  testWidgets('ولا يظهر مفتاحُ طلبِ الضيف قبل إشعال العرض', (tester) async {
    // مفتاحٌ يُشعَل ولا أثرَ له أسوأُ من مفتاحٍ مخفيّ: طلبُ الضيف يمرّ برمز
    // الجلسة الذي لا يُنال إلّا من القراءة.
    await _pumpTableBill(tester);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('السماح للضيف بطلب أصناف'), findsNothing);
  });

  testWidgets('وبعد إشعاله يظهر — ويكتب رايتَه هو', (tester) async {
    // ⚠️ **وهذه عينُ الفجوة التي شُحنت في ‎253 و‎254**: الرايةُ لها قارئٌ في
    // `api_handler` وطابورٌ ومحرّكُ اعتمادٍ وبانرٌ ونقطتا API — وصفرُ كُتّاب.
    await _pumpTableBill(tester, qr: true);
    expect(find.text('السماح للضيف بطلب أصناف'), findsOneWidget);

    // ⚠️ والنقرُ على **المفتاح** لا على نصّه: الصفُّ لا يقلب بالضغط عليه،
    // فنقرةُ النصّ تمرّ بلا أثرٍ ويقرأ الاختبارُ `null` فيبدو العطبُ قائماً.
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();
    expect(
      await _readAfterWrite(tester, kTableBillGuestOrderEnabledKey),
      'true',
    );
  });

  testWidgets('وعنوانٌ غيرُ صالحٍ يُرفَض ولا يُحفَظ', (tester) async {
    await _pumpTableBill(tester, qr: true);
    await tester.enterText(find.byType(TextField).first, 'shop.com/path?x=1');
    await tester.tap(find.text('حفظ'));
    await tester.pump();

    expect(await _readAfterWrite(tester, kTableBillPublicBaseUrlKey), isNull,
        reason: 'حُفظ عنوانٌ يرفضه المُسوِّي — فالرابطُ المطبوع يكسر');
    expect(find.textContaining('غيرُ صالح'), findsOneWidget);
  });

  testWidgets('وعنوانٌ صالحٌ يُحفَظ', (tester) async {
    await _pumpTableBill(tester, qr: true);
    await tester.enterText(find.byType(TextField).first, 'https://shop.com');
    await tester.tap(find.text('حفظ'));
    await tester.pump();

    expect(
      await _readAfterWrite(tester, kTableBillPublicBaseUrlKey),
      'https://shop.com',
    );
  });

  testWidgets('ورمزُ دولة واتساب يُحفَظ بالأرقام وحدَها', (tester) async {
    await _pumpWhatsApp(tester);
    await tester.enterText(find.byType(TextField).first, '966');
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    expect(await _readAfterWrite(tester, kWhatsAppCountryCodeKey), '966');
  });

  testWidgets('ورمزٌ فارغٌ يُرفَض — والفارغُ يعني «غيرُ مضبوط»',
      (tester) async {
    await _pumpWhatsApp(tester);
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    expect(await _readAfterWrite(tester, kWhatsAppCountryCodeKey), isNull);
    expect(find.textContaining('غيرُ صالح'), findsOneWidget);
  });

  testWidgets('والقيمةُ المحفوظةُ تُقرأ في الحقل عند الفتح', (tester) async {
    // ⚠️ حقلٌ يُفتَح فارغاً على قيمةٍ محفوظةٍ يُوهم أنّ الإعدادَ ضائع،
    // فيُعاد ضبطُه كلَّ مرّة — وهي شكوى «الإعداد لا يُحفَظ» بعينها.
    await _pumpWhatsApp(tester, code: '20');
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, '20');
  });
}
