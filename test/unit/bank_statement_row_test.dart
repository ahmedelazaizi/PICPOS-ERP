// تحليلُ صفِّ الكشف نقيٌّ عن قصد — كـ`reportCellValue` و`reportBranchLabel`:
// موضعُ الكذب المحتمل يجب أن يُقاس بلا قاعدةٍ ولا نظامِ ملفّات.
//
// ⚠️ **«مدين/دائن» من منظور البنك**: المحرّكُ يقلبهما عند المطابقة (مدينُ
// البنك = دائنُ دفترنا). فالتحليلُ ينقل ما في العمودَين كما هو، والقالبُ
// يحمل سطرَ الشرح.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/services/bank_statement_row.dart';

void main() {
  test('مرساة: صفٌّ سليمٌ يُقبَل بحقوله', () {
    final r = parseBankStatementRow(
        [DateTime(2026, 5, 10), 'REF-1', 'إيداع نقدي', 0, 500]);

    expect(r.error, isNull, reason: 'الصفُّ السليمُ يجب أن يُقبَل');
    expect(r.line!['reference'], 'REF-1');
    expect(r.line!['credit'], 500.0);
    expect(r.line!['debit'], 0.0);
    expect(r.line!['date'], DateTime(2026, 5, 10));
  });

  test('التاريخُ نصّاً `yyyy-MM-dd` يُقبَل', () {
    final r = parseBankStatementRow(['2026-05-10', 'R', '', 0, 5]);
    expect(r.error, isNull);
    expect(r.line!['date'], DateTime(2026, 5, 10));
  });

  test('🔴 تاريخٌ فاسدٌ يُرفَض بسببه لا يُطرَح', () {
    final r = parseBankStatementRow(['العاشر من مايو', 'R', '', 0, 5]);
    expect(r.line, isNull);
    expect(r.error, contains('التاريخ'));
  });

  test('🔴 مدينٌ ودائنٌ معاً يُرفَض', () {
    final r = parseBankStatementRow([DateTime(2026, 5, 10), 'R', '', 100, 50]);
    expect(r.line, isNull);
    expect(r.error, contains('مدين'));
  });

  test('🔴 صفرٌ في الاثنين يُرفَض — سطرٌ بلا حركة', () {
    final r = parseBankStatementRow([DateTime(2026, 5, 10), 'R', '', 0, 0]);
    expect(r.line, isNull);
    expect(r.error, isNotNull);
  });

  test('صفٌّ أقصرُ من خمسةِ أعمدةٍ يُرفَض ولا يرمي', () {
    final r = parseBankStatementRow([DateTime(2026, 5, 10), 'R']);
    expect(r.line, isNull);
    expect(r.error, isNotNull);
  });

  test('المبلغُ السالبُ يُرفَض — الإشارةُ يحملها العمود', () {
    final r = parseBankStatementRow([DateTime(2026, 5, 10), 'R', '', 0, -5]);
    expect(r.line, isNull);
    expect(r.error, isNotNull);
  });
}
