import 'dart:convert';

import 'package:crypto/crypto.dart';

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

  /// يُنادى مرّةً عند إقلاع الخادم بنفس بذرةِ [ApiAuthMiddleware.generateToken].
  static void deriveKey(String machineSeed) {
    _signingKey = sha256.convert(utf8.encode('$machineSeed:$_salt')).bytes;
  }

  /// مفتاحٌ حتميٌّ للاختبارات بلا بذرةِ جهاز.
  static void setKeyForTesting(String key) =>
      _signingKey = sha256.convert(utf8.encode(key)).bytes;

  static void clearKey() => _signingKey = null;

  static String _sign(String payload) =>
      base64Url.encode(Hmac(sha256, _signingKey!).convert(utf8.encode(payload)).bytes);

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
    // التحقّقُ من التوقيع **قبل** الثقة بالحمولة.
    if (!_constantTimeEquals(token.substring(dot + 1), _sign(payload))) {
      return null;
    }
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
