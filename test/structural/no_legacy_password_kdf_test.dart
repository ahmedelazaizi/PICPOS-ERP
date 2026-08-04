// حارس بنيوي — ممنوع إنشاء أي كلمة مرور بالـKDF القديم.
//
// ── ليه بنيوي مش سلوكي ──────────────────────────────────────────────────────
// فئة العطل هي «مسار إنشاء **جديد** نسي إنه لازم يستعمل Argon2id». الاختبار
// السلوكي بيغطّي المسارات اللي حد فتكر يكتبلها اختبار؛ ده بيوقع لحظة ما أي حد
// يضيف نداء `hashPassword` في أي مكان في `lib/`.
//
// ── الخلفية ─────────────────────────────────────────────────────────────────
// ترقية الأسبوع الثامن ضافت Argon2id للـ**تحقق** وإعادة التجزئة الشفافة، لكن
// **الإنشاء** فضل على PBKDF2-SHA256 في اتناشر موضعاً — بما فيهم زرع المدير
// وتغيير كلمة مرور المدير. النتيجة إن أي تنصيب جديد كان بيطلع بكل كلمات مروره
// بالـKDF الرخيص، والهاش **والملح** بيتبعتوا مع بعض على الشبكة المحلية في
// `GET /api/users` (بالتصميم، عشان العميل يصادق محلياً وهو offline).
//
// PBKDF2-SHA256 بـ١٠٠٠٠ دورة ≈ ١-٣ ملّي للتخمين. Argon2id بـ٤ ميجا و٣ مرات
// ≈ ٦٣ ملّي، ومقاوم للتوازي على كروت الشاشة. الفرق ده هو كل الفرق لما الهاش
// والملح يبقوا في إيد المهاجم.
//
// `verifyPassword` (التحقق من هاش قديم) **مسموح ومطلوب** — بس الإنشاء ممنوع.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// خط أساس موثَّق — **مش نمطاً مقبولاً**، دي مواضع باقية بسبب اعتمادية بنيوية.
///
/// الملفّين دول بيخزّنوا الهاش في **الإعدادات** مش في جدول `users`، فمش
/// معرَّضين في `GET /api/users`. والمشكلة إن `verify()` فيهم **متزامنة**
/// (‏`bool verify(String)`) وبتتندَه من الواجهة، وArgon2 غير متزامن — فترقيتهم
/// بتغيّر توقيع الدالة وكل مستدعيها. تغيير منفصل بمخاطرته الخاصة.
///
/// لترقية ملف: حوّل `verify` لـ`Future<bool>` بـ`verifyPasswordFull`، حوّل
/// الإنشاء لـ`hashPasswordArgon2`، أصلح المستدعين، وشيله من هنا.
const Map<String, int> _baseline = {
  'lib/services/admin_password_service.dart': 1,
  'lib/services/developer_auth_service.dart': 1,
};

void main() {
  test('مفيش أي نداء لـSecurityService.hashPassword في lib/', () {
    final offenders = <String>[];
    final perFile = <String, int>{};

    final libDir = Directory('lib');
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // الملف المولَّد مش مصدر حقيقة ومش بيتكتب بإيد.
      if (entity.path.endsWith('.g.dart')) continue;

      final rel = entity.path.replaceAll(r'\', '/');
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('SecurityService.hashPassword(')) {
          perFile[rel] = (perFile[rel] ?? 0) + 1;
          if (!_baseline.containsKey(rel)) offenders.add('$rel:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'الإنشاء لازم يبقى بـ`SecurityService.hashPasswordArgon2` — '
          'الـKDF القديم بيخلّي كلمة المرور تتكسر offline لأن الهاش والملح '
          'بيتبعتوا مع بعض في GET /api/users.\nالمواضع: ${offenders.join(', ')}',
    );

    // خط الأساس بيقلّ ولا يزيد أبداً.
    for (final entry in _baseline.entries) {
      expect(perFile[entry.key] ?? 0, lessThanOrEqualTo(entry.value),
          reason: 'زادت نداءات الـKDF القديم في ${entry.key}');
    }
  });
}
