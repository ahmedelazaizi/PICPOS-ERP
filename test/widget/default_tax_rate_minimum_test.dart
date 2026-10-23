import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/tax_rate_bounds.dart';
import 'package:picpos_erp/presentation/widgets/settings/pos_settings_widget.dart';

/// الحدُّ الأدنى للنسبة **حيث يُكتَب الإعداد** — لا حيث يُقرأ.
///
/// `pos_default_tax_rate` هو منبعُ اللقطة التي تُثبَّت على كلِّ طلبِ طاولة.
/// ورفضُ نسبةٍ لا تُحصَّل عند المصدر أوضحُ للمستخدم من رفضٍ لاحقٍ عند فتح
/// طاولةٍ برسالةٍ تحيله إلى الإعدادات.
///
/// **ولا تُفتَح شاشةُ الإعدادات هنا**: اختباراتُ الويدجت تتعلّق عند فتح
/// الشاشات في هذا المستودع. المقيسُ دالّتان خالصتان وودجتٌ واحدٌ معزول — وكلُّها
/// كودُ إنتاجٍ يُستدعى من الشاشة نفسِها، لا نسخةٌ منه في الاختبار.
void main() {
  group('المُتحقِّقُ من المدخل — النسبةُ مئويّةٌ كما يكتبها المستخدم', () {
    test('الحدُّ الأدنى نفسُه يُقبل', () {
      expect(validateDefaultTaxRatePercent('1'), isNull);
    });

    test('الصفرُ يُقبل — «محلٌّ بلا ضريبة»', () {
      expect(validateDefaultTaxRatePercent('0'), isNull);
    });

    test('النسبُ الواقعيّةُ تُقبل', () {
      for (final raw in ['5', '14', '15', '16', '20', '100']) {
        expect(validateDefaultTaxRatePercent(raw), isNull,
            reason: '$raw٪ نسبةٌ واقعيّةٌ يجب أن تُقبل');
      }
    });

    test('ما دون الحدِّ فوق الصفرِ يُرفض — وهذه هي الثغرةُ بعينها', () {
      for (final raw in ['0.5', '0.001', '0.9']) {
        expect(validateDefaultTaxRatePercent(raw), isNotNull,
            reason: '$raw٪ تَعِد بضريبةٍ ولا تُحصّل شيئاً');
      }
    });

    test('ما فوق المئةِ يُرفض', () {
      expect(validateDefaultTaxRatePercent('101'), isNotNull);
      expect(validateDefaultTaxRatePercent('1600'), isNotNull);
    });

    test('السالبُ يُرفض', () {
      expect(validateDefaultTaxRatePercent('-1'), isNotNull);
    });

    test('الفارغُ وغيرُ الرقمِ يُرفضان — لا يُبتلعان صامتَين', () {
      // `onChanged` تتجاهل ما لا يُحلَّل، فتبقى الحالةُ على قيمتها القديمة
      // والحقلُ يعرض شيئاً آخر. الرفضُ يُظهر الافتراقَ بدل أن يُخفيه.
      expect(validateDefaultTaxRatePercent(''), isNotNull);
      expect(validateDefaultTaxRatePercent(null), isNotNull);
      expect(validateDefaultTaxRatePercent('س'), isNotNull);
    });

    test('رسالةُ الرفضِ تذكر الحدَّ — لا «قيمة غير صالحة» مبهمة', () {
      expect(validateDefaultTaxRatePercent('0.5'), contains('١'));
    });
  });

  group('بوّابةُ الحفظ — يُرفَض ما يكتبه المستخدمُ لا ما ورثه', () {
    test('قيمةٌ موروثةٌ مخالفةٌ لم تُلمَس لا تمنع الحفظ', () {
      // الحقلُ **لا يُخفى** عند نقص الصلاحية — `PermissionGuard` يقفله
      // والقيمةُ تُحمَّل وتُرحَّل مع الحفظ. فمنعٌ مطلقٌ يعني أن مستخدماً لا
      // يملك `settings_tax` يعجز عن حفظ خمسين إعداداً آخر بسبب حقلٍ لا
      // يُسمح له بلمسه.
      expect(blocksSaveForTaxRate(touched: false, rate: 0.005), isFalse);
      expect(blocksSaveForTaxRate(touched: false, rate: -1), isFalse);
    });

    test('قيمةٌ مخالفةٌ كتبها المستخدمُ الآن تمنع الحفظ', () {
      expect(blocksSaveForTaxRate(touched: true, rate: 0.005), isTrue);
      expect(blocksSaveForTaxRate(touched: true, rate: 1.6), isTrue);
    });

    test('قيمةٌ صحيحةٌ كتبها المستخدمُ لا تمنع', () {
      expect(blocksSaveForTaxRate(touched: true, rate: TaxRateBounds.minRate),
          isFalse);
      expect(blocksSaveForTaxRate(touched: true, rate: 0.16), isFalse);
      expect(blocksSaveForTaxRate(touched: true, rate: 0), isFalse);
    });
  });

  group('الحقلُ الحقيقيُّ داخل Form — المُتحقِّقُ موصولٌ لا مكتوبٌ وحدَه', () {
    // `validator:` بلا `Form` لا يعمل: لا أحدَ يستدعي `validate()`. وهذا الفوجُ
    // يقيس أن الوصلَ قائمٌ في ودجتِ الإنتاج نفسِه.
    Future<void> pumpField(
      WidgetTester tester, {
      required GlobalKey<FormState> formKey,
      required void Function(double) onRateChanged,
      double initialRate = 0.16,
    }) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: buildDefaultTaxRateFormField(
            formKey: formKey,
            initialRate: initialRate,
            onRateChanged: onRateChanged,
          ),
        ),
      ));
    }

    testWidgets('نسبةٌ دون الحدِّ تُظهر رفضاً في الحقل', (tester) async {
      final formKey = GlobalKey<FormState>();
      await pumpField(tester, formKey: formKey, onRateChanged: (_) {});

      await tester.enterText(find.byType(TextFormField), '0.5');
      await tester.pump();

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.textContaining('١'), findsWidgets);
    });

    testWidgets('نسبةٌ صحيحةٌ لا تُظهر رفضاً', (tester) async {
      final formKey = GlobalKey<FormState>();
      await pumpField(tester, formKey: formKey, onRateChanged: (_) {});

      await tester.enterText(find.byType(TextFormField), '16');
      await tester.pump();

      expect(formKey.currentState!.validate(), isTrue);
    });

    testWidgets('الحقلُ يُخرج كسريّةً من المئويّة المكتوبة', (tester) async {
      double? seen;
      // نصٌّ يخالف الابتدائيَّ عمداً: إدخالُ نفسِ القيمة لا يُطلق `onChanged`.
      await pumpField(tester,
          formKey: GlobalKey<FormState>(),
          initialRate: 0.16,
          onRateChanged: (r) => seen = r);

      await tester.enterText(find.byType(TextFormField), '20');
      await tester.pump();

      expect(seen, closeTo(0.20, 1e-12));
    });

    testWidgets('الحقلُ يبدأ بالمئويّة المشتقّة من الكسريّة', (tester) async {
      await pumpField(tester,
          formKey: GlobalKey<FormState>(),
          initialRate: 0.16,
          onRateChanged: (_) {});

      expect(find.text('16'), findsOneWidget);
    });
  });
}
