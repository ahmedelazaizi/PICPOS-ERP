// test/unit/pending_picpos_report_test.dart
//
// طلبُ فتحِ تقريرٍ من الشريط الجانبيّ — البندُ التاسع من أمر المالك
// 2026-09-12.
//
// ⚠️ **ولماذا `ValueNotifier` ثابتٌ لا مزوِّدُ Riverpod**: مزوّداتُ هذا
// المستودع `autoDispose` افتراضاً. والطلبُ يُكتَب في الشريط ثم تُبنى شاشةُ
// التقارير — وبين الكتابة والقراءة **لا مشترِكَ يُبقيه حيّاً**، فيسقط
// المزوّدُ إلى حالته الأولى ويصل الطلبُ فارغاً. والعطبُ من صنفٍ لا يظهر في
// اختبارٍ يُبقي المزوّدَ مشترَكاً فيه طوال الاختبار.
//
// ⚠️ **ولماذا استهلاكٌ لا قراءة**: الشاشةُ تُبنى مرّاتٍ (تدويرُ الجهاز،
// إعادةُ بناءِ الأب، العودةُ من تقرير). وطلبٌ يبقى مكتوباً يُعيد فتحَ نفس
// التقرير في كلّ بناء — فيُحبَس المستخدمُ فيه ولا يرى مركزَ التقارير.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/providers/pending_picpos_report.dart';

void main() {
  setUp(pendingPicposReport.clear);

  test('لا طلبَ في البداية', () {
    expect(pendingPicposReport.take(), isNull);
  });

  test('الطلبُ يصل كما كُتب', () {
    pendingPicposReport.request(categoryId: 'sales', reportId: 'sales_main');
    final got = pendingPicposReport.take();
    expect(got, isNotNull);
    expect(got!.categoryId, 'sales');
    expect(got.reportId, 'sales_main');
  });

  test('ويُستهلَك مرّةً واحدةً فقط', () {
    pendingPicposReport.request(categoryId: 'sales', reportId: 'sales_main');
    expect(pendingPicposReport.take(), isNotNull);
    expect(pendingPicposReport.take(), isNull,
        reason: 'طلبٌ باقٍ يُعيد فتحَ نفس التقرير في كلّ إعادة بناء');
  });

  test('وفئةٌ بلا تقريرٍ طلبٌ صالح — تُفتح الفئةُ وحدَها', () {
    pendingPicposReport.request(categoryId: 'inventory');
    final got = pendingPicposReport.take();
    expect(got!.categoryId, 'inventory');
    expect(got.reportId, isNull);
  });

  test('والطلبُ الثاني يحلُّ محلَّ الأوّل غيرِ المستهلَك', () {
    pendingPicposReport.request(categoryId: 'sales', reportId: 'sales_main');
    pendingPicposReport.request(categoryId: 'taxes', reportId: 'tax_summary');
    final got = pendingPicposReport.take();
    expect(got!.categoryId, 'taxes',
        reason: 'الأحدثُ هو ما نقره المستخدم — والأقدمُ لم يُفتح قطّ');
    expect(pendingPicposReport.take(), isNull);
  });

  test('والشاشةُ المركَّبةُ تُوقَظ بالإشعار لا بإعادة البناء', () {
    // من كان على شاشة التقارير ونقر تقريراً آخرَ في الشريط: `onNavigate`
    // إلى نفس الفهرس لا يُعيد تركيبَ الشاشة، فلا `initState` يقرأ الطلب.
    var woke = 0;
    void listener() => woke++;
    pendingPicposReport.addListener(listener);
    addTearDown(() => pendingPicposReport.removeListener(listener));

    pendingPicposReport.request(categoryId: 'sales', reportId: 'sales_main');
    expect(woke, 1, reason: 'الشاشةُ المركَّبةُ لن تعلم بالطلب');

    pendingPicposReport.request(categoryId: 'sales', reportId: 'sales_main');
    expect(woke, 2,
        reason: 'طلبٌ مطابقٌ للسابق لا يوقظ — والمساواةُ تبتلع النقرةَ '
            'الثانية على نفس التقرير بعد الرجوع منه');
  });
}
