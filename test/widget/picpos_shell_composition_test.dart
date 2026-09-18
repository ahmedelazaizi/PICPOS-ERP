// تركيبُ لبِنات القشرة الثلاثِ الجديدة — **على عرضَين لا واحد.**
//
// ═══ لماذا اختبارُ تركيبٍ لا اختبارُ قطعة ═══
//
// درسٌ مسجَّلٌ في هذا المستودع: اختبارُ التركيب أمسك **خمسةَ أعطابِ تخطيطٍ في
// جلسةٍ واحدة** لم تلحظها اختباراتُ القطع، لأنّ القطعةَ وحدَها تُرسَم في فضاءٍ
// لا حدَّ له فلا تفيض أبداً. والفيضُ يقع عند **حدٍّ ضيّق**.
//
// وهذه اللبِناتُ الثلاثُ تُبنى لتحمل شاشاتِ إعادة التصميم الستَّ عشرة، فعطبُ
// تخطيطٍ فيها يتضاعف ستَّ عشرةَ مرّة.
//
// ⚠️ **ولا يكفي «لم تنهر».** `RenderFlex overflowed` **لا يرمي** في وضع
// الإصدار — يرسم شريطاً أصفرَ وأسودَ ويمضي. فالتوكيدُ على `exception == null`
// وحدَه يمرّ على شاشةٍ مشوّهة. ولذلك يُفحَص `FlutterError.onError` صراحةً.
//
// ⚠️ **وقياسُ الارتفاع لا الفيضِ وحدَه**: الشريطُ الذي يلتفّ يزيد ارتفاعُه
// على العرض الضيّق. فلو تساوى الارتفاعان فالالتفافُ لم يقع — وهو يعني أنّ
// المحتوى خرج من الحدّ صامتاً أو أنّ `Wrap` صار `Row`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_document_header.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_form_action_bar.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_totals_bar.dart';

/// يرسم [child] بعرضٍ محدَّدٍ ويعيد ارتفاعَه، ويجمع كلَّ خطأِ تخطيطٍ وقع.
Future<({double height, List<String> layoutErrors})> _measure(
  WidgetTester tester,
  Widget child,
  double width,
) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  try {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  } finally {
    FlutterError.onError = previous;
  }
  return (
    height: tester.getSize(find.byWidget(child)).height,
    layoutErrors: errors,
  );
}

const _wide = 1400.0;
const _narrow = 420.0;

void main() {
  testWidgets('شريطُ الإجماليّات يلتفّ على الضيّق ولا يفيض', (tester) async {
    // ستّةُ بنودٍ — أقصى ما تعرضه شاشاتُ التصميم.
    PicPosTotalsBar build() => const PicPosTotalsBar(
          items: [
            PicPosTotal(label: 'إجمالي المشتريات', value: '900.00'),
            PicPosTotal(label: 'إجمالي المرتجعات', value: '100.00'),
            PicPosTotal(label: 'الخصم', value: '0.00'),
            PicPosTotal(label: 'الضريبة', value: '0.00'),
            PicPosTotal(label: 'المسدَّد', value: '400.00'),
            PicPosTotal(label: 'الصافي', value: '800.00', emphasis: true),
          ],
        );

    final wide = await _measure(tester, build(), _wide);
    expect(wide.layoutErrors, isEmpty, reason: 'فاض على العرض الواسع');

    final narrow = await _measure(tester, build(), _narrow);
    expect(narrow.layoutErrors, isEmpty,
        reason: 'فاض على العرض الضيّق — `Wrap` لم يلتفّ');

    expect(narrow.height, greaterThan(wide.height),
        reason: 'الارتفاعُ لم يزد على العرض الضيّق ⇒ لم يقع التفافٌ، '
            'فالمحتوى خرج من الحدّ صامتاً');
  });

  testWidgets('وشريطُ الأفعال يلتفّ ولا يفيض', (tester) async {
    PicPosFormActionBar build() => PicPosFormActionBar(
          onBack: () {},
          hint: 'يتطلب الترحيل تساوي المدين والدائن',
          extras: [
            OutlinedButton(onPressed: () {}, child: const Text('معاينة')),
            OutlinedButton(onPressed: () {}, child: const Text('حفظ كعرض سعر')),
          ],
          draft: PicPosFormAction(label: 'حفظ مسودة', onPressed: () {}),
          primary: PicPosFormAction(label: 'مراجعة واعتماد', onPressed: () {}),
        );

    final wide = await _measure(tester, build(), _wide);
    expect(wide.layoutErrors, isEmpty, reason: 'فاض على العرض الواسع');

    final narrow = await _measure(tester, build(), _narrow);
    expect(narrow.layoutErrors, isEmpty, reason: 'فاض على العرض الضيّق');
    expect(narrow.height, greaterThan(wide.height),
        reason: 'لم يقع التفافٌ على الضيّق');
  });

  testWidgets('وترويسةُ المستند تلتفّ ولا تفيض', (tester) async {
    PicPosDocumentHeader build() => PicPosDocumentHeader(
          title: 'فاتورة مشتريات',
          number: 'PINV-0201',
          status: const PicPosDocStatus.draft(),
          icon: Icons.receipt_long,
          note: 'نموذج بديل لنفس السند',
          trailing: [
            OutlinedButton(onPressed: () {}, child: const Text('قائمة القيود')),
          ],
        );

    final wide = await _measure(tester, build(), _wide);
    expect(wide.layoutErrors, isEmpty, reason: 'فاضت على العرض الواسع');

    final narrow = await _measure(tester, build(), _narrow);
    expect(narrow.layoutErrors, isEmpty, reason: 'فاضت على العرض الضيّق');
    expect(narrow.height, greaterThan(wide.height),
        reason: 'لم يقع التفافٌ على الضيّق');
  });

  testWidgets('و«مشغول» يُعطّل كلَّ الأزرار لا المضغوطَ وحدَه',
      (tester) async {
    // ⚠️ تعطيلُ المضغوطِ وحدَه يترك «مراجعة واعتماد» حيّاً أثناء حفظِ
    // مسوّدةٍ، فضغطةٌ ثانيةٌ تُرحّل مستنداً نصفَ محفوظ.
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: PicPosFormActionBar(
              busy: true,
              onBack: () {},
              draft: PicPosFormAction(label: 'حفظ مسودة', onPressed: () {}),
              primary:
                  PicPosFormAction(label: 'مراجعة واعتماد', onPressed: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final f in [
      find.widgetWithText(FilledButton, 'مراجعة واعتماد'),
      find.widgetWithText(OutlinedButton, 'حفظ مسودة'),
      find.widgetWithText(OutlinedButton, 'رجوع'),
    ]) {
      expect(tester.widget<ButtonStyleButton>(f).onPressed, isNull,
          reason: 'زرٌّ ما زال حيّاً أثناء الحفظ');
    }
  });

  testWidgets('ووسمُ الحالة يقول ما يُمرَّر لا ما يُفترَض', (tester) async {
    // درسُ هذه الجلسة: تصميمُ سند القبض عرض شيكاً «برسم التحصيل» لحظةَ
    // إنشائه، وهي حالةٌ لاحقةٌ لا تقع إلّا بالإيداع.
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: PicPosDocumentHeader(
              title: 'سند قبض',
              number: 'RV-0051',
              status: PicPosDocStatus.draft(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('مسودة'), findsOneWidget);
    expect(find.text('معتمد'), findsNothing,
        reason: 'وسمٌ لم يُمرَّر ظهر — الترويسةُ تخترع حالة');
  });

  testWidgets('ومحتوى شاشة مردود المشتريات بعينِه لا يفيض', (tester) async {
    // ⚠️ **اللبِناتُ مقيسةٌ أعلاه بمحتوىً اخترتُه أنا.** والخطرُ الحقيقيُّ
    // في النصوص التي تحملها الشاشاتُ فعلاً: «من فاتورة PINV-0201 · 8/9/2026
    // · 900.00 ج.م» سطرُ ملاحظةٍ أطولُ بكثيرٍ ممّا جرّبت، و«تنفيذ المرتجع»
    // مع تلميحٍ طويل. فتُقاس هنا **بنصّها** لا بعيّنةٍ مشابهة.
    PicPosDocumentHeader header() => const PicPosDocumentHeader(
          title: 'مردود مشتريات',
          icon: Icons.keyboard_return,
          note: 'من فاتورة PINV-0201 • 8/9/2026 • 900.00 ج.م',
          trailing: [Text('PINV-0201')],
        );

    final wideH = await _measure(tester, header(), _wide);
    expect(wideH.layoutErrors, isEmpty, reason: 'الترويسةُ فاضت على الواسع');
    final narrowH = await _measure(tester, header(), _narrow);
    expect(narrowH.layoutErrors, isEmpty, reason: 'الترويسةُ فاضت على الضيّق');
    expect(narrowH.height, greaterThan(wideH.height));

    PicPosTotalsBar totals() => const PicPosTotalsBar(
          items: [
            PicPosTotal(label: 'صافي المرتجع', value: '100.00'),
            PicPosTotal(label: 'الضريبة', value: '14.00'),
            PicPosTotal(label: 'إجمالي المرتجع', value: '114.00', emphasis: true),
          ],
        );
    final wideT = await _measure(tester, totals(), _wide);
    expect(wideT.layoutErrors, isEmpty, reason: 'الإجماليّاتُ فاضت على الواسع');
    final narrowT = await _measure(tester, totals(), _narrow);
    expect(narrowT.layoutErrors, isEmpty, reason: 'الإجماليّاتُ فاضت على الضيّق');
    expect(narrowT.height, greaterThan(wideT.height));

    // شريطُ أفعالٍ **بفعلٍ واحد** — الشكلُ الذي تستعمله هذه الشاشة.
    PicPosFormActionBar bar() => PicPosFormActionBar(
          primary: PicPosFormAction(
            label: 'تنفيذ المرتجع',
            icon: Icons.keyboard_return,
            onPressed: () {},
          ),
        );
    for (final w in const [_wide, _narrow]) {
      final m = await _measure(tester, bar(), w);
      expect(m.layoutErrors, isEmpty, reason: 'شريطُ الأفعال فاض عند $w');
    }
  });

}
