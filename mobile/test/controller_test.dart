import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_van/data/local_store.dart';
import 'package:picpos_van/domain/sale_math.dart';
import 'package:picpos_van/l10n/strings.dart';
import 'package:picpos_van/state/app_controller.dart';

import 'support/fakes.dart';

CartLine water(double q) => CartLine(productGlobalId: 'p1', name: 'water', unitPrice: 2.5, taxRate: 16, quantity: q);

void main() {
  test('admin-app code and other server pairing rejections show specific AR/EN messages', () async {
    const cases = [
      ('invalid_code', 'invalidPairingCode', 'رمز الربط غير صحيح أو مخصّص لتطبيق آخر', 'Invalid pairing code, or it belongs to another app'),
      ('code_expired', 'pairingCodeExpired', 'انتهت صلاحية رمز الربط — اطلب رمزاً جديداً', 'Pairing code expired, ask for a new one'),
      ('too_many_attempts', 'pairingTooManyAttempts', 'محاولات كثيرة، انتظر قليلاً ثم أعد المحاولة', 'Too many attempts, wait and retry'),
      ('invalid_request', 'invalidPairingRequest', 'تحقّق من الرمز (٨ خانات) وعنوان الخادم', 'Check the 8-character code and server address'),
      ('other_server_error', 'pairingRejected', 'رفض الخادم طلب الربط', 'Server rejected the pairing request'),
    ];
    for (final (serverCode, key, arabic, english) in cases) {
      final api = FakeCloudApi()..failWith = serverCode;
      final controller = AppController(store: MemoryLocalStore(), api: api);
      await expectLater(
        controller.pair('http://test', 'ABCDEFGH'),
        throwsA(isA<AppFailure>()
            .having((failure) => failure.code, 'code', key)
            .having((failure) => failure.detail, 'detail', serverCode)),
      );
      expect(S(const Locale('ar')).t(key), arabic);
      expect(S(const Locale('en')).t(key), english);
      expect(controller.creds, isNull);
    }
  });

  test('unreachable server retains the connection error during pairing', () async {
    final api = FakeCloudApi()..offline = true;
    final controller = AppController(store: MemoryLocalStore(), api: api);
    await expectLater(controller.pair('http://test', 'ABCDEFGH'), throwsA(isNot(isA<AppFailure>())));
    expect(S(const Locale('ar')).t('error'), 'تعذّر الاتصال بالخادم');
    expect(controller.creds, isNull);
  });

  test('totals use the shared tax rule (exempt = 0)', () {
    expect(effectiveItemTaxRate(rate: 16, exempt: true, companyDefault: 16), 0);
    expect(effectiveItemTaxRate(rate: 0, exempt: false, companyDefault: 16), 16);
    final t = cartTotals([water(2), CartLine(productGlobalId: 'p2', name: 'b', unitPrice: 1, taxRate: 0, quantity: 3)]);
    expect((t.subtotal, t.tax, t.total), (8.0, 0.8, 8.8));
  });

  test('login bootstraps; sale takes leased numbers and deducts pending van stock', () async {
    final (c, api) = await readyController();
    expect(api.bootstraps, 1);
    expect((await c.routeCustomers()).map((x) => x['globalId']), ['c1', 'c2']);
    final e1 = await c.createSale(customerGlobalId: 'c2', lines: [water(2)], paid: 5.8);
    final e2 = await c.createSale(customerGlobalId: 'c2', lines: [water(1)], paid: 0);
    expect(e1.payload['number'], 'VS-100000');
    expect(e2.payload['number'], 'VS-100001');
    expect(await c.availableStock('p1'), 2.0);
    expect(await c.effectiveBalance('c2'), 2.9);
    expect(await c.visitedToday('c2'), isTrue);
    expect(await c.visitedToday('c1'), isFalse);
  });

  test('offline rules: van stock and credit limit block the sale', () async {
    final (c, _) = await readyController();
    await expectLater(() => c.createSale(customerGlobalId: 'c2', lines: [water(6)], paid: 100),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'insufficientStock')));
    // c1: balance 90, limit 100 → 4 water on credit = 11.6 exceeds
    await expectLater(() => c.createSale(customerGlobalId: 'c1', lines: [water(4)], paid: 0),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'creditExceeded')));
    await c.createSale(customerGlobalId: 'c1', lines: [water(4)], paid: 11.6);
  });

  test('voucher-book leaf suggestion skips used/cancelled and pending leaves', () async {
    final (c, _) = await readyController();
    final book = (await c.voucherBooks()).single;
    expect(await c.suggestLeaf(book), 1003);
    await c.createCollection(customerGlobalId: 'c1', amount: 10, book: book, leaf: 1003);
    expect(await c.suggestLeaf(book), 1004);
    await expectLater(() => c.createCollection(customerGlobalId: 'c1', amount: 10, book: book, leaf: 1003),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', 'leafInvalid')));
    await expectLater(() => c.createCollection(customerGlobalId: 'c1', amount: 10, book: book, leaf: 2000),
        throwsA(isA<AppFailure>()));
    expect(await c.effectiveBalance('c1'), 80.0);
  });

  test('sync pushes the outbox once and records server results; pull keeps local lease ahead', () async {
    final (c, api) = await readyController();
    await c.createSale(customerGlobalId: 'c2', lines: [water(1)], paid: 2.9);
    await c.createCollection(customerGlobalId: 'reject-me', amount: 5, book: (await c.voucherBooks()).single, leaf: 1003);
    api.pullPayload = {
      'serverTime': 2000,
      'leases': [
        {'globalId': 'l1', 'docType': 'sales_invoice', 'prefix': 'VS-', 'rangeFrom': 100000, 'rangeTo': 100499,
         'nextNumber': 100000, 'status': 'active'},
      ],
    };
    await c.syncNow();
    expect(api.pushed.single, hasLength(2));
    final ob = await c.store.outbox();
    expect(ob.map((e) => e.status), [OutboxStatus.accepted, OutboxStatus.rejected]);
    expect(ob.last.error, 'customer_not_on_route');
    await c.syncNow();
    expect(api.pushed, hasLength(1), reason: 'nothing pending → no second push');
    final next = await c.createSale(customerGlobalId: 'c2', lines: [water(1)], paid: 2.9);
    expect(next.payload['number'], 'VS-100001');
  });
}
