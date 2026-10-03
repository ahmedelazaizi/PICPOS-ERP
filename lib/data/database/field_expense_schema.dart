part of 'database.dart';

/// v194 — مصروفاتُ المندوب الميدانية وموقعُ GPS (قرارات المالك K).
///
/// Raw SQL outside Drift's table model (no codegen run), following
/// `distribution_model_schema.dart`:
///
/// • `field_expense_categories` — the configurable list of rep expense
///   categories (fuel, porters, parking, …) each mapped to an expense account
///   **code**; pushed to the cloud (`expenseCategories`) and chosen by the rep
///   on the van app. The cloud posts nothing: the desktop poster debits the
///   category's account through the payment-voucher path.
/// • `route_visits.latitude` / `longitude` / `field_geo` and
///   `sales_invoices.field_geo` / `safe_transactions.field_geo` (raw columns)
///   — the GPS stamp the van captured (`field_geo` = JSON `{status, lat, lng,
///   accuracy, at}`; status ≠ `ok` records why there is no fix).
extension FieldExpenseSchema on AppDatabase {
  /// [seed]: the default categories are seeded by the v194 migration and on
  /// a new database only (the every-start call just repairs the schema).
  Future<void> ensureFieldExpenseSchema({bool seed = true}) async {
    await customStatement(_isPostgres
        ? _fieldExpenseCategoriesPostgres
        : _fieldExpenseCategoriesSqlite);
    await _dmAddColumns('route_visits', const [
      'latitude REAL',
      'longitude REAL',
      'field_geo TEXT',
    ]);
    await _dmAddColumns('sales_invoices', const ['field_geo TEXT']);
    await _dmAddColumns('safe_transactions', const ['field_geo TEXT']);
    if (seed) await _seedFieldExpenseCategories();
  }

  /// Live categories (deleted ones excluded), in display order.
  Future<List<FieldExpenseCategory>> listFieldExpenseCategories(
      {bool activeOnly = false}) async {
    final rows = await customSelect(
      'SELECT * FROM field_expense_categories WHERE deleted_at IS NULL '
      '${activeOnly ? 'AND is_active = 1 ' : ''}ORDER BY sort_order, id',
    ).get();
    return [for (final r in rows) FieldExpenseCategory.fromRow(r.data)];
  }

  /// Every row incl. soft-deleted ones (the cloud push sends tombstones).
  Future<List<FieldExpenseCategory>> allFieldExpenseCategories() async {
    final rows = await customSelect(
      'SELECT * FROM field_expense_categories ORDER BY sort_order, id',
    ).get();
    return [for (final r in rows) FieldExpenseCategory.fromRow(r.data)];
  }

  Future<FieldExpenseCategory?> fieldExpenseCategoryByGlobalId(
      String globalId) async {
    final row = await customSelect(
      'SELECT * FROM field_expense_categories WHERE global_id = ? LIMIT 1',
      variables: [Variable<String>(globalId)],
    ).getSingleOrNull();
    return row == null ? null : FieldExpenseCategory.fromRow(row.data);
  }

  /// Creates ([id] null) or updates a category.
  Future<int> saveFieldExpenseCategory({
    int? id,
    required String name,
    String? nameEn,
    required String accountCode,
    int sortOrder = 0,
    bool isActive = true,
  }) async {
    final values = {
      'name': name.trim(),
      'name_en': (nameEn == null || nameEn.trim().isEmpty) ? null : nameEn.trim(),
      'account_code': accountCode.trim(),
      'sort_order': sortOrder,
      'is_active': isActive ? 1 : 0,
    };
    if (id == null) return _dmInsert('field_expense_categories', values);
    await customUpdate(
      'UPDATE field_expense_categories SET name = ?, name_en = ?, '
      'account_code = ?, sort_order = ?, is_active = ?, last_modified_at = ?, '
      'row_version = row_version + 1 WHERE id = ?',
      variables: [
        Variable<String>(values['name'] as String),
        Variable<String>(values['name_en'] as String?),
        Variable<String>(values['account_code'] as String),
        Variable<int>(sortOrder),
        Variable<int>(isActive ? 1 : 0),
        Variable<int>(_dmNow()),
        Variable<int>(id),
      ],
    );
    return id;
  }

  /// K-3: row id → Google Maps link of the van GPS stamp (`field_geo`) of
  /// [table] (`sales_invoices` / `safe_transactions`); rows without a fix
  /// are absent. Empty when the column is missing (never fails a report).
  Future<Map<int, String>> fieldGeoMapsUrls(String table) async {
    try {
      final rows = await customSelect(
        'SELECT id, field_geo FROM $table WHERE field_geo IS NOT NULL',
      ).get();
      return {
        for (final r in rows)
          (r.data['id'] as num).toInt(): ?fieldGeoMapsUrl(r.data['field_geo']),
      };
    } catch (e) {
      debugPrint('[GEO] $table field_geo unavailable: $e');
      return const {};
    }
  }

  /// K-3: Google Maps link of route visit [visitId] (van GPS), or null.
  Future<String?> routeVisitMapsUrl(int visitId) async {
    try {
      final row = await customSelect(
        'SELECT latitude, longitude FROM route_visits WHERE id = ?',
        variables: [Variable<int>(visitId)],
      ).getSingleOrNull();
      final lat = row?.data['latitude'], lng = row?.data['longitude'];
      if (lat is! num || lng is! num) return null;
      return googleMapsUrl(lat.toDouble(), lng.toDouble());
    } catch (e) {
      debugPrint('[GEO] route_visits geo unavailable: $e');
      return null;
    }
  }

  Future<void> deleteFieldExpenseCategory(int id) => customUpdate(
        'UPDATE field_expense_categories SET deleted_at = ?, '
        'last_modified_at = ? WHERE id = ?',
        variables: [
          Variable<int>(_dmNow()),
          Variable<int>(_dmNow()),
          Variable<int>(id),
        ],
      );
}

/// A rep expense category (v194 `field_expense_categories`).
class FieldExpenseCategory {
  const FieldExpenseCategory({
    required this.id,
    required this.name,
    required this.accountCode,
    this.nameEn,
    this.sortOrder = 0,
    this.isActive = true,
    this.globalId,
    this.deleted = false,
  });

  factory FieldExpenseCategory.fromRow(Map<String, dynamic> r) =>
      FieldExpenseCategory(
        id: (r['id'] as num).toInt(),
        name: '${r['name']}',
        nameEn: r['name_en'] as String?,
        accountCode: '${r['account_code']}',
        sortOrder: (r['sort_order'] as num?)?.toInt() ?? 0,
        isActive: r['is_active'] == 1 || r['is_active'] == true,
        globalId: r['global_id'] as String?,
        deleted: r['deleted_at'] != null,
      );

  final int id;
  final String name;
  final String? nameEn;
  final String accountCode;
  final int sortOrder;
  final bool isActive;
  final String? globalId;
  final bool deleted;
}

/// Google Maps link of a point (opens the map app / browser).
String googleMapsUrl(double lat, double lng) =>
    'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

/// Google Maps link of a stored `field_geo` JSON, or null without a fix.
String? fieldGeoMapsUrl(Object? fieldGeo) {
  if (fieldGeo is! String || fieldGeo.isEmpty) return null;
  try {
    final g = jsonDecode(fieldGeo);
    if (g is Map && g['lat'] is num && g['lng'] is num) {
      return googleMapsUrl(
          (g['lat'] as num).toDouble(), (g['lng'] as num).toDouble());
    }
  } on FormatException {
    return null;
  }
  return null;
}

/// Desktop setting: what the cloud does with an expense beyond the rep's
/// custody balance — `flag` (default, «تجاوز العهدة») or `reject`.
const kCloudExpenseOverCustodySetting = 'cloud_expense_over_custody';

extension _FieldExpenseSeed on AppDatabase {

  /// Default categories (owner list), seeded once when the table is empty.
  /// Accounts: 614 freight & distribution, 617 travel & transport (sales),
  /// 627 maintenance, 6214 miscellaneous.
  Future<void> _seedFieldExpenseCategories() async {
    final any = await customSelect(
            'SELECT COUNT(*) AS n FROM field_expense_categories')
        .getSingle();
    if (((any.data['n'] as num?) ?? 0) > 0) return;
    const defaults = [
      ('وقود', 'Fuel', '614'),
      ('تنزيل وعتالة', 'Unloading / porters', '614'),
      ('مواقف', 'Parking', '617'),
      ('صيانة', 'Maintenance', '627'),
      ('وجبات', 'Meals', '617'),
      ('أخرى', 'Other', '6214'),
    ];
    for (var i = 0; i < defaults.length; i++) {
      await _dmInsert('field_expense_categories', {
        'name': defaults[i].$1,
        'name_en': defaults[i].$2,
        'account_code': defaults[i].$3,
        'sort_order': i,
        'is_active': 1,
      });
    }
  }
}

const _fieldExpenseCategoriesSqlite = '''CREATE TABLE IF NOT EXISTS field_expense_categories (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       name TEXT NOT NULL,
       name_en TEXT,
       account_code TEXT NOT NULL,
       sort_order INTEGER NOT NULL DEFAULT 0,
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
       global_id TEXT UNIQUE,
       last_modified_at INTEGER,
       deleted_at INTEGER,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''';

const _fieldExpenseCategoriesPostgres = '''CREATE TABLE IF NOT EXISTS field_expense_categories (
       id SERIAL PRIMARY KEY,
       name TEXT NOT NULL,
       name_en TEXT,
       account_code TEXT NOT NULL,
       sort_order INTEGER NOT NULL DEFAULT 0,
       is_active INTEGER NOT NULL DEFAULT 1,
       created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
       global_id TEXT UNIQUE,
       last_modified_at BIGINT,
       deleted_at BIGINT,
       origin_client_id TEXT,
       row_version INTEGER NOT NULL DEFAULT 0
     )''';
