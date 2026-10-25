// Bin lookup by scanned barcode (`BIN-...`). Raw SQL: warehouse_locations is
// not a Drift table (plan A.2 v195).
import 'package:drift/drift.dart';

import '../../../data/database/database.dart';

class WhLocation {
  WhLocation(this.id, this.warehouseId, this.binCode, this.barcode, this.isDefault);
  final int id;
  final int warehouseId;
  final String binCode;
  final String barcode;
  final bool isDefault;
}

Future<WhLocation?> locationByBarcode(AppDatabase db, String barcode) async {
  final r = await db.customSelect(
    'SELECT id, warehouse_id, bin_code, barcode, is_default FROM warehouse_locations '
    'WHERE barcode = ? AND deleted_at IS NULL AND is_active = 1 LIMIT 1',
    variables: [Variable<String>(barcode.trim())],
  ).getSingleOrNull();
  if (r == null) return null;
  final d = r.data;
  return WhLocation((d['id'] as num).toInt(), (d['warehouse_id'] as num).toInt(), d['bin_code'] as String,
      d['barcode'] as String, ((d['is_default'] as num?) ?? 0) != 0);
}

Future<int?> defaultLocationId(AppDatabase db, int warehouseId) async {
  final r = await db.customSelect(
    'SELECT id FROM warehouse_locations WHERE warehouse_id = ? AND is_default = 1 AND deleted_at IS NULL LIMIT 1',
    variables: [Variable<int>(warehouseId)],
  ).getSingleOrNull();
  return (r?.data['id'] as num?)?.toInt();
}
