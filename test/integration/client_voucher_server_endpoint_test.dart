// ═══════════════════════════════════════════════════════════════════════════
// E-fix ١ — سندا القبض والصرف من جهاز العميل عبر الخادم.
// ═══════════════════════════════════════════════════════════════════════════
//
// المسارُ الحقيقيّ كلُّه إلا النقلَ الشبكيّ:
//   `ClientVoucherInterceptor.buildPayload` (من قاعدة **العميل** بمعرّفاتٍ
//   محلّيّةٍ مختلفةٍ عمداً) → `ApiHandler.buildRouter()` على قاعدة **الخادم**
//   → `ApiVoucherHandler` — ويُقارَن الناتجُ (القيدُ، صفُّ الخزنة، رصيدُ
//   الخزنة والطرف، حالةُ الدفتر) بنفس السند مكتوباً على **الجهاز الرئيسيّ**
//   بالمسار المحلّيّ الذي تسلكه الشاشة.
//
// ثمّ: إعادةُ الإرسال لا تقيّد مرّتين، وورقةُ الدفتر خارج المدى/المكرّرة/
// الملغاة تُرفَض على الخادم (409) بلا أيّ كتابة، ونصُّ الرفض يعود للعميل.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/domain/models/document_record.dart';
import 'package:picpos_erp/domain/models/voucher_book.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';
import 'package:picpos_erp/services/client_write_interceptor.dart';
import 'package:picpos_erp/services/server_proxy.dart';

const _safeGid = 'safe-efix-1';
const _partyGid = 'party-efix-1';

/// One device's chart: a cash safe (1000), a supplier/customer party with
/// its own sub-account, two general detail accounts, a fiscal year, and a
/// receipt + payment voucher book. [skew] inserts throw-away rows first so
/// the CLIENT's local ids differ from the server's.
Future<({int safe, int party, int clearing, int other, int expense})> _seed(
  AppDatabase db, {
  bool skew = false,
}) async {
  await db.delete(db.journalEntryLines).go();
  await db.delete(db.journalEntries).go();
  await db.delete(db.safeTransactions).go();
  await db.delete(db.commercialPapers).go();
  await db.delete(db.accountingPeriods).go();
  await db.delete(db.fiscalYears).go();
  await db.delete(db.accountMappings).go();
  await db
      .update(db.safes)
      .write(const SafesCompanion(linkedAccountId: Value(null)));
  await db.delete(db.safes).go();
  await db.delete(db.parties).go();
  await db.syncDefaultAccounts();
  final now = DateTime.now();
  await db.into(db.fiscalYears).insert(FiscalYearsCompanion.insert(
        name: '${now.year}',
        startDate: DateTime(now.year, 1, 1),
        endDate: DateTime(now.year, 12, 31),
        isClosed: const Value(false),
      ));
  if (skew) {
    await db.into(db.safes).insert(SafesCompanion.insert(name: 'ضجيج'));
    await db.into(db.parties).insert(PartiesCompanion.insert(name: 'ضجيج'));
    await account(db, '1901', gid: 'noise-acc');
  }
  final safe = await db.into(db.safes).insert(SafesCompanion.insert(
        name: 'الصندوق',
        balance: const Value(1000),
        isDefault: const Value(true),
        safeType: const Value('cash'),
        globalId: const Value(_safeGid),
      ));
  final party = await db.insertParty(PartiesCompanion.insert(
    name: 'طرف السند',
    isCustomer: const Value(true),
    isSupplier: const Value(true),
    globalId: const Value(_partyGid),
  ));
  return (
    safe: safe,
    party: party,
    clearing: await account(db, '1199', gid: 'acc-clearing'),
    other: await account(db, '2199', gid: 'acc-other', type: 'liability'),
    expense: await account(db, '5777', gid: 'acc-expense', type: 'expense'),
  );
}

Future<int> account(AppDatabase db, String code,
        {required String gid, String type = 'asset'}) =>
    db.into(db.accounts).insert(AccountsCompanion.insert(
          code: code,
          name: 'حساب $code',
          accountType: type,
          accountNature: const Value('detail'),
          isSystem: const Value(false),
          globalId: Value(gid),
        ));

/// Copies [table] rows `SELECT *` → `INSERT OR REPLACE` — what delta pull
/// does — so the client holds the server's books with the server's ids.
Future<void> _pull(AppDatabase from, AppDatabase to, String table) async {
  for (final r in await from.customSelect('SELECT * FROM $table').get()) {
    final cols = r.data.keys.toList();
    await to.customStatement(
      'INSERT OR REPLACE INTO $table (${cols.join(', ')}) '
      'VALUES (${List.filled(cols.length, '?').join(', ')})',
      [for (final c in cols) r.data[c]],
    );
  }
}

/// Everything a voucher leaves behind, in device-independent terms.
Future<Map<String, Object?>> _state(AppDatabase db, String gid) async {
  final rows = await db.customSelect(
    'SELECT t.*, b.global_id AS book_gid, a.code AS treasury_code '
    'FROM safe_transactions t '
    'LEFT JOIN voucher_books b ON b.id = t.book_id '
    'LEFT JOIN accounts a ON a.id = t.treasury_account_id '
    'WHERE t.global_id IN (?, ?)',
    variables: [Variable<String>(gid), Variable<String>('$gid-chq')],
  ).get();
  final txn = rows.single.data;
  final txnId = txn['id'] as int;
  final je = await db.customSelect(
    'SELECT e.global_id, a.code, l.debit, l.credit FROM journal_entries e '
    'JOIN journal_entry_lines l ON l.entry_id = e.id '
    'JOIN accounts a ON a.id = l.account_id '
    "WHERE e.reference_id = ? AND e.reference_type IN "
    "('receipt_voucher', 'payment_voucher') ORDER BY a.code, l.debit",
    variables: [Variable<int>(txnId)],
  ).get();
  final safe = await (db.select(db.safes)
        ..where((s) => s.globalId.equals(_safeGid)))
      .getSingle();
  final party = await (db.select(db.parties)
        ..where((p) => p.globalId.equals(_partyGid)))
      .getSingle();
  final books = await db
      .customSelect('SELECT global_id, next_number, status FROM voucher_books '
          'ORDER BY global_id')
      .get();
  return {
    'type': txn['transaction_type'],
    'category': txn['category'],
    'amount': txn['amount'],
    'discount': txn['discount'],
    'balanceAfter': txn['balance_after'],
    'hasParty': txn['party_id'] != null,
    'bookGid': txn['book_gid'],
    'bookNumber': txn['book_number'],
    'treasuryCode': txn['treasury_code'],
    'rep': txn['rep_employee_id'],
    'route': txn['route_id'],
    'je': [
      for (final l in je)
        '${l.data['global_id']}|${l.data['code']}|'
            '${l.data['debit']}|${l.data['credit']}',
    ],
    'safeBalance': safe.balance,
    'partyBalance': party.balance,
    'books': [
      for (final b in books)
        '${b.data['global_id']}|${b.data['next_number']}|${b.data['status']}',
    ],
  };
}

void main() {
  late AppDatabase main;
  late AppDatabase server;
  late AppDatabase client;
  late ({int safe, int party, int clearing, int other, int expense}) m, s, c;
  late int adminId;
  late int receiptBook;
  late int paymentBook;

  setUp(() async {
    SyncInterceptor.instance = null;
    main = AppDatabase.forTesting();
    server = AppDatabase.forTesting();
    client = AppDatabase.forTesting();
    m = await _seed(main);
    s = await _seed(server);
    c = await _seed(client, skew: true);
    receiptBook =
        await server.createVoucherBook(type: 'receipt', rangeFrom: 1, rangeTo: 5);
    paymentBook = await server.createVoucherBook(
        type: 'payment', rangeFrom: 100, rangeTo: 105);
    await server.cancelVoucherBookLeaf(
        bookId: paymentBook, number: 103, reason: 'تالفة');
    // الجهازُ الرئيسيُّ والعميلُ يحملان دفاترَ الخادم كما تصلهما بالسحب.
    for (final t in ['voucher_books', 'voucher_book_leaves_cancelled']) {
      await _pull(server, main, t);
      await _pull(server, client, t);
    }
    adminId = (await (server.select(server.users)..limit(1)).getSingle()).id;
  });

  tearDown(() async {
    await main.close();
    await server.close();
    await client.close();
  });

  Future<shelf.Response> post(Map<String, dynamic> payload) =>
      ApiHandler(server).buildRouter().call(shelf.Request(
            'POST',
            Uri.parse('http://localhost/api/vouchers/${payload['kind']}'),
            body: jsonEncode(payload),
            headers: {'content-type': 'application/json'},
            context: {ApiUserCtx.userIdKey: adminId},
          ));

  Future<Map<String, dynamic>> body(shelf.Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, dynamic>;

  test('1a — تحويلٌ محاسبيّ من العميل = نفسُ القيد والخزنة والدفتر', () async {
    const gid = 'efix-transfer-1';
    // الجهازُ الرئيسيّ: مسارُ الشاشة المحلّيّ (المستودعُ يمرّر إلى الـDAO).
    final mainTxn = await main.createAccountTransferVoucher(
      isReceipt: true,
      amount: 300,
      treasuryAccountId: m.clearing,
      beneficiaryAccountId: m.other,
      category: 'other',
      description: 'تحويل',
      documentSafeId: m.safe,
      globalId: gid,
    );
    await main.assignVoucherBookLeaf(
        txnId: mainTxn, bookId: receiptBook, number: 1);

    final payload = await ClientVoucherInterceptor.buildPayload(
      client,
      isReceipt: true,
      transfer: true,
      globalId: gid,
      amount: 300,
      category: 'other',
      description: 'تحويل',
      safeId: c.safe,
      treasuryAccountId: c.clearing,
      beneficiaryAccountId: c.other,
      bookId: receiptBook,
      bookNumber: 1,
    );
    expect(c.clearing, isNot(s.clearing),
        reason: 'المعرّفاتُ المحلّيّةُ تختلف — الخادمُ يحلّ بالمعرّف العامّ');
    final r = await post(payload);
    expect(r.statusCode, 200, reason: await r.readAsString());

    final serverState = await _state(server, gid);
    expect(serverState, await _state(main, gid));
    expect(serverState['type'], kAccountTransferReceiptTxnType);
    expect(serverState['safeBalance'], 1000, reason: 'لا حركةَ خزنة');
    expect(serverState['treasuryCode'], '1199');
    expect(serverState['bookNumber'], 1);

    // يعود لكلّ العملاء بالسحب العامّ (`SELECT *`) بأعمدة الدفتر والخزينة.
    final pulled = await server.customSelect(
        'SELECT * FROM safe_transactions WHERE global_id = ?',
        variables: [const Variable<String>(gid)]).getSingle();
    expect(pulled.data['book_id'], receiptBook);
    expect(pulled.data['treasury_account_id'], s.clearing);
  });

  test('1b — صرفٌ لحسابٍ ليس طرفاً من العميل = نفسُ الحالة', () async {
    const gid = 'efix-payment-1';
    final mainTxn = await main.createPaymentVoucher(
      amount: 80,
      category: 'other',
      description: 'مصروف',
      safeId: m.safe,
      linkedAccountId: m.expense,
      globalId: gid,
    );
    await main.assignVoucherBookLeaf(
        txnId: mainTxn, bookId: paymentBook, number: 100);

    final r = await post(await ClientVoucherInterceptor.buildPayload(
      client,
      isReceipt: false,
      transfer: false,
      globalId: gid,
      amount: 80,
      category: 'other',
      description: 'مصروف',
      safeId: c.safe,
      beneficiaryAccountId: c.expense,
      bookId: paymentBook,
      bookNumber: 100,
    ));
    expect(r.statusCode, 200, reason: await r.readAsString());

    final serverState = await _state(server, gid);
    expect(serverState, await _state(main, gid));
    expect(serverState['safeBalance'], 920);
    expect((serverState['je'] as List).any((l) => '$l'.contains('|5777|80.0|')),
        isTrue,
        reason: 'المستفيدُ المختارُ مدينٌ في القيد');
  });

  test('قبضٌ نقديٌّ بورقة دفتر من العميل = نفسُ الحالة، ومختومٌ بالمندوب',
      () async {
    const gid = 'efix-receipt-1';
    // v185 — العميلُ على خطٍّ بمندوب على الجهازين؛ الخادمُ يحلّ الختم.
    for (final (db, party) in [(main, m.party), (server, s.party)]) {
      final rep = await db
          .into(db.employees)
          .insert(EmployeesCompanion.insert(name: 'مندوب'));
      final route = await db.saveDistributionRoute(name: 'خط');
      await db.setRouteRep(route, rep);
      await db.assignCustomerToRoute(customerId: party, routeId: route);
    }
    final mainTxn = await main.createReceiptVoucher(
      amount: 200,
      discount: 5,
      category: 'customer_payment',
      partyId: m.party,
      safeId: m.safe,
      globalId: gid,
    );
    await main.assignVoucherBookLeaf(
        txnId: mainTxn, bookId: receiptBook, number: 2);

    final r = await post(await ClientVoucherInterceptor.buildPayload(
      client,
      isReceipt: true,
      transfer: false,
      globalId: gid,
      amount: 200,
      discount: 5,
      category: 'customer_payment',
      partyId: c.party,
      safeId: c.safe,
      bookId: receiptBook,
      bookNumber: 2,
    ));
    expect(r.statusCode, 200, reason: await r.readAsString());

    final serverState = await _state(server, gid);
    expect(serverState, await _state(main, gid));
    expect(serverState['hasParty'], isTrue);
    expect(serverState['rep'], isNotNull, reason: 'ختمُ المندوب على الخادم');
    expect(serverState['route'], isNotNull);
    expect(serverState['partyBalance'], -205);
    expect(serverState['safeBalance'], 1200);
  });

  test('🔴 إعادةُ الإرسال لا تقيّد مرّتين', () async {
    const gid = 'efix-dup-1';
    final payload = await ClientVoucherInterceptor.buildPayload(
      client,
      isReceipt: true,
      transfer: false,
      globalId: gid,
      amount: 50,
      category: 'customer_payment',
      partyId: c.party,
      safeId: c.safe,
      bookId: receiptBook,
      bookNumber: 3,
    );
    final first = await body(await post(payload));
    final before = await _state(server, gid);
    final jeCount = (await server.select(server.journalEntries).get()).length;

    final again = await post(payload);
    expect(again.statusCode, 200);
    final second = await body(again);
    expect(second['duplicate'], isTrue);
    expect(second['serverId'], first['serverId']);
    expect(await _state(server, gid), before);
    expect((await server.select(server.journalEntries).get()).length, jeCount);
  });

  group('🔴 ورقةُ الدفتر تُفحَص على الخادم', () {
    Future<void> rejected(int bookId, int number, String why) async {
      const gid = 'efix-rejected';
      final txnsBefore =
          (await server.select(server.safeTransactions).get()).length;
      Future<double> balance() async => (await (server.select(server.safes)
                ..where((x) => x.id.equals(s.safe)))
              .getSingle())
          .balance;
      final balanceBefore = await balance();
      final r = await post(await ClientVoucherInterceptor.buildPayload(
        client,
        isReceipt: false,
        transfer: false,
        globalId: gid,
        amount: 10,
        category: 'other',
        safeId: c.safe,
        beneficiaryAccountId: c.expense,
        bookId: bookId,
        bookNumber: number,
      ));
      expect(r.statusCode, 409, reason: why);
      final b = await body(r);
      expect(b['voucherBookKey'], isNotNull);
      expect((await server.select(server.safeTransactions).get()).length,
          txnsBefore,
          reason: '$why — لا كتابةَ ألبتّة');
      expect(await balance(), balanceBefore, reason: why);

      // والعميلُ يقرأ نصَّ الرفض لا «خطأ خادم».
      final e = ServerProxy.voucherBookRejectionOf(
          Exception('Server error (409): ${jsonEncode(b)}'));
      expect(e, isA<VoucherBookException>());
      expect(e!.key, b['voucherBookKey']);
    }

    test('خارجَ المدى', () => rejected(paymentBook, 999, 'خارج المدى'));
    test('ملغاة', () => rejected(paymentBook, 103, 'ورقة ملغاة'));
    test('مكرّرة', () async {
      final ok = await post(await ClientVoucherInterceptor.buildPayload(
        client,
        isReceipt: false,
        transfer: false,
        globalId: 'efix-first',
        amount: 10,
        category: 'other',
        safeId: c.safe,
        beneficiaryAccountId: c.expense,
        bookId: paymentBook,
        bookNumber: 101,
      ));
      expect(ok.statusCode, 200);
      await rejected(paymentBook, 101, 'ورقة مستخدمة');
    });
  });
}
