import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_van/data/local_store.dart';
import 'package:picpos_van/domain/sale_math.dart' show CartLine;
import 'package:picpos_van/geo/geo_capture.dart';
import 'package:picpos_van/l10n/strings.dart';
import 'package:picpos_van/printing/receipt_composer.dart';
import 'package:picpos_van/screens/common.dart';
import 'package:picpos_van/screens/expense_screen.dart';
import 'package:picpos_van/screens/location_permission.dart';
import 'package:picpos_van/state/app_controller.dart';
import 'package:picpos_van/sync/background_worker.dart';

import 'support/fakes.dart';

/// K-1 expense payload as the cloud sends it (bootstrap/pull additions).
Map<String, dynamic> expenseFixture({double? custody = 50, String policy = 'flag'}) => {
      'expenseCategories': [
        {'globalId': 'ec2', 'name': 'تنزيل', 'nameEn': 'Porters', 'sortOrder': 1, 'active': true},
        {'globalId': 'ec1', 'name': 'وقود', 'nameEn': 'Fuel', 'sortOrder': 0, 'active': true},
      ],
      'expenseCategoryScope': ['ec1', 'ec2'],
      'paymentBooks': [
        {'globalId': 'pb1', 'bookType': 'payment', 'prefix': 'P-', 'label': 'دفتر صرف', 'rangeFrom': 5001,
         'rangeTo': 5010, 'nextNumber': 5001, 'status': 'active', 'usedNumbers': [5001], 'cancelledNumbers': []},
      ],
      'paymentBookScope': ['pb1'],
      'custodyBalance': custody,
      'expenseOverCustody': policy,
    };

class FakeGeoProvider implements GeoProvider {
  FakeGeoProvider({this.perm = GeoPermission.granted, this.fix, this.hang = false});
  GeoPermission perm;
  GeoFix? fix;
  bool hang;
  int requests = 0;

  @override
  Future<GeoPermission> permission() async => perm;
  @override
  Future<GeoPermission> request() async {
    requests++;
    perm = GeoPermission.granted;
    return perm;
  }

  @override
  Future<GeoFix?> currentFix(Duration timeout) {
    if (hang) return Completer<GeoFix?>().future; // never answers
    return Future.value(fix);
  }
}

final _fix = GeoFix(lat: 31.95, lng: 35.91, accuracy: 7.5, at: DateTime.utc(2026, 5, 1, 7, 59));

Future<(AppController, FakeCloudApi)> _ready({double? custody = 50, String policy = 'flag', GeoProvider? geo}) async {
  final (c, api) = await readyController();
  await c.applyServerPayload(expenseFixture(custody: custody, policy: policy));
  if (geo != null) c.geo = GeoCapture(geo, timeout: const Duration(milliseconds: 50));
  return (c, api);
}

void main() {
  group('K-1 expense', () {
    test('categories, payment book and custody arrive; expense queued with the next free payment leaf', () async {
      final (c, _) = await _ready();
      expect((await c.expenseCategories()).map((x) => x['globalId']), ['ec1', 'ec2']);
      final book = (await c.paymentBooks()).single;
      expect(await c.suggestLeaf(book), 5002); // 5001 used on the server
      expect(await c.custodyBalance(), 50.0);

      final e = await c.createExpense(categoryGlobalId: 'ec1', amount: 12.5, book: book, leaf: 5002, note: ' محطة ');
      expect(e.kind, kExpenseKind);
      expect(e.payload['kind'], 'expense');
      expect(e.payload['categoryGlobalId'], 'ec1');
      expect(e.payload['amount'], 12.5);
      expect(e.payload['note'], 'محطة');
      expect(e.payload['bookGlobalId'], 'pb1');
      expect(e.payload['bookNumber'], 5002);
      expect(e.payload['_overCustody'], false);
      expect(e.payload['_custodyAfter'], 37.5);
      expect((await c.pendingDocs()).single.globalId, e.globalId);
      // The pending expense takes the leaf and the custody.
      expect(await c.suggestLeaf(book), 5003);
      expect(await c.custodyBalance(), 37.5);
      expect(() => c.createExpense(categoryGlobalId: 'ec1', amount: 1, book: book, leaf: 5002),
          throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'leafInvalid')));
      expect(() => c.createExpense(categoryGlobalId: 'ec1', amount: 1, book: book, leaf: 4999),
          throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'leafInvalid')));
      expect(() => c.createExpense(categoryGlobalId: 'nope', amount: 1, book: book, leaf: 5003),
          throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'categoryRequired')));
      expect(() => c.createExpense(categoryGlobalId: 'ec1', amount: 0, book: book, leaf: 5003),
          throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'amount')));
    });

    test('custody: cash sales and collections add, flag by default, reject by policy', () async {
      final (c, _) = await _ready(custody: 10);
      await c.createSale(
          customerGlobalId: 'c2', lines: [CartLine(productGlobalId: 'p2', name: 'خبز', quantity: 2, unitPrice: 1, taxRate: 0)], paid: 2);
      expect(await c.custodyBalance(), 12.0);
      final book = (await c.paymentBooks()).single;
      final flagged = await c.createExpense(categoryGlobalId: 'ec1', amount: 20, book: book, leaf: 5002);
      expect(flagged.payload['_overCustody'], true);
      expect(flagged.payload['_custodyAfter'], -8.0);

      final (r, _) = await _ready(custody: 10, policy: 'reject');
      final rb = (await r.paymentBooks()).single;
      expect(() => r.createExpense(categoryGlobalId: 'ec1', amount: 20, book: rb, leaf: 5002),
          throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'custodyExceeded')));
      // No custody known (desktop never sent one): no check possible.
      final (u, _) = await _ready(custody: null, policy: 'reject');
      expect(await u.custodyBalance(), isNull);
      final ub = (await u.paymentBooks()).single;
      expect((await u.createExpense(categoryGlobalId: 'ec1', amount: 999, book: ub, leaf: 5002)).payload['_overCustody'],
          false);
    });

    test('push sends the receipt photo as base64 JPEG, never device-only keys; oversized photo is left out', () async {
      final photos = {
        '/p/ok.jpg': [0xFF, 0xD8, 1, 2, 3],
        '/p/big.jpg': List<int>.filled(kMaxExpensePhotoBytes + 1, 1),
      };
      final api = FakeCloudApi();
      final c = AppController(
          store: MemoryLocalStore(), api: api, clock: () => DateTime(2026, 5, 1, 10), readPhoto: (p) async => photos[p]);
      await c.init();
      await c.pair('http://test', 'ABCDEFGH');
      await c.login('1234');
      await c.applyServerPayload(expenseFixture());
      final book = (await c.paymentBooks()).single;
      final a = await c.createExpense(categoryGlobalId: 'ec1', amount: 1, book: book, leaf: 5002, photoPath: '/p/ok.jpg');
      final b = await c.createExpense(categoryGlobalId: 'ec2', amount: 2, book: book, leaf: 5003, photoPath: '/p/big.jpg');
      api.pushed.clear();
      expect(await c.syncNow(), isTrue);
      final docs = api.pushed.expand((x) => x).toList();
      final wa = docs.singleWhere((d) => d['globalId'] == a.globalId);
      expect(wa['photo'], {'mime': 'image/jpeg', 'data': base64.encode(photos['/p/ok.jpg']!)});
      expect(wa.keys.where((k) => k.startsWith('_')), isEmpty);
      expect(docs.singleWhere((d) => d['globalId'] == b.globalId).containsKey('photo'), isFalse);
      expect((await c.store.outbox()).every((e) => e.status == OutboxStatus.accepted), isTrue);
    });

    test('large documents are split into ≤ 3 MB push requests', () async {
      final photo = List<int>.filled(900 * 1024, 7);
      final api = FakeCloudApi();
      final c = AppController(
          store: MemoryLocalStore(), api: api, clock: () => DateTime(2026, 5, 1, 10), readPhoto: (_) async => photo);
      await c.init();
      await c.pair('http://test', 'ABCDEFGH');
      await c.login('1234');
      await c.applyServerPayload(expenseFixture(custody: 1000));
      final book = (await c.paymentBooks()).single;
      for (var leaf = 5002; leaf <= 5006; leaf++) {
        await c.createExpense(categoryGlobalId: 'ec1', amount: 1, book: book, leaf: leaf, photoPath: '/x.jpg');
      }
      api.pushed.clear();
      expect(await c.syncNow(), isTrue);
      expect(api.pushed.length, greaterThan(1));
      for (final batch in api.pushed) {
        expect(jsonEncode(batch).length, lessThanOrEqualTo(AppController.kMaxPushBytes + 1024 * 1024));
      }
      expect(api.pushed.expand((b) => b).length, 5);
    });

    test('printable expense voucher (58/80 shared model) in Arabic and English', () async {
      final (c, _) = await _ready(custody: 5);
      expect(kPrintableKinds, contains('expense'));
      final book = (await c.paymentBooks()).single;
      final e = await c.createExpense(categoryGlobalId: 'ec1', amount: 12.5, book: book, leaf: 5002, note: 'محطة');
      final ar = await ReceiptComposer(c).compose(e);
      expect(ar.kind, 'expense');
      expect(ar.number, 'P-5002');
      expect(ar.texts, contains('سند صرف'));
      expect(ar.valueOf('بند المصروف'), 'وقود');
      expect(ar.valueOf('البيان'), 'محطة');
      expect(ar.valueOf('المبلغ'), '12.50');
      expect(ar.valueOf('صُرف من عهدة'), 'مندوب ١');
      expect(ar.valueOf('رصيد العهدة بعد الصرف'), '-7.50');
      expect(ar.texts, contains('تجاوز العهدة'));
      expect(ar.barcode?.data, 'P-5002');
      final en = await ReceiptComposer(c).compose(e, locale: 'en', reprint: true);
      expect(en.texts, contains('Payment Voucher'));
      expect(en.valueOf('Expense'), 'Fuel');
      expect(en.texts, contains('REPRINT'));
    });

    testWidgets('expense screen: category, amount, photo, save → outbox', (tester) async {
      final (c, _) = await _ready(custody: 5);
      await tester.pumpWidget(AppScope(
        controller: c,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: S.supported,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                    builder: (_) => ExpenseScreen(takePhoto: (_) async => '/receipts/1.jpg'))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('وقود'), findsOneWidget);
      expect(find.text('5002'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('expenseAmount')), '7');
      await tester.pump();
      expect(find.byKey(const Key('overCustodyWarning')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('expenseNote')), 'عتالة السوق');
      await tester.tap(find.byKey(const Key('takePhoto')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('saveExpense')));
      await tester.tap(find.byKey(const Key('saveExpense')));
      await tester.pumpAndSettle();
      final e = (await c.pendingDocs()).single;
      expect(e.kind, 'expense');
      expect(e.payload['amount'], 7.0);
      expect(e.payload['note'], 'عتالة السوق');
      expect(e.payload['_photoPath'], '/receipts/1.jpg');
      expect(e.payload['_overCustody'], true);
      expect(find.text('open'), findsOneWidget); // back on the previous page
    });
  });

  group('K-3 GPS', () {
    test('granted: visit and documents carry lat/lng/accuracy/time', () async {
      final (c, _) = await _ready(geo: FakeGeoProvider(fix: _fix));
      final v = await c.createVisit(customerGlobalId: 'c1', outcome: 'visited');
      expect(v.payload['latitude'], 31.95);
      expect(v.payload['longitude'], 35.91);
      expect(v.payload['geo'],
          {'status': 'ok', 'lat': 31.95, 'lng': 35.91, 'accuracy': 7.5, 'at': '2026-05-01T07:59:00.000Z'});
      final sale = await c.createSale(
          customerGlobalId: 'c2', lines: [CartLine(productGlobalId: 'p2', name: 'خبز', quantity: 1, unitPrice: 1, taxRate: 0)], paid: 1);
      expect((sale.payload['geo'] as Map)['status'], 'ok');
      final book = (await c.voucherBooks()).single;
      final col = await c.createCollection(customerGlobalId: 'c1', amount: 5, book: book, leaf: 1003);
      expect((col.payload['geo'] as Map)['lat'], 31.95);
      final exp = await c.createExpense(
          categoryGlobalId: 'ec1', amount: 1, book: (await c.paymentBooks()).single, leaf: 5002);
      expect((exp.payload['geo'] as Map)['accuracy'], 7.5);
    });

    test('denied, location off and no fix in time: saved without GPS and marked', () async {
      final denied = FakeGeoProvider(perm: GeoPermission.denied);
      final (c, _) = await _ready(geo: denied);
      final v = await c.createVisit(customerGlobalId: 'c1', outcome: 'no_sale', noSaleReason: 'closed');
      expect(v.payload['geo'], {'status': 'denied'});
      expect(v.payload.containsKey('latitude'), isFalse);

      denied.perm = GeoPermission.serviceOff;
      expect((await c.createVisit(customerGlobalId: 'c2', outcome: 'visited')).payload['geo'], {'status': 'unavailable'});

      final hang = FakeGeoProvider(hang: true);
      c.geo = GeoCapture(hang, timeout: const Duration(milliseconds: 30));
      final sw = Stopwatch()..start();
      final t = await c.createVisit(customerGlobalId: 'c2', outcome: 'visited');
      expect(t.payload['geo'], {'status': 'timeout'});
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));

      c.geo = GeoCapture(FakeGeoProvider(), timeout: const Duration(milliseconds: 30)); // granted, no fix
      expect((await c.createVisit(customerGlobalId: 'c2', outcome: 'visited')).payload['geo'], {'status': 'timeout'});
    });

    test('no location support (tests / old builds): payloads carry no geo', () async {
      final (c, _) = await readyController();
      final v = await c.createVisit(customerGlobalId: 'c1', outcome: 'visited');
      expect(v.payload.containsKey('geo'), isFalse);
    });

    testWidgets('rationale first, then the OS prompt; once a day; never when already granted', (tester) async {
      final (c, _) = await _ready();
      final provider = FakeGeoProvider(perm: GeoPermission.denied);
      c.geo = GeoCapture(provider);
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: S.supported,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(builder: (context) {
          ctx = context;
          return const Scaffold();
        }),
      ));
      final day = DateTime(2026, 5, 1, 8);
      final asked = askLocationIfNeeded(ctx, c, clock: () => day);
      await tester.pumpAndSettle();
      expect(find.textContaining('confirm the visit'), findsOneWidget);
      await tester.tap(find.byKey(const Key('allowLocation')));
      await tester.pumpAndSettle();
      await asked;
      expect(provider.requests, 1);

      provider.perm = GeoPermission.denied; // refused at the OS prompt
      unawaited(askLocationIfNeeded(ctx, c, clock: () => day));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('allowLocation')), findsNothing); // not twice the same day

      provider.perm = GeoPermission.granted;
      unawaited(askLocationIfNeeded(ctx, c, clock: () => day.add(const Duration(days: 1))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('allowLocation')), findsNothing);
    });
  });

  group('K-2 background sync', () {
    test('the session survives a restart (encrypted store) for the background worker', () async {
      final store = MemoryLocalStore();
      final api = FakeCloudApi();
      final c = AppController(store: store, api: api, clock: () => DateTime(2026, 5, 1, 10));
      await c.init();
      await c.pair('http://test', 'ABCDEFGH');
      await c.login('1234');
      final again = AppController(store: store, api: api);
      await again.init();
      expect(again.session, 'session');
      expect(again.loggedIn, isFalse); // the UI still asks for the PIN
      again.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(await store.getKv('session'), isNull);
    });

    test('worker pushes pending documents then pulls, exactly once per document', () async {
      final (c, api) = await _ready();
      final book = (await c.paymentBooks()).single;
      final e = await c.createExpense(categoryGlobalId: 'ec1', amount: 3, book: book, leaf: 5002);
      api.pushed.clear();
      expect(await runBackgroundSync(() async => c, clock: () => DateTime(2026, 5, 1, 10, 1)), isTrue);
      expect(api.pushed.expand((b) => b).map((d) => d['globalId']), [e.globalId]);
      expect((await c.store.outbox()).single.status, OutboxStatus.accepted);
      // A second run (app open or another worker) never re-sends it.
      api.pushed.clear();
      expect(await runBackgroundSync(() async => c, clock: () => DateTime(2026, 5, 1, 11)), isTrue);
      expect(api.pushed, isEmpty);
    });

    test('idle outbox: no work within 15 min of the last sync, a pull after', () async {
      final (c, api) = await _ready();
      final last = c.lastSync!;
      api.pullPayload = {'serverTime': 3000};
      final bootstraps = api.bootstraps;
      expect(await runBackgroundSync(() async => c, clock: () => last.add(const Duration(minutes: 5))), isTrue);
      expect(await c.store.getKv('watermark'), isNot('3000')); // skipped: synced 5 min ago
      expect(await runBackgroundSync(() async => c, clock: () => last.add(const Duration(minutes: 16))), isTrue);
      expect(await c.store.getKv('watermark'), '3000'); // pulled (delta, not a new bootstrap)
      expect(api.bootstraps, bootstraps);
    });

    test('failures: network error → retry (false); expired session or unpaired → no retry', () async {
      final (c, api) = await _ready();
      await c.createVisit(customerGlobalId: 'c1', outcome: 'visited');
      api.offline = true;
      expect(await runBackgroundSync(() async => c), isFalse);
      api.offline = false;
      api.failWith = 'invalid_session';
      expect(await runBackgroundSync(() async => c), isTrue);
      expect(c.session, isNull);
      expect(await runBackgroundSync(() async => c), isTrue); // nothing to do without a session

      final fresh = AppController(store: MemoryLocalStore(), api: FakeCloudApi());
      await fresh.init();
      expect(await runBackgroundSync(() async => fresh), isTrue);
    });
  });
}
