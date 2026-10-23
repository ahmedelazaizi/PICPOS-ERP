// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

class DocumentSequenceSyncStrategy extends SyncStrategy {
  DocumentSequenceSyncStrategy(super.db);

  @override
  String get tableName => 'documentSequences';

  @override
  String get apiEndpoint => '/api/document-sequences';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final items = json['document_sequences'] as List;
    for (final d in items) {
      await db.into(db.documentSequences).insertOnConflictUpdate(
        DocumentSequencesCompanion(
          prefix: Value(d['prefix'] as String),
          nextValue: Value(parseInt(d['nextValue'], 1)),
        ),
      );
    }
    // Force UI refresh after sync
    if (items.isNotEmpty) {
      db.markTablesUpdated({db.documentSequences});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async => 0;

  @override
  Future<void> upsert(Insertable record) async {
    await db
        .into(db.documentSequences)
        .insertOnConflictUpdate(record as DocumentSequencesCompanion);
  }
}