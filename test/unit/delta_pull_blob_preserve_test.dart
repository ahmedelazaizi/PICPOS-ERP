// ═══════════════════════════════════════════════════════════════════════════
// السحبُ التفاضليُّ كان يمحو صورةَ الصنف المخزَّنةَ محلّيّاً
// ═══════════════════════════════════════════════════════════════════════════
//
// ── العطل ───────────────────────────────────────────────────────────────────
// مُسلسِلُ الصفوف في `/api/sync/pull` (‏`_getSyncPull` في `api_handler.dart`)
// يتعامل مع كلِّ قيمةٍ على النحو:
//     if (v is DateTime) …  else if (v is List<int>) continue;  else out[k] = v;
// فللعمودِ الـblob الواحدِ **شكلان** على السلك:
//
//   • الخادمُ يملك بايتات ⇒ المفتاحُ **غائبٌ** تماماً (‏`continue`).
//   • الخادمُ يملك NULL   ⇒ `null` ليس `List<int>` فيقع في الـ`else`:
//     المفتاحُ **حاضرٌ بقيمةِ null**.
//
// والشكلُ الثاني هو **الواقعيُّ** اليوم لـ`products.image_data`: لا مسارَ
// دفعٍ يكتب العمودَ إلى الخادم إطلاقاً (‏`ClientWriteInterceptor.createProduct`
// بلا وسيطِ صورة، و`grep` على `lib/` يعطي قارئاً واحداً هو
// `drift_product_repository.dart:42`) — فعمودُ الخادم NULL دائماً.
// ولهذا يُختبَر الشكلان: علاجٌ يفحص غيابَ المفتاح وحدَه يمرّ أخضرَ هنا
// ويبقى **ميّتاً في الميدان**.
//
// وكلا الشكلين كان يمحو الصورةَ، عبر مسارَي الكتابة في `_upsertRow`:
//   • `INSERT OR REPLACE INTO <t> (<مفاتيحُ الحمولة>) VALUES (…)` — العمودُ
//     الغائبُ يعود إلى افتراضه، و`Products.imageData` هو `blob().nullable()`
//     بلا افتراضٍ ⇒ NULL.
//   • التحديثُ في المكان (صفٌّ محلّيُّ المنشأ يحمل رقمَ خادمٍ مختلفاً) —
//     يكتب الـnull الحاضرَ حرفاً.
//
// وسياسةُ `products` هي `serverWins` (‏`_lastWriteWinsTables` لا تضمّها)
// فالصفُّ يُطبَّق دوماً بلا مقارنةِ إصدار — أي أنّ **كلَّ** سحبةٍ تُعيد صفَّ
// الصنف كانت تمحو صورتَه، بلا رسالةٍ ولا سجلّ.
//
// والمستودعُ يعرف هذه المصيدةَ ويرقّعها لـ`users` وحدَها (كتلةُ
// `pin`/`card_code` في `_upsertRow`).
//
// ── الأثرُ على المستخدم ─────────────────────────────────────────────────────
// صورةٌ تُرفَع على جهازٍ وتُعرَض في نقطة البيع
// (`pos/widgets/product_card.dart` — `_buildImage`) تختفي بعد أوّل سحبةٍ
// تُعيد صفَّ الصنف.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/delta_pull_service.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
    DeltaPullService.instance.initialize(db);
  });
  tearDown(() => db.close());

  final photo = Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

  Future<Uint8List?> imageOf(int id) async {
    final row = await db
        .customSelect(
          'SELECT image_data FROM products WHERE id = ? LIMIT 1',
          variables: [Variable.withInt(id)],
        )
        .getSingleOrNull();
    return row?.data['image_data'] as Uint8List?;
  }

  /// حمولةُ سحبٍ كما يبنيها الخادمُ فعلاً.
  Map<String, dynamic> serverRow({
    required int id,
    required String globalId,
    String name = 'صنفٌ مُحدَّث',
    String code = 'P-1',
  }) =>
      {
        'id': id,
        'global_id': globalId,
        'code': code,
        'name': name,
        'sale_price': 12.5,
        'cost_price': 8.0,
        'is_active': 1,
        'last_modified_at': 1700000000,
        'row_version': 2,
      };

  // الشكلان معاً — والثاني هو ما يصل من الخادم فعلاً.
  const wireShapes = <String, bool>{
    'المفتاحُ غائبٌ (خادمٌ يملك بايتات)': false,
    'المفتاحُ حاضرٌ بقيمةِ null (الشكلُ الواقعيُّ اليوم)': true,
  };

  group('صورةُ الصنف تنجو من السحب التفاضليّ', () {
    for (final shape in wireShapes.entries) {
      final withNullKey = shape.value;

      test('مسارُ INSERT OR REPLACE — ${shape.key}', () async {
        await db.into(db.products).insert(
              ProductsCompanion.insert(
                id: const Value(41),
                code: 'P-1',
                name: 'صنفٌ بصورة',
                globalId: const Value('prod-gid-1'),
                imageData: Value(photo),
              ),
            );
        expect(await imageOf(41), isNotNull,
            reason: 'خطُّ الأساس: الصورةُ مخزَّنةٌ قبل السحب');

        final payload = serverRow(id: 41, globalId: 'prod-gid-1');
        if (withNullKey) payload['image_data'] = null;

        await DeltaPullService.instance.upsertRowForTest('products', payload);

        final after = await db
            .customSelect('SELECT name, image_data FROM products WHERE id = 41')
            .getSingle();
        expect(after.data['name'], 'صنفٌ مُحدَّث',
            reason: 'الصفُّ طُبِّق فعلاً — وإلّا فالاختبارُ يمرّ لسببٍ خاطئ');
        expect(
          after.data['image_data'] as Uint8List?,
          photo,
          reason: 'null الوارِدُ على عمودِ blob ليس حذفاً — القناةُ عاجزةٌ '
              'عن التعبير عن غيره',
        );
      });

      test(
          'مسارُ التحديثِ في المكان (رقمٌ محلّيٌّ ≠ رقمُ الخادم) — ${shape.key}',
          () async {
        // صنفٌ أُنشئ دون اتّصالٍ فحمل رقماً محلّيّاً عالياً، ثمّ أعطاه
        // الخادمُ رقمَه. `_upsertRow` يجده بالـ`global_id` ويحدّثه في مكانه
        // بأعمدةِ الحمولة — وهي تحمل `image_data: null` في الشكل الواقعيّ.
        // وهذا أرجحُ الحالات: الصورةُ تُرفَع على الجهاز الّذي أنشأ الصنف.
        await db.into(db.products).insert(
              ProductsCompanion.insert(
                id: const Value(1000000007),
                code: 'P-9',
                name: 'صنفٌ محلّيُّ المنشأ',
                globalId: const Value('prod-gid-9'),
                imageData: Value(photo),
              ),
            );

        final payload = serverRow(id: 55, globalId: 'prod-gid-9', code: 'P-9');
        if (withNullKey) payload['image_data'] = null;

        await DeltaPullService.instance.upsertRowForTest('products', payload);

        final after = await db
            .customSelect(
                'SELECT name, image_data FROM products WHERE id = 1000000007')
            .getSingle();
        expect(after.data['name'], 'صنفٌ مُحدَّث',
            reason: 'التحديثُ في المكان وقع فعلاً');
        expect(after.data['image_data'] as Uint8List?, photo,
            reason: 'مسارُ التحديثِ في المكان يمحو الـblob هو أيضاً — '
                'الحمولةُ تحمل العمودَ بقيمةِ null');
      });
    }
  });

  test('صفٌّ جديدٌ من الخادم بلا مقابلٍ محلّيّ يبقى بلا صورة', () async {
    final payload = serverRow(id: 77, globalId: 'prod-gid-new', code: 'P-77');
    payload['image_data'] = null;

    await DeltaPullService.instance.upsertRowForTest('products', payload);

    expect(await imageOf(77), isNull,
        reason: 'لا صورةَ محلّيّةً تُحفَظ — ولا انهيار');
  });

  test('صورةُ صنفٍ آخرَ لا تُلتقَط عند تصادمِ الأرقام', () async {
    // صنفٌ محلّيُّ المنشأ يحتلّ الرقم 41 بهُويّةٍ عالميّةٍ مختلفة. حارسُ
    // التصادم في `_upsertRow` يُعيد ترقيمَه ثمّ يترك الرقمَ لصفِّ الخادم —
    // فلا يجوز أن تُورَّث صورتُه إلى صنفٍ ليس صنفَه. الحفظُ يتبع الهُويّةَ
    // لا الرقم.
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: const Value(41),
            code: 'LOCAL-1',
            name: 'صنفٌ محلّيٌّ آخر',
            globalId: const Value('prod-gid-other'),
            imageData: Value(photo),
          ),
        );

    final payload =
        serverRow(id: 41, globalId: 'prod-gid-server', code: 'P-41');
    payload['image_data'] = null;

    await DeltaPullService.instance.upsertRowForTest('products', payload);

    final server = await db
        .customSelect('SELECT image_data FROM products '
            "WHERE global_id = 'prod-gid-server'")
        .getSingle();
    expect(server.data['image_data'], isNull,
        reason: 'الحفظُ يتبع الهُويّةَ لا الرقم');

    final other = await db
        .customSelect('SELECT image_data FROM products '
            "WHERE global_id = 'prod-gid-other'")
        .getSingle();
    expect(other.data['image_data'] as Uint8List?, photo,
        reason: 'الصنفُ المُعادُ ترقيمُه يحتفظ بصورته');
  });

  test('جدولٌ بلا أعمدةِ blob لا يتأثّر', () async {
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: 'فئة',
            color: const Value('#FF0000'),
            id: const Value(31),
          ),
        );
    await DeltaPullService.instance.upsertRowForTest('categories', {
      'id': 31,
      'name': 'فئةٌ مُحدَّثة',
      'color': '#00FF00',
      'last_modified_at': 1700000000,
      'row_version': 2,
    });
    final after = await db
        .customSelect('SELECT name FROM categories WHERE id = 31')
        .getSingle();
    expect(after.data['name'], 'فئةٌ مُحدَّثة');
  });
}
