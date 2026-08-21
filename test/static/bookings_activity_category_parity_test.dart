// ═══════════════════════════════════════════════════════════════════════════
// تكافؤُ تصنيف «الحجوزات» في سجلّ النشاط العامّ — التوأمان
// ═══════════════════════════════════════════════════════════════════════════
//
// سطرٌ يُكتب في دلوٍ لا يراه أحد. وقع فعلاً مع تصنيف «الطاولات»:
// `TableSessionService` صارت تكتب `table_reserve` بينما بقيت خريطةُ
// `_categoryActions` على الاسم القديم `add_reservation` وحده — فمن يصفّي
// بتصنيف «الطاولات» لا يرى شيئاً
// (test/static/activity_log_tables_category_parity_test.dart). نفسُ
// الفجوة ممكنةٌ هنا: `BookingActionsService` تكتب `booking_create` وأخواتِها،
// وإن غابت خريطةُ `_categoryActions['bookings']` عن إحدى الشاشتين — أو
// نقص منها فعلٌ واحد — بقي السطرُ مكتوباً في القاعدة ولا يراه من يصفّي
// بتصنيف «الحجوزات» في سجلّ النشاط العامّ.
//
// والخريطةُ خاصّةٌ (`_categoryActions`) فلا اختبارَ سلوكٍ عاديّ يصل إليها؛
// الحارسُ نصّيٌّ بالضرورة — نفسُ نمط
// test/static/activity_log_tables_category_parity_test.dart.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// الشاشتان التوأمان — كلُّ إضافةٍ إلى إحداهما يجب أن تدخل الأخرى، وإلّا
/// تباعدتا كما تباعدت نافذةُ فاتورة المشتريات عن أخواتها في Spec 103.
const _screens = <String>[
  'lib/presentation/screens/activity_log_screen.dart',
  'lib/presentation/activity_log_picpos/screens/activity_log_picpos_screen.dart',
];

/// أفعالُ `BookingActionsService` — `lib/services/booking_actions_service.dart`.
const _actions = <String>[
  'booking_create',
  'booking_reassign',
  'booking_reschedule',
  'booking_cancel',
  'booking_status',
];

String _read(String relPath) {
  final file = File(relPath);
  expect(file.existsSync(), isTrue,
      reason: 'الملفُّ $relPath غير موجود — حدِّث القائمةَ في هذا الحارس');
  return file.readAsStringSync();
}

/// محتوى قائمة `'bookings': [...]` داخل `_categoryActions` — لا الخريطةُ
/// كلُّها. الاستخراجُ يفشل بصوتٍ (عبر `expect` أدناه) إن تغيّر شكلُ
/// الخريطة أو غاب المدخلُ، لا بصمتٍ يمرّ بسلسلةٍ فارغة.
String _bookingsCategoryList(String src) {
  final match = RegExp(r"'bookings':\s*\[([\s\S]*?)\]").firstMatch(src);
  expect(match, isNotNull,
      reason: 'تعذّر العثورُ على قائمة bookings في _categoryActions — '
          'إمّا التصنيفُ غائبٌ عن الملف أصلاً، أو تغيّر شكلُ الخريطة '
          'فحدِّث نمطَ البحث في هذا الحارس');
  return match!.group(1)!;
}

void main() {
  group('تكافؤُ تصنيف الحجوزات في سجلّ النشاط العامّ', () {
    for (final path in _screens) {
      test('$path يضمّ كلَّ أفعال الحجوزات', () {
        final list = _bookingsCategoryList(_read(path));
        for (final action in _actions) {
          expect(list.contains("'$action'"), isTrue,
              reason: "$path — الفعلُ '$action' غائبٌ عن تصنيف bookings؛ "
                  'من يصفّي بـ«الحجوزات» في سجلّ النشاط لن يرى سطوره');
        }
      });
    }

    test('الشاشتان لا تتباعدان في مجموعة أفعال تصنيف الحجوزات', () {
      final lists =
          _screens.map((p) => _bookingsCategoryList(_read(p))).toList();

      // نطبّع إلى مجموعةِ أسماء الأفعال مرتّبةً — يهمّنا التكافؤُ في
      // المحتوى لا تطابقُ التنسيق سطراً بسطر.
      List<String> actionsOf(String list) =>
          (RegExp(r"'[a-z_]+'").allMatches(list).map((m) => m.group(0)!).toList()
            ..sort());

      expect(actionsOf(lists[0]), actionsOf(lists[1]),
          reason: 'خريطتا تصنيف الحجوزات تباعدتا بين الشاشتين التوأمين — '
              '${_screens[0]} و${_screens[1]} يجب ألّا تفترقا');
    });
  });
}
