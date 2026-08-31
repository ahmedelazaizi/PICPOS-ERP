// ═══════════════════════════════════════════════════════════════════════════
// نسبةُ الضريبة: عُرفان في سطرٍ واحد — بخسٌ في ض.ق.م بمئةِ ضعف
// ═══════════════════════════════════════════════════════════════════════════
//
// بندٌ **لم يكن في خارطة الطريق**، ظهر أثناء إغلاق §٤‑٦ حين لزم قراءةُ
// النسبة الحقيقيّة.
//
// ── العُرفان ──────────────────────────────────────────────────────────────
//   · `pos_default_tax_rate` و`TableOrders.taxRate` تُخزَّنان **كسريّاً**
//     (‏0.16 = ١٦٪) — و`posDefaultTaxRateProvider` يعيد الخامَ كما هو.
//   · `Products.taxRate` و`CartItemEntity.taxRate` و
//     `FinancialUtils.calculateTaxAmount` كلُّها **مئويّة** (‏16 = ١٦٪).
//
// والمشروعُ يعرف الفرقَ ويضرب في ١٠٠ في سبعةِ مواضعَ على الأقلّ
// (‏`TableOrderTotals.taxPercentFromRate` هو المحوّلُ المُسمّى). وشذّ موضعان:
// نموذجا الفاتورة بهوية PicPos — المبيعات والمشتريات — فمرّرا الكسرَ إلى
// ودجتٍ عقدُها مئويّة.
//
// ── الأثر ────────────────────────────────────────────────────────────────
// في `PicPosInvoiceForm._addProduct`:
//
//     final rate = p.taxRate > 0 ? p.taxRate : widget.systemTaxRate;
//
// فصنفٌ بلا نسبةٍ خاصّةٍ (‏`Products.taxRate == 0`، وهو الافتراضُ في القاعدة)
// كان يأخذ `0.16` فيُحسَب سطرُه بـ**٠٫١٦٪ بدل ١٦٪**، والشريحةُ تعرض
// «ضريبة 0%» (‏`0.16.toStringAsFixed(0)`).
//
// وفي المبيعات عطبٌ ثانٍ فوقه: `ref.read(p).value` قراءةٌ **باردة** ترجع
// `null` قبل اكتمال المستقبَل فتسقط إلى صفرٍ — فاتورةٌ بلا ضريبةٍ إطلاقاً.
//
// ⚠️ **ولا يُقاس هذا بقراءة الودجت**: عقدُها سليمٌ ومُختبَرٌ أصلاً
// (`picpos_invoice_form_test`: ١٤ ⇒ «ضريبة 14%»). العطبُ عند **المنادي**،
// فالمقيسُ هنا المزوّدُ نفسُه وأثرُ الوحدة على الحساب.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/utils/financial_utils.dart';
// `providers.dart` يصدّر `database.dart` و`settings_providers.dart` معاً.
import 'package:ural_erp/data/providers/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting();
    container =
        ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('المزوّدُ المئويُّ يحوّل ولا يمرّر الخام', () {
    test('٠٫١٦ مخزَّنةً ⇒ ١٦ مئويّةً (والخامُ يبقى كسراً)', () async {
      await db.setSetting('pos_default_tax_rate', '0.16');

      final raw = await container.read(posDefaultTaxRateProvider.future);
      final percent = await container.read(posDefaultTaxPercentProvider.future);

      // مرساة: الإعدادُ وصل المزوّدَ فعلاً — لولاها لقِسنا الافتراضَ لا القراءة.
      expect(raw, closeTo(0.16, 1e-9),
          reason: 'مرساة: الخامُ يبقى كسريّاً لمستهلكيه القدامى');
      expect(percent, closeTo(16.0, 1e-9),
          reason: 'المستهلكُ المئويُّ يحتاج ١٦ لا ٠٫١٦');
    });

    test('٠٫١٤ مخزَّنةً ⇒ ١٤ — والقيمةُ تتبع الإعداد لا رقماً مطبوعاً',
        () async {
      await db.setSetting('pos_default_tax_rate', '0.14');
      expect(await container.read(posDefaultTaxPercentProvider.future),
          closeTo(14.0, 1e-9));
    });

    test('بلا إعدادٍ ⇒ ١٦ لا ٠٫١٦', () async {
      expect(await container.read(posDefaultTaxPercentProvider.future),
          closeTo(16.0, 1e-9),
          reason: 'الافتراضُ نفسُه يجب أن يخرج مئويّاً');
    });
  });

  group('أثرُ الوحدة على المال', () {
    test('الكسرُ في مكان المئويّة يبخس الضريبةَ مئةَ ضعف', () async {
      const base = 1000.0;

      // ما كان يقع: الكسرُ يُمرَّر كما هو.
      final wrong = FinancialUtils.calculateTaxAmount(base, 0.16);
      // ما يقع الآن.
      final right = FinancialUtils.calculateTaxAmount(base, 16);

      // قيمٌ محسوبةٌ يدويّاً لا «> صفر»: ١٠٠٠ × ٠٫١٦٪ = ١٫٦ · ١٠٠٠ × ١٦٪ = ١٦٠.
      expect(wrong, closeTo(1.6, 1e-9));
      expect(right, closeTo(160.0, 1e-9));
      expect(right / wrong, closeTo(100.0, 1e-6),
          reason: 'الفارقُ مئةُ ضعفٍ بالضبط — وهو حجمُ البخس في ض.ق.م');
    });

    test('وعرضاً: ٠٫١٦ تُقرأ «0%» على الشريحة', () {
      // نفسُ تنسيق `picpos_invoice_money.dart` — الشريحةُ تعرض
      // `systemTaxRate.toStringAsFixed(0)`.
      expect(0.16.toStringAsFixed(0), '0',
          reason: 'الكسرُ يُعرَض صفراً — فالمستخدمُ يقرأ «ضريبة 0%»');
      expect(16.0.toStringAsFixed(0), '16');
    });
  });

  // ── حارسُ المنادي ────────────────────────────────────────────────────────
  //
  // الاختباراتُ أعلاه تحرس المزوّدَ والحساب. والعطبُ كان في **الوصلة**:
  // منادٍ يقرأ المزوّدَ الخامَ ويمرّره لمستهلكٍ مئويّ. فلو عاد أحدُ الموضعَين
  // إلى `posDefaultTaxRateProvider` لعاد البخسُ بلا أن يسقط شيءٌ أعلاه.
  group('نموذجا PicPos يقرآن المزوّدَ المئويّ', () {
    String read(String path) {
      final src = File(path).readAsStringSync();
      expect(src.length, greaterThan(500), reason: 'مرساة: $path قُرئ فعلاً');
      return src;
    }

    test('المشتريات', () {
      final src =
          read('lib/presentation/purchases_picpos/screens/purchases_picpos_crud.dart');
      // مرساة: الملفُّ المقروءُ هو الذي يبني النموذج.
      expect(src.contains('PicPosInvoiceForm('), isTrue,
          reason: 'مرساة: هذا الملفُّ يبني `PicPosInvoiceForm`');
      expect(src.contains('posDefaultTaxPercentProvider'), isTrue,
          reason: 'المئويُّ لا الخام');
      expect(src.contains('posDefaultTaxRateProvider'), isFalse,
          reason: 'الخامُ كسريٌّ — تمريرُه هنا يبخس الضريبةَ مئةَ ضعف');
    });

    test('المبيعات', () {
      final src = read(
          'lib/presentation/sales_invoices_picpos/screens/sales_invoice_dialogs.dart');
      expect(src.contains('PicPosInvoiceForm('), isTrue,
          reason: 'مرساة: هذا الملفُّ يبني `PicPosInvoiceForm`');
      expect(src.contains('posDefaultTaxPercentProvider'), isTrue,
          reason: 'المئويُّ للفرع الـPicPos');
      expect(src.contains('posDefaultTaxRateProvider'), isFalse,
          reason: 'الخامُ كسريٌّ — و`SalesInvoiceForm` كسريّةُ العقد تُشتقّ '
              'من المئويّة بقسمةٍ صريحةٍ لا بقراءةٍ ثانية');
      // القراءةُ الباردةُ ترجع `null` ⇒ فاتورةٌ بلا ضريبةٍ صامتة.
      expect(src.contains('.value ?? 0'), isFalse,
          reason: 'لا سقوطَ إلى صفرٍ من قراءةٍ باردة');
      // ⚠️ وفي Riverpod 3 كلُّ مزوّدٍ `autoDispose`، و`read(p.future)` لا
      // يُبقيه حيّاً — فيتعلّق ولا يعود. الإبقاءُ شرطٌ لا زينة.
      expect(src.contains('listenManual(posDefaultTaxPercentProvider'), isTrue,
          reason: '`read(p.future)` بلا مستمعٍ يتعلّق حتى المهلة');
    });
  });
}
