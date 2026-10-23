// ═══════════════════════════════════════════════════════════════════════════
// E-fix ٢ (v186) — ساحبُ الشيك من دليل الحسابات.
// ═══════════════════════════════════════════════════════════════════════════
//
// • `commercial_papers.drawer_account_id` + `drawer_name` موجودان بعد الفتح.
// • الحفظ: الحسابُ ولقطةُ اسمه؛ والاستعلامُ يقرؤهما بمعرّف الورقة.
// • الخادم: الحمولةُ من العميل تحمل `{code, globalId}` فيُحَلّ إلى حساب الخادم.
// • المزامنة: `/api/commercial-papers` يحملهما، و`CommercialPaperSyncStrategy`
//   يكتبهما على العميل، والسحبُ العامّ (`SELECT *`) يراهما.
// • الشيكاتُ القديمة: الملاحظةُ كما هي، ولا ساحبَ يُخترَع.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';
import 'package:picpos_erp/services/sync/strategies/commercial_paper_sync_strategy.dart';

Future<({int party, int drawer})> _seed(AppDatabase db) async {
  await db.syncDefaultAccounts();
  final now = DateTime.now();
  if ((await db.select(db.fiscalYears).get()).isEmpty) {
    await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
          name: '${now.year}',
          startDate: DateTime(now.year, 1, 1),
          endDate: DateTime(now.year, 12, 31),
          isClosed: const Value(false),
        ));
  }
  final party = await db.insertParty(PartiesCompanion.insert(
    name: 'عميل الشيك',
    isCustomer: const Value(true),
    globalId: const Value('party-drawer'),
  ));
  final drawer = await db.into(db.accounts).insert(AccountsCompanion.insert(
        code: '2398',
        name: 'شركة الساحب',
        accountType: 'liability',
        accountNature: const Value('detail'),
        isSystem: const Value(false),
        globalId: const Value('acc-drawer'),
      ));
  return (party: party, drawer: drawer);
}

Future<int> _paper(AppDatabase db, int party, {String? notes}) =>
    db.createCommercialPaper(
      paperNumber: 'CH-${DateTime.now().microsecondsSinceEpoch}',
      type: 'cheque',
      direction: 'received',
      partyId: party,
      amount: 500,
      issueDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 30)),
      bankName: 'بنك',
      notes: notes,
    );

void main() {
  late AppDatabase db;
  late ({int party, int drawer}) seed;
  late int adminId;

  setUp(() async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();
    seed = await _seed(db);
    adminId = (await (db.select(db.users)..limit(1)).getSingle()).id;
  });

  tearDown(() => db.close());

  test('v186 — العمودان موجودان على commercial_papers', () async {
    final cols = {
      for (final r
          in await db.customSelect('PRAGMA table_info(commercial_papers)').get())
        r.data['name'] as String,
    };
    expect(cols, containsAll(const ['drawer_account_id', 'drawer_name']));
    expect(db.schemaVersion, greaterThanOrEqualTo(186));
  });

  test('الحفظ: الحسابُ ولقطةُ اسمه، والاستعلامُ يقرؤهما', () async {
    final id = await _paper(db, seed.party);
    await db.setCommercialPaperDrawer(id, accountId: seed.drawer);
    final drawers = await db.commercialPaperDrawers();
    expect(drawers[id], (accountId: seed.drawer, name: 'شركة الساحب'));

    // اسمٌ مكتوبٌ صراحةً يغلب اسمَ الحساب.
    await db.setCommercialPaperDrawer(id,
        accountId: seed.drawer, name: 'أحمد');
    expect((await db.commercialPaperDrawers())[id]?.name, 'أحمد');
  });

  test('🔴 الشيكُ القديم: الملاحظةُ كما هي ولا ساحبَ يُخترَع', () async {
    const legacy = 'ترحيل تلقائي من سند قبض RV1 | الساحب: أحمد';
    final id = await _paper(db, seed.party, notes: legacy);
    // لا عنصرَ يُمرَّر ⇒ لا كتابة.
    await db.setCommercialPaperDrawer(id);
    expect((await db.commercialPaperDrawers()).containsKey(id), isFalse);
    final row = await (db.select(db.commercialPapers)
          ..where((p) => p.id.equals(id)))
        .getSingle();
    expect(row.notes, legacy);
  });

  test('الخادم ← العميل: الإنشاءُ يحلّ الحساب، واللقطةُ والسحبُ يحملانه',
      () async {
    final router = ApiHandler(db).buildRouter();
    final created = await router.call(shelf.Request(
      'POST',
      Uri.parse('http://localhost/api/commercial-papers'),
      body: jsonEncode({
        'paperNumber': 'CH-SRV-1',
        'type': 'cheque',
        'direction': 'received',
        'partyId': 999, // معرّفُ العميل المحلّيّ — يُحَلّ بالمعرّف العامّ
        'partyGlobalId': 'party-drawer',
        'amount': 750,
        'issueDate': DateTime.now().toIso8601String(),
        'dueDate':
            DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        'globalId': 'cp-drawer-1',
        'drawerAccount': {'id': 4242, 'code': '2398', 'globalId': 'acc-drawer'},
      }),
      headers: {'content-type': 'application/json'},
      context: {ApiUserCtx.userIdKey: adminId},
    ));
    expect(created.statusCode, 200, reason: await created.readAsString());
    final paper = await (db.select(db.commercialPapers)
          ..where((p) => p.globalId.equals('cp-drawer-1')))
        .getSingle();
    expect((await db.commercialPaperDrawers())[paper.id],
        (accountId: seed.drawer, name: 'شركة الساحب'),
        reason: 'معرّفُ العميل 4242 لا يوجد على الخادم — يُحَلّ بالرمز/العامّ');

    // السحبُ العامّ يرى العمودَين.
    final raw = await db.customSelect(
        'SELECT * FROM commercial_papers WHERE id = ?',
        variables: [Variable<int>(paper.id)]).getSingle();
    expect(raw.data['drawer_account_id'], seed.drawer);
    expect(raw.data['drawer_name'], 'شركة الساحب');

    // لقطةُ `/api/commercial-papers` ثمّ استراتيجيّةُ العميل.
    final snap = await router.call(shelf.Request(
        'GET', Uri.parse('http://localhost/api/commercial-papers'),
        context: {ApiUserCtx.userIdKey: adminId}));
    final body = jsonDecode(await snap.readAsString()) as Map<String, dynamic>;
    final item = (body['commercial_papers'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['id'] == paper.id);
    expect(item['drawerAccountId'], seed.drawer);
    expect(item['drawerName'], 'شركة الساحب');

    final client = AppDatabase.forTesting();
    addTearDown(client.close);
    final c = await _seed(client);
    await CommercialPaperSyncStrategy(client).syncFromJson({
      'commercial_papers': [
        {...item, 'partyId': c.party, 'statusHistory': const []},
      ],
    });
    expect((await client.commercialPaperDrawers())[paper.id]?.name,
        'شركة الساحب');
  });
}
