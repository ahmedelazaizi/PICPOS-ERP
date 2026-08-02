// مسح ملاحظة الصنف — الحلقة التانية من نفس الباج.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// `CartItemEntity.copyWith` مكتوبة بالنمط المعتاد `x ?? this.x`، فتمرير `null`
// معناها «ما تغيّرش» مش «امسح». يعني `updateItemNote(index, null)` بتسيب
// `itemNote` و`note` القدام مكانهم بالظبط. النتيجة: الكاشير يمسح الملاحظة
// ويحفظ، الملاحظة تفضل مكتوبة، وتتطبع على تذكرة المطبخ.
//
// نفس العطل بيضرب `updateItemModifiers` لما آخر معدِّل يتشال من صنف مالوش
// ملاحظة يدوية — النص المركّب المفروض يبقى `null` فيفضل بالمعدِّلات القديمة
// رغم إن `item.modifiers` بقت فاضية. يعني السلة بتقول حاجة والمطبوع بيقول
// حاجة تانية.
//
// ── ليه أعلام صريحة مش تغيير دلالة copyWith ─────────────────────────────────
// `copyWith` مستعملة في عشرات المواضع في المنتجين، وتغيير دلالة `null` فيها
// كان هيمسح حقول من غير قصد في كل واحد منهم. الأعلام إضافة بقيمة افتراضية
// `false` = سلوك النهاردة بالحرف.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ural_erp/data/providers/settings_providers.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/presentation/pos/providers/cart_controller.dart';
import 'package:ural_erp/presentation/pos/widgets/modifier_selection_dialog.dart';

void main() {
  CartItemEntity item({
    String? note,
    String? itemNote,
    List<SelectedModifier> modifiers = const [],
  }) =>
      CartItemEntity(
        productId: 7,
        productName: 'شاي',
        productCode: 'T01',
        quantity: 1,
        unitPrice: 10,
        note: note,
        itemNote: itemNote,
        modifiers: modifiers,
      );

  SelectedModifier option(String group, String name) => SelectedModifier(
        itemId: 1,
        itemName: name,
        groupName: group,
        extraPrice: 0,
        isOption: true,
      );

  // ═════════════════════════════════════════════════════════════════════════
  // الكيان: copyWith تقدر تمسح
  // ═════════════════════════════════════════════════════════════════════════
  group('CartItemEntity.copyWith — المسح الصريح', () {
    test('من غير الأعلام: null لسه معناها «ما تغيّرش» (سلوك النهاردة)', () {
      final before = item(note: '📝 حار', itemNote: 'حار');
      final after = before.copyWith(note: null, itemNote: null);
      expect(after.note, '📝 حار');
      expect(after.itemNote, 'حار');
    });

    test('clearItemNote بيمسح الملاحظة اليدوية', () {
      final after =
          item(note: '📝 حار', itemNote: 'حار').copyWith(clearItemNote: true);
      expect(after.itemNote, isNull);
    });

    test('clearNote بيمسح النص المركّب', () {
      final after =
          item(note: '📝 حار', itemNote: 'حار').copyWith(clearNote: true);
      expect(after.note, isNull);
    });

    test('العلم بيغلب أي قيمة اتبعتت معاه', () {
      final after = item(note: '📝 حار').copyWith(note: 'x', clearNote: true);
      expect(after.note, isNull);
    });

    test('المسح ما بيلمسش أي حقل تاني', () {
      final before = item(note: '📝 حار', itemNote: 'حار');
      final after = before.copyWith(clearNote: true, clearItemNote: true);
      expect(after.productId, 7);
      expect(after.productName, 'شاي');
      expect(after.quantity, 1);
      expect(after.unitPrice, 10);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // التوصيلة: updateItemNote / updateItemModifiers بيمسحوا فعلاً
  // ═════════════════════════════════════════════════════════════════════════
  group('CartController — المسح بيوصل للسلة', () {
    late ProviderContainer container;
    late CartController cart;

    setUp(() {
      // `CartController.build` بيقرا معدّل الضريبة الافتراضي بس — تجاوزه
      // بيخلّي تركيب المتحكّم ممكن من غير قاعدة بيانات ولا شاشة.
      container = ProviderContainer(overrides: [
        posDefaultTaxRateProvider.overrideWith((ref) async => 0.0),
      ]);
      cart = container.read(cartControllerProvider.notifier);
      addTearDown(container.dispose);
    });

    void seed(CartItemEntity i) {
      cart.state = container.read(cartControllerProvider).copyWith(items: [i]);
    }

    CartItemEntity first() => container.read(cartControllerProvider).items.first;

    test('updateItemNote(null) بيمسح الملاحظة اليدوية والنص المركّب', () {
      seed(item(note: '📝 حار', itemNote: 'حار'));
      cart.updateItemNote(0, null);
      expect(first().itemNote, isNull);
      expect(first().note, isNull);
    });

    test('updateItemNote(null) على صنف له معدِّلات بيسيب المعدِّلات', () {
      seed(item(
        note: '(الحجم: كبير) | 📝 حار',
        itemNote: 'حار',
        modifiers: [option('الحجم', 'كبير')],
      ));
      cart.updateItemNote(0, null);
      expect(first().itemNote, isNull);
      expect(first().note, '(الحجم: كبير)');
    });

    test('شيل آخر معدِّل من صنف بلا ملاحظة → النص المركّب بيتمسح', () {
      seed(item(
        note: '(الحجم: كبير)',
        modifiers: [option('الحجم', 'كبير')],
      ));
      cart.updateItemModifiers(0, const []);
      expect(first().modifiers, isEmpty);
      expect(first().note, isNull);
    });

    test('كتابة ملاحظة عادية لسه شغالة (ما اتكسرتش)', () {
      seed(item());
      cart.updateItemNote(0, 'بدون سكر');
      expect(first().itemNote, 'بدون سكر');
      expect(first().note, '📝 بدون سكر');
    });
  });
}
