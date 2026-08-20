// test/static/bookings_permission_registration_test.dart
//
// كودُ صلاحيةٍ في `permission_codes.dart` وحدَه **لا يمكن منحُه لأحد**:
// شاشةُ «الأدوار والصلاحيات» تُبنى من خريطة `permissionCategories` لا من
// القاعدة. فكودٌ غائبٌ عنها يحرس زرّاً حيّاً ويجعله ميّتاً لغير مدير النظام —
// وهو حالُ `tables_pos_access` اليوم.

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

void main() {
  test('كلُّ كودِ حجزٍ مسجَّلٌ في الملفَّين معاً', () {
    final codes =
        File('lib/core/permissions/permission_codes.dart').readAsStringSync();
    final categories = File(
      'lib/presentation/screens/role_management/data/permission_categories.dart',
    ).readAsStringSync();

    final missingFromCodes =
        _expected.where((c) => !codes.contains("'$c'")).toList();
    final missingFromCategories =
        _expected.where((c) => !categories.contains("'$c'")).toList();

    expect(missingFromCodes, isEmpty,
        reason: 'غائبٌ عن permission_codes.dart: $missingFromCodes');
    expect(missingFromCategories, isEmpty,
        reason: 'غائبٌ عن permission_categories.dart — '
            'فلا يمكن منحُه لأحد: $missingFromCategories');
  });
}
