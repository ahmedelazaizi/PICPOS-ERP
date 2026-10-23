part of 'database.dart';

/// علمُ «اكتمل الربط» — يمنع إعادةَ تحويلِ الضيوفِ الجُدد (حجزٌ بهاتفٍ بلا طرف
/// بقرار المستخدم) إلى عملاءَ في كلّ إقلاع.
const String kReservationPartiesBackfillDoneKey =
    'reservation_parties_backfill_done';

/// علمُ «فشل الربطُ سابقاً — أعِد المحاولةَ عند الإقلاع». لا يُضبط على التثبيت
/// الجديد (لا حجوزاتٍ قديمة) فلا يتحوّل ضيوفُ ما بعد الترحيل إلى عملاء.
const String kReservationPartiesBackfillPendingKey =
    'reservation_parties_backfill_pending';

/// حصيلةُ الربط — تُطبَع سطراً واحداً في سجلّ الترحيل.
class ReservationPartiesBackfillResult {
  /// صفوفٌ بلا طرفٍ ولها هاتفٌ صالحٌ دخلت الربط.
  int rows = 0;
  int rowsLinkedByPhone = 0;
  int rowsLinkedByNameFilledPhone = 0;
  int partiesCreated = 0;
  int suspects = 0;

  /// صفوفٌ بلا هاتفٍ صالح: تبقى ضيوفاً (`party_id` معدوم).
  int guestRows = 0;
  int failedGroups = 0;
  String? skipped;

  /// استثناءٌ على مستوى التشغيل كلِّه (لا مجموعة بعينها).
  String? error;

  bool get failed => failedGroups > 0 || error != null;

  String toLogLine() => error != null
      ? 'reservation_parties backfill FAILED: $error (failedGroups=$failedGroups)'
      : skipped != null
      ? 'reservation_parties backfill skipped ($skipped)'
      : 'reservation_parties backfill: rows=$rows '
          'linkedByPhone=$rowsLinkedByPhone '
          'linkedByNameFilledPhone=$rowsLinkedByNameFilledPhone '
          'partiesCreated=$partiesCreated suspects=$suspects '
          'guests=$guestRows failedGroups=$failedGroups';
}

class _BfRow {
  _BfRow(this.src, this.id, this.name, this.phone);
  final String src; // 'table_reservations' | 'bookings'
  final int id;
  final String name;
  final String phone;
}

class _BfParty {
  _BfParty(this.id, this.name, this.phone);
  final int id;
  final String name;
  String? phone;
}

/// قرار المالك F.1 (2026-10-18) — لكلّ هاتفٍ فريدٍ عميلٌ بلا تكرار:
///  (أ) هاتفٌ مطابقٌ (بعد التطبيع) لعميلٍ قائم ⇒ ربطٌ بلا إنشاء؛
///  (ب) اسمٌ مطابقٌ تماماً لعميلٍ **بلا هاتف** ⇒ ربطٌ + استكمالُ هاتفه؛
///  (ج) اسمٌ مطابقٌ لعميلٍ هاتفُه مختلف ⇒ عميلٌ جديدٌ بلا دمج + سجلٌّ في
///      `party_dedup_suspects`؛
///  (د) لا مطابقة ⇒ عميلٌ جديد (عبر `insertParty` المعتاد: كودٌ وحسابٌ فرعيٌّ
///      ورصيدٌ افتتاحيٌّ صفر)؛
///  (هـ) بلا هاتف ⇒ ضيفٌ كما هو.
/// اللقطاتُ النصيّةُ لا تُمسّ. متساويةُ القوى.
extension ReservationPartiesBackfill on AppDatabase {
  Future<ReservationPartiesBackfillResult> backfillReservationParties({
    bool force = false,
  }) async {
    final res = ReservationPartiesBackfillResult();
    if (!force) {
      // العميلُ/المرآةُ يستقبلان الأطرافَ والحجوزاتِ من الخادم بالسحب؛
      // إنشاءُ أطرافٍ محلّيّةٍ هنا يزدوج معها. يُغلَق عند الفشل (A-9): إن تعذّرت
      // قراءةُ وضع الشبكة فلا إنشاءَ أطرافٍ — يُعاد المحاولة في الإقلاع التالي.
      final mode = await _bfNetworkMode();
      if (mode == null) return res..skipped = 'network mode unreadable';
      if (mode == 'client' || mode == 'mirror') return res..skipped = 'client';
      if (await getSettingValue(kReservationPartiesBackfillDoneKey) == '1') {
        return res..skipped = 'already done';
      }
    }
    try {
      await _bfRun(res);
    } catch (e, st) {
      res.error = '$e';
      debugPrint('[ReservationParties] backfill failed: $e\n$st');
    }

    if (res.failed) {
      // مرئيٌّ للمالك/الدعم؛ والعلمُ يبقى غير مضبوطٍ فيُعاد في الإقلاع التالي.
      try {
        await setSetting(kReservationPartiesBackfillPendingKey, '1');
        await DiagnosticLogger.log('RESERVATION-PARTIES-FAILED',
            '${res.toLogLine()} — will retry on next boot');
      } catch (_) {}
    } else {
      await setSetting(kReservationPartiesBackfillDoneKey, '1');
      if (await getSettingValue(kReservationPartiesBackfillPendingKey) == '1') {
        await setSetting(kReservationPartiesBackfillPendingKey, '0');
      }
    }
    debugPrint('[Migration] ${res.toLogLine()}');
    try {
      await DiagnosticLogger.log('RESERVATION-PARTIES', res.toLogLine());
    } catch (_) {}
    return res;
  }

  /// إعادةُ المحاولة عند الإقلاع (A-1): تعمل فقط إن فشلت محاولةٌ سابقةٌ
  /// (`pending`) ولم يكتمل الربط؛ المضيف/المستقلّ فقط (الحراسُ داخل الدالّة).
  /// لا ترمي أبداً (إقلاعٌ لا يتعطّل بسببها).
  Future<ReservationPartiesBackfillResult?> retryResPartiesBackfill() async {
    try {
      if (await getSettingValue(kReservationPartiesBackfillPendingKey) != '1') {
        return null;
      }
      return await backfillReservationParties();
    } catch (e) {
      debugPrint('[Startup] reservation parties backfill retry: $e');
      return null;
    }
  }

  /// `null` عند تعذّر القراءة (⇒ فشلٌ مغلق).
  Future<String?> _bfNetworkMode() async {
    try {
      return (await getSettingValue('network_mode')) ?? '';
    } catch (_) {
      return null;
    }
  }

  Future<void> _bfRun(ReservationPartiesBackfillResult res) async {
    await ensureReservationPartiesSchema();

    final rows = await _bfCollectRows(res);
    final groups = <String, List<_BfRow>>{};
    for (final r in rows) {
      groups.putIfAbsent(normalizePhone(r.phone), () => []).add(r);
    }
    res.rows = rows.length;

    final customers = await _bfLoadCustomers();
    final byPhone = <String, List<_BfParty>>{};
    final byName = <String, List<_BfParty>>{};
    for (final p in customers) {
      final pk = normalizePhone(p.phone);
      if (pk.isNotEmpty) byPhone.putIfAbsent(pk, () => []).add(p);
      final nk = normalizePersonName(p.name);
      if (nk.isNotEmpty) byName.putIfAbsent(nk, () => []).add(p);
    }

    for (final entry in groups.entries) {
      try {
        await transaction(() => _bfProcessGroup(
            entry.key, entry.value, byPhone, byName, res));
      } catch (e) {
        res.failedGroups++;
        debugPrint('[ReservationParties] group ${entry.key} failed: $e');
      }
    }
  }

  Future<List<_BfRow>> _bfCollectRows(ReservationPartiesBackfillResult res) async {
    final out = <_BfRow>[];
    for (final t in const ['table_reservations', 'bookings']) {
      final rows = await customSelect(
        'SELECT id, customer_name, customer_phone FROM $t '
        'WHERE party_id IS NULL AND deleted_at IS NULL '
        'ORDER BY created_at ASC, id ASC',
      ).get();
      for (final r in rows) {
        final phone = (r.data['customer_phone'] as String?)?.trim() ?? '';
        if (normalizePhone(phone).isEmpty) {
          res.guestRows++;
          continue;
        }
        out.add(_BfRow(t, (r.data['id'] as num).toInt(),
            (r.data['customer_name'] as String?)?.trim() ?? '', phone));
      }
    }
    return out;
  }

  Future<List<_BfParty>> _bfLoadCustomers() async {
    final rows = await customSelect(
      'SELECT id, name, phone FROM parties '
      'WHERE is_active = ${sqlBool(true)} AND is_customer = ${sqlBool(true)} '
      'AND deleted_at IS NULL '
      'AND system_role IS NULL ORDER BY id ASC',
    ).get();
    return [
      for (final r in rows)
        _BfParty((r.data['id'] as num).toInt(),
            r.data['name'] as String? ?? '', r.data['phone'] as String?),
    ];
  }

  Future<void> _bfProcessGroup(
    String phoneKey,
    List<_BfRow> group,
    Map<String, List<_BfParty>> byPhone,
    Map<String, List<_BfParty>> byName,
    ReservationPartiesBackfillResult res,
  ) async {
    final rawPhone = group.first.phone;
    // أحدثُ اسمٍ غيرِ فارغ يمثّل المجموعة (الصفوفُ مرتّبةٌ بالأقدم أولاً).
    final repName = group.lastWhere((r) => r.name.isNotEmpty,
        orElse: () => _BfRow('', 0, rawPhone, rawPhone)).name;

    int partyId;
    var byNameFill = false;
    final samePhoneParties = byPhone[phoneKey];
    if (samePhoneParties != null && samePhoneParties.isNotEmpty) {
      partyId = samePhoneParties.first.id; // (أ)
    } else {
      final nameKey = normalizePersonName(repName);
      // نسخةٌ: القائمةُ الأصل تُضاف إليها نتيجةُ الإنشاء أدناه، فلا يُسجَّل
      // الطرفُ الجديد مشتبهاً بنفسه.
      final sameName = List<_BfParty>.of(byName[nameKey] ?? const <_BfParty>[]);
      final noPhone = [
        for (final p in sameName)
          if (normalizePhone(p.phone).isEmpty) p,
      ];
      if (noPhone.length == 1) {
        // (ب) نفسُ الاسم بلا هاتف ⇒ ربطٌ واستكمالُ الهاتف.
        final p = noPhone.single;
        partyId = p.id;
        byNameFill = true;
        final filled = await customUpdate(
          'UPDATE parties SET phone = ?, last_modified_at = ? WHERE id = ? '
          "AND (phone IS NULL OR TRIM(phone) = '')",
          variables: [
            Variable<String>(rawPhone),
            Variable<int>(DateTime.now().millisecondsSinceEpoch ~/ 1000),
            Variable<int>(p.id),
          ],
          updates: {parties},
        );
        if (filled > 0) {
          // A-3: كتابةُ هاتفٍ على سجلّ عميلٍ قائمٍ بمطابقة اسمٍ فقط ⇒ أثرٌ
          // للمراجعة/التراجع. الطرفُ نفسُه على الجانبين (لا طرفَ جديد).
          final n = await customUpdate(
            'INSERT INTO party_dedup_suspects '
            '(new_party_id, existing_party_id, name, new_phone, '
            'existing_phone, reason) VALUES (?, ?, ?, ?, ?, ?) '
            'ON CONFLICT DO NOTHING',
            variables: [
              Variable<int>(p.id),
              Variable<int>(p.id),
              Variable<String>(p.name),
              Variable<String>(rawPhone),
              const Variable<String>(null),
              const Variable<String>('name_match_phone_filled'),
            ],
          );
          if (n > 0) res.suspects++;
        }
        p.phone = rawPhone;
        byPhone.putIfAbsent(phoneKey, () => []).add(p);
      } else {
        // (ج)/(د) عميلٌ جديدٌ؛ والمتشابهون بالاسم يُسجَّلون للمالك.
        partyId = await insertParty(PartiesCompanion.insert(
          name: repName.isEmpty ? rawPhone : repName,
          phone: Value(rawPhone),
          isCustomer: const Value(true),
          isActive: const Value(true),
          lastModifiedAt: Value(DateTime.now()),
        ));
        res.partiesCreated++;
        final created = _BfParty(partyId, repName, rawPhone);
        byPhone.putIfAbsent(phoneKey, () => []).add(created);
        if (nameKey.isNotEmpty) byName.putIfAbsent(nameKey, () => []).add(created);
        for (final other in sameName) {
          final ambiguous = normalizePhone(other.phone).isEmpty;
          final n = await customUpdate(
            'INSERT INTO party_dedup_suspects '
            '(new_party_id, existing_party_id, name, new_phone, '
            'existing_phone, reason) VALUES (?, ?, ?, ?, ?, ?) '
            'ON CONFLICT DO NOTHING',
            variables: [
              Variable<int>(partyId),
              Variable<int>(other.id),
              Variable<String>(repName),
              Variable<String>(rawPhone),
              Variable<String>(other.phone),
              Variable<String>(ambiguous
                  ? 'ambiguous_name_no_phone'
                  : 'same_name_different_phone'),
            ],
          );
          if (n > 0) res.suspects++;
        }
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final r in group) {
      await customUpdate(
        'UPDATE ${r.src} SET party_id = ?, last_modified_at = ? '
        'WHERE id = ? AND party_id IS NULL',
        variables: [
          Variable<int>(partyId),
          Variable<int>(now),
          Variable<int>(r.id),
        ],
        updates: {tableReservations, bookings},
      );
    }
    if (byNameFill) {
      res.rowsLinkedByNameFilledPhone += group.length;
    } else if (samePhoneParties != null && samePhoneParties.isNotEmpty) {
      res.rowsLinkedByPhone += group.length;
    }
  }
}
