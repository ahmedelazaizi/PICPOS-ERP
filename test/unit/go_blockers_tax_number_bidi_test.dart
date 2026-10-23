// ═══════════════════════════════════════════════════════════════════════════
// البند ٤‑٢ — الرقمُ الضريبيُّ يُطبَع مقلوباً
// ═══════════════════════════════════════════════════════════════════════════
//
// ── العطب ─────────────────────────────────────────────────────────────────
//
// رقمٌ مثل `310-123-456-789` داخلَ فقرةٍ عربيّةٍ يخرج على الورق
// `789-456-123-310` — **مقلوبَ المقاطع**. مرصودٌ في بصمةٍ مشحونة:
// `test/goldens/printing/asset_a4_customer_statement.txt:20`.
//
// وهذا **رقمُ تسجيلٍ ضريبيٍّ على مستندٍ ضريبيّ**: قراءتُه معكوسةً تعني
// مستنداً يحمل رقمَ منشأةٍ أخرى — أو رقماً لا وجودَ له.
//
// ── الجذر: قاعدةُ W2 لا W4 ───────────────────────────────────────────────
//
// الأرقامُ اللاتينيّةُ صنفُها `EN`. وقاعدةُ **W2** في خوارزميّة bidi تحوّل
// `EN` إلى `AN` حين يكون أقربُ صنفٍ قويٍّ **سابقٍ** هو `AL` (حرفٌ عربيّ) —
// وهو حالُ التسمية «السجل الضريبي:» قبلَه.
//
// وبعد التحوّل إلى `AN` **تسقط قاعدةُ W4**: هي تصل `EN ES EN` فقط، ولا
// تعرف `AN ES AN`. فتبقى الشُّرَطُ محايدةً وتُقطَّع السلسلةُ إلى مقاطعَ
// تُرتَّب من اليمين لليسار ⇒ الانقلاب.
//
// ── العلاج: LRM لا LRI ───────────────────────────────────────────────────
//
// ⚠️ **العلاجُ الموصوفُ في تسليمٍ أقدم (`U+2066 LRI` عازلٌ) لا يعمل**:
// حزمةُ الـPDF لا تنفّذ محارفَ العزل، فتمرُّ كأنّها لا شيءٌ ويبقى الرقمُ
// مقلوباً. المطلوبُ `U+200E LRM` — علامةٌ **قويّةٌ يساريّة** تصير هي
// «أقربَ صنفٍ قويٍّ سابق»، فلا تنطبق W2، وتبقى الأرقامُ `EN`، فتعمل W4
// وتصل السلسلةَ مقطعاً واحداً يساريَّ الاتّجاه.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/templated_invoice_service.dart';

import '../helpers/pdf_probe.dart';

/// رقمٌ بمقاطعَ **غيرِ متناظرة** عن قصد: لو كان `123-123` لَقُرئ صحيحاً
/// حتّى وهو مقلوب، فمرَّ العطبُ. هذا ينقلب إلى `789-456-123-310` ظاهراً.
const _taxId = '310-123-456-789';
const _reversed = '789-456-123-310';
const _phone = '011-987-6543';
const _phoneReversed = '6543-987-011';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.seedDefaultTemplates();
  });
  tearDown(() => db.close());

  Future<List<String>> printAndReadTexts(String type, String category) async {
    final bytes = (await TemplatedInvoiceService.printWithTemplate(
      db: db,
      debugBuildOnly: true,
      type: type,
      category: category,
      invoiceNumber: 'TAX-1',
      date: DateTime(2026, 8, 31),
      customerName: 'عميل',
      customerPhone: null,
      customerAddress: null,
      items: const [
        {'name': 'صنف', 'quantity': 1.0, 'price': 100.0, 'total': 100.0}
      ],
      subtotal: 100.0,
      discount: 0.0,
      tax: 0.0,
      deliveryFee: 0.0,
      total: 100.0,
      paid: 100.0,
      companyName: 'شركة',
      companyAddress: '',
      companyPhone: _phone,
      companyTaxId: _taxId,
    )).bytes;
    return probePdf(bytes).allTexts.map((t) => t.text).toList();
  }

  /// يجرّد محارفَ الضبط كي تُقارَن **القيمةُ** لا التمثيل.
  String strip(String s) => s.replaceAll('‎', '').replaceAll('‏', '');

  group('الرقمُ الضريبيُّ يُطبَع بترتيبه الصحيح', () {
    test('🔴 A4 — لا يظهر مقلوباً', () async {
      final texts = (await printAndReadTexts('a4', 'invoice')).map(strip);
      final joined = texts.join(' ');

      expect(joined.contains(_reversed), isFalse,
          reason: 'الرقمُ الضريبيُّ مقلوبٌ على الورق — مستندٌ ضريبيٌّ '
              'يحمل رقمَ منشأةٍ أخرى');
      expect(joined.contains(_taxId), isTrue,
          reason: 'ولا يكفي ألّا يكون مقلوباً: يجب أن يكون **موجوداً** '
              'بترتيبه الصحيح، وإلّا لمرَّ حذفُه بالكامل');
    });

    // ⚠️ القالبُ الحراريُّ المبذورُ **لا يحمل عنصرَ الرقم الضريبيّ** أصلاً
    // (‏مقيسٌ في `_thermalDefaultElements`: اسمُ الشركة وعنوانُها وهاتفُها
    // فقط). فتوكيدُ حضورِ الرقم هناك كان يقيس **غيابَ عنصرٍ** لا عطبَ
    // اتّجاه — أي توكيدٌ يسقط لسببٍ غيرِ الذي كُتب له.
    //
    // والهاتفُ هو معرِّفُ هذا القالب، وكان مقلوباً في المسارَين.
    test('🔴 الحراريّ — الهاتفُ لا يظهر مقلوباً', () async {
      final texts = (await printAndReadTexts('thermal', 'receipt')).map(strip);
      final joined = texts.join(' ');

      expect(joined.contains(_phoneReversed), isFalse,
          reason: 'المسارُ القديم (v1) يبني نصَّه بنفسه ولا يمرُّ بـ'
              '`resolveContentValue` — فإصلاحُ ذاك وحدَه تركه مقلوباً');
      expect(joined.contains(_phone), isTrue);
    });

    test('وA4 يُصلح الهاتفَ كذلك — المساران معاً', () async {
      final texts = (await printAndReadTexts('a4', 'invoice')).map(strip);
      final joined = texts.join(' ');
      expect(joined.contains(_phoneReversed), isFalse);
      expect(joined.contains(_phone), isTrue);
    });
  });
}
