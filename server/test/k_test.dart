@Tags(['postgres'])
library;

import 'dart:convert';

import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'support/harness.dart';

/// Owner decisions K: rep expense (payment) vouchers from the custody safe
/// and the field GPS stamp on documents.
const _uuid = Uuid();

/// Smallest byte string the gate accepts as a JPEG (SOI marker + payload).
String _jpeg(int size) => base64.encode([0xFF, 0xD8, ...List<int>.filled(size - 2, 7)]);

void main() {
  late Harness h;
  late Map<String, String> desk;
  late RepDevice rep;
  setUp(() async {
    h = await Harness.start();
    final (st, b) = await h.call('POST', '/admin/desktop-links',
        headers: {'x-admin-key': Harness.adminKey}, body: {'companyGlobalId': Demo.companyGid});
    expect(st, 201, reason: '$b');
    desk = {'authorization': 'Bearer ${b['linkSecret']}', 'x-desktop-link': b['linkId'] as String};
    rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
  });
  tearDown(() async => h.stop());

  Future<List<Map<String, dynamic>>> push(List<Map<String, Object?>> docs, {RepDevice? d}) async {
    final (st, b) = await h.call('POST', '/mobile/sync/push', headers: (d ?? rep).headers, body: {'documents': docs});
    expect(st, 200, reason: '$b');
    return (b['results'] as List).cast<Map<String, dynamic>>();
  }

  Map<String, Object?> expense(int leaf, double amount,
          {String? gid, String book = Demo.payBook1Gid, String category = Demo.expFuelGid, Object? photo, Object? geo}) =>
      {
        'kind': 'expense',
        'globalId': gid ?? _uuid.v4(),
        'date': '2026-05-01T08:30:00.000Z',
        'categoryGlobalId': category,
        'amount': amount,
        'note': 'محطة الشمال',
        'bookGlobalId': book,
        'bookNumber': leaf,
        'photo': ?photo,
        'geo': ?geo,
      };

  List<Object?> codes(List<Map<String, dynamic>> r) =>
      [for (final x in r) x['status'] == 'accepted' ? 'ok' : x['code']];

  group('bootstrap', () {
    test('carries expense categories, the payment book, custody balance and policy', () async {
      final (st, b) = await h.call('GET', '/mobile/bootstrap', headers: rep.headers);
      expect(st, 200, reason: '$b');
      final cats = (b['expenseCategories'] as List).cast<Map>();
      expect(cats.map((c) => c['name']).take(2), ['وقود', 'تنزيل/عتالة']);
      expect(cats.first['nameEn'], 'Fuel');
      expect((b['expenseCategoryScope'] as List).length, 6);
      final books = (b['paymentBooks'] as List).cast<Map>();
      expect(books.single['globalId'], Demo.payBook1Gid);
      expect(books.single['bookType'], 'payment');
      expect(books.single['rangeFrom'], 5001);
      expect(b['paymentBookScope'], [Demo.payBook1Gid]);
      expect(b['custodyBalance'], Demo.rep1CustodyBalance);
      expect(b['expenseOverCustody'], 'flag');
      // Receipt books are unchanged (no payment book among them).
      expect((b['voucherBooks'] as List).map((x) => x['globalId']), [Demo.book1Gid]);
    });

    test('rep2 holds no payment book and no custody balance from the desktop yet', () async {
      final rep2 = await h.repDevice(Demo.rep2Gid, Demo.rep2Pin);
      final (_, b) = await h.call('GET', '/mobile/bootstrap', headers: rep2.headers);
      expect(b['paymentBooks'], isEmpty);
      expect(b['custodyBalance'], isNull);
    });
  });

  group('push', () {
    test('accepted expense is a custody payment with the book leaf; replay is idempotent', () async {
      final doc = expense(5001, 12.5, photo: {'mime': 'image/jpeg', 'data': _jpeg(2048)});
      final r = await push([doc, doc]);
      expect(r[0]['status'], 'accepted', reason: '${r[0]}');
      expect(r[0]['number'], 'P-5001');
      expect(r[0]['overCustody'], false);
      expect(r[0]['custodyBalance'], 87.5);
      expect(r[1]['status'], 'duplicate');
      expect(r[1]['number'], 'P-5001');

      final rows = await h.db.query('''
        SELECT st.transaction_type, st.amount, st.book_number, st.voucher_number, ec.global_id, st.note,
               st.doc_date, sf.id = rr.custody_safe_id
        FROM safe_transactions st
        JOIN expense_categories ec ON ec.id = st.expense_category_id
        JOIN rep_resources rr ON rr.employee_id = st.rep_employee_id
        JOIN safes sf ON sf.id = st.safe_id
        WHERE st.global_id=@g''', {'g': doc['globalId']});
      expect(rows.length, 1);
      final m = rows.first;
      expect(m[0], 'payment');
      expect(num0(m[1]), 12.5);
      expect(m[2], 5001);
      expect(m[3], 'P-5001');
      expect(m[4], Demo.expFuelGid);
      expect(m[5], 'محطة الشمال');
      expect(m[6], '2026-05-01T08:30:00.000Z');
      expect(m[7], true);
      final book = await h.db.query('SELECT next_number FROM voucher_books WHERE global_id=@g', {'g': Demo.payBook1Gid});
      expect(book.first[0], 5002);
      final photo = await h.db.query(
          'SELECT size_bytes FROM field_attachments WHERE document_global_id=@g', {'g': doc['globalId']});
      expect(photo.first[0], 2048);
      // The pull marks it accepted for the device.
      final (_, pull) = await h.call('GET', '/mobile/sync/pull?since=0', headers: rep.headers);
      expect((pull['documents'] as List).where((d) => d['kind'] == 'expense').single['number'], 'P-5001');
    });

    test('book rules: used leaf, out of range, receipt book, other rep, missing category', () async {
      final r = await push([
        expense(5001, 1),
        expense(5001, 1),
        expense(5100, 1),
        expense(1001, 1, book: Demo.book1Gid),
        expense(5002, 1, category: _uuid.v4()),
        expense(5003, 0),
      ]);
      expect(codes(r), [
        'ok',
        'book_leaf_used',
        'book_number_out_of_range',
        'book_not_found',
        'unknown_expense_category',
        'invalid_amount',
      ]);
      final rep2 = await h.repDevice(Demo.rep2Gid, Demo.rep2Pin);
      expect(codes(await push([expense(5004, 1)], d: rep2)), ['book_not_held_by_rep']);
    });

    test('photo is bounded to 1 MB JPEG', () async {
      final r = await push([
        expense(5001, 1, photo: {'mime': 'image/png', 'data': _jpeg(10)}),
        expense(5002, 1, photo: {'mime': 'image/jpeg', 'data': base64.encode([1, 2, 3, 4])}),
        expense(5003, 1, photo: {'mime': 'image/jpeg', 'data': _jpeg(kMaxExpensePhotoBytes + 1)}),
        expense(5004, 1, photo: {'mime': 'image/jpeg', 'data': _jpeg(kMaxExpensePhotoBytes)}),
      ]);
      expect(codes(r), ['invalid_photo', 'invalid_photo', 'photo_too_large', 'ok']);
    });

    test('over custody: flagged by default, rejected when the company says so', () async {
      final r = await push([expense(5001, 60), expense(5002, 50)]);
      expect(codes(r), ['ok', 'ok']);
      expect(r[0]['overCustody'], false);
      expect(r[1]['overCustody'], true);
      expect(r[1]['flags'], ['over_custody']);
      expect(r[1]['custodyBalance'], -10.0);

      final (st, _) = await h.call('POST', '/desktop/master',
          headers: desk, body: {'company': {'name': 'PicPos Demo', 'expenseOverCustody': 'reject'}});
      expect(st, 200);
      final rejected = await push([expense(5003, 1)]);
      expect(codes(rejected), ['custody_exceeded']);
      expect(rejected.single['details']['custodyBalance'], -10.0);
      // Cash collected in the field refills the custody before the desktop posts.
      final col = {
        'kind': 'collection',
        'globalId': _uuid.v4(),
        'customerGlobalId': Demo.cust2Gid,
        'amount': 30,
        'bookGlobalId': Demo.book1Gid,
        'bookNumber': 1001,
      };
      expect(codes(await push([col, expense(5003, 15)])), ['ok', 'ok']);
    });

    test('pending (desktop) carries the expense with its geo, then ack posts it', () async {
      final gid = _uuid.v4();
      final r = await push([
        expense(5001, 9,
            gid: gid,
            photo: {'mime': 'image/jpeg', 'data': _jpeg(100)},
            geo: {'lat': 31.95, 'lng': 35.91, 'accuracy': 12.0, 'at': '2026-05-01T08:29:55.000Z'}),
      ]);
      expect(codes(r), ['ok']);
      final (_, ping) = await h.call('GET', '/desktop/ping', headers: desk);
      expect(ping['pending']['expense'], 1);
      final (_, p) = await h.call('GET', '/desktop/documents/pending', headers: desk);
      final doc = (p['documents'] as List).cast<Map>().singleWhere((d) => d['kind'] == 'expense');
      expect(doc['globalId'], gid);
      expect(doc['number'], 'P-5001');
      expect(doc['amount'], 9.0);
      expect(doc['bookGlobalId'], Demo.payBook1Gid);
      expect(doc['bookNumber'], 5001);
      expect(doc['categoryGlobalId'], Demo.expFuelGid);
      expect(doc['categoryName'], 'وقود');
      expect(doc['repEmployeeGlobalId'], Demo.rep1Gid);
      expect(doc['safeGlobalId'], isNotNull);
      expect(doc['routeGlobalId'], isNotNull);
      expect(doc['hasPhoto'], true);
      expect(doc['overCustody'], false);
      expect(doc['geo'], {'status': 'ok', 'lat': 31.95, 'lng': 35.91, 'accuracy': 12.0, 'at': '2026-05-01T08:29:55.000Z'});

      final (attSt, att) = await h.call('GET', '/desktop/documents/attachment?globalId=$gid', headers: desk);
      expect(attSt, 200);
      expect(base64.decode(att['data'] as String).length, 100);

      final (ak, ab) = await h.call('POST', '/desktop/documents/ack', headers: desk, body: {
        'results': [
          {'kind': 'expense', 'globalId': gid, 'status': 'posted', 'desktopId': '77', 'desktopNumber': 'PV-1'},
        ]
      });
      expect(ak, 200);
      expect(ab['results'].single['status'], 'posted');
      final (_, after) = await h.call('GET', '/desktop/ping', headers: desk);
      expect(after['pending']['expense'], 0);
    });

    test('desktop master: expense categories and the safe balance', () async {
      final catGid = _uuid.v4();
      final (st, b) = await h.call('POST', '/desktop/master', headers: desk, body: {
        'expenseCategories': [
          {'globalId': catGid, 'name': 'غسيل السيارة', 'nameEn': 'Car wash', 'sortOrder': 9},
          {'globalId': Demo.expPortersGid, 'name': 'عتالة', 'isActive': false},
        ],
      });
      expect(st, 200, reason: '$b');
      expect(b['applied']['expenseCategories'], 2);
      final (_, boot) = await h.call('GET', '/mobile/bootstrap', headers: rep.headers);
      final scope = (boot['expenseCategoryScope'] as List);
      expect(scope, contains(catGid));
      expect(scope, isNot(contains(Demo.expPortersGid)));
      expect(codes(await push([expense(5001, 1, category: Demo.expPortersGid)])), ['unknown_expense_category']);
    });
  });

  group('geo', () {
    test('documents keep the GPS stamp or the reason there is none; bad geo rejects', () async {
      final visitGid = _uuid.v4(), colGid = _uuid.v4();
      final r = await push([
        {
          'kind': 'visit',
          'globalId': visitGid,
          'customerGlobalId': Demo.cust1Gid,
          'outcome': 'visited',
          'latitude': 31.9,
          'longitude': 35.9,
          'geo': {'lat': 31.9, 'lng': 35.9, 'accuracy': 8, 'at': '2026-05-01T09:00:00.000Z'},
        },
        {
          'kind': 'collection',
          'globalId': colGid,
          'customerGlobalId': Demo.cust2Gid,
          'amount': 5,
          'bookGlobalId': Demo.book1Gid,
          'bookNumber': 1001,
          'geo': {'status': 'denied'},
        },
        {
          'kind': 'visit',
          'globalId': _uuid.v4(),
          'customerGlobalId': Demo.cust1Gid,
          'outcome': 'visited',
          'geo': {'lat': 120, 'lng': 35.9},
        },
        {
          'kind': 'visit',
          'globalId': _uuid.v4(),
          'customerGlobalId': Demo.cust1Gid,
          'outcome': 'visited',
          'geo': {'status': 'nowhere'},
        },
      ]);
      expect(codes(r), ['ok', 'ok', 'invalid_geo', 'invalid_geo']);
      final v = await h.db.query('SELECT latitude, field_geo FROM customer_visits WHERE global_id=@g', {'g': visitGid});
      expect(v.first[0], 31.9);
      expect(jsonDecode(v.first[1] as String)['accuracy'], 8.0);
      final (_, p) = await h.call('GET', '/desktop/documents/pending', headers: desk);
      final docs = (p['documents'] as List).cast<Map>();
      expect(docs.singleWhere((d) => d['globalId'] == colGid)['geo'], {'status': 'denied'});
      expect(docs.singleWhere((d) => d['globalId'] == visitGid)['geo']['lat'], 31.9);
    });
  });
}
