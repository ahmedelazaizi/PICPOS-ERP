// الإقلاع بيجدول المرحلة المؤجلة في الـ root zone للاتصال الحقيقي. قواعد
// الاختبار في الذاكرة لازم تفضل على Future.microtask (محمية بـ isTestExecutor).
//
// ملاحظة: فتح القاعدة أول مرة داخل fake-async بيعلّق حتى قبل التغيير ده
// (راجع setUp في quick_sale_discount_doors_test) فالفتح هنا بـ runAsync.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/connection.dart' show isTestExecutor;
import 'package:picpos_erp/data/providers/providers.dart';

void main() {
  testWidgets('forTesting DB is marked as test executor and opens quickly',
      (tester) async {
    final db = AppDatabase.forTesting();
    expect(isTestExecutor(db.executor), isTrue);
    await tester.runAsync(() => db.saveSettings({'k': 'v'}));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
