// SYNC-004 — host-side duplicate-customer defence for `POST /api/parties`.
//
// Two offline terminals that create the same customer get different
// `globalId`s, and the previous natural-key fallback only matched an EXACT
// `name + phone` string, so `0101 234 5678` vs `+20 101 234 5678` created a
// duplicate. The lookup here compares NORMALISED phones (`samePhone`) and
// normalised names (`normalizePersonName`):
//
//  * same phone + same name + same kind  -> the same person: adopt the row;
//  * same phone + different name         -> maybe a family/shared line, so do
//    NOT merge, but record a `party_dedup_suspects` row for the owner.

import 'package:drift/drift.dart';

import '../../core/utils/phone_normalizer.dart';
import '../../data/database/database.dart';

class PartyPhoneMatch {
  const PartyPhoneMatch({this.same, this.suspects = const []});

  /// Existing party that is clearly the same person (merge target).
  final Party? same;

  /// Existing parties with the same phone but another name.
  final List<Party> suspects;
}

Future<PartyPhoneMatch> findPartyByNormalizedPhone(
  AppDatabase db, {
  required String? name,
  required String? phone,
  required bool isSupplier,
}) async {
  final national = normalizePhone(phone);
  if (national.isEmpty || name == null || name.trim().isEmpty) {
    return const PartyPhoneMatch();
  }
  // Cheap SQL pre-filter on the last 4 digits; exact comparison in Dart.
  final tail = national.substring(national.length - 4);
  final candidates = await (db.select(db.parties)
        ..where((p) => p.phone.like('%$tail') & p.isSupplier.equals(isSupplier)))
      .get();
  final wantedName = normalizePersonName(name);
  Party? same;
  final suspects = <Party>[];
  for (final c in candidates) {
    if (!samePhone(c.phone, phone)) continue;
    if (normalizePersonName(c.name) == wantedName) {
      same ??= c;
    } else {
      suspects.add(c);
    }
  }
  return PartyPhoneMatch(same: same, suspects: suspects);
}

/// Records `existing` parties as duplicate suspects of [newPartyId]. Never
/// throws: the report is advisory and must not fail the sync write.
Future<void> recordPhoneDuplicateSuspects(
  AppDatabase db, {
  required int newPartyId,
  required String newName,
  required String? newPhone,
  required List<Party> existing,
}) async {
  for (final other in existing) {
    try {
      await db.customUpdate(
        'INSERT INTO party_dedup_suspects '
        '(new_party_id, existing_party_id, name, new_phone, existing_phone, reason, source) '
        'VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT DO NOTHING',
        variables: [
          Variable<int>(newPartyId),
          Variable<int>(other.id),
          Variable<String>(newName),
          Variable<String>(newPhone ?? ''),
          Variable<String>(other.phone ?? ''),
          const Variable<String>('same_phone_different_name'),
          const Variable<String>('api_post_party'),
        ],
      );
    } catch (_) {
      // table missing on a very old schema, or FK race: advisory only.
    }
  }
}
