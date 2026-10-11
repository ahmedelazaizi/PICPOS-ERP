import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// مفتاحُ تفعيل «رمزُ حساب الطاولة» في `settings`.
///
/// ⚠️ **والافتراضُ مُطفأ، وهو قرارٌ لا سهو.** المساراتُ الثلاثةُ تُخدَم **بلا
/// مصادقة** — الزبونُ ليس جهازاً مقترناً ولا مستخدماً. فتنصيبةٌ رقّت ولم تطلب
/// الميزةَ يجب ألّا تفتح سطحاً جديداً على شبكتها لمجرّد أنها رقّت.
const String kTableBillQrEnabledKey = 'table_bill_qr_enabled';

/// مفتاحُ السماح للضيف بطلبِ أصنافٍ من هاتفه — **مطفأٌ افتراضاً**.
///
/// ⚠️ **ورايةٌ ثانيةٌ لا فرعٌ من الأولى**: القراءةُ تعرض ما طُلب أصلاً، وهذه
/// تفتح باباً يُدخِل منه هاتفٌ غيرُ مصادَقٍ **طلباً إلى المطبخ**. ومحلٌّ يرضى
/// بالأولى قد لا يرضى بالثانية، فدمجُهما في مفتاحٍ واحدٍ يفرض عليه الاثنتين.
///
/// وحتى مُشعَلةً لا يدخل الطلبُ الحسابَ إلّا باعتماد النادل — راجع
/// `GuestOrderRequests`.
const String kTableBillGuestOrderEnabledKey = 'table_bill_guest_order_enabled';

/// عنوانُ الخادم العامّ (‏دومين) — فارغٌ يعني «شبكةُ المحلّ وحدَها».
///
/// ⚠️ **وضبطُه يغيّر نموذجَ التهديد لا العنوانَ فقط.** الحاجزُ الأوّلُ في هذا
/// التصميم كان الشبكةَ نفسَها: خادمٌ محلّيٌّ لا يبلغه إلّا من هو في المحلّ.
/// وخادمٌ على دومينٍ يُسقطه — فمن صوّر الرمزَ المطبوعَ مرّةً يقرأ حسابَ تلك
/// الطاولة من أيّ مكانٍ كلّما شُغلت، ويبلغ رمزَ الجلسة فيكتب.
///
/// ولذلك: **ضبطُه يُشعِل اشتراطَ الرقم القصير على كلّ كتابة** تلقائيّاً —
/// راجع `TableBillToken.sessionPin`. ولا يُترَك ذلك لإعدادٍ ثالثٍ يُنسى.
const String kTableBillPublicBaseUrlKey = 'table_bill_public_base_url';

/// [raw] بعد التسوية، أو `null` إن لم يكن عنواناً صالحاً للاستعمال.
///
/// ⚠️ **ويُرفَض ما فيه مسارٌ أو استعلام**: العنوانُ **أساسٌ** يُلحَق به
/// `/t/<token>`، فقيمةٌ مثل `https://x.com/menu` كانت تُنتج `…/menu/t/…` —
/// رمزاً مطبوعاً ومُلصَقاً لا يفتح شيئاً، ولا يُكتشَف إلّا من ضيف.
String? normalizeTableBillBaseUrl(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  if (uri.hasQuery || uri.hasFragment) return null;
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (path.isNotEmpty) return null;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}

/// رمزا رابطِ حسابِ الطاولة — القراءةُ بالمطبوع والكتابةُ بالجلسة.
///
/// ═══ لماذا رمزان ═══
///
/// الـQR **يُطبَع مرّةً ويُلصَق على الطاولة**، فرمزُه لا يتغيّر مع كلّ جلسة.
/// ورمزٌ ثابتٌ تُقبَل به الكتابةُ يعني أنّ من مسحه مرّةً يظلّ قادراً على
/// «طلب الحساب» لطاولةٍ يجلس عليها غيرُه بعد شهر.
///
/// فالقراءةُ بـ[mintTable] الثابت، والكتابةُ بـ[mintSession] المشتقِّ من
/// الطلب ولحظةِ فتحه — يموت بإغلاق الطلب ولا يُحيا.
///
/// ═══ والحدُّ الأمنيُّ الحقيقيُّ يُقال لا يُدَّعى ═══
///
/// الخادمُ على شبكة المحلّ، فمن لا يبلغ الشبكةَ لا يبلغ هذه المسارات أصلاً —
/// وهذا هو الحاجزُ الأوّل. والتوقيعُ يمنع التخمينَ والتلاعبَ بالرقم؛ لا يمنع
/// من جلس أمسَ وعاد اليوم إلى نفس الشبكة من **قراءة** حسابٍ مفتوح. ورمزُ
/// الجلسة هو ما يمنعه من **الكتابة**، وهو الحدُّ الذي يقبل الادّعاء.
///
/// ═══ وبلا جدولٍ ولا هجرة ═══
///
/// الرمزان مشتقّان لا مخزَّنان — نفسُ عقد [ApiSessionToken]. والمفتاحُ
/// يُشتقّ من بذرة الجهاز عند إقلاع الخادم، فيثبت عبر إعادات التشغيل،
/// وتدويرُ البذرة يُبطل كلَّ ما طُبع.
class TableBillToken {
  TableBillToken._();

  /// ⚠️ ملحٌ ثابتٌ حرفيّ — **ممنوع** ربطُه بالعلامة أو بأيّ قيمةٍ متغيّرة:
  /// تغييرُه يُبطل كلَّ رمزِ طاولةٍ **مطبوعٍ وملصوقٍ على الطاولات**، وإصلاحُه
  /// يقتضي إعادةَ طباعتها كلِّها.
  static const String _salt = 'PicPos-TableBill-v1';

  /// مفتاحُ التوقيع — لا يُرسَل لعميلٍ أبداً. `null` حتى يشتقَّه الخادمُ
  /// عند الإقلاع، والتحقّقُ **يرفض** ما دام كذلك (فشلٌ مغلق).
  static List<int>? _signingKey;

  static bool get isReady => _signingKey != null;

  /// اشتقاقٌ قديم من بذرة الجهاز. **للاختبارات فقط** الآن؛ الإنتاج يستعمل
  /// [setSigningKey] بسرٍّ عشوائيٍّ مستقلّ من `ServerSecrets`.
  @visibleForTesting
  static void deriveKey(String machineSeed) {
    _signingKey = _legacyDerive(machineSeed);
  }

  static List<int> _legacyDerive(String machineSeed) =>
      sha256.convert(utf8.encode('$machineSeed:$_salt')).bytes;

  /// مفتاحُ التوقيع العشوائيّ الجديد (يُصدَر ويُتحقَّق به).
  static void setSigningKey(List<int> key) {
    if (key.length < 32) {
      throw ArgumentError('table-bill signing key must be >= 32 bytes');
    }
    _signingKey = List<int>.unmodifiable(key);
  }

  /// مفتاحٌ سابق (بعد `rotate`) — **للتحقّق من [verifyTable] فقط**، لا يُصدَر به.
  static void setPreviousSigningKey(List<int>? key) {
    _previousKey = key == null ? null : List<int>.unmodifiable(key);
  }

  /// ق-3 (أ): المفتاحُ المشتقّ القديم من بذرة الجهاز، **للتحقّق من رموز الطاولات
  /// المطبوعة فقط** (حتى يُطفأ العلم `table_bill_legacy_accepted`). لا تُصدَر
  /// به رموزٌ جديدة، ولا يصلح لـ[verifySession]/[verifySessionPin].
  static void setLegacyVerifyKeyFromSeed(String? machineSeed) {
    _legacyVerifyKey = machineSeed == null ? null : _legacyDerive(machineSeed);
  }

  static List<int>? _previousKey;
  static List<int>? _legacyVerifyKey;

  /// هل يُقبل المشتقّ القديم للتحقّق الآن؟
  static bool get legacyVerifyActive => _legacyVerifyKey != null;

  /// مفتاحٌ حتميٌّ للاختبارات بلا بذرةِ جهاز.
  @visibleForTesting
  static void setKeyForTesting(String key) =>
      _signingKey = sha256.convert(utf8.encode(key)).bytes;

  static void clearKey() {
    _signingKey = null;
    _previousKey = null;
    _legacyVerifyKey = null;
  }

  static String _sign(String payload, [List<int>? key]) => base64Url.encode(
      Hmac(sha256, key ?? _signingKey!).convert(utf8.encode(payload)).bytes);

  // ═══════════════════════════════════════════════════════════════
  // رمزُ الطاولة — المطبوع
  // ═══════════════════════════════════════════════════════════════

  /// رمزٌ يُوضَع في الـQR: `<tableId>.<sig>`.
  ///
  /// ⚠️ **ولا انتهاءَ له عمداً**: الورقةُ ملصوقةٌ على الخشب، ورمزٌ ينتهي
  /// يعني طاولةً تتوقّف عن العمل في يومٍ لا أحدَ يتوقّعه.
  static String mintTable(int tableId) {
    if (_signingKey == null) {
      throw StateError('TableBillToken.mintTable before deriveKey');
    }
    final payload = 't$tableId';
    return '$payload.${_sign(payload)}';
  }

  /// رقمُ الطاولة إن صحّ التوقيع، وإلّا `null`.
  static int? verifyTable(String? token) {
    if (token == null || _signingKey == null) return null;
    final dot = token.indexOf('.');
    if (dot <= 0 || dot == token.length - 1) return null;
    final payload = token.substring(0, dot);
    // التحقّقُ من التوقيع **قبل** الثقة بالحمولة. المفتاحُ الحاليّ أولاً، ثم
    // السابقُ (بعد التدوير) ثم المشتقُّ القديمُ (ق-3 أ) — للتحقّق فقط.
    final sig = token.substring(dot + 1);
    var valid = _constantTimeEquals(sig, _sign(payload));
    for (final extra in [_previousKey, _legacyVerifyKey]) {
      if (!valid && extra != null) {
        valid = _constantTimeEquals(sig, _sign(payload, extra));
      }
    }
    if (!valid) return null;
    if (!payload.startsWith('t')) return null;
    final id = int.tryParse(payload.substring(1));
    // معرِّفاتُ drift تبدأ من ١؛ صفرٌ أو سالبٌ حمولةٌ ملفَّقة.
    if (id == null || id <= 0) return null;
    return id;
  }

  // ═══════════════════════════════════════════════════════════════
  // رمزُ الجلسة — الذي يموت بإغلاق الطلب
  // ═══════════════════════════════════════════════════════════════

  /// رمزٌ يُعاد مع قراءة الحساب، وتُشترَط إعادتُه في كلّ كتابة.
  ///
  /// ⚠️ **ولحظةُ الفتح جزءٌ من الحمولة** لا زينة: معرِّفُ الطلب وحدَه كافٍ ما
  /// دام `autoIncrement` لا يُعاد استعمالُه — و«ما دام» شرطٌ يكسره استعادةُ
  /// نسخةٍ احتياطيّةٍ أو إعادةُ بناءِ جدولٍ. وحينَها يُحيا رمزٌ ميّت.
  static String mintSession({required int orderId, required DateTime openedAt}) {
    if (_signingKey == null) {
      throw StateError('TableBillToken.mintSession before deriveKey');
    }
    return _sign(_sessionPayload(orderId, openedAt));
  }

  /// هل [token] رمزُ جلسةِ هذا الطلب بعينه؟
  ///
  /// ⚠️ ومعزولٌ عن [verifyTable] بلاحقةٍ في الحمولة (`s` مقابل `t`): بلا ذلك
  /// كان رمزُ الطاولة **المطبوعُ** يصلح للكتابة لو تصادفت الأرقام — وهو عينُ
  /// ما يُبنى هذا كلُّه لمنعه.
  static bool verifySession(
    String? token, {
    required int orderId,
    required DateTime openedAt,
  }) {
    if (token == null || token.isEmpty || _signingKey == null) return false;
    return _constantTimeEquals(token, _sign(_sessionPayload(orderId, openedAt)));
  }

  // ═══════════════════════════════════════════════════════════════
  // الرقمُ القصير — الحاجزُ البديلُ حين يخرج الخادمُ إلى دومين
  // ═══════════════════════════════════════════════════════════════

  /// رقمٌ من أربع خاناتٍ لجلسةِ طلبٍ بعينها.
  ///
  /// ⚠️ **لماذا وُجد أصلاً.** الحاجزُ الأوّلُ في هذا التصميم كان **الشبكةَ**:
  /// خادمٌ محلّيٌّ لا يبلغه إلّا من هو في المحلّ. وخادمٌ على دومينٍ يُسقط ذلك
  /// كلَّه — فمن صوّر الرمزَ المطبوعَ مرّةً يقرأ حسابَ تلك الطاولة من أيّ
  /// مكانٍ كلّما شُغلت، ويبلغ رمزَ الجلسة (‏يُعاد مع القراءة) فيكتب.
  ///
  /// فهذا ما **لا يُنال إلّا من داخل المحلّ**: يقرؤه النادلُ من شاشته ويقوله
  /// للضيف الجالس أمامه. ويُشتقّ ولا يُخزَّن — لا عمودَ ولا هجرة، ويتبدّل مع
  /// كلّ جلسةٍ بلا عملٍ من أحد.
  ///
  /// ⚠️ **وأربعُ خاناتٍ ليست سرّاً قويّاً** — عشرةُ آلافِ احتمالٍ تُمسَح في
  /// دقائقَ بلا مانع. فالمانعُ هو محدِّدُ المعدّل على `/api/table-bill`
  /// (‏١٢٠/دقيقة لكلّ عنوان)، وهما معاً لا أحدُهما.
  static String sessionPin({required int orderId, required DateTime openedAt}) {
    if (_signingKey == null) {
      throw StateError('TableBillToken.sessionPin before deriveKey');
    }
    final mac = Hmac(sha256, _signingKey!)
        .convert(utf8.encode('pin${_sessionPayload(orderId, openedAt)}'))
        .bytes;
    // أربعةُ بايتاتٍ لا واحد: بايتٌ واحدٌ يعطي ٢٥٦ قيمةً فقط من عشرة آلاف،
    // فتتصادم الأرقامُ بكثافةٍ ويُخمَّن الرقمُ بمحاولاتٍ قليلة.
    final value = (mac[0] << 24) | (mac[1] << 16) | (mac[2] << 8) | mac[3];
    return (value % 10000).toString().padLeft(4, '0');
  }

  /// هل [pin] رقمُ هذه الجلسة؟ يتجاوز الفراغَ حولَه — الضيفُ يكتبه بيده.
  static bool verifySessionPin(
    String? pin, {
    required int orderId,
    required DateTime openedAt,
  }) {
    if (pin == null || _signingKey == null) return false;
    final trimmed = pin.trim();
    if (trimmed.isEmpty) return false;
    return _constantTimeEquals(
      trimmed,
      sessionPin(orderId: orderId, openedAt: openedAt),
    );
  }

  /// ⚠️ **بالميلي ثانية UTC**: drift يخزّن الوقتَ بدقّة الثانية، والمنطقةُ
  /// المحلّيّةُ تختلف بين الخادم وما يُقرأ. فالتوحيدُ هنا لا عند المنادي.
  static String _sessionPayload(int orderId, DateTime openedAt) =>
      's$orderId@${openedAt.toUtc().millisecondsSinceEpoch}';

  /// مقارنةٌ ثابتةُ الزمن — القناةُ الجانبيّةُ مغلقةٌ ولو كان الطرفان
  /// بصمتَي SHA-256 بطولٍ واحد.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
