// Spec 084d dedup data classes.
part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Spec 084d — parties dedup data classes
// ═══════════════════════════════════════════════════════════════════════════

class DuplicatePartyRow {
  final int id;
  final String name;
  final String? phone;
  final double balance;
  final bool isCustomer;
  final bool isSupplier;
  final String? globalId;
  final int refCount;
  final int attachedTxnRefs;

  const DuplicatePartyRow({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
    required this.isCustomer,
    required this.isSupplier,
    required this.globalId,
    required this.refCount,
    required this.attachedTxnRefs,
  });
}

class DuplicatePartyGroup {
  final String name;
  final DuplicatePartyRow canonical;
  final List<DuplicatePartyRow> duplicates;

  const DuplicatePartyGroup({
    required this.name,
    required this.canonical,
    required this.duplicates,
  });

  bool get hasDuplicates => duplicates.isNotEmpty;
}

class MergedPartyDedupRecord {
  final int dupId;
  final int canonicalId;
  final String name;

  const MergedPartyDedupRecord({
    required this.dupId,
    required this.canonicalId,
    required this.name,
  });
}

class SkippedPartyDedupRecord {
  final int dupId;
  final int canonicalId;
  final String name;
  final int attachedTxnRefs;
  final double balance;

  const SkippedPartyDedupRecord({
    required this.dupId,
    required this.canonicalId,
    required this.name,
    required this.attachedTxnRefs,
    required this.balance,
  });
}

class PartyDedupResult {
  final List<MergedPartyDedupRecord> merged;
  final List<SkippedPartyDedupRecord> skipped;

  const PartyDedupResult({
    required this.merged,
    required this.skipped,
  });

  int get mergedCount => merged.length;
  int get skippedCount => skipped.length;
  bool get hasSkipped => skipped.isNotEmpty;
}
