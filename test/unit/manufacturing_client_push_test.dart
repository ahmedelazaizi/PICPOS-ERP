// v166 / المرحلة ٢ — التصنيع: العميلُ يُرسل الحدثَ ولا يستهلك خامةً.
//
// ═══ لماذا هذا أخطرُ من سابقيه ═══
//
// 🔴 أثرُ التصنيع **مخزنيٌّ** لا محاسبيٌّ فقط: بدءُ الإنتاج يخصم خاماتٍ من
// الرصيد، والإنجازُ يُدخل تامّاً. وقيدٌ مضاعفٌ يُعكَس بقيدٍ عكسيّ يُبقي أثراً
// مقروءاً؛ أمّا **خصمٌ مضاعفٌ من رصيد** فيُنتج كمّيّةً سالبةً أو نقصاً لا
// يُفسَّر، ولا يُصحَّح إلّا بجردٍ يدويّ.
//
// وجهازان يبدآن نفسَ الأمر يخصمان الخاماتِ مرّتين: كلٌّ يفحص حالةَ **قاعدته**
// فيراها `draft` ويمضي. فالمنفّذُ لا بدّ أن يكون واحداً.
//
// ═══ وبالهويّة لا بالرقم ═══
//
// رقمُ الأمر على العميل يخالف رقمَه على الخادم بالتصميم. فحدثٌ يصل برقمٍ
// محلّيٍّ قد يُشغَّل على أمرٍ **آخر** فيستهلك خاماتِ غيره — ولا يظهر ذلك في
// أيّ رصيدٍ حتّى الجرد.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';

class _RecordingClient implements SyncInterceptor {
  final List<Map<String, dynamic>> actions = [];

  @override
  bool get isClientModeImpl => true;

  @override
  bool get isMirrorModeImpl => false;

  @override
  Future<void> submitManufacturingAction(Map<String, dynamic> req) async {
    actions.add(req);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late AppDatabase db;
  late int rawId;
  late int finishedId;
  late int warehouseId;
  late int orderId;

  setUp(() async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    rawId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            code: 'RAW-1',
            name: 'خامة',
            salePrice: const Value(0),
            costPrice: const Value(10),
            currentStock: const Value(1000),
            globalId: const Value('raw-gid'),
          ),
        );
    finishedId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            code: 'FIN-1',
            name: 'منتجٌ تامّ',
            salePrice: const Value(100),
            costPrice: const Value(50),
            globalId: const Value('fin-gid'),
          ),
        );
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'مخزنُ الإنتاج'),
        );

    // رصيدُ المخزن — الخصمُ يقرأ `inventory_balances` لا `products` وحدَه،
    // وبلا هذا الصفِّ يرمي الـDAO «غيرُ متوفّرٍ في أيّ مستودع» فتسقط
    // المرساةُ وتُخفي أنّ فحوصَ المنعِ لا تقيس شيئاً.
    await db.into(db.inventoryBalances).insert(
      InventoryBalancesCompanion.insert(
        productId: rawId,
        warehouseId: warehouseId,
        quantity: const Value(1000),
        averageCost: const Value(10),
      ),
    );

    final bomId = await db.createBOM(
      finishedProductId: finishedId,
      bomCode: 'BOM-1',
      components: [
        {'rawMaterialId': rawId, 'quantity': 2.0},
      ],
    );
    orderId = await db.createManufacturingOrder(
      bomId: bomId,
      orderedQty: 10,
      warehouseId: warehouseId,
      startDate: DateTime(2026, 8, 27),
    );
  });

  tearDown(() async {
    SyncInterceptor.instance = null;
    await db.close();
  });

  Future<double> rawStock() async {
    final p = await (db.select(db.products)..where((x) => x.id.equals(rawId)))
        .getSingle();
    return p.currentStock;
  }

  test('القائمةُ والأمرُ يحملان هويّةً', () async {
    final order = await (db.select(db.manufacturingOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();
    expect(order.globalId, isNotNull,
        reason: 'أمرٌ بلا هويّةٍ لا يُدعى على الخادم، فكلُّ حدثٍ عليه '
            'يُنفَّذ محلّيّاً — وهو التفاوتُ نفسُه.');

    final components = await db.select(db.bomComponents).get();
    expect(components.single.globalId, isNotNull);
  });

  group('أحداثٌ من عميل', () {
    late _RecordingClient client;

    setUp(() {
      client = _RecordingClient();
      SyncInterceptor.instance = client;
    });

    test('🔴 بدءُ الإنتاج لا يخصم خامةً محلّيّاً', () async {
      final before = await rawStock();
      await db.startProduction(orderId);

      expect(await rawStock(), before,
          reason: 'العميلُ خصم الخامةَ ⇒ الخادمُ سيخصمها ثانيةً عند التنفيذ. '
              'وخصمٌ مضاعفٌ لا يُعكَس بقيد — رصيدٌ سالبٌ أو نقصٌ لا يُفسَّر.');

      final order = await (db.select(db.manufacturingOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();
      expect(order.status, 'draft',
          reason: 'الحالةُ تتقدّم على الخادم وتعود بالدلتا؛ تقديمُها محلّيّاً '
              'يمنع إعادةَ المحاولة لو رُدَّ الطلب.');
    });

    test('والحدثُ أُرسل بالهويّة لا بالرقم', () async {
      await db.startProduction(orderId);
      expect(client.actions, hasLength(1));

      final order = await (db.select(db.manufacturingOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();
      expect(client.actions.single['orderGlobalId'], order.globalId,
          reason: 'رقمٌ محلّيٌّ يصل الخادمَ قد يطابق أمراً آخرَ فيستهلك '
              'خاماتِ غيره.');
      expect(client.actions.single['action'], 'start');
    });

    test('والإنجازُ يمرّر الكمّيّةَ ومركزَ التكلفة', () async {
      await db.completeProduction(orderId, actualProducedQty: 9);
      final req = client.actions.single;
      expect(req['action'], 'complete');
      expect(req['actualProducedQty'], 9);
    });

    test('والعكسُ يُرسَل ولا يُنفَّذ', () async {
      await db.reverseManufacturingOrder(orderId);
      expect(client.actions.single['action'], 'reverse');
    });

    test('🔴 وتكلفةٌ إضافيّةٌ تُرسَل ولا تُكتَب', () async {
      await db.addMfgOrderCost(
        orderId: orderId,
        costType: 'overhead',
        description: 'كهرباء',
        amount: 300,
      );

      expect(await db.select(db.mfgOrderCosts).get(), isEmpty,
          reason: 'صفُّ تكلفةٍ محلّيٌّ بلا قيدِه يجعل تكلفةَ الأمر تخالف '
              'الأستاذ.');
      final req = client.actions.single;
      expect(req['action'], 'add_cost');
      expect(req['amount'], 300);
      expect(req['globalId'], isNotNull,
          reason: 'بلا هويّةٍ لا يستطيع الخادمُ إزالةَ تكرارِ إعادة الإرسال.');
    });

    test('وأمرٌ بلا هويّةٍ يفشل صريحاً لا صامتاً', () async {
      await (db.update(db.manufacturingOrders)
            ..where((o) => o.id.equals(orderId)))
          .write(const ManufacturingOrdersCompanion(globalId: Value(null)));

      await expectLater(
        db.startProduction(orderId),
        throwsA(isA<StateError>()),
        reason: 'التمريرُ الصامتُ يعني تنفيذاً محلّيّاً — أي عينَ التفاوت '
            'الذي تسدّه المرحلة.',
      );
      expect(client.actions, isEmpty);
    });
  });

  test('⚓ مرساة: الوضعُ المستقلُّ ما زال يخصم الخامةَ فعلاً', () async {
    // بلا هذه المرساةِ يمرّ كلُّ فحصٍ أعلاه أخضرَ لو كانت التجهيزةُ لا تخصم
    // أصلاً — «لم يُخصَم» يُشبه «مُنِع».
    SyncInterceptor.instance = null;
    final before = await rawStock();
    await db.startProduction(orderId);

    expect(await rawStock(), lessThan(before),
        reason: 'المستقلُّ لا يخصم الخامةَ ⇒ فحصُ المنعِ أعلاه بلا معنى.');

    final order = await (db.select(db.manufacturingOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();
    expect(order.status, 'in_progress');
  });
}
