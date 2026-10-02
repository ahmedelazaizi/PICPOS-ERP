part of 'database.dart';

/// v186 — ساحبُ الشيك (E-fix ٢): `commercial_papers.drawer_account_id` +
/// `drawer_name`.
///
/// • الشيكُ الوارد: **الساحب** — حسابٌ من دليل الحسابات (منتقي المرحلة هـ).
/// • الشيكُ الصادر: **المستفيد** حين يختلف عن طرف السند.
/// • `drawer_name` لقطةٌ من اسم الحساب وقتَ الحفظ — ليقرأها الاستعلامُ ولو
///   أُعيدت تسميةُ الحساب أو حُذف.
///
/// Raw SQL outside Drift's table model (no codegen run), following
/// [ensureDistributionModelSchema]. Travels by the generic `SELECT *` delta
/// pull (the columns ride `commercial_papers`), by the `/api/commercial-papers`
/// snapshot and by the client create payload.
///
/// ⚠️ الشيكاتُ القديمة لا تُمَسّ: من حفظ الساحبَ نصّاً في الملاحظات يبقى
///    هناك كما هو — لا ترحيلَ ولا إعادةَ كتابة.
extension ChequeDrawerSchema on AppDatabase {
  Future<void> ensureChequeDrawerSchema() async {
    for (final column in const [
      'drawer_account_id INTEGER',
      'drawer_name TEXT',
    ]) {
      final name = column.split(' ').first;
      if (_isPostgres) {
        await customStatement(
            'ALTER TABLE commercial_papers ADD COLUMN IF NOT EXISTS $column');
        continue;
      }
      final existing =
          await customSelect('PRAGMA table_info(commercial_papers)').get();
      if (existing.any((c) => c.data['name'] == name)) continue;
      try {
        await customStatement(
            'ALTER TABLE commercial_papers ADD COLUMN $column');
      } catch (error) {
        if (!isIdempotentMigrationError(error.toString())) rethrow;
      }
    }
  }

  /// Stamps paper [paperId] with its drawer/payee account. [name] defaults to
  /// the account's own name (the snapshot); both `null` clears nothing.
  Future<void> setCommercialPaperDrawer(
    int paperId, {
    int? accountId,
    String? name,
  }) async {
    var snapshot = name?.trim();
    if ((snapshot == null || snapshot.isEmpty) && accountId != null) {
      snapshot = (await accountingDao.getAccountById(accountId))?.name;
    }
    if (accountId == null && (snapshot == null || snapshot.isEmpty)) return;
    await customUpdate(
      'UPDATE commercial_papers SET drawer_account_id = ?, drawer_name = ?, '
      'last_modified_at = ? WHERE id = ?',
      variables: [
        Variable<int>(accountId),
        Variable<String>(snapshot),
        Variable<DateTime>(DateTime.now()),
        Variable<int>(paperId),
      ],
      updates: {commercialPapers},
    );
  }

  /// Every paper's drawer, keyed by paper id (papers without one are absent).
  Future<Map<int, ({int? accountId, String? name})>>
      commercialPaperDrawers() async {
    final rows = await customSelect(
      'SELECT id, drawer_account_id, drawer_name FROM commercial_papers '
      'WHERE drawer_account_id IS NOT NULL OR drawer_name IS NOT NULL',
      readsFrom: {commercialPapers},
    ).get();
    return {
      for (final r in rows)
        (r.data['id'] as num).toInt(): (
          accountId: (r.data['drawer_account_id'] as num?)?.toInt(),
          name: r.data['drawer_name'] as String?,
        ),
    };
  }
}
