// ═══════════════════════════════════════════════════════════════════════════
// TLS TRUST — تثبيتُ بصمةِ شهادةِ الخادم (pin) بدل القبول المطلق
// ═══════════════════════════════════════════════════════════════════════════
//
// ── لماذا وُجد هذا الملفّ ──────────────────────────────────────────────────
//
// كان في المستودع **سطحان متناقضان** لنفس المسألة:
//
//   ١. أربعةُ مواضعَ تكتب `badCertificateCallback = (c, h, p) => true` —
//      أي «اقبل أيَّ شهادةٍ من أيِّ أحد». وهذا يُبطل TLS تماماً: يمنع
//      المتلصّصَ السلبيَّ ولا يمنع الرجلَ في المنتصف، وهو التهديدُ الحقيقيُّ
//      على شبكةٍ محلّيّةٍ يشاركها كثيرون.
//   ٢. **أحدَ عشرَ نداءً** في `ServerProxy` عبر دوالِّ `package:http`
//      العلويّة — وهي تستعمل عميلاً افتراضيّاً **بلا أيِّ خطّاف**. فبشهادةٍ
//      ذاتيّةٍ كانت تُخفق كلُّها فوراً بينما الأربعةُ الأخرى تنجح.
//
// وأثرُ التناقض مكتوبٌ في الكود نفسِه منذ مدّة (`server_proxy.dart:889`):
// «fetchUsers ترجع null في 0.02s بينما `_fetchJson` تنجح» — عَرَضُ نفسِ
// العلّة، شُخِّص ثمّ عولج في موضعٍ واحدٍ من اثني عشر.
//
// ⚠️ **ولهذا كان تشغيلُ TLS اليومَ انقطاعاً لا أماناً**: مسارٌ ينجح ومسارٌ
// يُخفق على نفس الجهاز.
//
// ── النموذج: ثقةٌ عند أوّلِ اقتران (TOFU) ثمّ إنفاذ ─────────────────────
//
// البصمةُ تُسلَّم داخلَ **نافذة الاقتران** التي يفتحها المشغّلُ عمداً
// (خمسُ دقائق، `ApiAuthMiddleware.openPairingWindow`) — وهي نفسُ النافذة
// التي يُسلَّم فيها توكنُ الـAPI واعتماداتُ المستخدمين. فلا قناةَ جديدةً
// تُفتَح، ولا سرَّ يُكشَف خارجَ نافذةٍ قائمة.
//
// وبعد التثبيت: **أيُّ شهادةٍ لا تطابق البصمةَ تُرفَض** — وهذا هو الفرق
// بين TLS الذي يمنع MITM وTLS الذي يزيّن السجلّ.
//
// ── لماذا «لا بصمةَ ⇒ اقبل» وليس «لا بصمةَ ⇒ ارفض» ──────────────────────
//
// لأنّ الرفضَ يكسر حالتَين مشروعتَين قائمتَين:
//   • الأنفاق (ngrok وأمثالُها) — شهادتُها موقَّعةٌ من جهةٍ معروفةٍ وتتبدّل،
//     وتثبيتُها يعني قطعَ الخدمة عند كلِّ تجديد. والتلميحُ في شاشة الإعدادات
//     يذكرها صراحةً، فهي استعمالٌ مقصودٌ لا حافّة.
//   • كلُّ تنصيبةٍ قائمةٍ لم تُقترن بعد بشهادة.
//
// فالتثبيتُ **إضافةٌ صارمة**: من ثبّت لا يُخدَع، ومن لم يثبّت يبقى كما كان.
// وهذا يجعل الترقيةَ آمنةَ الطرح — لا تنصيبةَ تنكسر يومَ التحديث.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'secure_storage_service.dart';
import 'tls_trust_client_io.dart'
    if (dart.library.js_interop) 'tls_trust_client_web.dart';

class TlsTrust {
  TlsTrust._();

  /// `host:port` ⇒ بصمةُ SHA-256 للـDER بالسدس عشريّ (حروفٌ صغيرة).
  static final Map<String, String> _pins = <String, String>{};

  static final SecureStorageService _storage = SecureStorageService();

  static String _storeKey(String host, int port) =>
      'tls_pin_${host.toLowerCase()}_$port';

  static String _mapKey(String host, int port) =>
      '${host.toLowerCase()}:$port';

  /// بصمةُ شهادةٍ بصيغةِ DER — SHA-256 بالسدس عشريّ.
  ///
  /// ⚠️ **على الـDER لا على الـPEM**: الـPEM ترميزٌ نصّيٌّ لنفس البايتات
  /// وقد يختلف في الأسطر والمسافات، فبصمتُه غيرُ مستقرّة. وهذا هو نفسُ ما
  /// يعرضه `openssl x509 -fingerprint -sha256`، فيستطيع المشغّلُ مقارنتَه
  /// بعينِه إن أراد.
  static String fingerprintOfDer(List<int> der) =>
      sha256.convert(der).toString().toLowerCase();

  /// بصمةُ شهادةٍ من ملفِّ PEM — تُستعمَل على **الخادم** لينشرها.
  ///
  /// يقبل ملفّاً فيه أكثرُ من شهادة (سلسلة) ويأخذ **الأولى** — وهي شهادةُ
  /// الخادم نفسِه، والباقي وسطاء. ويعيد `null` بدل أن يرمي: النشرُ ميزةٌ
  /// إضافيّةٌ ويجب ألّا يمنع الخادمَ من الإقلاع.
  static String? fingerprintOfPemFile(String path) {
    try {
      final text = File(path).readAsStringSync();
      const begin = '-----BEGIN CERTIFICATE-----';
      const end = '-----END CERTIFICATE-----';
      final startIdx = text.indexOf(begin);
      if (startIdx < 0) return null;
      final endIdx = text.indexOf(end, startIdx);
      if (endIdx < 0) return null;
      final body = text.substring(startIdx + begin.length, endIdx);
      // إزالةُ كلِّ ما ليس من أبجديّة base64 (أسطرٌ ومسافاتٌ وCR).
      final b64 = body.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
      if (b64.isEmpty) return null;
      return fingerprintOfDer(base64.decode(b64));
    } catch (e) {
      debugPrint('[TLS] fingerprintOfPemFile failed for $path: $e');
      return null;
    }
  }

  /// يحمّل البصماتِ المثبَّتةَ من المخزن الآمن لمضيفٍ بعينِه.
  /// يُنادى عند الإقلاع وقبل أوّلِ نداءٍ شبكيّ.
  static Future<void> loadPin(String host, int port) async {
    try {
      final fp = await _storage.read(_storeKey(host, port));
      if (fp != null && fp.isNotEmpty) {
        _pins[_mapKey(host, port)] = fp.toLowerCase();
        debugPrint('[TLS] 📌 pin loaded for ${_mapKey(host, port)}');
      }
    } catch (e) {
      debugPrint('[TLS] loadPin failed: $e');
    }
  }

  /// يثبّت بصمةً لمضيف. يُنادى **داخلَ نافذة الاقتران** وحدَها.
  static Future<void> pin(String host, int port, String fingerprint) async {
    final fp = fingerprint.toLowerCase().trim();
    if (fp.isEmpty) return;
    _pins[_mapKey(host, port)] = fp;
    try {
      await _storage.write(_storeKey(host, port), fp);
      debugPrint('[TLS] 📌 pinned ${_mapKey(host, port)} → ${fp.substring(0, 16)}…');
    } catch (e) {
      // الذاكرةُ ثُبِّتت ولو أخفق القرص — الجلسةُ الحاليّة محميّة.
      debugPrint('[TLS] pin persist failed (in-memory only): $e');
    }
  }

  /// يزيل تثبيتاً — لإعادةِ الاقتران بخادمٍ بشهادةٍ جديدة.
  static Future<void> unpin(String host, int port) async {
    _pins.remove(_mapKey(host, port));
    try {
      await _storage.delete(_storeKey(host, port));
    } catch (e) {
      debugPrint('[TLS] unpin failed: $e');
    }
  }

  /// البصمةُ المثبَّتةُ لمضيف، أو `null` إن لم يُثبَّت.
  static String? pinFor(String host, int port) => _pins[_mapKey(host, port)];

  /// هل من بصمةٍ مثبَّتةٍ لأيِّ مضيف؟ (لاختباراتٍ وشاراتِ واجهة)
  @visibleForTesting
  static int get pinCount => _pins.length;

  @visibleForTesting
  static void clearAllForTest() => _pins.clear();

  /// قرارُ قبولِ شهادة — **نقطةُ الحقيقة الوحيدة**.
  ///
  /// مثبَّتٌ ⇒ يجب أن تطابق البصمةُ حرفيّاً.
  /// غيرُ مثبَّتٍ ⇒ يُقبَل (انظر رأسَ الملفّ: الأنفاقُ والتنصيباتُ القائمة).
  static bool acceptCertificate(X509Certificate cert, String host, int port) =>
      acceptFingerprint(fingerprintOfDer(cert.der), host, port);

  /// نفسُ القرار على بصمةٍ محسوبةٍ سلفاً.
  ///
  /// مفصولٌ عن [acceptCertificate] عن قصد: `X509Certificate` نوعٌ من
  /// `dart:io` لا يُصطنَع في اختبارِ وحدة، فلولا هذا الفصلُ لبقي **قرارُ
  /// القبول نفسُه** — وهو كلُّ البند — بلا اختبار.
  static bool acceptFingerprint(String actual, String host, int port) {
    final expected = _pins[_mapKey(host, port)];
    if (expected == null) return true;
    final ok = actual.toLowerCase() == expected;
    if (!ok) {
      debugPrint(
        '[TLS] ⛔ REJECTED $host:$port — expected ${expected.substring(0, 16)}… '
        'got ${actual.substring(0, 16)}…',
      );
    }
    return ok;
  }

  /// عميلُ `dart:io` مضبوطاً على التثبيت.
  /// يحلّ محلَّ كلِّ `HttpClient()` يليه `badCertificateCallback => true`.
  static HttpClient ioClient({Duration? connectionTimeout}) {
    final client = HttpClient();
    if (connectionTimeout != null) {
      client.connectionTimeout = connectionTimeout;
    }
    client.badCertificateCallback = acceptCertificate;
    return client;
  }

  /// عميلٌ لأوّلِ اقتران (TOFU): مضيفٌ مثبَّتٌ ⇒ مطابقةٌ حرفيّة؛ غيرُ مثبَّتٍ ⇒
  /// يُقبَل **ويُسجَّل** ما قدّمه عبر [onFirstUse] ليثبّته المنادي بعد نجاح
  /// الاقتران. يختلف عن [ioClient] بأنّ البصمة المرصودة هي التي صافحنا بها
  /// فعلاً لا ادّعاءٌ في متن الاستجابة.
  static HttpClient ioClientTofu({
    required void Function(String host, int port, String fingerprint) onFirstUse,
    Duration? connectionTimeout,
  }) {
    final client = HttpClient();
    if (connectionTimeout != null) client.connectionTimeout = connectionTimeout;
    client.badCertificateCallback = (cert, host, port) {
      final fp = fingerprintOfDer(cert.der);
      final pinned = _pins[_mapKey(host, port)];
      if (pinned == null) {
        onFirstUse(host, port, fp);
        return true;
      }
      return acceptFingerprint(fp, host, port);
    };
    return client;
  }

  static http.Client? _shared;

  /// عميلُ `package:http` مضبوطاً على التثبيت — **مشترَكٌ ومُعادُ استعماله**.
  ///
  /// 🔴 هذا هو الذي كان غائباً تماماً. دوالُّ `http.get`/`http.post`
  /// العلويّةُ تُنشئ عميلاً افتراضيّاً لكلِّ نداءٍ ولا سبيلَ لضبطه — فكانت
  /// أحدَ عشرَ نداءً في `ServerProxy` تُخفق على أوّل شهادةٍ ذاتيّة.
  ///
  /// ⚠️ **مشترَكٌ عن قصد**: عميلٌ جديدٌ لكلِّ نداءٍ يفتح وصلةً جديدةً ولا
  /// يُغلقها (‏الدوالُّ العلويّةُ كانت تُغلق ضمناً؛ عميلٌ صريحٌ لا يفعل)،
  /// فتتسرّب المقابسُ حتّى نفادها على جهازٍ يزامن كلَّ دقيقة. وإعادةُ
  /// الاستعمال تُبقي تجميعَ الوصلات عاملاً كما كان.
  ///
  /// وتبدُّلُ البصماتِ لا يحتاج إعادةَ بناء: الخطّافُ يقرأ [_pins] لحظةَ
  /// المصافحة لا لحظةَ الإنشاء.
  ///
  /// م3-7: على الويب يرجع `BrowserClient` (استيراد شرطي) بدل `IOClient`.
  static http.Client httpClient() => _shared ??= createPlatformHttpClient(
        (der, host, port) =>
            acceptFingerprint(fingerprintOfDer(der), host, port),
      );

  @visibleForTesting
  static void resetSharedClientForTest() {
    _shared?.close();
    _shared = null;
  }
}
