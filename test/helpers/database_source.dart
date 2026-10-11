import 'dart:io';

/// Part files carved out of lib/data/database/database.dart (pure move,
/// no behaviour change). Source-grep tests that used to read database.dart
/// alone read the merged text through [readDatabaseSource] instead, so every
/// assertion keeps searching the same code.
const List<String> kDatabaseSplitParts = <String>[
  'lib/data/database/database_types.dart',
  'lib/data/database/database_sql_constants.dart',
  'lib/data/database/database_pg_create.dart',
  'lib/data/database/database_pg_sync_infra.dart',
  'lib/data/database/database_pg_parity.dart',
  'lib/data/database/database_numbering.dart',
  'lib/data/database/database_misc_dao_methods.dart',
];

const String kDatabaseMainPath = 'lib/data/database/database.dart';

/// database.dart plus the parts split out of it, joined by newlines.
String readDatabaseSource() => [
      for (final p in <String>[kDatabaseMainPath, ...kDatabaseSplitParts])
        File(p).readAsStringSync(),
    ].join('\n');

/// Like File(path).readAsStringSync(), but [kDatabaseMainPath] returns the
/// merged text from [readDatabaseSource].
String readSourceMerged(String path) =>
    path.replaceAll(r'\', '/') == kDatabaseMainPath
        ? readDatabaseSource()
        : File(path).readAsStringSync();