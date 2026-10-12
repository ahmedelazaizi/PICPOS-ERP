import 'dart:io';

/// DAO files carved into several part of '../database.dart' files (pure
/// move, no behaviour change). Source-grep tests that used to read one DAO
/// file read the merged text through [readDaoSourceMerged] instead, so every
/// assertion keeps searching the same code. Parts are listed in the order
/// their code appeared in the original file.
const Map<String, List<String>> kSplitDaoParts = <String, List<String>>{
  'lib/data/database/daos/purchase_dao.dart': <String>[
    'lib/data/database/daos/purchase_models.dart',
    'lib/data/database/daos/purchase_queries_dao.dart',
    'lib/data/database/daos/purchase_return_reads_dao.dart',
    'lib/data/database/daos/purchase_dao.dart',
    'lib/data/database/daos/purchase_insert_support_dao.dart',
    'lib/data/database/daos/purchase_update_dao.dart',
    'lib/data/database/daos/purchase_payments_dao.dart',
    'lib/data/database/daos/purchase_void_dao.dart',
    'lib/data/database/daos/purchase_summary_dao.dart',
  ],
  'lib/data/database/daos/party_dao.dart': <String>[
    'lib/data/database/daos/party_dao.dart',
    'lib/data/database/daos/party_reads_dao.dart',
    'lib/data/database/daos/party_profile_dao.dart',
    'lib/data/database/daos/party_coa_repair_dao.dart',
    'lib/data/database/daos/party_balances_dao.dart',
    'lib/data/database/daos/party_transactions_dao.dart',
    'lib/data/database/daos/party_reconciliation_dao.dart',
    'lib/data/database/daos/party_models.dart',
    'lib/data/database/daos/party_group_dao.dart',
    'lib/data/database/daos/party_dedup_dao.dart',
    'lib/data/database/daos/party_dedup_models.dart',
  ],
  'lib/data/database/daos/accounting_autopost_dao.dart': <String>[
    'lib/data/database/daos/accounting_autopost_dao.dart',
    'lib/data/database/daos/accounting_autopost_cash_sale_dao.dart',
    'lib/data/database/daos/accounting_autopost_documents_dao.dart',
    'lib/data/database/daos/accounting_autopost_sales_return_dao.dart',
    'lib/data/database/daos/accounting_autopost_purchase_return_dao.dart',
    'lib/data/database/daos/accounting_autopost_delivery_repair_dao.dart',
  ],
};

/// Like File(path).readAsStringSync(), but a path listed in [kSplitDaoParts]
/// returns the merged text of all its parts (joined by newlines).
String readDaoSourceMerged(String path) {
  final parts = kSplitDaoParts[path.replaceAll(r'\', '/')];
  if (parts == null) return File(path).readAsStringSync();
  return [for (final p in parts) File(p).readAsStringSync()].join('\n');
}