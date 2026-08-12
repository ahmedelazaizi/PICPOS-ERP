// Structural guard — لا يُبنى رابطُ سيرفرٍ معروضٌ للمستخدم بلصق
// `serverAddress` في نصّ، دائماً عبر `NetworkService.buildServerUrl()`.
//
// ── لماذا حارسٌ بنيويٌّ لا سلوكيّ ──────────────────────────────────────────
// `NetworkService.serverAddress` نوعُه `String?`، ولا يُملأ إلا عند تشغيل
// خادمٍ فعليّ (`_serverAddress = await getLocalIpAddress()`) أو عند ضبطه
// يدوياً لوضع العميل. وPicPos يعمل مستقلاً افتراضياً — فيبقى `null`.
//
// والاستيفاءُ النصّيُّ في Dart لا يشتكي من `null`؛ يطبعها حرفياً. فينتج
// `http://null:8080/cfd` — رابطٌ معروضٌ للمستخدم في «التكاملات والخدمات»
// تحت عنوانٍ يقول «متاحة دائماً» (رُصد في لقطة المالك 2026-08-12).
//
// العطبُ صامتٌ عند القياس: لا استثناء، ولا تحذيرَ محلِّل، ولا اختبارَ يسقط —
// نصٌّ خاطئٌ فحسب. والفئةُ تتكرّر: اثنا عشر موضعاً في أربعة ملفات (‏مصدرٌ
// وفوركُه) لصقوا العنوانَ يدوياً بينما المِقبضُ الصحيح موجودٌ من البداية.
//
// `buildServerUrl()` يحتاطُ بـ`localhost`، ويمرّر روابطَ الأنفاق
// (‏ngrok وأمثالها) كما هي، ويقصّ الشرطةَ الزائدة.
//
// ⚠️ خارج الحراسة عمداً: أسطرُ التشخيص (`diagnostics['عنوان السيرفر']`)
// تعرض `serverAddress` عاريةً — وهناك `null` **هي** المعلومة المطلوبة
// («العنوان غير مضبوط»)، لا عطبٌ يُخفى بـ`localhost`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `http://` أو `https://` يعقبها استيفاءٌ ينتهي بـ`serverAddress`.
/// يمسك `${_ns.serverAddress}` و`${syncRepo.serverAddress}` و`$serverAddress`.
final _rawUrl = RegExp(r'https?://\$\{?[\w.]*serverAddress');

void main() {
  test('لا رابطَ سيرفرٍ مبنيٌّ بلصق serverAddress في lib/presentation', () {
    final offenders = <String>[];

    for (final entity in Directory('lib/presentation').listSync(
      recursive: true,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trimLeft();
        // التعليقاتُ التوضيحية تذكر الشكلَ عمداً.
        if (trimmed.startsWith('//')) continue;
        if (_rawUrl.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'استعمل NetworkService.buildServerUrl() — العنوان قد يكون null '
          'فيُطبع "null" في الرابط المعروض:\n${offenders.join("\n")}',
    );
  });
}
