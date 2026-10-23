// v196 على قاعدةٍ بشكل v195: عمودُ party_id + فهارس + جدولُ الاشتباه، ثم
// ربطُ الحجوزات القديمة بالعملاء وفق قرار المالك F.1:
//   (أ) هاتفٌ مطابقٌ ⇒ ربطٌ بلا إنشاء   (ب) اسمٌ مطابقٌ بلا هاتف ⇒ ربطٌ + استكمالُ الهاتف
//   (ج) اسمٌ مطابقٌ بهاتفٍ مختلف ⇒ عميلٌ جديدٌ + تقرير اشتباه (بلا دمج)
//   (د) لا مطابقة ⇒ عميلٌ جديد   (هـ) بلا هاتف ⇒ ضيف.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

import '../helpers/v195_reservations_db.dart';

void main() {
  late AppDatabase db;
  late int t1;
  late int svc;
  late int p1, p2, p3, supplier;
  late List<int> r; // r[1]..r[9]
  late int b1, b2;

  Future<Set<String>> cols(String t) async =>
      (await db.customSelect('PRAGMA table_info($t)').get())
          .map((e) => e.data['name'] as String)
          .toSet();

  setUp(() async {
    db = await openV195ReservationsDb();
    t1 = await insertTestTable(db, 'T1');
    svc = await insertTestServiceId(db);
    p1 = await insertTestParty(db, 'ليلى محمد', phone: '+20 100 111 2222');
    p2 = await insertTestParty(db, 'سامي علي'); // بلا هاتف
    p3 = await insertTestParty(db, 'منى حسن', phone: '01055550000');
    supplier = await insertTestParty(db, 'تاجر',
        phone: '01099990000', customer: false, supplier: true);
    Future<int> res(String n, String? p) =>
        insertTestReservation(db, t1, n, p, hasPartyColumn: false);
    r = [
      0,
      await res('ليلى', '01001112222'), // (أ)
      await res('ليلى محمد', '0100 111 2222'), // (أ) نفس المجموعة
      await res('سامي علي', '01077778888'), // (ب)
      await res('منى حسن', '01066660000'), // (ج)
      await res('زبون جديد', '01088889999'), // (د)
      await res('زبون جديد', '+20 108 888 9999'), // (د) نفس الرقم
      await res('ضيف', null), // (هـ)
      await res('ضيف٢', '123'), // (هـ) رقم غير صالح
      await res('تاجر', '01099990000'), // مورّد فقط ⇒ لا يُربط به
    ];
    b1 = await insertTestBooking(db, svc, 'ليلى', '01001112222'); // (أ)
    b2 = await insertTestBooking(db, svc, 'عميل حجز', '01012121212'); // (د)
  });

  test('مرساة سالبة: التجهيزة بلا party_id ولا جدول اشتباه', () async {
    expect((await cols('table_reservations')).contains('party_id'), isFalse);
    expect(
        await scalar(db,
            "SELECT COUNT(*) FROM sqlite_master WHERE name='party_dedup_suspects'"),
        0);
  });

  test('🔴 الترقية 195→196 تُضيف العمود والفهارس وجدول الاشتباه', () async {
    await db.runOnUpgrade(Migrator(db), 195, 196);
    expect(await cols('table_reservations'), contains('party_id'));
    final idx = (await db
            .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
            .get())
        .map((e) => e.data['name'] as String)
        .toSet();
    expect(idx, containsAll(['idx_table_reservations_party', 'idx_bookings_party']));
    expect(await cols('party_dedup_suspects'),
        containsAll(['new_party_id', 'existing_party_id', 'name', 'status']));
  });

  test('🔴 كلُّ فرعٍ من F.1 على حدة + العدّادات', () async {
    final partiesBefore = await scalar(db, 'SELECT COUNT(*) FROM parties');
    await db.runOnUpgrade(Migrator(db), 195, 196);
    final partiesAfter = await scalar(db, 'SELECT COUNT(*) FROM parties');
    Future<int?> pid(String t, int id) async =>
        (await rowOf(db, t, id))['party_id'] as int?;

    // (أ) هاتف مطابق (بعد التطبيع) ⇒ ربط بلا إنشاء، عبر الجدولين.
    expect(await pid('table_reservations', r[1]), p1);
    expect(await pid('table_reservations', r[2]), p1);
    expect(await pid('bookings', b1), p1);

    // (ب) اسم مطابق لعميل بلا هاتف ⇒ ربط + استكمال هاتفه.
    expect(await pid('table_reservations', r[3]), p2);
    expect((await rowOf(db, 'parties', p2))['phone'], '01077778888');

    // (ج) اسم مطابق وهاتف مختلف ⇒ عميل جديد ≠ p3، وتقرير اشتباه، بلا دمج.
    final newMona = await pid('table_reservations', r[4]);
    expect(newMona, isNotNull);
    expect(newMona, isNot(p3));
    expect((await rowOf(db, 'parties', p3))['phone'], '01055550000',
        reason: 'لا دمج: هاتف الطرف القائم لم يُمَسّ');
    // (A-3: فرعُ (ب) يضيف أيضاً سطراً name_match_phone_filled — يُختبر أدناه.)
    final sus = (await db.listPartyDedupSuspects())
        .where((s) => s.reason != 'name_match_phone_filled')
        .toList();
    expect(sus.length, 1,
        reason: sus.map((s) => '${s.newPartyId}->${s.existingPartyId} ${s.name} ${s.reason}').join(' | '));
    expect(sus.single.newPartyId, newMona);
    expect(sus.single.existingPartyId, p3);
    expect(sus.single.newPhone, '01066660000');
    expect(sus.single.existingPhone, '01055550000');
    expect(sus.single.reason, 'same_name_different_phone');

    // (د) لا مطابقة ⇒ عميل جديد واحد لكل رقم فريد (الصيغتان = رقم واحد).
    final fresh = await pid('table_reservations', r[5]);
    expect(fresh, isNotNull);
    expect(await pid('table_reservations', r[6]), fresh);
    final created = await rowOf(db, 'parties', fresh!);
    expect(created['name'], 'زبون جديد');
    expect(created['is_customer'], 1);
    expect(created['is_active'], 1);
    expect(created['balance'], 0);
    expect(created['global_id'], isNotNull);
    expect(created['code'], isNotNull);
    expect(created['account_id'], isNotNull,
        reason: 'الإنشاء عبر insertParty المعتاد ⇒ حسابٌ فرعيٌّ للعميل');
    expect(await pid('bookings', b2), isNotNull);

    // (هـ) بلا هاتف أو برقم غير صالح ⇒ ضيف.
    expect(await pid('table_reservations', r[7]), isNull);
    expect(await pid('table_reservations', r[8]), isNull);

    // المورّد فقط لا يُربط به حجز عميل ⇒ عميل جديد.
    final forSupplier = await pid('table_reservations', r[9]);
    expect(forSupplier, isNotNull);
    expect(forSupplier, isNot(supplier));

    // العدّ: أنشأ 4 (منى، زبون جديد، تاجر، عميل حجز) لا غير.
    expect(partiesAfter - partiesBefore, 4);
    expect(await db.getSettingValue(kReservationPartiesBackfillDoneKey), '1');
  });

  test('🔴 لا فقدانَ بيانات: اللقطاتُ النصيّة والصفوفُ كما هي', () async {
    final rowsBefore = await scalar(db, 'SELECT COUNT(*) FROM table_reservations');
    final bookingsBefore = await scalar(db, 'SELECT COUNT(*) FROM bookings');
    await db.runOnUpgrade(Migrator(db), 195, 196);
    expect(await scalar(db, 'SELECT COUNT(*) FROM table_reservations'), rowsBefore);
    expect(await scalar(db, 'SELECT COUNT(*) FROM bookings'), bookingsBefore);
    expect((await rowOf(db, 'table_reservations', r[1]))['customer_name'], 'ليلى');
    expect((await rowOf(db, 'table_reservations', r[1]))['customer_phone'],
        '01001112222');
    expect((await rowOf(db, 'table_reservations', r[6]))['customer_phone'],
        '+20 108 888 9999');
    expect((await rowOf(db, 'bookings', b2))['customer_name'], 'عميل حجز');
  });

  test('متساوية القوى: تشغيلان لا ينشئان طرفاً ولا يغيّران ربطاً', () async {
    await db.runOnUpgrade(Migrator(db), 195, 196);
    final snapshot = await scalar(db, 'SELECT COUNT(*) FROM parties');
    final linked = await scalar(
        db, 'SELECT COUNT(*) FROM table_reservations WHERE party_id IS NOT NULL');
    final suspects = (await db.listPartyDedupSuspects()).length;

    await db.runOnUpgrade(Migrator(db), 195, 196); // الترقية نفسها مرة ثانية
    expect(await scalar(db, 'SELECT COUNT(*) FROM parties'), snapshot);

    final again = await db.backfillReservationParties(force: true);
    expect(again.partiesCreated, 0);
    expect(again.rowsLinkedByPhone, 0);
    expect(again.rows, 0, reason: 'لم يبقَ حجزٌ بهاتفٍ صالح بلا طرف');
    expect(await scalar(db, 'SELECT COUNT(*) FROM parties'), snapshot);
    expect(
        await scalar(db,
            'SELECT COUNT(*) FROM table_reservations WHERE party_id IS NOT NULL'),
        linked);
    expect((await db.listPartyDedupSuspects()).length, suspects);
  });

  test('الضيفُ بهاتفٍ بعد الترحيل لا يتحوّل إلى عميل (العلم يمنع التكرار)',
      () async {
    await db.runOnUpgrade(Migrator(db), 195, 196);
    final guest = await insertTestReservation(db, t1, 'ضيف جديد', '01234567890');
    final res = await db.backfillReservationParties(); // بلا force
    expect(res.skipped, 'already done');
    expect((await rowOf(db, 'table_reservations', guest))['party_id'], isNull);
  });

  test('عميل/مرآة: لا إنشاء محلّي (الخادمُ صاحبُ الأطراف)', () async {
    await db.setSetting('network_mode', 'client');
    final before = await scalar(db, 'SELECT COUNT(*) FROM parties');
    await db.runOnUpgrade(Migrator(db), 195, 196);
    expect(await scalar(db, 'SELECT COUNT(*) FROM parties'), before);
    expect(await scalar(db, 'SELECT COUNT(*) FROM table_reservations WHERE party_id IS NOT NULL'), 0);
    expect(await cols('table_reservations'), contains('party_id'),
        reason: 'الأعمدة تُضاف على العميل أيضاً');
    expect(await db.getSettingValue(kReservationPartiesBackfillDoneKey), isNot('1'));
  });

  test('عميلان بنفس الاسم بلا هاتف ⇒ غموض: عميل جديد + اشتباه (لا اختيار عشوائي)',
      () async {
    final a = await insertTestParty(db, 'غامض');
    final b = await insertTestParty(db, 'غامض');
    final res = await insertTestReservation(db, t1, 'غامض', '01300000001',
        hasPartyColumn: false);
    await db.runOnUpgrade(Migrator(db), 195, 196);
    final pid = (await rowOf(db, 'table_reservations', res))['party_id'] as int?;
    expect(pid, isNotNull);
    expect(pid, isNot(a));
    expect(pid, isNot(b));
    final sus = await db.listPartyDedupSuspects();
    final mine = sus.where((s) => s.newPartyId == pid).toList();
    expect(mine.map((s) => s.existingPartyId).toSet(), {a, b});
    expect(mine.every((s) => s.reason == 'ambiguous_name_no_phone'), isTrue);
  });

  test('هاتفٌ مكرَّر عند عدّة عملاء ⇒ الأقدم (أقل معرّف) بشكل حتمي', () async {
    final first = await insertTestParty(db, 'نسخة١', phone: '01400000001');
    await insertTestParty(db, 'نسخة٢', phone: '+20 140 000 0001');
    final res = await insertTestReservation(db, t1, 'x', '0140 000 0001',
        hasPartyColumn: false);
    await db.runOnUpgrade(Migrator(db), 195, 196);
    expect((await rowOf(db, 'table_reservations', res))['party_id'], first);
  });

  test('A-3: فرعُ (ب) يسجّل اشتباه name_match_phone_filled للمراجعة', () async {
    await db.runOnUpgrade(Migrator(db), 195, 196);
    final rows = (await db.listPartyDedupSuspects())
        .where((s) => s.reason == 'name_match_phone_filled')
        .toList();
    expect(rows.length, 1);
    expect(rows.single.newPartyId, p2);
    expect(rows.single.existingPartyId, p2);
    expect(rows.single.newPhone, '01077778888');
    expect(rows.single.existingPhone, isNull);
    expect(rows.single.status, 'open');
  });

  group('A-1: إعادة المحاولة عند الإقلاع', () {
    Future<void> failPartyInserts() => db.customStatement(
        'CREATE TRIGGER bf_fail BEFORE INSERT ON parties BEGIN '
        "SELECT RAISE(ABORT, 'injected failure'); END");

    test('فشلُ مجموعاتٍ ⇒ العلمُ غير مضبوط + pending + سطر تشخيصٍ؛ ثم نجاحٌ عند الإقلاع',
        () async {
      await failPartyInserts();
      final first = await db.backfillReservationParties();
      expect(first.failedGroups, greaterThan(0));
      expect(first.failed, isTrue);
      expect(await db.getSettingValue(kReservationPartiesBackfillDoneKey),
          isNot('1'));
      expect(await db.getSettingValue(kReservationPartiesBackfillPendingKey),
          '1');

      await db.customStatement('DROP TRIGGER bf_fail');
      final retry = await db.retryResPartiesBackfill();
      expect(retry, isNotNull);
      expect(retry!.failedGroups, 0);
      expect(await db.getSettingValue(kReservationPartiesBackfillDoneKey), '1');
      expect(await db.getSettingValue(kReservationPartiesBackfillPendingKey),
          '0');
      expect(
          await scalar(
              db,
              'SELECT COUNT(*) FROM table_reservations '
              'WHERE party_id IS NULL AND customer_phone IS NOT NULL '
              "AND LENGTH(customer_phone) > 5"),
          0,
          reason: 'كلُّ حجزٍ بهاتفٍ صالح رُبط بعد المحاولة الثانية');
      // ثالثةٌ: لا عملَ (pending=0).
      expect(await db.retryResPartiesBackfill(), isNull);
    });

    test('بلا فشلٍ سابق لا تعمل إعادة المحاولة (الضيفُ لا يتحوّل إلى عميل)',
        () async {
      expect(await db.retryResPartiesBackfill(), isNull);
      expect(await db.getSettingValue(kReservationPartiesBackfillDoneKey),
          isNot('1'));
    });

    test('عميل/مرآة: إعادة المحاولة لا تُنشئ أطرافاً حتى مع pending', () async {
      await db.setSetting(kReservationPartiesBackfillPendingKey, '1');
      await db.setSetting('network_mode', 'mirror');
      final before = await scalar(db, 'SELECT COUNT(*) FROM parties');
      final res = await db.retryResPartiesBackfill();
      expect(res?.skipped, 'client');
      expect(await scalar(db, 'SELECT COUNT(*) FROM parties'), before);
    });

    test('A-9: تعذّر قراءة وضع الشبكة ⇒ فشلٌ مغلق (لا إنشاء)', () async {
      await db.customStatement('ALTER TABLE settings RENAME TO settings_x');
      final before = await scalar(db, 'SELECT COUNT(*) FROM parties');
      final res = await db.backfillReservationParties();
      expect(res.skipped, 'network mode unreadable');
      expect(await scalar(db, 'SELECT COUNT(*) FROM parties'), before);
    });
  });

  test('طرفٌ محذوفٌ/غير نشط لا يُختار: يُنشأ عميلٌ جديد', () async {
    final dead = await insertTestParty(db, 'محذوف', phone: '01500000001', active: false);
    final res = await insertTestReservation(db, t1, 'محذوف', '01500000001',
        hasPartyColumn: false);
    await db.runOnUpgrade(Migrator(db), 195, 196);
    final pid = (await rowOf(db, 'table_reservations', res))['party_id'] as int?;
    expect(pid, isNotNull);
    expect(pid, isNot(dead));
  });
}
