// حارسُ العقد: مساراتُ حساب الطاولة الثلاثةُ مسيَّجةٌ ومعفاةٌ من المصادقة معاً.
//
// ═══ فئةُ العطب ═══
//
// هذه المساراتُ **الوحيدةُ** في الخادم التي تُخدَم بلا مصادقةٍ وتقرأ بياناتِ
// معاملةٍ حقيقيّة. و`/menu` و`/cfd` معفيّان كذلك لكنّهما شاشتا عرضٍ عامّة —
// قائمةُ أصنافٍ وشاشةُ زبون — لا حسابُ طاولةٍ بعينها.
//
// فسقوطُ سياجٍ واحدٍ من الثلاثة لا يُنتج خطأً ولا شاشةً مكسورة: يُنتج سطحاً
// مفتوحاً على شبكة المحلّ يقرأ منه أيُّ جهازٍ حساباتِ الطاولات. وهو عطبٌ
// **لا يظهر في أيّ اختبارٍ سلوكيّ ناجح** — كلُّ ما يفعله أنه يسمح بأكثر.
//
// ⚠️ **والإغراءُ محدَّدٌ ومعروف**: من يُصحِّح «الصفحةُ لا تفتح عندي» أسرعُ
// إصلاحٍ أمامه حذفُ فحصِ الراية. فالاختبارُ السلوكيُّ يُثبت أنها تعمل مُشعَلةً،
// وهذا يُثبت أنها لا تعمل مُطفأةً — وهما توكيدان مختلفان.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/api_handler_source.dart';

const _authPath = 'lib/services/api/api_auth_middleware.dart';
const _limiterPath = 'lib/services/api/api_rate_limiter.dart';

/// جسمُ الدالّة المسمّاة — بموازنة الأقواس بعد تجاوزِ قائمة المعاملات.
String _body(String src, String signature) {
  final at = src.indexOf(signature);
  expect(at, greaterThanOrEqualTo(0), reason: 'لم أجد «$signature»');

  // ⚠️ **المسحُ يبدأ من [at] لا من نهاية التوقيع.** توقيعٌ يحمل جزءاً من
  // قائمة المعاملات — و`_getTableBill(Request` يحمله اضطراراً لأنّ
  // `_getTableBill` سابقةٌ لـ`_getTableBillPage` فتطابقها أوّلاً — يكون قوسُه
  // الفاتحُ **قد استُهلك** في التوقيع، فيبدأ العدُّ من صفرٍ ويقع على القوس
  // المغلق فينزل إلى ‎-1 ولا يساوي صفراً أبداً. والجسمُ المُستخرَجُ حينَها
  // لدالّةٍ أخرى تماماً — ويمرّ الحارسُ أو يسقط لسببٍ لا علاقةَ له بالشيفرة.
  var i = at;
  var parens = 0;
  for (; i < src.length; i++) {
    if (src[i] == '(') parens++;
    if (src[i] == ')') {
      parens--;
      if (parens == 0) {
        i++;
        break;
      }
    }
  }
  final open = src.indexOf('{', i);
  expect(open, greaterThanOrEqualTo(0), reason: 'لا جسمَ لـ«$signature»');

  var depth = 0;
  for (var j = open; j < src.length; j++) {
    if (src[j] == '{') depth++;
    if (src[j] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, j + 1);
    }
  }
  fail('جسمُ «$signature» غيرُ مغلق');
}

/// إعلانٌ ينتهي بفاصلةٍ منقوطة — قائمةٌ ثابتةٌ أو دالّةٌ بجسمٍ تعبيريّ.
///
/// ⚠️ **و[_body] لا تصلح لهما**: تلك توازن `{}`، و`static const x = [...];`
/// لا أقواسَ معقوفةً فيها أصلاً، ودالّةُ `=> …;` كذلك. وأوّلُ صياغةٍ لهذا
/// الحارس استعملت [_body] للثلاثة فسقطت — لا لأن الشيفرةَ خاطئةٌ بل لأن
/// المستخرِجَ كان يقرأ ما بعدها.
String _decl(String src, String anchor) {
  final at = src.indexOf(anchor);
  expect(at, greaterThanOrEqualTo(0), reason: 'لم أجد «$anchor»');
  final end = src.indexOf(';', at);
  expect(end, greaterThan(at), reason: 'إعلانُ «$anchor» بلا نهاية');
  return src.substring(at, end + 1);
}

void main() {
  late String handler;

  setUpAll(() => handler = readApiHandlerSource());

  test('مرساةُ القراءة — المسارات الثلاثةُ مسجَّلةٌ فعلاً', () {
    // بلا هذه المرساة تقرأ الفحوصُ أدناه غياباً وتمرّ وهي عمياء.
    for (final route in const [
      "router.get('/t/<token>'",
      "router.get('/api/table-bill/<token>'",
      "router.post('/api/table-bill/<token>/request'",
    ]) {
      expect(handler.contains(route), isTrue,
          reason: 'المسارُ غيرُ مسجَّل — أو تبدّل نصُّه فالفحوصُ عمياء: $route');
    }
  });

  test('وكلُّ معالجٍ منها يفحص الرايةَ قبل أيّ شيء', () {
    for (final fn in const [
      'Future<Response> _getTableBillPage',
      'Future<Response> _getTableBill(Request',
      'Future<Response> _requestTableBill',
    ]) {
      final body = _body(handler, fn);
      expect(body.contains('_tableBillEnabled()'), isTrue,
          reason: '«$fn» يُخدَم بلا سياجٍ — سطحٌ مفتوحٌ على شبكة المحلّ');
    }
  });

  test('والرايةُ تشترط `true` صريحةً — لا «ليست false»', () {
    // `!= 'false'` كان يُشعلها على كلّ تنصيبةٍ لم تُكتَب فيها قيمةٌ قطّ.
    final body = _decl(handler, 'Future<bool> _tableBillEnabled()');
    expect(body.contains("== 'true'"), isTrue,
        reason: 'شرطُ الإشعال ليس مساواةً بـ`true` — الافتراضُ انقلب');
  });

  test('والكتابةُ تشترط رمزَ الجلسة لا رمزَ الطاولة المطبوع', () {
    final body = _body(handler, 'Future<Response> _requestTableBill');
    expect(body.contains('TableBillToken.verifySession('), isTrue,
        reason: 'الكتابةُ بلا رمزِ جلسة — الرمزُ المطبوعُ يكفي لمناداة النادل');
  });

  test('والمستحقُّ من المحرّك الواحد لا من جمعِ السطور', () {
    final body = _body(handler, 'Future<Response> _getTableBill(Request');
    expect(body.contains('TableSessionService(_db).totalsFor('), isTrue,
        reason: 'حسابٌ رابعٌ يعرض على الضيف رقماً يخالف ما يُطبَع في يده');
  });

  test('والمسارُ معفىً من المصادقة — وإلّا رُفض كلُّ زبون', () {
    final auth = File(_authPath).readAsStringSync();
    final body = _decl(auth, 'static const _exemptPrefixes');
    expect(body.contains("'/api/table-bill'"), isTrue,
        reason: 'بلا إعفاءٍ يرُدّ الوسيطُ 401 على كلّ هاتف');
  });

  test('ولا يُعفى من محدّد المعدّل — بخلاف /menu و/cfd', () {
    final limiter = File(_limiterPath).readAsStringSync();
    final exempt = _decl(limiter, 'static const _exemptPrefixes');
    expect(exempt.contains('table-bill'), isFalse,
        reason: 'الإعفاءُ من المحدِّد يجعل تخمينَ التواقيع مسحاً بلا كلفة');
    expect(limiter.contains("MapEntry('/api/table-bill'"), isTrue,
        reason: 'بلا قاعدةِ تصنيفٍ يسقط على الافتراضيّ مع تحذيرِ «غيرُ مصنَّف»');
  });

  group('وضعُ الدومين العامّ — الحاجزُ الأوّلُ ساقط', () {
    // ⚠️ على شبكةٍ محلّيّةٍ كان الحاجزُ الأوّلُ **الشبكةَ نفسَها**. وخادمٌ على
    // دومينٍ يُسقطه: من صوّر الرمزَ المطبوعَ مرّةً يقرأ من أيّ مكانٍ ويبلغ
    // رمزَ الجلسة من القراءة نفسِها فيكتب. فالرقمُ القصير هو كلُّ ما يبقى.

    test('الكتابتان كلتاهما تمرّان بفحص الرقم', () {
      for (final fn in const [
        'Future<Response> _requestTableBill',
        'Future<Response> _addGuestOrderRequest',
      ]) {
        expect(_body(handler, fn).contains('_requireSessionPin('), isTrue,
            reason: '«$fn» يكتب بلا رقمٍ على خادمٍ عامّ — للعالم كلِّه');
      }
    });

    test('والاشتراطُ مشتقٌّ من وجود العنوان لا من إعدادٍ ثالث', () {
      // إعدادان يصفان نفسَ الحقيقة يفترقان: من ينشر على دومينٍ وينسى
      // الثانيَ يفتح الكتابةَ بلا حاجزٍ واحد.
      final body = _decl(handler, 'Future<bool> _tableBillIsPublic()');
      expect(body.contains('kTableBillPublicBaseUrlKey'), isTrue);
      expect(body.contains('normalizeTableBillBaseUrl('), isTrue,
          reason: 'عنوانٌ غيرُ صالحٍ يُعدّ نشراً — أو العكس');
    });

    test('ولا تُرسَل قيمةُ الرقم مع القراءة', () {
      // إرسالُه يُلغيه: من يقرأ عن بُعدٍ يأخذه ويكتب.
      final body = _body(handler, 'Future<Response> _getTableBill(Request');
      expect(body.contains('sessionPin('), isFalse,
          reason: 'الرقمُ يُشتقّ داخلَ جواب القراءة — فبطل معناه');
      expect(body.contains("'pinRequired'"), isTrue,
          reason: 'الصفحةُ لا تعرف أنّ الرقمَ مطلوب فلا تسأل عنه');
    });
  });

  test('ومفتاحُ التوقيع يُشتقّ عند إقلاع الخادم', () {
    // بلا هذا السطر يفشل التحقّقُ مغلقاً — وهو الصوابُ — فيبدو كلُّ رمزٍ
    // مطبوعٍ معطّلاً بلا سببٍ ظاهرٍ في أيّ سجلّ.
    final ns =
        File('lib/services/network_service.dart').readAsStringSync();
    // E-02: المفتاحُ صار سرًّا عشوائيًّا مستقلًّا يُهيَّأ من ServerSecrets
    // (يضبط TableBillToken.setSigningKey)، لا اشتقاقًا من بذرة الجهاز.
    expect(ns.contains('ServerSecrets()'), isTrue,
        reason: 'المفتاحُ لا يُهيَّأ — كلُّ الرموز المطبوعة ميّتة');
    expect(ns.contains('await secrets.initialize()'), isTrue);
    final secrets =
        File('lib/services/api/server_secrets.dart').readAsStringSync();
    expect(secrets.contains('TableBillToken.setSigningKey('), isTrue,
        reason: 'ServerSecrets لا يضبط مفتاحَ الطاولات');
    expect(ns.contains('getDatabaseEncryptionKey'), isFalse,
        reason: 'startServer لا يمسّ مفتاح القاعدة (E-02)');
  });
}
