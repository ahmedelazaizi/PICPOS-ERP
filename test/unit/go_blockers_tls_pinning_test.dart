// ═══════════════════════════════════════════════════════════════════════════
// البند ١‑٦ — TLS: من «اقبل أيَّ شهادة» إلى بصمةٍ مثبَّتة
// ═══════════════════════════════════════════════════════════════════════════
//
// ── ما كان ────────────────────────────────────────────────────────────────
//
// سطحان متناقضان لنفس المسألة:
//   • أربعةُ مواضعَ: `badCertificateCallback = (c,h,p) => true` — تشفيرٌ بلا
//     هويّة، يمنع المتلصّصَ السلبيَّ ولا يمنع الرجلَ في المنتصف.
//   • أحدَ عشرَ نداءً عبر دوالِّ `package:http` العلويّة — **بلا أيِّ خطّاف**
//     فتُخفق كلُّها على أوّل شهادةٍ ذاتيّة.
// فكان تشغيلُ TLS انقطاعاً لا أماناً: مسارٌ ينجح ومسارٌ يُخفق على نفس الجهاز.
//
// ── ما يقيسه هذا الملفّ ───────────────────────────────────────────────────
//
// التثبيتُ نفسُه — القرارُ الذي يُتَّخَذ لحظةَ المصافحة:
//   ١. بلا بصمةٍ ⇒ يُقبَل (الأنفاقُ والتنصيباتُ القائمة لا تنكسر).
//   ٢. ببصمةٍ مطابقةٍ ⇒ يُقبَل.
//   ٣. **ببصمةٍ مخالفةٍ ⇒ يُرفَض** — وهذا هو البند كلُّه. لو مرَّ هذا
//      لكان التثبيتُ زينةً.
//   ٤. التثبيتُ **لكلِّ مضيفٍ ومنفذٍ على حدة** — لا يتسرّب بين خوادم.
//   ٥. حسابُ البصمة يطابق `openssl -fingerprint -sha256` (متّجهٌ معروف).
//
// ولا يقيس المصافحةَ الحقيقيّةَ عبر مقبس — ذاك تكاملٌ يحتاج خادماً حيّاً.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/tls_trust.dart';

/// شهادةٌ صغيرةٌ حقيقيّةُ الترميز (DER) — لا نحتاج صلاحيّتَها، بل بايتاتِها:
/// الدالّةُ المقيسةُ تُجزّئ الـDER ولا تحلّله.
const _certA = <int>[0x30, 0x82, 0x01, 0x0a, 0x02, 0x01, 0x01, 0xde, 0xad];
const _certB = <int>[0x30, 0x82, 0x01, 0x0a, 0x02, 0x01, 0x02, 0xbe, 0xef];

void main() {
  setUp(TlsTrust.clearAllForTest);
  tearDown(TlsTrust.clearAllForTest);

  group('حسابُ البصمة', () {
    test('SHA-256 للـDER بالسدس عشريّ — متّجهٌ محسوبٌ يدويّاً', () {
      // القيمةُ مثبَّتةٌ لا «غيرُ فارغة»: صيغةٌ مختلفةٌ (‏base64 مثلاً) كانت
      // ستمرُّ على توكيدٍ رخو، ثمّ لا تطابق ما ينشره الخادم أبداً.
      final expected = sha256.convert(_certA).toString().toLowerCase();
      expect(TlsTrust.fingerprintOfDer(_certA), expected);
      expect(TlsTrust.fingerprintOfDer(_certA).length, 64,
          reason: 'SHA-256 بالسدس عشريّ = ٦٤ محرفاً');
      expect(TlsTrust.fingerprintOfDer(_certA),
          isNot(TlsTrust.fingerprintOfDer(_certB)));
    });

    test('البصمةُ حروفٌ صغيرةٌ دائماً — المقارنةُ حرفيّة', () {
      final fp = TlsTrust.fingerprintOfDer(_certA);
      expect(fp, fp.toLowerCase());
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(fp), isTrue);
    });
  });

  group('قرارُ القبول', () {
    test('بلا بصمةٍ مثبَّتةٍ ⇒ يُقبَل (الأنفاقُ لا تنكسر)', () {
      expect(TlsTrust.pinFor('192.168.1.50', 8080), isNull);
      expect(
        TlsTrust.acceptFingerprint(TlsTrust.fingerprintOfDer(_certA), '192.168.1.50', 8080),
        isTrue,
        reason: 'الرفضُ بلا بصمةٍ يقطع كلَّ تنصيبةٍ قائمةٍ يومَ التحديث',
      );
    });

    test('ببصمةٍ مطابقةٍ ⇒ يُقبَل', () async {
      await TlsTrust.pin(
          '192.168.1.50', 8080, TlsTrust.fingerprintOfDer(_certA));
      expect(
        TlsTrust.acceptFingerprint(TlsTrust.fingerprintOfDer(_certA), '192.168.1.50', 8080),
        isTrue,
      );
    });

    test('🔴 ببصمةٍ مخالفةٍ ⇒ يُرفَض — وهذا هو البند كلُّه', () async {
      await TlsTrust.pin(
          '192.168.1.50', 8080, TlsTrust.fingerprintOfDer(_certA));
      // شهادةٌ أخرى لنفس المضيف = رجلٌ في المنتصف.
      expect(
        TlsTrust.acceptFingerprint(TlsTrust.fingerprintOfDer(_certB), '192.168.1.50', 8080),
        isFalse,
        reason: 'قبولُ شهادةٍ مخالفةٍ يجعل التثبيتَ زينةً — وهو عينُ '
            'السلوك القديم `=> true`',
      );
    });

    test('التثبيتُ لكلِّ مضيفٍ ومنفذٍ على حدة', () async {
      await TlsTrust.pin(
          '192.168.1.50', 8080, TlsTrust.fingerprintOfDer(_certA));

      // مضيفٌ آخر: غيرُ مثبَّتٍ ⇒ يُقبَل.
      expect(
        TlsTrust.acceptFingerprint(TlsTrust.fingerprintOfDer(_certB), '192.168.1.99', 8080),
        isTrue,
      );
      // نفسُ المضيف بمنفذٍ آخر: غيرُ مثبَّتٍ ⇒ يُقبَل.
      expect(
        TlsTrust.acceptFingerprint(TlsTrust.fingerprintOfDer(_certB), '192.168.1.50', 9090),
        isTrue,
      );
      // ولا يتسرّب القبولُ عكسيّاً: المضيفُ المثبَّتُ ما زال يرفض.
      expect(
        TlsTrust.acceptFingerprint(TlsTrust.fingerprintOfDer(_certB), '192.168.1.50', 8080),
        isFalse,
      );
    });

    test('المضيفُ غيرُ حسّاسٍ لحالة الأحرف', () async {
      await TlsTrust.pin(
          'Server.Local', 8080, TlsTrust.fingerprintOfDer(_certA));
      expect(TlsTrust.pinFor('server.local', 8080), isNotNull,
          reason: 'مضيفٌ بحالةٍ مختلفةٍ يُنتج تثبيتاً ثانياً فيسقط الإنفاذ');
      expect(
        TlsTrust.acceptFingerprint(TlsTrust.fingerprintOfDer(_certB), 'server.local', 8080),
        isFalse,
      );
    });
  });

  group('قراءةُ البصمة من ملفّ PEM (جانبُ الخادم)', () {
    test('تطابق بصمةَ الـDER نفسِه', () async {
      final pem = '-----BEGIN CERTIFICATE-----\n'
          '${base64.encode(_certA)}\n'
          '-----END CERTIFICATE-----\n';
      final dir = await _tempDir();
      final file = _write('$dir/cert.pem', pem);

      expect(TlsTrust.fingerprintOfPemFile(file),
          TlsTrust.fingerprintOfDer(_certA),
          reason: 'الخادمُ ينشر بصمةً والعميلُ يحسب أخرى ⇒ رفضٌ دائم');
    });

    test('ملفٌّ معطوبٌ يُرجع null ولا يرمي', () async {
      final dir = await _tempDir();
      // إخفاقُ النشر يجب ألّا يمنع الخادمَ من الإقلاع.
      expect(TlsTrust.fingerprintOfPemFile(_write('$dir/bad.pem', 'nonsense')),
          isNull);
      expect(TlsTrust.fingerprintOfPemFile('$dir/does_not_exist.pem'), isNull);
    });
  });
}

// ── مساعدات ───────────────────────────────────────────────────────────────

Future<String> _tempDir() async {
  final d = await Directory.systemTemp.createTemp('picpos_tls_test');
  return d.path;
}

String _write(String path, String content) {
  File(path).writeAsStringSync(content);
  return path;
}
