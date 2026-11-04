import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/delta_pull_column_filter.dart';

void main() {
  test('SQLite: يحذف المفاتيح غير المحلّية ويُبقي الباقي', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final out = await DeltaPullColumnFilter().apply(db, 'permissions', {
      'code': 'x',
      'name': 'n',
      'no_such_column_zzz': 1,
    });
    expect(out.keys.toSet(), {'code', 'name'});
  });
}
