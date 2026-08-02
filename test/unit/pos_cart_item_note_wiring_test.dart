// باج ملاحظة الكاشير — الحلقة كاملة من الديالوج للفاتورة المحفوظة.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// الكاشير بيفتح «تعديل الصنف» في `PosScreenV2`، بيكتب ملاحظة، بيحفظ،
// والملاحظة بتتبخّر. `PosDialogs.showEditCartItem` بترجّع
// `CartItemEditData(price:, note:)` صح، لكن المستدعي في
// `pos_main_dialogs.dart` كان بيقرا `shouldDelete` و`price` **بس**
// ويرمي `note` في الأرض. مفيش نداء لـ`updateItemNote` خالص.
//
// ── ليه تلات اختبارات مش واحد ────────────────────────────────────────────────
// الملاحظة بتعدّي على تلات حلقات مستقلة، وكل واحدة انكسرت قبل كده أو ممكن
// تنكسر لوحدها:
//   (أ) نتيجة الديالوج → نداء `updateItemNote`  ← ده اللي كان مقطوع
//   (ب) `itemNote` اليدوي + المعدِّلات → نص `note` المركّب
//   (ج) نص `note` المركّب → سطر الفاتورة المحفوظ
// اختبار على (ب) لوحده كان هيفضل أخضر والباج شغّال، لأن (ب) مكسورش أصلاً.
//
// ── ليه دوال top-level مش اختبار ودجت ────────────────────────────────────────
// `_showEditItemDialog` جوه mixin على `ConsumerState<PosScreenV2>` — تركيبه
// يحتاج شاشة نقطة بيع كاملة على `AppDatabase.forTesting()` (مهلة ١٠ دقايق،
// نفس فخ Task 6a/7). فالخطوة اللي بتطبّق نتيجة الديالوج اتستخرجت لدالة
// top-level `applyCartItemEdit` والإنتاج بينادي نفسها بالظبط.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/data/repositories/sales_transaction_orchestrator.dart';
import 'package:ural_erp/presentation/pos/providers/cart_controller.dart';
import 'package:ural_erp/presentation/pos/screens/pos_main_screen.dart';
import 'package:ural_erp/presentation/pos/widgets/modifier_selection_dialog.dart';
import 'package:ural_erp/presentation/pos/widgets/pos_dialogs.dart';

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  // (أ) التوصيلة: نتيجة الديالوج → نداء updateItemNote
  // ═════════════════════════════════════════════════════════════════════════
  group('applyCartItemEdit — نتيجة ديالوج تعديل الصنف بتتطبّق كاملة', () {
    late List<String> calls;
    late String? capturedNote;
    late double? capturedPrice;

    /// بيجمع النداءات بالترتيب عشان الاختبار يمسك **غياب** أي نداء، مش بس
    /// قيمته — لو حد مسح سطر الملاحظة تاني، `calls` هيفضل من غير 'note'.
    void run(CartItemEditData edit) {
      calls = [];
      capturedNote = null;
      capturedPrice = null;
      applyCartItemEdit(
        edit,
        onDelete: () => calls.add('delete'),
        onPrice: (p) {
          calls.add('price');
          capturedPrice = p;
        },
        onNote: (n) {
          calls.add('note');
          capturedNote = n;
        },
      );
    }

    test('الملاحظة بتتمرّر لما الكاشير يكتبها', () {
      run(const CartItemEditData(price: 25, note: 'بدون سكر'));
      expect(calls, contains('note'));
      expect(capturedNote, 'بدون سكر');
    });

    test('السعر بيتمرّر مع الملاحظة في نفس الحفظة', () {
      run(const CartItemEditData(price: 25, note: 'بدون سكر'));
      expect(calls, containsAll(<String>['price', 'note']));
      expect(capturedPrice, 25);
    });

    test('مسح الملاحظة بيتمرّر كـnull مش بيتتجاهل', () {
      run(const CartItemEditData(price: 25, note: null));
      expect(calls, contains('note'));
      expect(capturedNote, isNull);
    });

    test('حفظ الملاحظة من غير تغيير السعر شغّال', () {
      run(const CartItemEditData(note: 'حار'));
      expect(calls, contains('note'));
      expect(calls, isNot(contains('price')));
      expect(capturedNote, 'حار');
    });

    test('الحذف بيلغي أي كتابة تانية — الصنف مش موجود أصلاً', () {
      run(const CartItemEditData.delete());
      expect(calls, <String>['delete']);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // (ب) التركيب: itemNote + المعدِّلات → نص note المركّب
  // ═════════════════════════════════════════════════════════════════════════
  group('composeCartItemNote — الملاحظة اليدوية ما بتمسحش المعدِّلات', () {
    SelectedModifier option(String group, String name) => SelectedModifier(
          itemId: 1,
          itemName: name,
          groupName: group,
          extraPrice: 0,
          isOption: true,
        );

    SelectedModifier addon(String name, double price) => SelectedModifier(
          itemId: 2,
          itemName: name,
          groupName: 'إضافات',
          extraPrice: price,
        );

    test('ملاحظة يدوية من غير معدِّلات', () {
      expect(composeCartItemNote(const [], 'بدون سكر'), '📝 بدون سكر');
    });

    test('المعدِّلات بتفضل قدّام الملاحظة اليدوية', () {
      expect(
        composeCartItemNote([option('الحجم', 'كبير'), addon('جبنة', 5)],
            'بدون سكر'),
        '(الحجم: كبير) | +جبنة 5 ${AppConstants.currencySymbolEn} | '
            '📝 بدون سكر',
      );
    });

    test('مسح الملاحظة اليدوية بيسيب المعدِّلات مكانها', () {
      expect(
        composeCartItemNote([option('الحجم', 'كبير')], null),
        '(الحجم: كبير)',
      );
    });

    test('لا معدِّلات ولا ملاحظة → null مش نص فاضي', () {
      expect(composeCartItemNote(const [], null), isNull);
      expect(composeCartItemNote(const [], ''), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // (ج) الترحيل: نص note المركّب → سطر الفاتورة المحفوظ
  // ═════════════════════════════════════════════════════════════════════════
  group('buildSalesLineCompanion — الملاحظة بتوصل لسطر الفاتورة', () {
    test('note المركّب بيتكتب في سطر الفاتورة زي ما هو', () {
      final note = composeCartItemNote(const [], 'بدون سكر');
      final line = SalesTransactionOrchestrator.buildSalesLineCompanion(
        item: CartItemEntity(
          productId: 7,
          productName: 'شاي',
          productCode: 'T01',
          quantity: 1,
          unitPrice: 10,
          itemNote: 'بدون سكر',
          note: note,
        ),
        netBeforeTax: 10,
        netTax: 0,
        netRate: 0,
      );
      expect(line.note.value, '📝 بدون سكر');
    });
  });
}
