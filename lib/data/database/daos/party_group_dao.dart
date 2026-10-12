// Party groups: CRUD, member counts, assignment.
part of '../database.dart';

extension PartyGroupDao on AppDatabase {
  /// Watch ALL party groups (active + archived) ordered alphabetically.
  /// The UI layer decides whether to hide archived ones.
  Stream<List<PartyGroup>> watchPartyGroups() {
    return (select(partyGroups)
          ..orderBy([(g) => OrderingTerm.asc(g.name)]))
        .watch();
  }

  /// Watch active party groups only — useful for dropdowns where
  /// archived groups shouldn't appear.
  Stream<List<PartyGroup>> watchActivePartyGroups() {
    return (select(partyGroups)
          ..where((g) => g.isActive.equals(true))
          ..orderBy([(g) => OrderingTerm.asc(g.name)]))
        .watch();
  }

  /// Get active party groups filtered by type.
  /// [type] must be `'customer'`, `'supplier'`, or `'both'`. Rows
  /// tagged `'both'` always match — they work for either side.
  Future<List<PartyGroup>> getPartyGroupsByType(String type) {
    return (select(partyGroups)
          ..where((g) => g.type.equals(type) | g.type.equals('both'))
          ..where((g) => g.isActive.equals(true))
          ..orderBy([(g) => OrderingTerm.asc(g.name)]))
        .get();
  }

  /// Stream the list of groups together with their current member counts.
  /// Triggers on any write to `parties` or `partyGroups` so the UI
  /// stays live without explicit invalidations.
  Stream<List<PartyGroupWithCount>> watchPartyGroupsWithCounts() {
    final groupCount = parties.id.count();
    final query = select(partyGroups).join([
      leftOuterJoin(
        parties,
        parties.groupId.equalsExp(partyGroups.id) &
            parties.isActive.equals(true),
      ),
    ])
      ..addColumns([groupCount])
      ..groupBy([partyGroups.id])
      ..orderBy([OrderingTerm.asc(partyGroups.name)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final g = row.readTable(partyGroups);
        final count = row.read(groupCount) ?? 0;
        return PartyGroupWithCount(g, count);
      }).toList();
    });
  }

  /// Count a single group's active members.
  Future<int> getGroupMemberCount(int groupId) async {
    final cnt = parties.id.count();
    final row = await (selectOnly(parties)
          ..addColumns([cnt])
          ..where(parties.groupId.equals(groupId) & parties.isActive.equals(true)))
        .getSingle();
    return row.read(cnt) ?? 0;
  }

  /// Stream active members of a given group, ordered by name.
  Stream<List<Party>> watchGroupMembers(int groupId) {
    return (select(parties)
          ..where((p) => p.groupId.equals(groupId) & p.isActive.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  /// Create a party group with full business-rule metadata.
  /// Only `name` is required; the rest default to sensible values.
  Future<int> createPartyGroup({
    required String name,
    String type = 'both',
    String? description,
    double defaultDiscount = 0,
    String? defaultPaymentTerms,
    String? priceLevel,
    String? notes,
    int? parentGroupId,
  }) async {
    final companion = PartyGroupsCompanion.insert(
      name: name,
      type: Value(type),
      description: Value(description),
      defaultDiscount: Value(defaultDiscount),
      defaultPaymentTerms: Value(defaultPaymentTerms),
      priceLevel: Value(priceLevel),
      notes: Value(notes),
      parentGroupId: Value(parentGroupId),
      globalId: Value(UuidV7.generate()),
    );
    if (SyncInterceptor.isClientMode) {
      final serverId = await SyncInterceptor.instance?.createPartyGroup(companion);
      if (serverId != null) return serverId;
    }
    return into(partyGroups).insert(companion);
  }

  /// Update a party group using a Companion.
  Future<bool> updatePartyGroup(int id, PartyGroupsCompanion data) async {
    if (SyncInterceptor.isClientMode) {
      final map = <String, dynamic>{};
      if (data.name.present) map['name'] = data.name.value;
      if (data.type.present) map['type'] = data.type.value;
      if (data.description.present) map['description'] = data.description.value;
      if (data.defaultDiscount.present) map['defaultDiscount'] = data.defaultDiscount.value;
      if (data.defaultPaymentTerms.present) map['defaultPaymentTerms'] = data.defaultPaymentTerms.value;
      if (data.priceLevel.present) map['priceLevel'] = data.priceLevel.value;
      if (data.notes.present) map['notes'] = data.notes.value;
      if (data.isActive.present) map['isActive'] = data.isActive.value;
      await SyncInterceptor.instance?.updatePartyGroup(id, map);
    }
    return (update(partyGroups)..where((g) => g.id.equals(id)))
        .write(data)
        .then((rows) => rows > 0);
  }

  /// Delete a party group. Refuses if it still has members.
  Future<bool> deletePartyGroup(int id) async {
    final membersRemaining = await getGroupMemberCount(id);
    if (membersRemaining > 0) {
      throw Exception(
        'لا يمكن حذف المجموعة لأن بها $membersRemaining طرف. '
        'انقل الأطراف لمجموعة أخرى أولاً أو قم بتعطيل المجموعة بدلاً من الحذف.',
      );
    }
    if (SyncInterceptor.isClientMode) {
      await SyncInterceptor.instance?.deletePartyGroup(id);
    }
    final rows = await (delete(partyGroups)..where((g) => g.id.equals(id))).go();
    return rows > 0;
  }

  /// Toggle the active state of a group (soft archive/restore).
  Future<bool> setPartyGroupActive(int id, bool isActive) {
    return (update(partyGroups)..where((g) => g.id.equals(id)))
        .write(PartyGroupsCompanion(isActive: Value(isActive)))
        .then((rows) => rows > 0);
  }

  /// Assign or detach a single party from a group. Pass `null` to detach.
  Future<void> assignPartyToGroup(int partyId, int? groupId) {
    return (update(parties)..where((p) => p.id.equals(partyId)))
        .write(PartiesCompanion(groupId: Value(groupId)));
  }

  /// Bulk-assign a list of parties to a group. Useful for the group
  /// detail screen's "add members" dialog.
  Future<void> assignPartiesToGroup(List<int> partyIds, int? groupId) async {
    if (partyIds.isEmpty) return;
    await transaction(() async {
      for (final pid in partyIds) {
        await (update(parties)..where((p) => p.id.equals(pid)))
            .write(PartiesCompanion(groupId: Value(groupId)));
      }
    });
  }
}
