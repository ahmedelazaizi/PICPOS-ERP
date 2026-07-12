import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import '../database.dart';

/// Feature 018 / Issue 10 — one-shot decision for the
/// `enable_negative_sales` setting on the FIRST boot of the new code.
///
/// The orchestrator's read-path now defaults to **false** (safe) when the
/// setting key is absent. That's the right default for fresh installs but
/// would silently flip behavior for existing installs that have been
/// running with the old hardcoded `'allow_negative'` policy. To preserve
/// behavior for existing installs (Constitution I), this pass detects
/// "is this an existing install?" by counting `sales_invoices` and writes
/// an explicit value:
///
///   - sales_invoices is NON-empty → set 'enable_negative_sales' = 'true'
///     (preserve legacy behavior; admins flip OFF in settings when ready)
///   - sales_invoices is empty → set 'enable_negative_sales' = 'false'
///     (the safe default for new installs)
///
/// Skipped if the setting already exists (idempotent — repeated boots are
/// O(1) after the first decision lands).
extension NegativeSalesDefaultBackfillExtension on AppDatabase {
  static const _settingKey = 'enable_negative_sales';

  /// Returns the chosen value if a write was performed, or null if the
  /// setting already existed and the pass was a no-op.
  Future<String?> ensureNegativeSalesDefault() async {
    final existing = await getSettingValue(_settingKey);
    if (existing != null) {
      // User has already configured (or a previous boot ran the backfill).
      return null;
    }

    final salesCountRow = await customSelect(
      'SELECT COUNT(*) AS c FROM sales_invoices',
    ).getSingleOrNull();
    final salesCount = (salesCountRow?.data['c'] as int?) ?? 0;
    final value = salesCount > 0 ? 'true' : 'false';

    // Use the same DAO write path that the settings UI uses — keeps the
    // sync_revision stamp + WAL coherent.
    await into(settings).insertOnConflictUpdate(
      SettingsCompanion.insert(key: _settingKey, value: Value(value)),
    );

    debugPrint(
      '[NEG-SALES-DEFAULT] sales_invoices=$salesCount → '
      'enable_negative_sales=$value',
    );
    return value;
  }
}
