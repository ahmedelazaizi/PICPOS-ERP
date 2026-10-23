// طلبُ الضيف من هاتفه — من الطابور إلى الحساب باعتماد النادل.
//
// ═══ ما تحرسه هذه الاختبارات ═══
//
// هذا هو المسارُ **الوحيدُ** في المنتج الذي يُدخِل فيه غيرُ مصادَقٍ بنداً
// يُطبَخ ويُحاسَب عليه. فكلُّ حاجزٍ بينه وبين الحساب يُقاس هنا:
//
//   ١. رايةٌ ثانيةٌ مستقلّةٌ ومطفأةٌ — لا تكفي رايةُ القراءة.
//   ٢. رمزُ الجلسة — كما في «اطلب الحساب».
//   ٣. **السعرُ لا يُقرأ من الجسم** بل من المنتج عند الاعتماد.
//   ٤. الاعتمادُ يُعيد فحصَ الطلب — الطاولةُ قد تكون أُغلقت في الأثناء.
//
// ⚠️ **والثالثُ أخطرُها**: سعرٌ يصل من هاتفٍ هو سعرٌ يكتبه الزبون. واختبارُه
// لا يكون بإرسالِ طلبٍ سليمٍ ثم قياسِ الإجماليّ — بل بإرسالِ سعرٍ **مخالفٍ
// عمداً** ثمّ إثباتِ أنّ المكتوبَ سعرُ المنتج لا ما أُرسل.

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/api/api_user_context.dart';
import 'package:picpos_erp/services/api/table_bill_token.dart';
import 'package:picpos_erp/services/guest_order_requests.dart';

void main() {
  late AppDatabase db;
  late ApiHandler handler;
  late int tableId;
  late int orderId;
  late int kebabId;
  late String token;

  setUp(() async {
    db = AppDatabase.forTesting();
    handler = ApiHandler(db);
    TableBillToken.setKeyForTesting('guest-order-test-key');
    GuestOrderRequests.instance.clear();

    // مسارُ النادل مصادَقٌ — بخلاف مسار الضيف.
    ApiAuthMiddleware.setToken('guest-order-bearer');

    tableId = await db.createTable(name: 'ط٥');
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'مشاوي'));
    kebabId = await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'كباب',
          code: 'P-KEBAB',
          categoryId: Value(catId),
          salePrice: const Value(100),
          taxRate: const Value(14),
        ));
    orderId = await db.into(db.tableOrders).insert(
          TableOrdersCompanion.insert(tableId: tableId),
        );
    token = TableBillToken.mintTable(tableId);
    await db.setSetting(kTableBillQrEnabledKey, 'true');
  });

  tearDown(() async {
    GuestOrderRequests.instance.clear();
    ApiAuthMiddleware.clearToken();
    TableBillToken.clearKey();
    await db.close();
  });

  Future<void> allowGuestOrders() =>
      db.setSetting(kTableBillGuestOrderEnabledKey, 'true');

  Future<Map<String, dynamic>> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool asStaff = false,
  }) async {
    final res = await handler.buildRouter().call(shelf.Request(
          method,
          Uri.parse('http://localhost$path'),
          body: body == null ? null : jsonEncode(body),
          // ⚠️ الهويّةُ تُحقَن في `context` لا في ترويسة: الوسيطُ هو من
          // يفكّ `X-Session-Token` ويضعها هناك، والاختبارُ ينادي المُوجِّهَ
          // مباشرةً بلا خطِّ الوسطاء. فغيابُها هو **عينُ** ما يراه مسارٌ
          // بلا جلسةٍ صالحة: `requirePermission` ترفض 401.
          context: asStaff ? {ApiUserCtx.userIdKey: 1} : const {},
        ));
    final raw = await res.readAsString();
    if (raw.isEmpty) return {'status': res.statusCode};
    return {
      ...jsonDecode(raw) as Map<String, dynamic>,
      'status': res.statusCode,
    };
  }

  Future<String> session() async {
    final body = await call('GET', '/api/table-bill/$token');
    return body['session'] as String;
  }

  Future<List<TableOrderItem>> items() => (db.select(db.tableOrderItems)
        ..where((i) => i.tableOrderId.equals(orderId)))
      .get();

  group('الرايةُ الثانيةُ مستقلّة', () {
    test('القراءةُ مُشعَلةٌ والطلبُ من الهاتف يبقى مرفوضاً', () async {
      final res = await call('POST', '/api/table-bill/$token/add', body: {
        'session': await session(),
        'items': [
          {'productId': kebabId, 'qty': 1},
        ],
      });
      expect(res['success'], isFalse,
          reason: 'رايةُ القراءة فتحت الطلبَ من الهاتف — وهما قراران مختلفان');
      expect(GuestOrderRequests.instance.pending, isEmpty);
    });
  });

  group('إرسالُ الضيف', () {
    test('يدخل الطابورَ ولا يمسّ الحسابَ', () async {
      await allowGuestOrders();
      final res = await call('POST', '/api/table-bill/$token/add', body: {
        'session': await session(),
        'items': [
          {'productId': kebabId, 'qty': 2, 'note': 'بلا بصل'},
        ],
      });

      expect(res['success'], isTrue);
      expect(GuestOrderRequests.instance.pending, hasLength(1));
      expect(await items(), isEmpty,
          reason: 'بندٌ غيرُ معتمَدٍ دخل الحساب — والمطبخُ يطبخه');
    });

    test('ويُرفَض بلا رمزِ جلسة', () async {
      await allowGuestOrders();
      final res = await call('POST', '/api/table-bill/$token/add', body: {
        'items': [
          {'productId': kebabId, 'qty': 1},
        ],
      });
      expect(res['success'], isFalse);
      expect(GuestOrderRequests.instance.pending, isEmpty);
    });

    test('وصنفٌ غيرُ موجودٍ لا يدخل الطابور', () async {
      await allowGuestOrders();
      final res = await call('POST', '/api/table-bill/$token/add', body: {
        'session': await session(),
        'items': [
          {'productId': 999999, 'qty': 1},
        ],
      });
      expect(res['success'], isFalse);
      expect(GuestOrderRequests.instance.pending, isEmpty,
          reason: 'سطرٌ بلا اسمٍ في شاشة النادل لا يستطيع اعتمادَه');
    });

    test('وصنفٌ معطَّلٌ كذلك', () async {
      await allowGuestOrders();
      await (db.update(db.products)..where((p) => p.id.equals(kebabId)))
          .write(const ProductsCompanion(isActive: Value(false)));
      final res = await call('POST', '/api/table-bill/$token/add', body: {
        'session': await session(),
        'items': [
          {'productId': kebabId, 'qty': 1},
        ],
      });
      expect(res['success'], isFalse);
    });

    test('وكمّيّةٌ سالبةٌ تُرفَض — لا تُنقص الحساب', () async {
      await allowGuestOrders();
      final res = await call('POST', '/api/table-bill/$token/add', body: {
        'session': await session(),
        'items': [
          {'productId': kebabId, 'qty': -3},
        ],
      });
      expect(res['success'], isFalse);
      expect(GuestOrderRequests.instance.pending, isEmpty);
    });
  });

  group('اعتمادُ النادل', () {
    Future<int> enqueueOne({double qty = 2}) async {
      await allowGuestOrders();
      await call('POST', '/api/table-bill/$token/add', body: {
        'session': await session(),
        'items': [
          {'productId': kebabId, 'qty': qty},
        ],
      });
      return GuestOrderRequests.instance.pending.single.id;
    }

    test('الطابورُ لا يُقرأ بلا مصادقة', () async {
      await enqueueOne();
      final res = await call('GET', '/api/table-requests');
      expect(res['status'], isNot(200),
          reason: 'طابورُ النادل قُرئ بلا حاملٍ — هاتفُ الضيف يراه');
    });

    test('والاعتمادُ يكتب البندَ بسعر المنتج ولقطةِ ضريبته', () async {
      final id = await enqueueOne();
      final res = await call('POST', '/api/table-requests/$id/approve',
          asStaff: true);
      expect(res['success'], isTrue);

      final rows = await items();
      expect(rows, hasLength(1));
      expect(rows.single.quantity, 2);
      expect(rows.single.unitPrice, 100,
          reason: 'السعرُ لم يُقرأ من المنتج');
      expect(rows.single.taxRate, 14,
          reason: 'لقطةُ الضريبة لم تُؤخذ — الإقرارُ سيُبنى على صفر');
      expect(GuestOrderRequests.instance.pending, isEmpty);
    });

    test('وسعرٌ مُرسَلٌ من الهاتف يُتجاهَل تماماً', () async {
      // ⚠️ الاختبارُ الذي يجعل سابقَه ذا معنى: الجسمُ يحمل سعراً **مخالفاً**،
      // فلو قُرئ منه لظهر ١ بدل ١٠٠ — أي وجبةٌ بجنيه.
      await allowGuestOrders();
      await call('POST', '/api/table-bill/$token/add', body: {
        'session': await session(),
        'items': [
          {'productId': kebabId, 'qty': 1, 'unitPrice': 1, 'price': 1},
        ],
      });
      final id = GuestOrderRequests.instance.pending.single.id;
      await call('POST', '/api/table-requests/$id/approve', asStaff: true);

      expect((await items()).single.unitPrice, 100,
          reason: 'سعرٌ من هاتف الزبون وصل الحساب');
    });

    test('واعتمادان لا يُضاعفان الكمّيّة', () async {
      final id = await enqueueOne();
      await call('POST', '/api/table-requests/$id/approve', asStaff: true);
      final second =
          await call('POST', '/api/table-requests/$id/approve', asStaff: true);

      expect(second['success'], isFalse);
      expect((await items()).single.quantity, 2);
    });

    test('وطاولةٌ أُغلقت بين الطلب والاعتماد لا يدخلها شيء', () async {
      final id = await enqueueOne();
      await (db.update(db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(const TableOrdersCompanion(status: Value('closed')));

      final res = await call('POST', '/api/table-requests/$id/approve',
          asStaff: true);
      expect(res['success'], isFalse);
      expect(await items(), isEmpty,
          reason: 'أصنافُ ضيفٍ مضت دخلت حسابَ من جلس بعده');
    });

    test('والرفضُ يُسقطه بلا كتابة', () async {
      final id = await enqueueOne();
      final res =
          await call('POST', '/api/table-requests/$id/reject', asStaff: true);
      expect(res['success'], isTrue);
      expect(await items(), isEmpty);
      expect(GuestOrderRequests.instance.pending, isEmpty);
    });

    test('والطابورُ يُقرأ بأسماء الطاولات وبنودِه', () async {
      await enqueueOne();
      final res = await call('GET', '/api/table-requests', asStaff: true);
      expect(res['success'], isTrue);
      final list = (res['requests'] as List).cast<Map<String, dynamic>>();
      expect(list, hasLength(1));
      expect(list.single['tableName'], 'ط٥');
      expect((list.single['lines'] as List), hasLength(1));
    });
  });
}
