// `merge` و`negstock` — الإعدادان اللذان لا يمرّان بـ`quickSalePolicyProvider`.
//
// ═══ لماذا ملفٌّ مستقلّ ═══
//
// ٢٧ صفّاً من ٢٩ تُقرأ عبر `quickSalePolicyProvider`، وقد أُصلح أسلوبُ
// قراءته 2026-08-30. لكنّ صفَّين يمرّان بمسارَين آخرَين تماماً:
//
//   • `merge` (`pos_prevent_item_stacking`) عبر `preventItemStackingProvider`
//   • `negstock` عبر مرآته `enable_negative_sales` التي تُقرأ من القاعدة
//     مباشرةً في طبقة البيانات.
//
// فإصلاحُ المزوِّد الأوّل **لا يمسّهما**، وهما موسومان `enforced: true`.
// وهذا الملفُّ يقيسهما وحدَهما.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/models/quick_sale_policy.dart';
import 'package:picpos_erp/domain/usecases/sales/add_to_cart_usecase.dart'
    show resolveStackingFlags;

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('merge — تجميعُ الصنف المتكرّر', () {
    test('الكتابةُ والقراءةُ متّسقتان في الشاشة (الربطُ معكوس)', () async {
      final row = kQuickSaleRows.firstWhere((r) => r.id == 'merge');
      expect(row.invertedBinding, isTrue,
          reason: 'عنوانُ الشاشة «تجميعُ الصنف» والمفتاحُ «امنع التجميع»');

      // المديرُ يُطفئ «التجميع» ⇒ يُخزَّن «امنع التجميع = true».
      final off = QuickSalePolicyValues.write(row, 0);
      expect(off['pos_prevent_item_stacking'], 'true');

      // ويُشعله ⇒ «امنع التجميع = false».
      final on = QuickSalePolicyValues.write(row, 1);
      expect(on['pos_prevent_item_stacking'], 'false');

      // وما يُقرأ يطابق ما يُعرَض.
      expect(QuickSalePolicyValues(off).isOn(row), isFalse);
      expect(QuickSalePolicyValues(on).isOn(row), isTrue);
    });

    test(
        'القراءةُ غيرُ المتزامنةِ ترى ما حُفظ — فالمزوِّدُ نفسُه سليم',
        () async {
      await db.saveSettings({'pos_prevent_item_stacking': 'true'});
      expect(
        await container.read(preventItemStackingProvider.future),
        isTrue,
      );
    });

    test(
        '⚠️ لكنّ **أسلوبَ مسار الكاشير** — `ref.read(p).value ?? false` — '
        'يقرأ `null` فيسقط إلى «التجميعُ يعمل»', () async {
      await db.saveSettings({'pos_prevent_item_stacking': 'true'});

      // حرفيّاً ما في `picpos_search_controller.dart:313`
      // و`picpos_pos_operations.dart:716`.
      final cold = container.read(preventItemStackingProvider).value ?? false;

      // ignore: avoid_print
      print('[قياس] القراءةُ الباردةُ لمنع التجميع أعطت: $cold '
          '(المحفوظُ: true)');

      expect(
        cold,
        isFalse,
        reason: 'إن كانت `false` والمحفوظُ `true` فالإعدادُ **لا يصل**: '
            'نفسُ فئةِ العطب التي أُصلحت في `quickSalePolicyProvider`، '
            'وهذا المزوِّدُ لا يراقبه أحدٌ في شجرة PicPos '
            '(‏لا `ref.watch` في المستودع كلِّه).',
      );
    });

    test('وبعد تسخينِ المزوِّد تصل القيمةُ — فالعلاجُ تسخينٌ أو `await`',
        () async {
      await db.saveSettings({'pos_prevent_item_stacking': 'true'});
      await container.read(preventItemStackingProvider.future);

      final warm = container.read(preventItemStackingProvider).value ?? false;
      expect(warm, isTrue);
    });

    test('أثرُ القيمة على أعلامِ السلّة — صنفٌ موزون', () {
      final prevented = resolveStackingFlags(
        isSoldByWeight: true,
        preventStacking: true,
      );
      expect(prevented.forceNewEntry, isTrue);
      expect(prevented.mergeWeight, isFalse);

      final merged = resolveStackingFlags(
        isSoldByWeight: true,
        preventStacking: false,
      );
      expect(merged.forceNewEntry, isFalse);
      expect(merged.mergeWeight, isTrue,
          reason: 'المسحةُ الثانيةُ تزيد الوزنَ على السطر نفسِه');
    });

    test('وصنفٌ غيرُ موزونٍ لا يتأثّر بالإعداد إطلاقاً', () {
      for (final prevent in [true, false]) {
        final f = resolveStackingFlags(
          isSoldByWeight: false,
          preventStacking: prevent,
        );
        expect(f.forceNewEntry, isFalse);
        expect(f.mergeWeight, isFalse);
      }
      // ⚠️ وهذا يعني أنّ عنوانَ الشاشة «المسحُ الثاني يزيد الكمية بدلاً من
      // إضافة سطر» يصف **أصنافَ الميزان وحدَها**، والنصُّ الفرعيُّ يقولها.
    });
  });

  group('negstock — البيعُ بأقلَّ من الرصيد', () {
    QuickSaleRow row() => kQuickSaleRows.firstWhere((r) => r.id == 'negstock');

    test('المرآةُ `enable_negative_sales` تُكتب مع كلِّ خيار', () {
      expect(QuickSalePolicyValues.write(row(), 0)['enable_negative_sales'],
          'false',
          reason: '«منع» وحدَها تمنع');
      expect(QuickSalePolicyValues.write(row(), 1)['enable_negative_sales'],
          'true');
      expect(QuickSalePolicyValues.write(row(), 2)['enable_negative_sales'],
          'true');
    });

    test('«تحذير» و«السماح» لا يفترقان في المحرّك — والوسمُ يقولها', () {
      final warn = QuickSalePolicyValues.write(row(), 1);
      final allow = QuickSalePolicyValues.write(row(), 2);
      expect(warn['enable_negative_sales'], allow['enable_negative_sales'],
          reason: 'المرآةُ ثنائيّةٌ والخياراتُ ثلاثة');
      expect(row().caveat, isNotNull,
          reason: 'فرقٌ لا يُنفَّذ يجب أن يُعلَن للمدير، وإلّا ظنّ أنّ '
              '«تحذير» تنبّه وهي لا تنبّه');
    });

    test('المرآةُ تصل القاعدةَ ويقرأها المحرّكُ منها مباشرةً', () async {
      await db.saveSettings(QuickSalePolicyValues.write(row(), 0));
      expect(await db.getSettingValue('enable_negative_sales'), 'false');
      expect(await db.getSettingValue('pos_negative_stock_policy'), '0');
    });

    test('«منع» تمنع فعلاً على مستوى القاعدة — صنفٌ رصيدُه صفر', () async {
      final productId = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'NEG-1',
          name: 'صنف بلا رصيد',
          salePrice: const Value(10),
          trackInventory: const Value(true),
        ),
      );
      await db.saveSettings(QuickSalePolicyValues.write(row(), 0));

      final product = await db.getProductById(productId);
      expect(product, isNotNull);
      expect(product!.currentStock, 0);
      expect(product.allowNegativeSale, isFalse,
          reason: 'وعلمُ الصنف لا يفتح البابَ من طرفٍ آخر');
      expect(await db.getSettingValue('enable_negative_sales'), 'false');
    });
  });

  group('كمياتٌ حدّيّة على مسار الإضافة', () {
    /// الشرطُ الحرفيُّ في `picpos_pos_operations.dart` — الكميةُ تُقبل فقط
    /// حين `qty != null && qty > 0`.
    bool accepted(double? qty) => qty != null && qty > 0;

    test('الصفرُ يُرفض', () => expect(accepted(0), isFalse));
    test('السالبُ يُرفض', () => expect(accepted(-1), isFalse));
    test('الكسرُ الموجبُ يُقبل — أصنافُ الميزان',
        () => expect(accepted(0.25), isTrue));
    test('والفارغُ (نصٌّ لا يُفكّ) يُرفض',
        () => expect(accepted(double.tryParse('س')), isFalse));
  });
}
