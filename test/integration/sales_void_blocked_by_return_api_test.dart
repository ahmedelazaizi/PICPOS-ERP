// عيب (2): رفض إلغاء فاتورة بيع لها مرتجع حيّ يصل للعميل كـ409 برسالة عربية
// (لا 500 عامة) على المسارين:
//   • POST   /api/sales/void   (ApiSalesHandler.postVoidSale)
//   • DELETE /api/sales/<id>   (ApiSalesHandler.deleteSalesInvoice)
// ولا يغيّر الإلغاء السليم (بلا مرتجع) شيئًا: 200 والفاتورة ملغاة.
// ويثبت أن رد 409 يُصنَّف في الصندوق الصادر فشلًا دائمًا (dead-letter) لا «ناجحًا»
// ولا إعادة محاولة لا نهائية.
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/return_original_link.dart';
import 'package:ural_erp/services/api/api_sales_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';
import 'package:ural_erp/services/offline_sync_worker.dart';

void main() {
  late AppDatabase db;
  late ApiSalesHandler handler;
  const uuid = Uuid();

  setUp(() async {
    db = AppDatabase.forTesting();
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'admin', isSystemRole: const drift.Value(true)),
        );
    await db.createUser(
        username: 'admin', password: 'pw', displayName: 'Admin', roleId: roleId);
    await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(
              name: 'Main',
              isActive: const drift.Value(true),
              isDefault: const drift.Value(true)),
        );
    handler = ApiSalesHandler(db, {});
  });

  tearDown(() async => db.close());

  final ctx = {ApiUserCtx.userIdKey: 1};

  /// فاتورة عبر معالج الـAPI نفسه (غير مدفوعة كليًا لتفادي بوابة voidPaidInvoice).
  Future<({int id, String gid, String number})> createSale(String number) async {
    final wh = await db.getDefaultWarehouse();
    final gid = uuid.v4();
    final resp = await handler.postSale(Request(
      'POST',
      Uri.parse('http://localhost/api/sales'),
      body: jsonEncode({
        'invoiceNumber': number,
        'globalId': gid,
        'subtotal': 100.0,
        'total': 100.0,
        'paid': 0.0,
        'paymentMethod': 'cash',
        'warehouseId': wh?.id ?? 1,
        'userId': 1,
        'items': <dynamic>[],
      }),
      headers: {'Content-Type': 'application/json'},
      context: ctx,
    ));
    final body = jsonDecode(await resp.readAsString()) as Map<String, dynamic>;
    return (id: (body['serverId'] ?? body['id']) as int, gid: gid, number: number);
  }

  Future<Response> postVoid(({int id, String gid, String number}) s) =>
      handler.postVoidSale(Request(
        'POST',
        Uri.parse('http://localhost/api/sales/void'),
        body: jsonEncode({
          'salesId': s.id,
          'salesGlobalId': s.gid,
          'invoiceNumber': s.number,
          'reason': 'اختبار',
          'globalId': uuid.v4(),
        }),
        headers: {'Content-Type': 'application/json'},
        context: ctx,
      ));

  Future<Response> deleteInvoice(int id) => handler.deleteSalesInvoice(
      Request('DELETE', Uri.parse('http://localhost/api/sales/$id'), context: ctx),
      id.toString());

  Future<SalesInvoiceData> row(int id) =>
      (db.select(db.salesInvoices)..where((i) => i.id.equals(id))).getSingle();

  Future<String> errorOf(Response r) async =>
      (jsonDecode(await r.readAsString()) as Map<String, dynamic>)['error'] as String;

  group('فاتورة لها مرتجع (الحالة partial_return) → 409', () {
    test('POST /api/sales/void', () async {
      final s = await createSale('API-RET-1');
      await db.updateSalesInvoiceStatus(s.id, 'partial_return');

      final r = await postVoid(s);

      expect(r.statusCode, 409);
      expect(await errorOf(r), kSalesVoidHasReturnMessage);
      final inv = await row(s.id);
      expect(inv.status, 'partial_return');
      expect(inv.isDeleted, isFalse);
    });

    test('DELETE /api/sales/<id>', () async {
      final s = await createSale('API-RET-2');
      await db.updateSalesInvoiceStatus(s.id, 'returned');

      final r = await deleteInvoice(s.id);

      expect(r.statusCode, 409);
      expect(await errorOf(r), kSalesVoidHasReturnMessage);
      final inv = await row(s.id);
      expect(inv.status, 'returned');
      expect(inv.isDeleted, isFalse);
    });

    test('صف مرتجع مربوط حيّ بالملاحظة والحالة completed → 409 على المسارين', () async {
      final s = await createSale('API-RET-3');
      final orig = await row(s.id);
      await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: 'API-RET-3-R',
            warehouseId: orig.warehouseId,
            userId: orig.userId,
            invoiceDate: DateTime.now(),
            total: const drift.Value(50),
            saleType: const drift.Value('return'),
            notes: drift.Value(
                localReturnLinkNote(orig.id, originalGlobalId: orig.globalId)),
          ));

      expect((await postVoid(s)).statusCode, 409);
      expect((await deleteInvoice(s.id)).statusCode, 409);
      expect((await row(s.id)).isDeleted, isFalse);
    });

    test('إلغاء مستند مرتجع مباشرة → 409 برسالة المستند', () async {
      final s = await createSale('API-RET-4');
      await (db.update(db.salesInvoices)..where((i) => i.id.equals(s.id)))
          .write(const SalesInvoicesCompanion(saleType: drift.Value('return')));

      final r = await postVoid(s);

      expect(r.statusCode, 409);
      expect(await errorOf(r), kSalesVoidReturnDocMessage);
    });
  });

  group('بلا مرتجع: السلوك كما كان', () {
    test('POST /api/sales/void → 200 والفاتورة ملغاة', () async {
      final s = await createSale('API-OK-1');
      final r = await postVoid(s);
      expect(r.statusCode, 200);
      expect((await row(s.id)).status, 'voided');
    });

    test('DELETE /api/sales/<id> → 200 والفاتورة ملغاة', () async {
      final s = await createSale('API-OK-2');
      final r = await deleteInvoice(s.id);
      expect(r.statusCode, 200);
      expect((await row(s.id)).status, 'voided');
    });
  });

  group('الصندوق الصادر: رد 409 فشل دائم', () {
    // نص الاستثناء كما يبنيه ServerProxy: `Server error (409): <body>`.
    String serverError(String message) =>
        'Exception: Server error (409): ${jsonEncode({'error': message})}';

    test('رفض "له مرتجع" و"مستند مرتجع" يُصنَّفان terminal → dead-letter', () {
      expect(isTerminalBusinessConflict(serverError(kSalesVoidHasReturnMessage)), isTrue);
      expect(isTerminalBusinessConflict(serverError(kSalesVoidReturnDocMessage)), isTrue);
    });

    test('أي 409 آخر (تكرار حميد) يبقى كما كان: غير terminal', () {
      expect(isTerminalBusinessConflict('Exception: Server error (409): already exists'),
          isFalse);
    });

    test('رد الخادم الفعلي (409) يُصنَّف terminal بنصه المُرسَل', () async {
      final s = await createSale('API-RET-5');
      await db.updateSalesInvoiceStatus(s.id, 'partial_return');
      final r = await postVoid(s);
      final text = 'Exception: Server error (${r.statusCode}): ${await r.readAsString()}';
      expect(r.statusCode, 409);
      expect(isTerminalBusinessConflict(text), isTrue);
    });
  });
}
