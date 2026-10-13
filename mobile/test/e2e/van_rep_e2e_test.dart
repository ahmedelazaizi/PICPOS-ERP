// E2E تطبيق المندوب (PicPos Van): `AppController` الحقيقي + `HttpCloudApi` الحقيقي
// (HTTP فعلي) ↔ خادم السحابة الحقيقي (عملية فرعية + Postgres)، مع مخزن محلي
// في الذاكرة. الشبكة تُقطع بغلاف `SwitchApi` يرمي استثناء الشبكة (أوفلاين).
//
// يُشغَّل: `flutter test test/e2e` من مجلد mobile (يحتاج Docker Postgres على 55432
// و`dart` في PATH). انظر docs/testing/E2E.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_van/data/cloud_api.dart';
import 'package:picpos_van/data/local_store.dart';
import 'package:picpos_van/domain/sale_math.dart';
import 'package:picpos_van/state/app_controller.dart';

import 'support/e2e_cloud.dart';

/// يلفّ HttpCloudApi الحقيقي: قطع الشبكة، أو «ضياع الرد بعد وصول الدفع».
class SwitchApi implements CloudApi {
  SwitchApi() : inner = HttpCloudApi();
  final CloudApi inner;
  bool offline = false;
  bool dropPushResponse = false;
  int pushCalls = 0;

  void _gate() {
    if (offline) throw Exception('SocketException: network unreachable');
  }

  @override
  Future<({String deviceToken, String employeeGlobalId})> pair(String u, String code, String id, String name) async {
    _gate();
    return inner.pair(u, code, id, name);
  }

  @override
  Future<String> login(DeviceCredentials c, String pin) async {
    _gate();
    return inner.login(c, pin);
  }

  @override
  Future<String> rotateToken(DeviceCredentials c) async {
    _gate();
    return inner.rotateToken(c);
  }

  @override
  Future<Map<String, dynamic>> bootstrap(DeviceCredentials c, String s) async {
    _gate();
    return inner.bootstrap(c, s);
  }

  @override
  Future<Map<String, dynamic>> pull(DeviceCredentials c, String s, int since) async {
    _gate();
    return inner.pull(c, s, since);
  }

  @override
  Future<List<Map<String, dynamic>>> push(DeviceCredentials c, String s, List<Map<String, Object?>> docs) async {
    _gate();
    pushCalls++;
    final r = await inner.push(c, s, docs);
    if (dropPushResponse) throw Exception('connection reset after push');
    return r;
  }
}

void main() {
  late E2eCloud cloud;
  late Map<String, String> desk;

  setUpAll(() async {
    cloud = await E2eCloud.start(pairLimit: 100);
    desk = await cloud.desktopLink(cloud.companyA);
  });
  tearDownAll(() => cloud.stop());

  /// مندوب مقترن ومسجَّل الدخول (بدون جهاز فعلي).
  Future<(AppController, SwitchApi)> loggedInVan({DateTime Function()? clock, String pin = E2eCloud.rep1Pin}) async {
    final api = SwitchApi();
    final c = AppController(store: MemoryLocalStore(), api: api, clock: clock);
    await c.init();
    await c.pair(cloud.url, await cloud.repPairingCode(E2eCloud.demoRep1));
    await c.login(pin);
    expect(c.lastSyncError, isNull);
    return (c, api);
  }

  CartLine waterLine(AppController c, Map<String, Object?> water, {double qty = 2}) => CartLine(
      productGlobalId: water['globalId'] as String,
      name: '${water['name']}',
      unitPrice: 2.5,
      taxRate: c.taxRateOf(water),
      quantity: qty);

  Future<Map<String, Object?>> waterOf(AppController c) async =>
      (await c.products()).firstWhere((p) => p['globalId'] == E2eCloud.water);

  test('رحلة اليوم: اقتران+PIN ← مزامنة ← مستندات أوفلاين ← عودة الشبكة ← مرتجع ← المكتب يرحّل', () async {
    final api = SwitchApi();
    final c = AppController(store: MemoryLocalStore(), api: api);
    await c.init();
    expect(c.isPaired, isFalse);

    // PIN خاطئ لا يفتح، ورمز اقتران خاطئ يُترجم لخطأ التطبيق.
    await expectLater(c.pair(cloud.url, 'ZZZZZZZZ'), throwsA(isA<AppFailure>().having((e) => e.code, 'code', 'invalidPairingCode')));
    await c.pair(cloud.url, await cloud.repPairingCode(E2eCloud.demoRep1));
    expect(c.isPaired, isTrue);
    await expectLater(c.login('0000'), throwsA(isA<AppFailure>().having((e) => e.code, 'code', 'invalidPin')));
    expect(c.loggedIn, isFalse);
    await c.login(E2eCloud.rep1Pin);
    expect(c.loggedIn, isTrue);
    expect(c.lastSyncError, isNull, reason: 'الإقلاع (bootstrap) تم بعد الدخول');

    // بيانات الإقلاع وصلت من السحابة.
    final customers = (await c.routeCustomers()).map((x) => x['globalId']).toSet();
    expect(customers, containsAll([E2eCloud.cust1, E2eCloud.cust2]));
    expect(customers, isNot(contains(E2eCloud.cust3)));
    final water = await waterOf(c);
    final stock0 = await c.availableStock(E2eCloud.water);
    expect(stock0, greaterThan(10));
    expect(c.repName, isNotEmpty);

    // ── أوفلاين: بيع آجل + سند قبض + سند صرف عهدة + زيارة، كلها محلية.
    api.offline = true;
    final sale = await c.createSale(customerGlobalId: E2eCloud.cust2, lines: [waterLine(c, water)], paid: 0);
    final book = (await c.voucherBooks()).first;
    final leaf = (await c.suggestLeaf(book))!;
    final coll = await c.createCollection(customerGlobalId: E2eCloud.cust2, amount: 2, book: book, leaf: leaf);
    final payBook = (await c.paymentBooks()).single;
    final cat = (await c.expenseCategories()).first;
    final custody0 = await c.custodyBalance();
    final expense = await c.createExpense(
        categoryGlobalId: cat['globalId'] as String,
        amount: 7.5,
        book: payBook,
        leaf: (await c.suggestLeaf(payBook))!,
        note: 'وقود');
    final visit = await c.createVisit(customerGlobalId: E2eCloud.cust1, outcome: 'no_sale', noSaleReason: 'closed');
    expect(await c.custodyBalance(), closeTo(custody0! - 7.5, 1e-9), reason: 'العهدة محليًا قبل المزامنة (custody0 يتضمن سند القبض المعلّق)');
    expect(await c.pendingDocs(), hasLength(4));
    expect(await c.availableStock(E2eCloud.water), stock0 - 2, reason: 'المخزون المحلي يخصم المعلّق');

    expect(await c.syncNow(), isFalse, reason: 'لا شبكة');
    expect(c.lastSyncError, isNotNull);
    expect(await c.pendingDocs(), hasLength(4), reason: 'لا يضيع شيء أوفلاين');

    // ── عودة الشبكة: كلها تُقبل مرة واحدة.
    api.offline = false;
    expect(await c.syncNow(), isTrue, reason: '${c.lastSyncError}');
    final outbox = {for (final e in await c.store.outbox()) e.globalId: e};
    for (final e in [sale, coll, expense, visit]) {
      expect(outbox[e.globalId]!.status, OutboxStatus.accepted, reason: '${e.kind}: ${outbox[e.globalId]!.error}');
    }
    expect(await c.pendingDocs(), isEmpty);
    expect(await c.availableStock(E2eCloud.water), stock0 - 2, reason: 'الخادم خصم مرة واحدة');
    final balance = await c.effectiveBalance(E2eCloud.cust2);
    expect(balance, closeTo(5.8 - 2, 1e-9), reason: '(2×2.5+16%=5.8) − سند 2');

    // ── مرتجع أوفلاين على فاتورة مقبولة ثم مزامنة.
    expect((await c.returnableInvoices(E2eCloud.cust2)).map((i) => i['globalId']), contains(sale.globalId));
    api.offline = true;
    final ret = await c.createReturn(invoiceGlobalId: sale.globalId, quantities: {E2eCloud.water: 1}, reason: 'damaged');
    api.offline = false;
    expect(await c.syncNow(), isTrue, reason: '${c.lastSyncError}');
    expect((await c.store.outbox()).firstWhere((e) => e.globalId == ret.globalId).status, OutboxStatus.accepted);

    // ── المكتب يرى كل ما رفعه المندوب (بنوع المستند) ويرحّله.
    final pend = await cloud.call('GET', '/desktop/documents/pending', headers: desk);
    final byGid = {for (final d in pend.json['documents'] as List) (d as Map)['globalId']: d};
    for (final e in [sale, coll, expense, visit, ret]) {
      expect(byGid, contains(e.globalId), reason: 'المكتب لا يرى ${e.kind}');
      expect(byGid[e.globalId]!['kind'], e.kind);
    }
    expect(byGid[expense.globalId]!['amount'], 7.5);
    final ack = await cloud.call('POST', '/desktop/documents/ack', headers: desk, body: {
      'results': [
        for (final e in [sale, coll, expense, visit, ret])
          {'kind': e.kind, 'globalId': e.globalId, 'status': 'posted', 'desktopId': '1', 'desktopNumber': 'D-${e.kind}'},
      ],
    });
    expect(ack.status, 200, reason: '$ack');

    // ── المكتب يلغي الجهاز ← أول مزامنة تمسح البيانات المحلية وترجع لشاشة الاقتران.
    await c.createVisit(customerGlobalId: E2eCloud.cust1, outcome: 'visited');
    final devices = await cloud.call('GET', '/desktop/devices', headers: desk);
    final mine = (devices.json['devices'] as List).cast<Map>().firstWhere((d) => d['deviceId'] == c.creds!.deviceId);
    final rev = await cloud.call('POST', '/desktop/devices/${mine['deviceId']}/revoke', headers: desk);
    expect(rev.status, 200, reason: '$rev');
    expect(await c.syncNow(), isFalse);
    expect(c.isPaired, isFalse, reason: 'wipe بعد device_revoked');
    expect(await c.store.outbox(), isEmpty);
    expect(await c.routeCustomers(), isEmpty);
  });

  test('ضياع الرد بعد وصول الدفع ← إعادة المحاولة duplicate: يُقبل مرة واحدة على الخادم', () async {
    final (c, api) = await loggedInVan();
    final water = await waterOf(c);
    final stock0 = await c.availableStock(E2eCloud.water);
    final sale = await c.createSale(customerGlobalId: E2eCloud.cust1, lines: [waterLine(c, water, qty: 1)], paid: 0);
    api.dropPushResponse = true;
    expect(await c.syncNow(), isFalse);
    expect((await c.store.outbox()).single.status, OutboxStatus.pending, reason: 'لم يصل الرد');
    api.dropPushResponse = false;
    expect(await c.syncNow(), isTrue, reason: '${c.lastSyncError}');
    expect(api.pushCalls, 2);
    expect((await c.store.outbox()).single.status, OutboxStatus.accepted);
    expect(await c.availableStock(E2eCloud.water), stock0 - 1, reason: 'لا خصم مضاعف رغم إرسالين');
    final pend = await cloud.call('GET', '/desktop/documents/pending', headers: desk);
    expect((pend.json['documents'] as List).where((d) => (d as Map)['globalId'] == sale.globalId), hasLength(1));
  });

  test('رمز اقتران مستعمل ← تُرجم لخطأ مناسب ولا يقترن الجهاز الثاني', () async {
    final code = await cloud.repPairingCode(E2eCloud.demoRep1);
    final a = AppController(store: MemoryLocalStore(), api: SwitchApi());
    await a.init();
    await a.pair(cloud.url, code.toLowerCase()); // الرمز يُحوَّل للأحرف الكبيرة
    final b = AppController(store: MemoryLocalStore(), api: SwitchApi());
    await b.init();
    await expectLater(b.pair(cloud.url, code), throwsA(isA<AppFailure>()));
    expect(b.isPaired, isFalse);
  });

  test('تدوير رمز الجهاز بعد 30 يومًا ← يعمل على الخادم ولا تنقطع المزامنة', () async {
    var now = DateTime.now();
    final (c, _) = await loggedInVan(clock: () => now);
    final oldToken = c.creds!.deviceToken;
    now = now.add(const Duration(days: 31));
    expect(await c.syncNow(), isTrue, reason: '${c.lastSyncError}');
    expect(c.creds!.deviceToken, isNot(oldToken), reason: 'تم التدوير');
    expect(await c.syncNow(), isTrue, reason: 'الرمز الجديد صالح');
  });

  test('جلسة منتهية/مزوّرة ← sessionRequired، وبعد الدخول بـ PIN تعود المزامنة', () async {
    final (c, _) = await loggedInVan();
    c.session = 'garbage';
    expect(await c.syncNow(), isFalse);
    expect(c.lastSyncError, 'sessionRequired');
    expect(c.session, isNull);
    await c.login(E2eCloud.rep1Pin);
    expect(await c.syncNow(), isTrue, reason: '${c.lastSyncError}');
  });

  test('دخول بـ PIN بلا اتصال يعمل بالبصمة المحلية للـ PIN الأخير', () async {
    final (c, api) = await loggedInVan();
    await c.signOut();
    api.offline = true;
    await expectLater(c.login('9999'), throwsA(isA<AppFailure>()));
    await c.login(E2eCloud.rep1Pin);
    expect(c.loggedIn, isTrue);
    expect(c.session, isNull, reason: 'لا جلسة خادم أوفلاين فلا دفع');
  });
}