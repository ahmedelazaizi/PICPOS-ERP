// حارسُ تباينٍ لشاشة «البيع السريع» — يقيس النسبةَ بين الحبرِ وسطحِه.
//
// ═══ لماذا التباينُ لا اللمعانُ وحدَه ═══
//
// `treasury_picpos_dark_mode_test.dart` يقيس لمعانَ السطح، وهو يكفي لسؤال
// «هل الكرتُ داكنٌ فعلاً؟». لكنّ بلاغَ المالك 2026-08-29 شطران:
// «تضاربٌ في ألوان النصوص» و«توزيعُ الوضع على الشاشة». والشطرُ الأوّلُ لا
// يُقاس بلمعانِ طرفٍ واحد: حبرٌ أسودُ على كرتٍ أسودَ لمعانُهما **كلاهما**
// منخفضٌ فيمرُّ فحصُ اللمعان أخضرَ والنصُّ غيرُ مقروء.
//
// فالمقياسُ هنا نسبةُ تباين WCAG بين الحبر وسطحِه: `(L1+.05)/(L2+.05)`.
// وبالسلوك القديم (`#0A0A0A` ثابتاً) قِيست **٢٫٠٦** — أي أقلُّ من نصفِ
// حدِّ المقروئيّة، وهو عينُ ما بلّغ عنه المالك.
//
// ⚠️ والرقمُ بالنكهةِ **الافتراضيّة**: `AppColors.cardDark` ثابتُ ترجمةٍ
// يتفرّع على `Brand.isPicPos`، والبوّابةُ تبني الافتراضيَّ فيُقرأ الفرعُ
// `#1E4A5A`. وعلى كرتِ PicPos `#121C2E` النسبةُ أسوأُ (١٫١٤). فلا تُثبِّت
// رقماً بعينه في التوكيد — الحدُّ ٤٫٥ يصحُّ في النكهتَين.
//
// ⚠️ **وضعٌ واحدٌ لكلِّ اختبار** — نفسُ درسِ اختبار الخزينة: ضخُّ الوضعَين
// في اختبارٍ واحدٍ يعيد استعمالَ نسخةِ الودجت `const` فيُقرأ لونُ الضخّةِ
// الأولى مرّتين.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_pos_text.dart';
import 'package:picpos_erp/presentation/widgets/enhanced_components.dart';

/// نسبةُ تباين WCAG بين لونَين — الأفتحُ في البسط دائماً.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// يضخُّ وضعاً واحداً ويُرجع (حبرَ القيمة، حبرَ التسمية، سطحَ الكرت).
Future<({Color value, Color label, Color card})> _inks(
  WidgetTester tester,
  Brightness brightness,
) async {
  late Color value;
  late Color label;
  late Color card;

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Builder(
        builder: (context) {
          value = PicPosText.valueOf(context);
          label = PicPosText.labelOf(context);
          card = context.picposCard;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();

  return (value: value, label: label, card: card);
}

void main() {
  group('حبرُ «البيع السريع» يُقرأ في الوضعَين', () {
    testWidgets('الفاتحُ — القيمةُ والتسميةُ مقروءتان على الكرت',
        (tester) async {
      final ink = await _inks(tester, Brightness.light);

      expect(_contrast(ink.value, ink.card), greaterThan(4.5),
          reason: 'حبرُ القيمة في الوضع الفاتح.');
      expect(_contrast(ink.label, ink.card), greaterThan(4.5),
          reason: 'حبرُ التسمية في الوضع الفاتح.');
    });

    testWidgets('والغامقُ — الحبرُ يقلب مع السطح لا يبقى أسودَ عليه',
        (tester) async {
      final ink = await _inks(tester, Brightness.dark);

      expect(
        _contrast(ink.value, ink.card),
        greaterThan(4.5),
        reason: 'حبرٌ داكنٌ على كرتٍ داكن = نصٌّ لا يُرى. وبالسلوك القديم '
            '(`PicPosText.value` ثابتاً `#0A0A0A`) النسبةُ ١٫١٤ — وهو '
            'شطرُ «تضارب ألوان النصوص» من بلاغ المالك 2026-08-29.',
      );
      expect(
        _contrast(ink.label, ink.card),
        greaterThan(4.5),
        reason: 'التسميةُ كانت `#334155` ثابتاً — نفسُ العطب.',
      );
    });

    testWidgets('والفاتحُ يبقى مطابقاً بايتاً ببايت', (tester) async {
      final ink = await _inks(tester, Brightness.light);

      // العقدُ المكتوبُ في `picpos_pos_text.dart`: حجّةُ الـhalation على
      // شاشات التِل الرخيصة ما زالت قائمةً، فالفاتحُ لا يتبدّل.
      expect(ink.value, const Color(0xFF0A0A0A));
      expect(ink.label, const Color(0xFF334155));
    });
  });

  // ── شريطُ التصنيفات — اختبارُ تركيبٍ لا اختبارُ قطعة ────────────────────
  //
  // الشريطُ يعيش في `EnhancedCategoryFilter` تحت `lib/presentation/widgets/`
  // لا تحت `pos_picpos/`، ويصله الكاشيرُ عبر
  // `picpos_pos_screen ← PosProductSelectionPanel ← ProductGrid`. ولهذا
  // بقيت أرضيّتُه بيضاءَ بينما مجلّدُ الشاشةِ نظيف.
  //
  // ⚠️ **وعرضان لا عرضٌ واحد**: عطبُ التخطيطِ لا يظهر إلّا عند عرضٍ بعينه،
  // وقد مُسِكت خمسةُ أعطابٍ في جلسةٍ واحدةٍ بقياسِ عرضَين فاتت اختباراتِ
  // القطعة. و«لم تنهر» ليست نتيجة.
  group('شريطُ التصنيفات يتبع الوضع', () {
    Future<Color?> barSurface(WidgetTester tester, double width) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: width,
                child: EnhancedCategoryFilter(
                  key: const Key('probe'),
                  categories: const [
                    CategoryFilterItem(
                        id: 1,
                        name: 'صناعة الحلويات',
                        icon: PhosphorIconsBold.cookie),
                    CategoryFilterItem(
                        id: 2,
                        name: 'بقوليات و مكرونة',
                        icon: PhosphorIconsBold.bread),
                    // ضابطٌ قصيرٌ يسع سطراً واحداً — به تُقاس النسبة.
                    CategoryFilterItem(
                        id: 3, name: 'خضار', icon: PhosphorIconsBold.carrot),
                  ],
                  selectedId: 1,
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const Key('probe')),
              matching: find.byType(Container),
            )
            .first,
      );
      return (container.decoration as BoxDecoration?)?.color;
    }

    for (final width in <double>[900, 1400]) {
      testWidgets('أرضيّتُه داكنةٌ فعلاً عند عرض ${width.toInt()}',
          (tester) async {
        final surface = await barSurface(tester, width);

        expect(surface, isNotNull);
        expect(
          surface!.computeLuminance(),
          lessThan(0.2),
          reason: 'شريطُ التصنيفات كان `Colors.white` مثبَّتاً '
              '(`enhanced_components.dart`) — شريطٌ ناصعٌ أسفلَ شبكةٍ داكنة.',
        );
      });
    }

    // ── البتر — بلاغُ المالك 2026-08-29 بالصورة ──────────────────────────
    //
    // «صناعة الحلو…» و«بقوليات و م…» و«كيك وكوكوا…». والسببُ رقمان في
    // `enhanced_components.dart`: `SizedBox(width: labelWidth)` بـ٥٢px
    // و`maxLines: 1`. فأيُّ اسمٍ عربيٍّ يتجاوز ~٧ محارفَ عند خطٍّ ٩ يُبتر.
    //
    // ⚠️ **والقياسُ على الارتفاعِ المرسوم لا على `maxLines`.** توكيدُ
    // `maxLines == 2` يقيس السطرَ الذي كتبناه لا النتيجةَ التي يراها
    // الكاشير. والارتفاعُ يقرأ الرسمَ نفسَه: اسمٌ طويلٌ نزل سطراً ثانياً
    // ارتفاعُه ضعفُ ارتفاعِ اسمٍ قصير.
    //
    // ⚠️ **ولا يصحُّ هنا `didExceedMaxLines`**: خطُّ `flutter_test`
    // الاحتياطيُّ يرسم كلَّ محرفٍ مربّعاً عرضُه = حجمُ الخط، فـ«صناعة
    // الحلويات» تقيس ١٤×٩ = ١٢٦px بينما سطران من ٥٢px يسعان ١٠٤ — فيسقط
    // التوكيدُ على خطِّ الاختبار لا على المنتج. و«القاهرة» الحقيقيّ عند ٩px
    // أضيقُ من ذلك بكثير. فالنسبةُ بين ارتفاعَين مقياسٌ لا يتعلّق بالخطّ.
    for (final width in <double>[900, 1400]) {
      testWidgets('واسمُ التصنيف الطويل ينزل سطراً ثانياً عند عرض '
          '${width.toInt()}', (tester) async {
        await barSurface(tester, width);

        final short =
            tester.renderObject<RenderParagraph>(find.text('خضار')).size.height;
        final long = tester
            .renderObject<RenderParagraph>(find.text('صناعة الحلويات'))
            .size
            .height;

        expect(
          long,
          greaterThan(short * 1.5),
          reason: 'الاسمُ الطويلُ ما زال محبوساً في سطرٍ واحدٍ فيُبتر — '
              'وهو عينُ ما صوّره المالكُ 2026-08-29 («صناعة الحلو…»). '
              'القصيرُ $short والطويلُ $long.',
        );
      });
    }

    // ── حبرُ اسم التصنيف ────────────────────────────────────────────────
    //
    // البترُ ليس عطبَ الشريطِ الوحيد: الاسمُ كان يُرسَم بـ
    // `AppColors.textSecondary` (`#374151`) وهو رماديٌّ داكن، والمختارُ
    // بـ`AppColors.primary` (`#0250D3`). وكلاهما حبرٌ **للأرضيّة الفاتحة**،
    // فنسبتُهما على الكرت الداكن ١٫٠٧ و١٫٤٤ — أي اسمٌ لا يُرى أصلاً. فلا
    // يكفي أن يُحَلَّ البترُ ويبقى النصُّ غيرَ مقروء.
    testWidgets('وحبرُ الاسم مقروءٌ على الشريط الداكن — مختاراً وغيرَ مختار',
        (tester) async {
      final surface = await barSurface(tester, 1400);

      for (final name in const ['صناعة الحلويات', 'خضار']) {
        final style = tester.widget<Text>(find.text(name)).style!;
        expect(
          _contrast(style.color!, surface!),
          greaterThan(4.5),
          reason: 'اسمُ التصنيف «$name» غيرُ مقروءٍ على شريطٍ داكن.',
        );
      }
    });
  });
}
