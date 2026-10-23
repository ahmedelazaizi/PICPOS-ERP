part of 'database.dart';

/// v196 — عملاءُ الحجوزات = أطرافُ النظام (خطة الطاولات والحجوزات، B.10 / F.1).
///
/// * `table_reservations.party_id` (→ parties.id، معدوم = ضيف). اللقطةُ النصيّةُ
///   (الاسم/الهاتف) تبقى للتاريخ. `bookings.party_id` موجودٌ منذ v159.
/// * `party_dedup_suspects`: تقريرُ «اشتباه تكرار» للمالك — جدولٌ **محلّيٌّ**
///   صغير (لا مزامنة): يسجّل أزواجَ (عميلٌ أنشأه الترحيل، عميلٌ قائمٌ بالاسم
///   نفسِه وهاتفٍ مختلف) دون أيّ دمجٍ تلقائيّ.
///
/// لا `m.alterTable` (الجدولان مُزامَنان — `alter_table_sync_columns_guard`):
/// عمودٌ بـ`ALTER TABLE ADD COLUMN` + فهارس. متساوي القوى.
extension ReservationPartiesSchema on AppDatabase {
  Future<void> ensureReservationPartiesSchema() async {
    await _dmAddColumns('table_reservations', const [
      'party_id INTEGER REFERENCES parties(id)',
    ]);
    for (final sql in _isPostgres ? _suspectsPgSql : _suspectsSqliteSql) {
      await customStatement(sql);
    }
  }

  /// أزواجُ الاشتباه المفتوحة (الأحدث أولاً) — يقرؤها المالك لاحقاً.
  Future<List<PartyDedupSuspect>> listPartyDedupSuspects(
      {bool openOnly = true}) async {
    await ensureReservationPartiesSchema();
    final rows = await customSelect(
      'SELECT s.*, np.name AS new_name, ep.name AS existing_name '
      'FROM party_dedup_suspects s '
      'LEFT JOIN parties np ON np.id = s.new_party_id '
      'LEFT JOIN parties ep ON ep.id = s.existing_party_id '
      "${openOnly ? "WHERE s.status = 'open' " : ''}"
      'ORDER BY s.id DESC',
    ).get();
    return [
      for (final r in rows)
        PartyDedupSuspect(
          id: (r.data['id'] as num).toInt(),
          newPartyId: (r.data['new_party_id'] as num).toInt(),
          existingPartyId: (r.data['existing_party_id'] as num).toInt(),
          name: r.data['name'] as String? ?? '',
          newPhone: r.data['new_phone'] as String?,
          existingPhone: r.data['existing_phone'] as String?,
          reason: r.data['reason'] as String? ?? '',
          status: r.data['status'] as String? ?? 'open',
        ),
    ];
  }

  Future<void> resolvePartyDedupSuspect(int id,
      {String status = 'dismissed'}) async {
    await customStatement(
      'UPDATE party_dedup_suspects SET status = ? WHERE id = ?',
      [status, id],
    );
  }

  /// دمجُ الأطراف لاحقاً: كلُّ حجزٍ يشير إلى [fromPartyId] (طرفٌ دُمج/حُذف)
  /// يتبع الطرفَ الباقي [toPartyId]. يُستدعى من مساراتِ إزالةِ التكرار.
  /// يعيد عددَ الصفوف المُعاد توجيهها.
  Future<int> repointReservationParties(int fromPartyId, int toPartyId) async {
    if (fromPartyId == toPartyId) return 0;
    var n = 0;
    for (final t in const ['table_reservations', 'bookings']) {
      n += await customUpdate(
        'UPDATE $t SET party_id = ?, last_modified_at = ? WHERE party_id = ?',
        variables: [
          Variable<int>(toPartyId),
          Variable<int>(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          Variable<int>(fromPartyId),
        ],
        updates: {tableReservations, bookings},
      );
    }
    return n;
  }
}

/// صفٌّ من تقرير «اشتباه تكرار».
class PartyDedupSuspect {
  final int id;
  final int newPartyId;
  final int existingPartyId;
  final String name;
  final String? newPhone;
  final String? existingPhone;
  final String reason;
  final String status;

  const PartyDedupSuspect({
    required this.id,
    required this.newPartyId,
    required this.existingPartyId,
    required this.name,
    required this.newPhone,
    required this.existingPhone,
    required this.reason,
    required this.status,
  });
}

const _suspectsSqliteSql = <String>[
  '''CREATE TABLE IF NOT EXISTS party_dedup_suspects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    new_party_id INTEGER NOT NULL REFERENCES parties(id),
    existing_party_id INTEGER NOT NULL REFERENCES parties(id),
    name TEXT NOT NULL, new_phone TEXT, existing_phone TEXT,
    reason TEXT NOT NULL DEFAULT 'same_name_different_phone',
    source TEXT NOT NULL DEFAULT 'reservations_v196',
    status TEXT NOT NULL DEFAULT 'open',
    created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
    UNIQUE(new_party_id, existing_party_id))''',
  'CREATE INDEX IF NOT EXISTS idx_party_dedup_suspects_status ON party_dedup_suspects(status)',
  'CREATE INDEX IF NOT EXISTS idx_table_reservations_party ON table_reservations(party_id)',
  'CREATE INDEX IF NOT EXISTS idx_bookings_party ON bookings(party_id)',
];

const _suspectsPgSql = <String>[
  '''CREATE TABLE IF NOT EXISTS party_dedup_suspects (
    id SERIAL PRIMARY KEY,
    new_party_id INTEGER NOT NULL REFERENCES parties(id),
    existing_party_id INTEGER NOT NULL REFERENCES parties(id),
    name TEXT NOT NULL, new_phone TEXT, existing_phone TEXT,
    reason TEXT NOT NULL DEFAULT 'same_name_different_phone',
    source TEXT NOT NULL DEFAULT 'reservations_v196',
    status TEXT NOT NULL DEFAULT 'open',
    created_at BIGINT NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW())::bigint,
    UNIQUE(new_party_id, existing_party_id))''',
  'CREATE INDEX IF NOT EXISTS idx_party_dedup_suspects_status ON party_dedup_suspects(status)',
  'CREATE INDEX IF NOT EXISTS idx_table_reservations_party ON table_reservations(party_id)',
  'CREATE INDEX IF NOT EXISTS idx_bookings_party ON bookings(party_id)',
];
