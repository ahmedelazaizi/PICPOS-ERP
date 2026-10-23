// عناصرُ تصميم شاشة الخزينة — **حرّاسٌ على الفورك نفسِه**.
//
// ═══ لماذا اختبارٌ خاصٌّ بالفورك ═══
//
// مقيسٌ في هذا المستودع لا مفترَض: أُزيل حارسُ التكلفة من فورك الأصناف فسقط
// اختبارُ الفورك و**بقي اختبارُ الأصل أخضر**. فكلُّ ما يُنسخ يحتاج قياسَه
// الموازي، وإلّا كان الأخضرُ شهادةً على ملفٍّ لا تفتحه الشاشة.
//
// وكلُّ ودجتٍ هنا **ودجتُ الإنتاج نفسُها** (‏`@visibleForTesting`) لا مكافئٌ
// محلّيّ: مكافئٌ يمرّ أخضرَ ولو انفصلت ودجتُ الإنتاج عنه تماماً — وهو عطبٌ
// وقع فعلاً في خليّة المخزون.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:picpos_erp/presentation/treasury_picpos/widgets/treasury_actions_grid_picpos.dart';
import 'package:picpos_erp/presentation/treasury_picpos/widgets/treasury_metrics_panel_picpos.dart';
import 'package:picpos_erp/presentation/treasury_picpos/widgets/treasury_movements_list_picpos.dart';
import 'package:picpos_erp/presentation/treasury_picpos/widgets/treasury_picpos_tokens.dart';
import 'package:picpos_erp/presentation/treasury_picpos/widgets/treasury_safe_card_picpos.dart';

void main() {
  Future<void> show(WidgetTester tester, Widget child,
      {double width = 900}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: Center(child: SizedBox(width: width, child: child)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // ══════════════════════════════════════════════════════════════════════
  // بطاقةُ الصندوق
  // ══════════════════════════════════════════════════════════════════════
  group('بطاقةُ الصندوق', () {
    testWidgets('تعرض الاسمَ والنوعَ والفرعَ والرصيد', (tester) async {
      await show(
        tester,
        const TreasurySafeCardPicpos(
          name: 'صندوق الكاشير',
          safeType: 'cash',
          balance: 1500,
          isDefault: false,
          branchName: 'فرع العقبة',
        ),
      );
      expect(find.text('صندوق الكاشير'), findsOneWidget);
      expect(find.text('نقدي · فرع العقبة'), findsOneWidget);
    });

    // ⚠️ **الحارسُ الأهمُّ في هذه البطاقة.** الأصلُ يكتب سطرَه الفرعيَّ
    // `isDefault ? 'افتراضي' : typeLabel` — فصندوقٌ افتراضيٌّ **يُخفي نوعَه**.
    // والتصميمُ يعرض الاثنين: شارةً بجانب الاسم، والنوعَ في السطر الفرعيّ.
    testWidgets('الافتراضيُّ يعرض الشارةَ **والنوعَ** معاً', (tester) async {
      await show(
        tester,
        const TreasurySafeCardPicpos(
          name: 'الخزنة الرئيسية',
          safeType: 'bank',
          balance: 9000,
          isDefault: true,
          branchName: 'الإدارة',
        ),
      );
      expect(find.text('افتراضي'), findsOneWidget);
      expect(find.text('بنك · الإدارة'), findsOneWidget,
          reason: 'النوعُ لا يُزاح بالشارة — هذا فرقُ الفورك عن الأصل');
    });

    testWidgets('غيرُ الافتراضيّ بلا شارة', (tester) async {
      await show(
        tester,
        const TreasurySafeCardPicpos(
          name: 'ص',
          safeType: 'cash',
          balance: 1,
          isDefault: false,
        ),
      );
      expect(find.text('افتراضي'), findsNothing);
    });

    // صندوقٌ قديمٌ بلا ربطِ فرع — لا فاصلةَ معلّقةٌ بلا ما بعدها.
    testWidgets('بلا فرعٍ ⇒ النوعُ وحدَه بلا فاصلة', (tester) async {
      await show(
        tester,
        const TreasurySafeCardPicpos(
          name: 'صندوق قديم',
          safeType: 'cash',
          balance: 10,
          isDefault: false,
        ),
      );
      expect(find.text('نقدي'), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
    });

    // ⚠️ التصميمُ يلوّن الرصيدَ بلون النوع دائماً لأن عيّنتَه كلُّها موجبة.
    // وحارسُ الأصل (`balance > 0 ? color : muted`) منقولٌ عمداً: رصيدٌ سالبٌ
    // بلونٍ أخضرَ يُقرأ سليماً وهو ليس كذلك.
    testWidgets('رصيدٌ سالبٌ لا يأخذ لونَ النوع', (tester) async {
      await show(
        tester,
        const TreasurySafeCardPicpos(
          name: 'مسحوبٌ عليه',
          safeType: 'cash',
          balance: -250,
          isDefault: false,
        ),
      );
      final t = tester.widget<Text>(find.textContaining('250'));
      expect(t.style?.color, isNot(TreasuryPicposTokens.cashTint));
      expect(t.style?.color, AppColors.textMuted);
    });

    testWidgets('رصيدٌ موجبٌ يأخذ لونَ النوع', (tester) async {
      await show(
        tester,
        const TreasurySafeCardPicpos(
          name: 'كاشير',
          safeType: 'cash',
          balance: 250,
          isDefault: false,
        ),
      );
      final t = tester.widget<Text>(find.textContaining('250'));
      expect(t.style?.color, TreasuryPicposTokens.cashTint);
    });

    testWidgets('اسمٌ طويلٌ جدّاً لا يفيض', (tester) async {
      await show(
        tester,
        const TreasurySafeCardPicpos(
          name: 'صندوقٌ باسمٍ طويلٍ جدّاً يتجاوز عرضَ البطاقة بكثيرٍ جدّاً جدّاً',
          safeType: 'click',
          balance: 12345678.9,
          isDefault: true,
          branchName: 'فرعٌ باسمٍ طويلٍ أيضاً لزيادة الضغط على التخطيط',
        ),
        width: 300,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // لونُ النوع — عقدٌ واحدٌ لا اثنان
  // ══════════════════════════════════════════════════════════════════════
  group('لونُ نوع الصندوق', () {
    // ⚠️ كان `#A78BFA` في شرائح التقسيم و`#8B5CF6` في بطاقة الصندوق — لونان
    // لنفس النوع على نفس الشاشة. المصدرُ صار واحداً، وهذا يثبّته.
    test('كليك لونٌ واحدٌ هو لونُ التصميم', () {
      expect(TreasuryPicposTokens.tintFor('click'), const Color(0xFF8B5CF6));
    });

    // نوعٌ مجهولٌ لا يُقرأ نقديّاً.
    test('النوعُ المجهولُ ليس بلون النقديّ', () {
      expect(
        TreasuryPicposTokens.tintFor('something_else'),
        isNot(TreasuryPicposTokens.cashTint),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // الرقمُ في البطاقة الداكنة — كودُ العملة قبل الرقم
  // ══════════════════════════════════════════════════════════════════════
  group('رقمُ البطاقة الداكنة', () {
    // ⚠️ **الخاصّيّةُ تُقاس هندسيّاً لا نصّيّاً.** كتابةُ `'$n $c'` في `Text`
    // واحدةٍ تُنتج المقطعَ اليساريَّ نفسَه فيقع الكودُ **يمينَ** الرقم — عكسَ
    // التصميم. والنصُّ في الحالتين يحوي الاثنين، فالبحثُ عن نصٍّ لا يكشف
    // الفرق. الموضعُ يكشفه.
    testWidgets('كودُ العملة يقع يسارَ الرقم (قبلَه بصريّاً)', (tester) async {
      await show(tester, const TreasuryHeroAmountPicpos(amount: 1234.5));

      final numberX =
          tester.getTopLeft(find.textContaining('1,234')).dx;
      final currencyX =
          tester.getTopLeft(find.text(AppConstants.currencySymbolEn)).dx;

      expect(currencyX, lessThan(numberX),
          reason: 'التصميمُ يضع الكودَ يسارَ الرقم في حاوٍ RTL');
    });

    testWidgets('كودُ العملة نصٌّ مستقلٌّ لا جزءٌ من الرقم', (tester) async {
      await show(tester, const TreasuryHeroAmountPicpos(amount: 10));
      expect(find.text(AppConstants.currencySymbolEn), findsOneWidget);
    });

    // أثناء التحميل نقاطٌ لا صفر — صفرٌ يُقرأ «الخزينةُ فارغة».
    testWidgets('أثناء التحميل نقاطٌ لا صفر', (tester) async {
      await show(tester, const TreasuryHeroAmountPicpos(amount: null));
      expect(find.text('...'), findsOneWidget);
      expect(find.textContaining('0.00'), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // بطاقاتُ الأفعال
  // ══════════════════════════════════════════════════════════════════════
  group('بطاقةُ الفعل', () {
    testWidgets('تعرض العنوانَ والعنوانَ الفرعيَّ وتستجيب للنقر',
        (tester) async {
      var tapped = 0;
      await show(
        tester,
        TreasuryActionCardPicpos(
          title: 'سند قبض',
          subtitle: 'تحصيل من عميل أو جهة',
          icon: Icons.add,
          tint: AppColors.success,
          onTap: () => tapped++,
        ),
        width: 300,
      );
      expect(find.text('سند قبض'), findsOneWidget);
      expect(find.text('تحصيل من عميل أو جهة'), findsOneWidget);

      await tester.tap(find.text('سند قبض'));
      expect(tapped, 1);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // صفُّ الحركة
  // ══════════════════════════════════════════════════════════════════════
  group('صفُّ الحركة', () {
    testWidgets('القبضُ بإشارةِ زائدٍ ولونِ النجاح', (tester) async {
      await show(
        tester,
        const TreasuryMovementRowPicpos(
          isReceipt: true,
          voucherNumber: 'RV-1001',
          time: 'اليوم 11:20',
          party: 'أحمد',
          safeName: 'كاشير 1',
          amount: 300,
        ),
      );
      final amount = tester.widget<Text>(find.textContaining('300'));
      expect(amount.data, startsWith('+'));
      expect(amount.style?.color, AppColors.success);
    });

    testWidgets('الصرفُ بإشارةِ ناقصٍ ولونِ الخطأ', (tester) async {
      await show(
        tester,
        const TreasuryMovementRowPicpos(
          isReceipt: false,
          voucherNumber: 'PV-2002',
          time: 'أمس 09:05',
          party: 'مورد',
          safeName: 'بنك',
          amount: 300,
        ),
      );
      final amount = tester.widget<Text>(find.textContaining('300'));
      expect(amount.data, startsWith('−'));
      expect(amount.style?.color, AppColors.error);
    });

    // الأعمدةُ الأربعةُ التي طلبها التصميمُ كلُّها مرسومة — عمودٌ فارغٌ
    // يُقرأ عطباً، وقد كان `TransactionData.safeName` يصل فارغاً دائماً.
    testWidgets('الأعمدةُ الأربعةُ كلُّها مرسومة', (tester) async {
      await show(
        tester,
        const TreasuryMovementRowPicpos(
          isReceipt: true,
          voucherNumber: 'RV-1001',
          time: 'اليوم 11:20',
          party: 'أحمد علي',
          safeName: 'كاشير 1',
          amount: 300,
        ),
      );
      expect(find.text('RV-1001'), findsOneWidget);
      expect(find.text('اليوم 11:20'), findsOneWidget);
      expect(find.text('أحمد علي'), findsOneWidget);
      expect(find.text('كاشير 1'), findsOneWidget);
    });

    testWidgets('نصوصٌ طويلةٌ لا تفيض', (tester) async {
      await show(
        tester,
        const TreasuryMovementRowPicpos(
          isReceipt: false,
          voucherNumber: 'PV-000000000000000000002',
          time: '12/8 09:05',
          party: 'اسمُ طرفٍ طويلٌ جدّاً يتجاوز عرضَ عمودِه بكثير',
          safeName: 'اسمُ صندوقٍ طويلٌ جدّاً أيضاً لزيادة الضغط',
          amount: 98765432.1,
        ),
        width: 420,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // وقتُ الحركة — دالّةٌ خالصة
  // ══════════════════════════════════════════════════════════════════════
  group('وقتُ الحركة', () {
    final now = DateTime(2026, 8, 22, 10, 0);

    test('اليومَ ⇒ «اليوم HH:mm»', () {
      expect(
        formatMovementTime(DateTime(2026, 8, 22, 11, 20), now),
        'اليوم 11:20',
      );
    });

    // ⚠️ **بالتقويم لا بفارق ٢٤ ساعة.** حركةٌ الساعةَ ٢٣:٥٠ أمسِ يفصلها عن
    // «الآن» عشرُ ساعاتٍ فقط — فحسابٌ بالفارق كان يسمّيها «اليوم».
    test('أمسِ ليلاً ⇒ «أمس» لا «اليوم»', () {
      expect(
        formatMovementTime(DateTime(2026, 8, 21, 23, 50), now),
        'أمس 23:50',
      );
    });

    test('أقدمُ من أمس ⇒ تاريخٌ مختصرٌ ووقت', () {
      expect(
        formatMovementTime(DateTime(2026, 8, 12, 9, 5), now),
        '12/8 09:05',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 🔴 الحارسُ الذي لا تراه يسقط — وصلُ `onGranted`
  // ══════════════════════════════════════════════════════════════════════
  //
  // `PermissionGuard` مع `allowManagerOverride` يلفُّ الابنَ في
  // `AbsorbPointer` ويمسك الضغطةَ بنفسه، ثمّ **يخمّن** الفعلَ بـ
  // `extractChildAction` — وهي تعرف الأزرارَ القياسيّةَ و`InkWell`
  // و`GestureDetector` **وترجع `null` لغيرها**.
  //
  // وبطاقاتُ التصميم `Material`+`InkWell` **داخلَ** ودجتٍ مخصَّصة، فالحارسُ
  // يرى `TreasuryActionCardPicpos` ولا يعرفها. النتيجةُ بلا `onGranted`:
  // يظهر حوارُ المدير، ويوافق المديرُ، **ولا يحدث شيء** — حارسٌ يبدو عاملاً
  // وهو يبتلع الفعل.
  //
  // ⚠️ ويُقاس على الكود **بلا تعليقات**: حارسٌ سابقٌ في هذه الجلسة سقط لأنه
  // طابق نصّاً في تعليقٍ يوثّقه. التعليقُ ليس كوداً.
  group('وصلُ حرّاس الأزرار', () {
    String stripComments(String src) {
      final out = StringBuffer();
      var i = 0;
      while (i < src.length) {
        if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '/') {
          while (i < src.length && src[i] != '\n') {
            i++;
          }
          continue;
        }
        if (src[i] == '/' && i + 1 < src.length && src[i + 1] == '*') {
          i += 2;
          while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
            i++;
          }
          i += 2;
          continue;
        }
        out.write(src[i]);
        i++;
      }
      return out.toString();
    }

    const path =
        'lib/presentation/treasury_picpos/widgets/treasury_actions_grid_picpos.dart';

    test('كلُّ حارسٍ بـ`allowManagerOverride` يمرّر `onGranted`', () {
      final f = File(path);
      expect(f.existsSync(), isTrue, reason: 'الملفُّ «$path» اختفى');
      final code = stripComments(f.readAsStringSync());

      final guards = 'PermissionGuard('.allMatches(code).length;
      expect(guards, greaterThan(0),
          reason: 'لا حارسَ أصلاً — الأزرارُ صارت بلا حراسة');

      final overrides = 'allowManagerOverride: true'.allMatches(code).length;
      final granted = 'onGranted:'.allMatches(code).length;

      expect(granted, greaterThanOrEqualTo(overrides),
          reason: 'حارسٌ بتخمينٍ لا يعرف بطاقةً مخصَّصة ⇒ الفعلُ يضيع بعد '
              'موافقة المدير');
    });

    // الكودان يبقيان مذكورَين في مجلد التوأم — وهو ما يقيسه
    // `picpos_permission_parity_test` على مستوى المجلد.
    test('كودا السندَين مذكوران في الشبكة', () {
      final code = stripComments(File(path).readAsStringSync());
      expect(code, contains('treasuryReceiptsCreate'));
      expect(code, contains('treasuryPaymentsCreate'));
    });
  });
}
