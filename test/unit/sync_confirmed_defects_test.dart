// ثلاثةُ عيوبِ تزامنٍ **مقيسة** — تدقيقُ 2026-08-13.
//
// كلُّ واحدٍ منها فئتُه «فشلٌ صامت»: المسارُ يعلن النجاحَ والكتابةُ لم تصل.
// وهي أخطرُ من الفشل الصريح لأن لا أحدَ يبحث عمّا يقول النظامُ إنه تمّ.
//
// ── لماذا تُقاس المصادرُ نصّاً ────────────────────────────────────────────
// المسارانِ الأوّلانِ يحتاجان خادمَ HTTP حيّاً وقاعدةَ عميلٍ مُقرَنة، والثالثُ
// طابورَ صادرٍ مع وسيطٍ وهميّ — وكلُّها بنيةٌ لا تقيسها سويّةُ الوحدة. والسؤالُ
// المطروحُ هنا **بنيويٌّ لا سلوكيّ**: هل يُحتسب الفشلُ فشلاً؟ هل يُولَّد الرقمُ
// مرّةً؟ هل ثمّة فرعٌ للعملية؟ والنصُّ يجيبها بدقّة.
//
// ⚠️ ويُقاس على الكود بلا تعليقات: التعليقاتُ هنا تشرح العطبَ وتذكر أسماءَه،
// فقياسٌ لا يجرّدها كان سيمرّ أخضرَ على شرحِ العطب لا على إصلاحه.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/library_source.dart';

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

String code(String path) {
  final f = File(path);
  expect(f.existsSync(), isTrue, reason: 'الملفُّ «$path» اختفى');
  return stripComments(readLibrarySource(path));
}

int at(String haystack, String needle) {
  final i = haystack.indexOf(needle);
  expect(i, greaterThan(-1), reason: '«$needle» غير موجود');
  return i;
}

void main() {
  group('B1 — المزامنةُ الأولى لا تُعلن نجاحاً على فشلٍ جزئيّ', () {
    late final String src = code('lib/services/sync_service.dart');

    test('نجاحُ `fullSync` مشروطٌ بصفر فشل', () {
      expect(src.contains('success: totalFailed == 0'), isTrue,
          reason: 'كان `success: true` **بلا شرط**، بينما '
              '`performFirstSync` يحرس بـ`if (!syncResult.success) throw` ثم '
              'يكتب علمَ الاكتمال — فحارسٌ يفحص علماً لا يُطفأ أبداً.');
    });

    test('وفشلُ الجلب يُحتسب فشلاً لا «لا شيء»', () {
      // `_fetchJson` يبتلع كلَّ ردٍّ غيرِ 200 ويعيد `null`. فإن أعاد المسارُ
      // `false` هنا لم يُحتسب لا نجاحاً ولا فشلاً ⇒ تُبذَر مؤشّراتُ الزمن
      // على «مُزامَنٌ حتى الآن» ⇒ كتالوجٌ فارغٌ إلى الأبد.
      final body = src.substring(
          at(src, 'final result = await _fetchJson(strategy.apiEndpoint);'));
      final window = body.substring(0, 600);
      expect(window.contains('return false;'), isFalse,
          reason: 'مسارُ فشلِ الجلب يجب أن يعيد `null` (فشل). و`false` '
              'محجوزٌ لمعناه الوحيد: تخطٍّ مقصودٌ (سبيك 151).');
    });

    test('والتخطّي المقصودُ يبقى `false` — لا يُحتسب فشلاً', () {
      // ضابط: لولاه لكان «الإصلاح» بقلب كلّ `false` إلى `null`، فيفشل
      // كلُّ عميلٍ بلا رمزِ جلسةٍ في أوّل مزامنة — كسرٌ لا تأمين.
      final skip = src.substring(
          at(src, '_branchScopedFullSyncEndpoints.contains'), );
      expect(skip.substring(0, 400).contains('return false;'), isTrue,
          reason: 'تخطّي جدولٍ محصورٍ بالفرع بلا رمزِ جلسة يجب أن يبقى '
              '«لا نجاحٌ ولا فشل»');
    });
  });

  group('H4 — رقمٌ واحدٌ للبيعة الواحدة', () {
    late final String src =
        code('lib/data/repositories/sales_transaction_orchestrator.dart');

    test('الإدخالُ المحليُّ يعيد استعمال الرقم المُرسَل للسيرفر', () {
      expect(src.contains('clientSaleNumber = localInvoiceNumber;'), isTrue,
          reason: 'الرقمُ يُولَّد مرّةً ويُحتفظ به');
      expect(src.contains('clientSaleNumber ??'), isTrue,
          reason: 'والإدخالُ المحليُّ يستعمله بدل توليدِ رقمٍ ثانٍ');
    });

    test('ولا بادئةَ `INV` في مسارِ العميل', () {
      // كانت `Receipt` للسيرفر و`INV` للمحليّ — عدّادان يتقدّمان لكلّ بيعة،
      // والورقةُ تحمل رقماً لا يعرفه السيرفر.
      //
      // ⚠️ والتأكيدُ مقصورٌ على **احتياطِ مسار العميل**، لا على الملفّ كلِّه:
      // المسارُ المستقلّ (`_db.transaction` في `createSale`) يستعمل `INV`
      // بحقّ — عدّادُ SINV القانونيُّ للمبيعات العادية. وأوّلُ صياغةٍ لهذا
      // التأكيد كانت على الملفّ كلِّه فأمسكت ذلك الموضعَ السليم.
      final fallback = src.substring(at(src, 'clientSaleNumber ??'));
      expect(fallback.substring(0, 160).contains("'INV'"), isFalse,
          reason: 'بادئةٌ ثانيةٌ في نفس البيعة تفتح سلسلةً موازيةً بفجوات');
      expect(fallback.substring(0, 160).contains("'Receipt'"), isTrue,
          reason: 'والاحتياطُ يجب أن يوافق ما يرسله للسيرفر');
    });
  });

  group('H6 — لا عمليةَ تُبتلع صامتةً في طابور الصادر', () {
    late final String src = code('lib/services/offline_sync_worker.dart');

    test('`product_units` يعالج `update`', () {
      final body = src.substring(at(src, "case 'product_units':"));
      final window = body.substring(0, 900);
      expect(window.contains('updateProductUnitMapping'), isTrue,
          reason: 'كان `update` يسقط على `break` فيعود `null` ⇒ يُعلَّم '
              '**ناجحاً** بلا إرسال. تعديلُ سعرِ وحدةٍ أثناء انقطاعٍ يضيع، '
              'ثم يُرجَع بأوّل سحبٍ (`serverWins`).');
    });

    test('وله فخُّ فئةٍ لعمليةٍ غيرِ معروفة', () {
      final body = src.substring(at(src, "case 'product_units':"));
      expect(body.substring(0, 900).contains('Unhandled op'), isTrue,
          reason: 'الصمتُ على عمليةٍ غيرِ معروفةٍ هو العطبُ نفسُه — '
              'يُرمى ولا يُبتلع');
    });
  });
}
