// test/static/bookings_permission_registration_test.dart
//
// كودُ صلاحيةٍ في `permission_codes.dart` وحدَه **لا يمكن منحُه لأحد**:
// شاشةُ «الأدوار والصلاحيات» تُبنى من خريطة `permissionCategories` لا من
// القاعدة. فكودٌ غائبٌ عنها يحرس زرّاً حيّاً ويجعله ميّتاً لغير مدير النظام —
// وهو حالُ `tables_pos_access` اليوم. ولكن الثالثُ الحاسمُ هو `masterList`:
// مَن لا يُدرَج فيه لا يُدخَل قاعدةَ البيانات أصلاً، فلا منحةَ حتى من المدير.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _expected = <String>[
  'bookings_view',
  'bookings_add',
  'bookings_edit',
  'bookings_cancel',
  'bookings_status',
  'bookings_assign',
  'bookings_deposit',
  'bookings_services_manage',
  'bookings_resources_manage',
  'bookings_reports',
  'bookings_settings',
];

/// خريطةُ تحويلِ الكودِ إلى اسمِ الثابتِ (snake_case → lowerCamelCase)
Map<String, String> _codeToConstantName(List<String> codes) {
  final result = <String, String>{};
  for (final code in codes) {
    final parts = code.split('_');
    final constantName =
        parts[0] + parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
    result[code] = constantName;
  }
  return result;
}

/// استخراجُ قسمِ masterList من ملف permission_codes.dart
String _extractMasterList(String src) {
  final match = RegExp(r'static final List<Map<String, String>> masterList = \[([\s\S]*?)\];')
      .firstMatch(src);
  expect(match, isNotNull,
      reason: 'تعذّر العثورُ على masterList في permission_codes.dart — تغيّرَ '
          'شكلُ القائمة، حدِّث نمطَ البحث في هذا الحارس');
  return match!.group(1)!;
}

void main() {
  test('كلُّ كودِ حجزٍ مسجَّلٌ في الملفَّات الثلاث معاً', () {
    final codes =
        File('lib/core/permissions/permission_codes.dart').readAsStringSync();
    final categories = File(
      'lib/presentation/screens/role_management/data/permission_categories.dart',
    ).readAsStringSync();

    // ─────────────────────────────────────────────────────────────────────
    // Check 1: في permission_codes.dart كثوابتٍ (بصيغة: static const String ...)
    // ─────────────────────────────────────────────────────────────────────
    final missingFromCodes = _expected
        .where((c) => !RegExp(
                r"static\s+const\s+String\s+\w+\s*=\s*'" + c + r"'")
            .hasMatch(codes))
        .toList();

    expect(missingFromCodes, isEmpty,
        reason: 'غائبٌ عن permission_codes.dart كثابتٍ: $missingFromCodes');

    // ─────────────────────────────────────────────────────────────────────
    // Check 2: في permission_categories.dart (بصيغة: 'bookings_*': '...')
    // ─────────────────────────────────────────────────────────────────────
    final missingFromCategories = _expected
        .where((c) => !RegExp(r"'" + c + r"':")
            .hasMatch(categories))
        .toList();

    expect(missingFromCategories, isEmpty,
        reason: 'غائبٌ عن permission_categories.dart — '
            'فلا يمكن منحُه لأحد: $missingFromCategories');

    // ─────────────────────────────────────────────────────────────────────
    // Check 3: في masterList (بصيغة: {'code': bookingsXxx, ...})
    // استخراجٌ من الأول — الكود لا يشتغل إن القائمةُ الشكل غيّرت
    // ─────────────────────────────────────────────────────────────────────
    final masterListSection = _extractMasterList(codes);
    final codeToConstant = _codeToConstantName(_expected);

    final missingFromMasterList = _expected
        .where((code) {
          final constantName = codeToConstant[code]!;
          // ابحث عن {'code': bookingsXxx, ... في قسم masterList فقط
          return !RegExp(r"'code':\s*" + constantName + r"\s*,")
              .hasMatch(masterListSection);
        })
        .toList();

    expect(missingFromMasterList, isEmpty,
        reason: 'غائبٌ عن masterList في permission_codes.dart — '
            'لن يُدرَج في قاعدة البيانات: $missingFromMasterList');
  });
}
