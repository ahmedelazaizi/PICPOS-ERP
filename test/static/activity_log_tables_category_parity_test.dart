// ═══════════════════════════════════════════════════════════════════════════
// تكافؤُ تصنيف «الطاولات» في سجلّ النشاط العامّ — التوأمان
// ═══════════════════════════════════════════════════════════════════════════
//
// الفجوةُ التي أنتجت هذا الحارس: `TableSessionService.reserveTable` صارت
// تكتب `action: 'table_reserve'` (سدُّ ثغرة سجلّ الحجز، المهمّة ٣،
// 2026-08-20)، لكنّ خريطة `_categoryActions['tables']` في شاشتَي سجلّ
// النشاط العامّ ظلّت تحمل الاسمَ القديمَ `add_reservation` وحده. فمن يفتح
// «سجل النشاط» ويصفّي بتصنيف «الطاولات» لن يرى سطرَ الحجز الجديد إطلاقاً —
// رغم أن شاشة سجلّ الطاولة الواحدة (تُرشِّح بـ`entityType` لا بهذه الخريطة)
// تعرضه بلا عائق. انحدارُ رؤيةٍ سبّبه تغييرُ الاسم، لا خطأٌ في الكتابة.
//
// والخريطةُ خاصّةٌ (`_categoryActions`) فلا اختبارَ سلوكٍ عاديّ يصل إليها؛
// الحارسُ نصّيٌّ بالضرورة — نفسُ نمط
// `test/static/invoice_form_scope_parity_test.dart`.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// الشاشتان التوأمان — كلُّ إضافةٍ إلى إحداهما يجب أن تدخل الأخرى، وإلّا
/// تباعدتا كما تباعدت نافذةُ فاتورة المشتريات عن أخواتها في Spec 103.
const _screens = <String>[
  'lib/presentation/screens/activity_log_screen.dart',
  'lib/presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart',
];

String _read(String relPath) {
  final file = File(relPath);
  expect(file.existsSync(), isTrue,
      reason: 'الملفُّ $relPath غير موجود — حدِّث القائمةَ في هذا الحارس');
  return file.readAsStringSync();
}

/// محتوى قائمة `'tables': [...]` داخل `_categoryActions` — لا خريطةَ
/// التسميات المجاورة (تلك `'tables': {...}` بقوسٍ مختلف، وليست مقصودةً هنا).
String _tablesCategoryList(String src) {
  final match = RegExp(r"'tables':\s*\[([\s\S]*?)\]").firstMatch(src);
  expect(match, isNotNull,
      reason: 'تعذّر العثورُ على قائمة tables في _categoryActions — تغيّر '
          'شكلُ الخريطة، حدِّث نمطَ البحث في هذا الحارس');
  return match!.group(1)!;
}

void main() {
  group('تكافؤُ تصنيف الطاولات في سجلّ النشاط العامّ', () {
    for (final path in _screens) {
      test('$path يضمّ table_reserve مع add_reservation معاً', () {
        final list = _tablesCategoryList(_read(path));

        expect(list.contains("'table_reserve'"), isTrue,
            reason: '$path — تصفيةُ «الطاولات» في سجلّ النشاط العامّ لن '
                'تُظهر سطرَ الحجز الجديد (table_reserve) رغم أن '
                'TableSessionService.reserveTable يكتبه منذ سدّ ثغرة السجلّ');
        expect(list.contains("'add_reservation'"), isTrue,
            reason: '$path — لا يُحذَف الاسمُ القديم: صفوفٌ حقيقيّةٌ في '
                'قاعدة المالك مسجَّلةٌ به، وحذفُه من الخريطة يُخفي تاريخاً '
                'حقيقيّاً من التصفية العامّة');
      });
    }

    test('الشاشتان لا تتباعدان في مجموعة أفعال تصنيف الطاولات', () {
      final lists =
          _screens.map((p) => _tablesCategoryList(_read(p))).toList();

      // نطبّع إلى مجموعةِ أسماء الأفعال مرتّبةً — يهمّنا التكافؤُ في
      // المحتوى لا تطابقُ التنسيق سطراً بسطر.
      List<String> actionsOf(String list) =>
          (RegExp(r"'[a-z_]+'").allMatches(list).map((m) => m.group(0)!).toList()
            ..sort());

      expect(actionsOf(lists[0]), actionsOf(lists[1]),
          reason: 'خريطتا تصنيف الطاولات تباعدتا بين الشاشتين التوأمين — '
              '${_screens[0]} و${_screens[1]} يجب ألّا تفترقا');
    });
  });
}
