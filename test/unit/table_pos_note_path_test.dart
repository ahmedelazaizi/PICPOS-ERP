// شاشة خدمة الطاولات — مسار الملاحظة التالت.
//
// ── ليه الملف ده موجود ───────────────────────────────────────────────────────
// البيع السريع ليه تلات فوركات: `PosScreenV2` و`PicPosPosScreen`
// و`TablePosScreen`. الأخيرة كان لها **مسار كتابة ملاحظة خاص بيها بالكامل**:
// `_showNoteDialog` كان بيعمل `item.copyWith(note: ...)` مباشرة على حالة
// السلة، متجاوز `updateItemNote` عن قصد موثَّق. يعني كان فيه طريقتين لكتابة
// نفس الحقل، واحدة بتحافظ على المعدِّلات وواحدة بتمسحها.
//
// ── القرار: ده انحراف مش قرار تصميم ─────────────────────────────────────────
// `note` حقل **مشتق** من `modifiers` + `itemNote`. الكتابة المباشرة عليه
// بتخلّي المشتق يخالف مصدره: `item.modifiers` فيها «الحجم: كبير» والنص
// المطبوع مفيهوش. وطبقتَي الطباعة الاتنين
// (`thermal_receipt_generator.dart:710` و`templated_invoice_service.dart:1078`)
// بتفكّكا النص بالفاصل ` | ` والبادئة `📝 ` — يعني الشكل المركّب **عقد**
// مع الطباعة مش تزيين. المسار المباشر كان بينتج نص خارج العقد ده.
//
// الاختبار هنا بيمسك الانحراف السلوكي (ضياع المعدِّلات) مش شكل الكود.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ural_erp/data/providers/settings_providers.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/presentation/pos/providers/cart_controller.dart';
import 'package:ural_erp/presentation/pos/screens/pos_table_service_screen.dart';
import 'package:ural_erp/presentation/pos/widgets/modifier_selection_dialog.dart';

void main() {
  late ProviderContainer container;
  late CartController cart;

  setUp(() {
    container = ProviderContainer(overrides: [
      posDefaultTaxRateProvider.overrideWith((ref) async => 0.0),
    ]);
    cart = container.read(cartControllerProvider.notifier);
    addTearDown(container.dispose);
  });

  SelectedModifier option(String group, String name) => SelectedModifier(
        itemId: 1,
        itemName: name,
        groupName: group,
        extraPrice: 0,
        isOption: true,
      );

  void seed(CartItemEntity i) {
    cart.state = container.read(cartControllerProvider).copyWith(items: [i]);
  }

  CartItemEntity first() => container.read(cartControllerProvider).items.first;

  group('applyTablePosItemNote — ملاحظة المطبخ ما بتمسحش المعدِّلات', () {
    test('صنف بمعدِّلات: الملاحظة بتتضاف والمعدِّلات بتفضل في النص', () {
      seed(CartItemEntity(
        productId: 7,
        productName: 'شاورما',
        productCode: 'S01',
        quantity: 1,
        unitPrice: 50,
        note: '(الحجم: كبير)',
        modifiers: [option('الحجم', 'كبير')],
      ));

      applyTablePosItemNote(cart, 0, 'بدون بصل');

      expect(first().itemNote, 'بدون بصل');
      expect(first().note, '(الحجم: كبير) | 📝 بدون بصل');
      expect(first().modifiers, hasLength(1));
    });

    test('«حذف الملاحظة» بيمسح فعلاً — النص الفاضي معناه مسح', () {
      seed(CartItemEntity(
        productId: 7,
        productName: 'شاورما',
        productCode: 'S01',
        quantity: 1,
        unitPrice: 50,
        note: '(الحجم: كبير) | 📝 بدون بصل',
        itemNote: 'بدون بصل',
        modifiers: [option('الحجم', 'كبير')],
      ));

      applyTablePosItemNote(cart, 0, '');

      expect(first().itemNote, isNull);
      expect(first().note, '(الحجم: كبير)');
    });

    test('صنف بلا معدِّلات: النص بيبقى الملاحظة بالبادئة اللي الطباعة بتقراها',
        () {
      seed(const CartItemEntity(
        productId: 7,
        productName: 'شاي',
        productCode: 'T01',
        quantity: 1,
        unitPrice: 10,
      ));

      applyTablePosItemNote(cart, 0, 'سكر زيادة');

      expect(first().note, '📝 سكر زيادة');
    });
  });
}
