import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/web/web_sql_comment_stripper.dart';

void main() {
  test('يزيل تعليق السطر والكتلة', () {
    final out = stripSqlComments('select 1 -- note\nfrom t /* c */ where x=1');
    expect(out, isNot(contains('--')));
    expect(out, isNot(contains('/*')));
    expect(out, contains('select 1'));
    expect(out, contains('where x=1'));
  });

  test('لا يمسّ ما داخل السلاسل المقتبسة', () {
    const sql = "select '-- not a comment', \"a/*b\", 'it''s -- ok' from t";
    expect(stripSqlComments(sql), sql);
  });

  test('تعليق كتلة غير مغلق يُقطع للنهاية', () {
    expect(stripSqlComments('select 1 /* open').trim(), 'select 1');
  });
}
