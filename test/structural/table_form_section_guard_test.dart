// حارسُ «القسم» في حوار إضافة/تعديل الطاولة.
//
// ═══ عطبٌ مقيسٌ في الميدان لا مفترَض ═══
//
// لوجُ المالك 2026-09-18T06:47:05 — حزمة 3.1.4+256:
//
//   [PLATFORM_ERROR] error=Null check operator used on a null value
//   #0 _TableSectionsMixin._showTableFormDialog…
//      (package:picpos_erp/presentation/screens/tables/table_sections_crud.dart:439)
//
// والسطرُ كان `sectionId: selectedSectionId!`. و`selectedSectionId` يُهيَّأ
// بـ`sectionId ?? existingTable?.sectionId` (سطر ٣٢٩) — فهو `null` لطاولةٍ
// **جديدةٍ** حين لا تحمل الشاشةُ نطاقَ قسمٍ («كل المناطق»)، أو حين لا أقسامَ
// بعد. والحوارُ يحرس **اسمَ الطاولة** ولا يحرس القسم.
//
// والموضعان اثنان لا واحد: الإنشاءُ (٤٣٩) والتعديلُ (٤٥٨).
//
// ═══ ولماذا حارسٌ بنيويٌّ ═══
//
// `_showTableFormDialog` عضوُ مخلوطٍ في ملفِّ `part of`، فلا يُستورَد ولا
// يُنادى وحدَه؛ وقيادتُه من الواجهة تقتضي مستودعاتٍ ومزوّداتٍ وقاعدةً — كلفةٌ
// لا تشتري يقيناً أكثرَ ممّا يشتريه قراءةُ السطر. فالحارسُ يقرأ الشيفرة،
// ومطابقتُه على **غياب** `!` تجعله يسقط بمجرّد عودتها.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نصُّ الملفّ بلا أسطر التعليق.
///
/// ⚠️ لازمٌ هنا: هذا التعليقُ نفسُه يكتب `selectedSectionId!` حرفيّاً وهو
/// عينُ ما يمنعه الحارس. حارسٌ يقرأ نثرَه يُبلّغ عن نفسه.
String _code(String raw) => [
      for (final line in raw.split('\n'))
        if (!line.trimLeft().startsWith('//')) line,
    ].join('\n');

void main() {
  late String src;

  setUpAll(() {
    final f = File('lib/presentation/screens/tables/table_sections_crud.dart');
    expect(f.existsSync(), isTrue,
        reason: 'حوارُ الطاولة انتقل — حدِّث مسارَ الحارس');
    src = _code(f.readAsStringSync());
  });

  test('مرساةٌ — الحوارُ ما زال يحمل حقلَ القسم', () {
    expect(src.contains('selectedSectionId'), isTrue,
        reason: 'الحقلُ تبدّل — راجع الحارسَ قبل أن تثق به');
  });

  test('ولا تُستعمل `!` على القسم — هي عينُ ما انهار في الميدان', () {
    expect(src.contains('selectedSectionId!'), isFalse,
        reason: 'عادت `selectedSectionId!` — وهي سطرُ الانهيار المقيسُ في '
            'لوج 2026-09-18T06:47:05');
  });

  test('والقسمُ محروسٌ برسالةٍ للمستخدم قبل الحفظ', () {
    // الحارسُ بلا رسالةٍ يُنتج زرّاً لا يفعل شيئاً — وهو أسوأُ من انهيارٍ
    // يُرى: المستخدمُ يضغط ويظنّ أنّ النظامَ لا يستجيب.
    expect(src.contains('يرجى اختيار القسم'), isTrue,
        reason: 'لا رسالةَ ترشد المستخدمَ إلى سبب التوقّف');
  });
}
