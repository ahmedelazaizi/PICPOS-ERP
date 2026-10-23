// حسابُ الطاولة على هاتف الزبون — مساراتُ الخادم الثلاثة.
//
// ═══ ما تحرسه هذه الاختبارات ═══
//
// المساراتُ الثلاثةُ تُخدَم **بلا مصادقة**: الزبونُ ليس جهازاً مقترناً ولا
// مستخدماً، فلا حاملَ عنده. وبديلُ المصادقة ثلاثةُ حرّاسٍ متعاقبة — رايةٌ
// مطفأةٌ افتراضاً، وتوقيعٌ على رقم الطاولة، ورمزُ جلسةٍ للكتابة. وكلُّ واحدٍ
// منها يُقاس هنا على حِدَة، لأن سقوطَ أيٍّ منها يفتح سطحاً على شبكة المحلّ.
//
// ⚠️ **والرقمُ المعروضُ يُقاس ضدّ المحرّك الواحد لا ضدّ حسابٍ يدويّ**:
// `TableOrderTotals.compute` هو ما تحسب به الشاشةُ والطباعةُ والتحصيل. وطلبٌ
// عليه خصمٌ وضريبةٌ هو الحالةُ التي يفترق فيها جمعُ `الكمية × السعر` عن
// المستحقّ — فبها تُقاس، لا بطلبٍ بسيطٍ يتّفق فيه الحسابان صدفةً.

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/api/api_handler.dart';
import 'package:picpos_erp/services/api/table_bill_token.dart';
import 'package:picpos_erp/services/table_session_service.dart';

void main() {
  late AppDatabase db;
  late ApiHandler handler;

  setUp(() {
    db = AppDatabase.forTesting();
    handler = ApiHandler(db);
    TableBillToken.setKeyForTesting('table-bill-test-key');
  });

  tearDown(() async {
    TableBillToken.clearKey();
    await db.close();
  });

  Future<void> enable() =>
      db.setSetting(kTableBillQrEnabledKey, 'true');

  Future<shelf.Response> get(String path) => handler
      .buildRouter()
      .call(shelf.Request('GET', Uri.parse('http://localhost$path')));

  Future<shelf.Response> post(String path, Map<String, dynamic> body) =>
      handler.buildRouter().call(shelf.Request(
            'POST',
            Uri.parse('http://localhost$path'),
            body: jsonEncode(body),
          ));

  Future<Map<String, dynamic>> getJson(String path) async =>
      jsonDecode(await (await get(path)).readAsString())
          as Map<String, dynamic>;

  /// طاولةٌ عليها طلبٌ مفتوحٌ بصنفين، **بخصمٍ وضريبة**.
  Future<({int tableId, int orderId})> seedOrder({
    bool withDiscountAndTax = true,
  }) async {
    final tableId = await db.createTable(name: 'ط١');
    final catId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'مشاوي'),
        );
    final p1 = await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'كباب',
          code: 'P-KEBAB',
          categoryId: Value(catId),
          salePrice: const Value(100),
        ));
    final p2 = await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'سلطة',
          code: 'P-SALAD',
          categoryId: Value(catId),
          salePrice: const Value(20),
        ));

    final orderId = await db.into(db.tableOrders).insert(
          TableOrdersCompanion.insert(
            tableId: tableId,
            guestCount: const Value(3),
            discountType: Value(withDiscountAndTax ? 'percent' : null),
            discountValue: Value(withDiscountAndTax ? 10 : 0),
            taxEnabled: Value(withDiscountAndTax),
            // كسريّةٌ — لقطةُ `pos_default_tax_rate`.
            taxRate: Value(withDiscountAndTax ? 0.14 : 0),
          ),
        );

    for (final (pid, qty, price) in [(p1, 2.0, 100.0), (p2, 1.0, 20.0)]) {
      await db.into(db.tableOrderItems).insert(TableOrderItemsCompanion.insert(
            tableOrderId: orderId,
            productId: pid,
            quantity: qty,
            unitPrice: price,
            total: qty * price,
          ));
    }
    return (tableId: tableId, orderId: orderId);
  }

  group('الرايةُ المطفأةُ تُغلق الثلاثةَ', () {
    test('ولا تُخدَم صفحةٌ ولا بياناتٌ ولا يُقبَل طلبُ حساب', () async {
      final seed = await seedOrder();
      final token = TableBillToken.mintTable(seed.tableId);

      expect((await get('/t/$token')).statusCode, 404);
      expect((await get('/api/table-bill/$token')).statusCode, 404);
      expect(
        (await post('/api/table-bill/$token/request', {})).statusCode,
        404,
      );
    });

    test('وهي مطفأةٌ بلا كتابةٍ صريحة — لا تُشعلها الترقية', () async {
      expect(await db.getSettingValue(kTableBillQrEnabledKey), isNull);
    });
  });

  group('القراءة', () {
    test('رمزٌ ملفَّقٌ لا يُفرَّق عن طاولةٍ خاليةٍ في الجواب', () async {
      await enable();
      // ⚠️ الجوابُ واحدٌ عمداً: «لا طاولة» و«لا طلب» لو افترقا لصار المسارُ
      // كاشفاً عن أيّ أرقامِ طاولاتٍ موجودة.
      final body = await getJson('/api/table-bill/t99.badsig');
      expect(body['open'], isFalse);
      expect(body['success'], isTrue);
    });

    test('وطاولةٌ بلا طلبٍ مفتوحٍ تعود بلا حساب', () async {
      await enable();
      final tableId = await db.createTable(name: 'فارغة');
      final body =
          await getJson('/api/table-bill/${TableBillToken.mintTable(tableId)}');
      expect(body['open'], isFalse);
    });

    test('ورمزُ طاولةٍ لا يقرأ حسابَ طاولةٍ أخرى', () async {
      await enable();
      final seed = await seedOrder();
      final other = await db.createTable(name: 'ط٢');
      final body =
          await getJson('/api/table-bill/${TableBillToken.mintTable(other)}');
      expect(body['open'], isFalse,
          reason: 'رمزُ ط٢ عرض حسابَ ط١');
      expect(seed.orderId, greaterThan(0));
    });

    test('والبنودُ تُعرَض بأسمائها وكمّيّاتها', () async {
      await enable();
      final seed = await seedOrder();
      final body =
          await getJson('/api/table-bill/${TableBillToken.mintTable(seed.tableId)}');

      expect(body['open'], isTrue);
      expect(body['tableName'], 'ط١');
      expect(body['guestCount'], 3);
      final items = (body['items'] as List).cast<Map<String, dynamic>>();
      expect(items, hasLength(2));
      expect(items.map((i) => i['name']), containsAll(['كباب', 'سلطة']));
    });

    test('والمستحقُّ يطابق المحرّكَ الواحدَ لا جمعَ السطور', () async {
      await enable();
      final seed = await seedOrder();
      final body =
          await getJson('/api/table-bill/${TableBillToken.mintTable(seed.tableId)}');

      final expected = await TableSessionService(db).totalsFor(seed.orderId);
      expect(body['total'], expected.total);
      expect(body['subtotal'], expected.subtotal);
      expect(body['discount'], expected.discount);
      expect(body['taxAmount'], expected.taxAmount);

      // ⚠️ وهذا هو التوكيدُ الذي يجعل السابقَ ذا معنى: لولا اختلافُ
      // الرقمين لكان جمعُ السطور يمرّ أيضاً — والاختبارُ يقيس لا شيء.
      const rawSum = 2 * 100.0 + 1 * 20.0;
      expect(expected.total, isNot(rawSum),
          reason: 'التجهيزةُ بلا خصمٍ ولا ضريبةٍ فعليّة — الفخُّ لا يُنصَب');
    });

    test('ومجموعُ حصص البنود يساوي المستحقَّ بالضبط', () async {
      await enable();
      final seed = await seedOrder();
      final body =
          await getJson('/api/table-bill/${TableBillToken.mintTable(seed.tableId)}');
      final items = (body['items'] as List).cast<Map<String, dynamic>>();
      final sum = items.fold<double>(0, (a, i) => a + (i['total'] as num));
      expect(sum, body['total'],
          reason: 'الضيفُ يجمع ما يراه فلا يبلغ الرقمَ المكتوب أسفلَ الصفحة');
    });
  });

  group('طلبُ الحساب', () {
    Future<String> sessionOf(int tableId) async {
      final body =
          await getJson('/api/table-bill/${TableBillToken.mintTable(tableId)}');
      return body['session'] as String;
    }

    Future<String> statusOf(int orderId) async => (await (db
            .select(db.tableOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle())
        .status;

    test('يُرفَض بلا رمزِ جلسة — والحالةُ لا تتحرّك', () async {
      await enable();
      final seed = await seedOrder();
      final token = TableBillToken.mintTable(seed.tableId);

      final res = await post('/api/table-bill/$token/request', {});
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(body['success'], isFalse);
      expect(await statusOf(seed.orderId), 'open');
    });

    test('ويُرفَض برمز الطاولة المطبوع نفسِه', () async {
      // ⚠️ عينُ ما تُبنى الطبقةُ لمنعه: الرمزُ المطبوعُ ملصوقٌ على الخشب ولا
      // ينتهي، فلو قُبل للكتابة لظلّ من مسحه مرّةً ينادي النادلَ لطاولةٍ
      // يجلس عليها غيرُه بعد شهر.
      await enable();
      final seed = await seedOrder();
      final token = TableBillToken.mintTable(seed.tableId);

      final res = await post('/api/table-bill/$token/request', {
        'session': token,
      });
      expect(
        (jsonDecode(await res.readAsString()) as Map)['success'],
        isFalse,
      );
      expect(await statusOf(seed.orderId), 'open');
    });

    test('ويُقبَل برمز الجلسة فتصير الحالةُ bill_requested', () async {
      await enable();
      final seed = await seedOrder();
      final token = TableBillToken.mintTable(seed.tableId);

      final res = await post('/api/table-bill/$token/request', {
        'session': await sessionOf(seed.tableId),
      });
      expect((jsonDecode(await res.readAsString()) as Map)['success'], isTrue);
      expect(await statusOf(seed.orderId), 'bill_requested');
    });

    test('وضغطتان لا تُنتجان خطأً — ساكنٌ عند التكرار', () async {
      await enable();
      final seed = await seedOrder();
      final token = TableBillToken.mintTable(seed.tableId);
      final session = await sessionOf(seed.tableId);

      for (var i = 0; i < 2; i++) {
        final res = await post('/api/table-bill/$token/request', {
          'session': session,
        });
        expect((jsonDecode(await res.readAsString()) as Map)['success'], isTrue,
            reason: 'الضغطةُ ${i + 1} رُفضت');
      }
      expect(await statusOf(seed.orderId), 'bill_requested');
    });

    test('والحسابُ يبقى مقروءاً بعد طلبه — الضيفُ يراجع', () async {
      await enable();
      final seed = await seedOrder();
      final token = TableBillToken.mintTable(seed.tableId);
      await post('/api/table-bill/$token/request', {
        'session': await sessionOf(seed.tableId),
      });

      final body = await getJson('/api/table-bill/$token');
      expect(body['open'], isTrue,
          reason: 'إخفاؤه بعد الطلب يبدو للضيف كأنّ حسابَه ضاع');
      expect(body['billRequested'], isTrue);
    });

    test('ورمزُ جلسةِ طلبٍ أُغلق لا يُحيا على الطلب التالي', () async {
      await enable();
      final seed = await seedOrder();
      final token = TableBillToken.mintTable(seed.tableId);
      final stale = await sessionOf(seed.tableId);

      // أُغلق الطلبُ وفُتح غيرُه على نفس الطاولة — وهذا هو السيناريو الحقيقيّ.
      await (db.update(db.tableOrders)..where((o) => o.id.equals(seed.orderId)))
          .write(const TableOrdersCompanion(status: Value('closed')));
      final next = await db.into(db.tableOrders).insert(
            TableOrdersCompanion.insert(tableId: seed.tableId),
          );

      final res = await post('/api/table-bill/$token/request', {
        'session': stale,
      });
      expect((jsonDecode(await res.readAsString()) as Map)['success'], isFalse,
          reason: 'رمزُ جلسةٍ ميّتةٍ حرّك طلبَ ضيفٍ آخر');
      expect(await statusOf(next), 'open');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // الخادمُ على دومينٍ عامّ — الحاجزُ الأوّلُ سقط
  // ═══════════════════════════════════════════════════════════════════════
  //
  // ⚠️ خادمٌ محلّيٌّ لا يبلغه إلّا من هو في المحلّ، وهذا هو ما كان يجعل
  // «من صوّر الرمزَ مرّةً» تهديداً نظريّاً. وخادمٌ على دومينٍ يجعله عمليّاً:
  // يقرأ الحسابَ من أيّ مكانٍ كلّما شُغلت الطاولة، ويبلغ رمزَ الجلسة من
  // القراءة نفسِها فيكتب. فالرقمُ القصير هو ما يبقى — ولا يُنال إلّا من
  // النادل وجهاً لوجه.
  group('وضعُ الدومين العامّ', () {
    Future<void> goPublic() =>
        db.setSetting(kTableBillPublicBaseUrlKey, 'https://shop.example.com');

    test('القراءةُ تُخبر الصفحةَ أنّ الرقمَ مطلوب — ولا ترسله', () async {
      await enable();
      await goPublic();
      final seed = await seedOrder();
      final body =
          await getJson('/api/table-bill/${TableBillToken.mintTable(seed.tableId)}');

      expect(body['pinRequired'], isTrue);
      // ⚠️ التوكيدُ الذي يحمي الميزةَ من أن تُلغيَ نفسَها: إرسالُ الرقم مع
      // القراءة يعني أن من يقرأ عن بُعدٍ يأخذه ويكتب — فلا حاجزَ بقي.
      expect(jsonEncode(body).contains('"pin"'), isFalse,
          reason: 'الرقمُ خرج مع القراءة فبطل معناه');
      final expected = TableBillToken.sessionPin(
        orderId: seed.orderId,
        openedAt: (await (db.select(db.tableOrders)
                  ..where((o) => o.id.equals(seed.orderId)))
                .getSingle())
            .openedAt,
      );
      expect(jsonEncode(body).contains(expected), isFalse,
          reason: 'قيمةُ الرقم ظهرت في الجواب');
    });

    test('وطلبُ الحساب يُرفَض بلا رقمٍ ولو صحّ رمزُ الجلسة', () async {
      await enable();
      await goPublic();
      final seed = await seedOrder();
      final token = TableBillToken.mintTable(seed.tableId);
      final body = await getJson('/api/table-bill/$token');

      final res = await post('/api/table-bill/$token/request', {
        'session': body['session'],
      });
      final json_ = jsonDecode(await res.readAsString()) as Map;
      expect(json_['success'], isFalse);
      expect(json_['pinRequired'], isTrue);

      final status = (await (db.select(db.tableOrders)
                ..where((o) => o.id.equals(seed.orderId)))
              .getSingle())
          .status;
      expect(status, 'open', reason: 'الحالةُ تحرّكت بلا رقم');
    });

    test('ويُقبَل بالرقم الصحيح', () async {
      await enable();
      await goPublic();
      final seed = await seedOrder();
      final token = TableBillToken.mintTable(seed.tableId);
      final body = await getJson('/api/table-bill/$token');
      final order = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(seed.orderId)))
          .getSingle();

      final res = await post('/api/table-bill/$token/request', {
        'session': body['session'],
        'pin': TableBillToken.sessionPin(
          orderId: order.id,
          openedAt: order.openedAt,
        ),
      });
      expect((jsonDecode(await res.readAsString()) as Map)['success'], isTrue);
    });

    test('ورقمُ جلسةٍ أخرى لا يصلح', () async {
      await enable();
      await goPublic();
      final seed = await seedOrder();
      final token = TableBillToken.mintTable(seed.tableId);
      final body = await getJson('/api/table-bill/$token');
      final order = await (db.select(db.tableOrders)
            ..where((o) => o.id.equals(seed.orderId)))
          .getSingle();

      final res = await post('/api/table-bill/$token/request', {
        'session': body['session'],
        'pin': TableBillToken.sessionPin(
          orderId: order.id + 7,
          openedAt: order.openedAt,
        ),
      });
      expect((jsonDecode(await res.readAsString()) as Map)['success'], isFalse);
    });

    test('وعلى الشبكة المحلّيّة لا يُطلَب رقمٌ أصلاً', () async {
      // الحاجزُ الأوّلُ قائمٌ هناك، وإقحامُ رقمٍ يُثقل ميزةً لا تحتاجه.
      await enable();
      final seed = await seedOrder();
      final token = TableBillToken.mintTable(seed.tableId);
      final body = await getJson('/api/table-bill/$token');
      expect(body['pinRequired'], isFalse);

      final res = await post('/api/table-bill/$token/request', {
        'session': body['session'],
      });
      expect((jsonDecode(await res.readAsString()) as Map)['success'], isTrue);
      expect(seed.orderId, greaterThan(0));
    });

    test('وعنوانٌ بمسارٍ أو بمخطَّطٍ غريبٍ لا يُعدّ نشراً', () async {
      // ⚠️ العنوانُ **أساسٌ** يُلحَق به `/t/<token>`. فقيمةٌ فيها مسارٌ كانت
      // تُنتج رمزاً مطبوعاً لا يفتح شيئاً — ولا يُكتشَف إلّا من ضيف.
      expect(normalizeTableBillBaseUrl('https://shop.example.com'),
          'https://shop.example.com');
      expect(normalizeTableBillBaseUrl('https://shop.example.com/'),
          'https://shop.example.com');
      expect(normalizeTableBillBaseUrl('https://shop.example.com:8443'),
          'https://shop.example.com:8443');
      for (final bad in const [
        '',
        '   ',
        'shop.example.com',
        'ftp://shop.example.com',
        'https://shop.example.com/menu',
        'https://shop.example.com?x=1',
        'https:///',
      ]) {
        expect(normalizeTableBillBaseUrl(bad), isNull, reason: 'قُبل: «$bad»');
      }
    });
  });

  test('صفحةُ الهاتف تُخدَم HTML حين تُشعَل الراية', () async {
    await enable();
    final seed = await seedOrder();
    final res = await get('/t/${TableBillToken.mintTable(seed.tableId)}');
    expect(res.statusCode, 200);
    expect(res.headers['content-type'], contains('text/html'));
  });
}
