// تدقيق القوائم المالية (2026-10-31) — مصدر العملة والأرقام المعروضة.
// تشغيل: flutter test --run-skipped --concurrency=1 --dart-define=APP_BRAND=picpos <الملف>
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';

const _skip = 'audit repro — pending owner approval';

void main() {
  test('F1 العملة الافتراضية قبل قراءة system_currency هي JOD', skip: _skip, () {
    // ignore: avoid_print
    print('F1 default code=${AppConstants.currencyCode} en=${AppConstants.currencySymbolEn} '
        'decimals=${AppConstants.decimalPlaces}');
    AppConstants.setCurrency('EGP');
    // ignore: avoid_print
    print('F1 after setCurrency(EGP) code=${AppConstants.currencyCode} en=${AppConstants.currencySymbolEn} '
        'decimals=${AppConstants.decimalPlaces}');
    expect(AppConstants.currencySymbolEn, 'EGP');
  });

  test('F2 حوار الرصيد الافتتاحي للوردية لا يحوي عملة مثبَّتة نصاً', skip: _skip, () {
    final hits = <String>[];
    for (final p in [
      'lib/presentation/shift_close_picpos/widgets/picpos_opening_balance_dialog.dart',
      'lib/presentation/pos/widgets/pos_opening_balance_dialog.dart',
    ]) {
      final lines = File(p).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains("'JOD'")) hits.add('$p:${i + 1}: ${lines[i].trim()}');
      }
    }
    // ignore: avoid_print
    print('F2 $hits');
    expect(hits, isEmpty);
  });

  test('F3 تنسيق الأرقام: NumberFormat(ar) مقابل toStringAsFixed', skip: _skip, () {
    final ar = NumberFormat('#,##0.00', 'ar').format(1234.5);
    final arEg = NumberFormat('#,##0.00', 'ar_EG').format(1234.5);
    final def = NumberFormat('#,##0.00').format(1234.5);
    // ignore: avoid_print
    print('F3 ar="$ar" ar_EG="$arEg" default="$def" fixed="${1234.5.toStringAsFixed(3)}"');
  });
}
