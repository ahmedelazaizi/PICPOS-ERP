import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('بحثُ فواتير المرتجع بلا سقفٍ زمنيّ', () {
    final src = File(
      'lib/presentation/sales_returns_picpos/screens/'
      'sales_returns_picpos_logic.dart',
    ).readAsStringSync();

    // جرّد التعليقاتِ أوّلاً — التعليقُ ليس كوداً، وقياسُ النصّ الخام
    // يلتقط شرحاً تاريخياً فيُرجع أخضرَ كاذباً أو أحمرَ كاذباً.
    final code = src
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    expect(
      code.contains('Duration(days: 365)'),
      isFalse,
      reason: 'قرارُ المالك 2026-08-16: الارتجاعُ جائزٌ بعد فترةٍ لا في نفس اليوم',
    );
  });
}
