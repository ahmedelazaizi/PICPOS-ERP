// ignore_for_file: avoid_dynamic_calls
import 'package:drift/drift.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/sync/sync_strategy.dart';

class CategorySyncStrategy extends SyncStrategy {
  CategorySyncStrategy(super.db);

  @override
  String get tableName => 'categories';

  @override
  String get apiEndpoint => '/api/categories';

  @override
  Future<void> syncFromJson(Map<String, dynamic> json) async {
    final categories = json['categories'] as List;
    for (final cat in categories) {
      final categoryId = parseInt(cat['id']);
      final catGlobalId = cat['globalId'] as String?;

      // Dedup 1: globalId-based match — prevents duplicate inserts when the
      // same category was created on two devices before their first sync.
      Category? existing;
      if (catGlobalId != null && catGlobalId.isNotEmpty) {
        existing = await (db.select(db.categories)
          ..where((c) => c.globalId.equals(catGlobalId))
          ..limit(1)
        ).getSingleOrNull();
      }

      // Dedup 2: name-based fallback — catches legacy categories that predate
      // globalId stamping (globalId may be null on server for old rows).
      existing ??= await (db.select(db.categories)
          ..where((c) => c.name.equals(cat['name'] as String))
          ..limit(1)
        ).getSingleOrNull();

      // Issue 3 (Phase 5A.5) — use the resolved local id consistently.
      // Previously we set `id: existing != null ? Value(existing.id) :
      // Value(categoryId)` and called `insertOnConflictUpdate`, which made
      // Drift route the write through the primary key on the companion.
      // When client and server had drifted autoincrement sequences (the
      // common multi-device case), `existing.id` (client's PK) and
      // `categoryId` (server's PK from the JSON payload) diverged. The
      // categoryBranches step downstream then keyed on `categoryId`
      // (server's id) while the categories row lived at `existing.id`
      // (client's id), orphaning links and — under retry pressure —
      // producing two visible category rows for the same logical record.
      //
      // The fix: when we already have an `existing` row (Tier 1 or 2),
      // UPDATE it by its own primary key explicitly. Only insert a fresh
      // row (taking the server's id) when no local match exists. The
      // categoryBranches step keys on the resolved local id throughout.
      final localId = existing?.id ?? categoryId;

      // Field-report 2026-05-14 (Feature 054 v134): an operator hides
      // categories from the POS on their branch device, restarts, and the
      // hidden categories come back visible. Cause: `showInPos` is a
      // single global flag, and this strategy unconditionally overwrote
      // it with the server's value on every sync (every ~5 min). The
      // periodic sync was effectively a "show all categories" cron.
      //
      // Until per-branch hide-state lands as a proper data-model change,
      // treat `showInPos` as a CLIENT-LOCAL preference: take the server's
      // value only when inserting a brand-new category row; preserve the
      // local value on every subsequent update. This matches operator
      // expectation (hide on branch → stays hidden on branch) and the
      // trade-off (HQ changes to showInPos don't propagate to branches
      // that already know about the category) is acceptable because the
      // flag is the operator's visibility preference, not master data.
      final baseFields = CategoriesCompanion(
        name: Value(cat['name'] as String),
        globalId: Value(catGlobalId),
        parentId: Value(parseIntNullable(cat['parentId'])),
        color: Value(cat['color'] as String? ?? '#2563EB'),
        iconName: Value(cat['iconName'] as String?),
        sortOrder: Value(parseInt(cat['sortOrder'])),
        isActive: Value(parseBool(cat['isActive'], true)),
        isGlobal: Value(parseBool(cat['isGlobal'], true)),
        printerId: Value(parseIntNullable(cat['printerId'])),
        isLocked: Value(parseBool(cat['isLocked'], false)),
        isExcluded: Value(parseBool(cat['isExcluded'], false)),
      );
      if (existing != null) {
        // Update path — DO NOT include showInPos so the local preference
        // survives the sync.
        await (db.update(db.categories)
              ..where((c) => c.id.equals(existing!.id)))
            .write(baseFields);
      } else {
        // Insert path — first time we see this category, seed showInPos
        // from the server's value (defaults to true if not present).
        await db.into(db.categories).insertOnConflictUpdate(
              baseFields.copyWith(
                id: Value(categoryId),
                showInPos: Value(parseBool(cat['showInPos'], true)),
              ),
            );
      }

      final branchIdsList = cat['branchIds'] as List?;
      if (branchIdsList != null) {
        // Feature 006 #7: UPSERT + diff-delete on the composite PK
        // (categoryId, branchId) instead of the previous wipe-and-rebuild.
        // The race we close: an admin attaching a category to a new branch
        // locally while a sync pull was in flight used to lose that link
        // because the wipe ran before the snapshot insert (and the snapshot
        // didn't yet include the just-added link).
        final serverBranchIds = branchIdsList.map(parseInt).toSet();
        await db.transaction(() async {
          // 1. UPSERT every link in the snapshot (no-op if it already exists).
          for (final bId in serverBranchIds) {
            await db.into(db.categoryBranches).insertOnConflictUpdate(
              CategoryBranchesCompanion.insert(
                categoryId: localId,
                branchId: bId,
              ),
            );
          }
          // 2. Diff-delete: drop links the server clearly removed for this
          //    category. Scoped to localId so we never touch other categories.
          final localLinks = await (db.select(db.categoryBranches)
            ..where((cb) => cb.categoryId.equals(localId))
          ).get();
          for (final link in localLinks) {
            if (!serverBranchIds.contains(link.branchId)) {
              await (db.delete(db.categoryBranches)
                    ..where((cb) =>
                        cb.categoryId.equals(localId) &
                        cb.branchId.equals(link.branchId)))
                  .go();
            }
          }
        });
      }
    }
    // Force UI refresh after sync
    if (categories.isNotEmpty) {
      db.markTablesUpdated({db.categories});
    }
  }

  @override
  Future<int> syncIncremental(DateTime since) async {
    return 0; // To be implemented
  }

  @override
  Future<void> upsert(Insertable record) async {
    await db.into(db.categories).insertOnConflictUpdate(record as CategoriesCompanion);
  }
}