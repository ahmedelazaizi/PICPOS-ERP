// الاستيرادُ يُبلّغ بعددَي المُدرَج والمرفوض — والصفُّ المرفوضُ يُقال بسببه.
// ⚠️ القياسُ على **دالّةِ التجميع** لا على `_pickFile`: اختيارُ الملفّ
// إضافةٌ من نظام التشغيل لا منطق.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/services/excel_service.dart';

void main() {
  test('مرساة: صفوفٌ سليمةٌ كلُّها تُقبَل', () {
    final r = summarizeBankStatementRows([
      [DateTime(2026, 5, 1), 'A', '', 0, 100],
      [DateTime(2026, 5, 2), 'B', '', 50, 0],
    ]);

    expect(r.lines, hasLength(2));
    expect(r.errors, isEmpty);
  });

  test('🔴 الصفُّ المرفوضُ يُعَدُّ ويُقال سببُه', () {
    final r = summarizeBankStatementRows([
      [DateTime(2026, 5, 1), 'A', '', 0, 100],
      ['تاريخٌ فاسد', 'B', '', 0, 50],
      [DateTime(2026, 5, 3), 'C', '', 0, 0],
    ]);

    expect(r.lines, hasLength(1), reason: 'السليمُ وحدَه يُدرَج');
    expect(r.errors, hasLength(2), reason: 'والمرفوضان يُعَدّان لا يُطرَحان');
    expect(r.errors.first, contains('٢'), reason: 'ورقمُ الصفِّ في الرسالة');
  });

  test('صفُّ الرؤوس وسطرُ الشرح يُتخطّيان', () {
    final r = summarizeBankStatementRows([
      ['⚠️ مدين/دائن من منظور البنك', '', '', '', ''],
      ['التاريخ', 'المرجع', 'البيان', 'مدين', 'دائن'],
      [DateTime(2026, 5, 1), 'A', '', 0, 100],
    ], skipRows: 2);

    expect(r.lines, hasLength(1));
    expect(r.errors, isEmpty);
  });

  test('🔴 الصفوفُ الفارغةُ في ذيل الملفّ تُتخطّى ولا تُعَدُّ أخطاءً', () {
    final r = summarizeBankStatementRows([
      [DateTime(2026, 5, 1), 'A', '', 0, 100],
      [DateTime(2026, 5, 2), 'B', '', 50, 0],
      [],
      [null, null, null, null, null],
    ]);

    expect(r.lines, hasLength(2), reason: 'السطرانِ السليمانِ وحدَهما');
    expect(r.errors, isEmpty, reason: 'الفراغُ ليس خطأً فيُتخطّى صامتاً');
  });

  test('🔴 صفٌّ فارغٌ لا يُزحزح ترقيمَ الصفِّ الذي يليه', () {
    final r = summarizeBankStatementRows([
      [DateTime(2026, 5, 1), 'A', '', 0, 100],
      [],
      ['تاريخٌ فاسد', 'B', '', 0, 50],
    ]);

    expect(r.lines, hasLength(1));
    expect(r.errors, hasLength(1), reason: 'الفراغُ لا يُحتسَب خطأً');
    expect(r.errors.first, contains('٣'),
        reason: 'الصفُّ الفاسدُ هو الثالثُ فعليّاً رغم تخطّي الثاني الفارغ');
  });
}
