// ═══════════════════════════════════════════════════════════════════════════
// PARTY GROUPS CONTROLLER — Phase 2
// ═══════════════════════════════════════════════════════════════════════════
//
// Riverpod notifier + stream providers for the party-groups module.
// Exposes a simple CRUD surface on top of `PartyGroupDao`, plus live
// streams of groups with member counts for reactive UI rendering.
//
// Scope (deliberate): the notifier does NOT apply group-level discounts
// or payment terms automatically. The user explicitly asked for
// infrastructure only — the stored values are advisory and applied by
// the admin via bulk operations in a later phase.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../data/providers/providers.dart';

/// UI-visible state of the groups screen.
class PartyGroupsState {
  final bool isLoading;
  final String? error;

  const PartyGroupsState({this.isLoading = false, this.error});

  PartyGroupsState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return PartyGroupsState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Notifier managing create/update/delete of party groups and
/// membership assignment. UI components read the live list from
/// [partyGroupsWithCountsProvider] / [partyGroupMembersProvider]
/// separately; this notifier only owns mutation operations + their
/// transient loading/error state.
class PartyGroupsNotifier extends Notifier<PartyGroupsState> {
  late final AppDatabase _db;

  @override
  PartyGroupsState build() {
    _db = ref.watch(databaseProvider);
    return const PartyGroupsState();
  }

  /// Create a new group. Returns the new group's id on success, or null
  /// on failure (error message is stored in state).
  Future<int?> createGroup({
    required String name,
    String type = 'both',
    String? description,
    double defaultDiscount = 0,
    String? defaultPaymentTerms,
    String? priceLevel,
    String? notes,
    int? parentGroupId,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final id = await _db.createPartyGroup(
        name: name,
        type: type,
        description: description,
        defaultDiscount: defaultDiscount,
        defaultPaymentTerms: defaultPaymentTerms,
        priceLevel: priceLevel,
        notes: notes,
        parentGroupId: parentGroupId,
      );
      state = state.copyWith(isLoading: false);
      return id;
    } catch (e, st) {
      logger.error('Failed to create party group', e, st, 'PARTY_GROUPS');
      state = state.copyWith(
        isLoading: false,
        error: 'فشل إنشاء المجموعة: $e',
      );
      return null;
    }
  }

  /// Update an existing group. All fields are optional — only the ones
  /// explicitly passed are touched.
  Future<bool> updateGroup({
    required int id,
    String? name,
    String? type,
    String? description,
    double? defaultDiscount,
    String? defaultPaymentTerms,
    String? priceLevel,
    String? notes,
    int? parentGroupId,
    bool clearParent = false,
    bool? isActive,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final companion = PartyGroupsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        type: type != null ? Value(type) : const Value.absent(),
        description:
            description != null ? Value(description) : const Value.absent(),
        defaultDiscount: defaultDiscount != null
            ? Value(defaultDiscount)
            : const Value.absent(),
        defaultPaymentTerms: defaultPaymentTerms != null
            ? Value(defaultPaymentTerms)
            : const Value.absent(),
        priceLevel:
            priceLevel != null ? Value(priceLevel) : const Value.absent(),
        notes: notes != null ? Value(notes) : const Value.absent(),
        parentGroupId: clearParent
            ? const Value(null)
            : (parentGroupId != null
                ? Value(parentGroupId)
                : const Value.absent()),
        isActive:
            isActive != null ? Value(isActive) : const Value.absent(),
      );
      final ok = await _db.updatePartyGroup(id, companion);
      state = state.copyWith(isLoading: false);
      return ok;
    } catch (e, st) {
      logger.error('Failed to update party group', e, st, 'PARTY_GROUPS');
      state = state.copyWith(
        isLoading: false,
        error: 'فشل تعديل المجموعة: $e',
      );
      return false;
    }
  }

  /// Delete a group. Refuses (via DAO) if members still belong to it —
  /// the error message guides the user to reassign first.
  Future<bool> deleteGroup(int id) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final ok = await _db.deletePartyGroup(id);
      state = state.copyWith(isLoading: false);
      return ok;
    } catch (e, st) {
      logger.error('Failed to delete party group', e, st, 'PARTY_GROUPS');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Archive / unarchive (soft). Useful when a group shouldn't appear
  /// in dropdowns but still has historical members we want to keep
  /// linked.
  Future<bool> setActive(int id, bool isActive) async {
    try {
      return await _db.setPartyGroupActive(id, isActive);
    } catch (e, st) {
      logger.error('Failed to toggle group active', e, st, 'PARTY_GROUPS');
      state = state.copyWith(error: 'فشل تعديل الحالة: $e');
      return false;
    }
  }

  /// Attach a party to a group (or detach if groupId is null).
  Future<void> assignParty(int partyId, int? groupId) async {
    try {
      await _db.assignPartyToGroup(partyId, groupId);
    } catch (e, st) {
      logger.error('Failed to assign party to group', e, st, 'PARTY_GROUPS');
      state = state.copyWith(error: 'فشل إسناد الطرف للمجموعة: $e');
    }
  }

  /// Bulk assign: used by the "add members" flow on the group detail view.
  Future<void> assignPartiesBulk(List<int> partyIds, int? groupId) async {
    try {
      await _db.assignPartiesToGroup(partyIds, groupId);
    } catch (e, st) {
      logger.error('Failed to bulk-assign parties', e, st, 'PARTY_GROUPS');
      state = state.copyWith(error: 'فشل الإسناد الجماعى: $e');
    }
  }
}

/// Main notifier provider.
final partyGroupsControllerProvider =
    NotifierProvider<PartyGroupsNotifier, PartyGroupsState>(
  PartyGroupsNotifier.new,
);

// ─── Live stream providers (reactive sources for the UI) ─────────────

/// Live stream of all groups with their member counts. Drives the
/// management screen's list so it updates whenever a party gets
/// reassigned or a group is edited.
final partyGroupsWithCountsProvider =
    StreamProvider<List<PartyGroupWithCount>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchPartyGroupsWithCounts();
});

/// Live stream of ACTIVE groups — the source for dropdowns in party
/// dialogs and the filter chip on the parties list.
final activePartyGroupsProvider = StreamProvider<List<PartyGroup>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchActivePartyGroups();
});

/// Live members of a given group (used by the group detail view).
final partyGroupMembersProvider =
    StreamProvider.family<List<Party>, int>((ref, groupId) {
  final db = ref.watch(databaseProvider);
  return db.watchGroupMembers(groupId);
});
