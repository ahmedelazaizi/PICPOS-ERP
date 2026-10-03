import 'package:drift/drift.dart';

import '../../core/utils/uuid_v7.dart';
import '../../data/database/database.dart';

/// K-1 — the rep expense categories as pushed to the cloud
/// (`expenseCategories` of `/desktop/master`). The account code stays on the
/// desktop (the poster debits it); deleted rows travel as tombstones.
Future<List<Map<String, Object?>>> cloudExpenseCategoriesJson(
    AppDatabase db) async {
  final out = <Map<String, Object?>>[];
  for (final c in await db.allFieldExpenseCategories()) {
    var gid = c.globalId;
    if (gid == null || gid.isEmpty) {
      gid = UuidV7.generate();
      await db.customUpdate(
        'UPDATE field_expense_categories SET global_id = ? WHERE id = ?',
        variables: [Variable<String>(gid), Variable<int>(c.id)],
      );
    }
    out.add({
      'globalId': gid,
      'name': c.name,
      'nameEn': c.nameEn,
      'sortOrder': c.sortOrder,
      'isActive': c.isActive,
      'deleted': c.deleted,
    });
  }
  return out;
}
