// أثرُ سياسة البيع السريع — قياسُ **السلوك** لا وجودِ الإعداد.
//
// ═══ لماذا هذا الملفُّ غيرُ `quick_sale_limits_test` ═══
//
// `quick_sale_limits_test` يبني `QuickSalePolicyValues` **يدوياً** من خريطةٍ
// حرفيّة، فيقيس الترجمةَ وحدَها. وهي خضراءُ منذ يومها، والميزةُ مع ذلك كانت
// ميّتةً في الميدان (‏بلاغُ المالك 2026-08-30).
//
// فهذا الملفُّ يبدأ من حيث يبدأ المديرُ: **يكتب في القاعدة**، ثمّ يمرّ
// بالمزوِّد الحقيقيّ، ثمّ يطبّق **دالّةَ القرار التي يناديها مسارُ الكاشير
// بعينها**، ثمّ يؤكّد على المآل. أيُّ حلقةٍ تنكسر — مفتاحٌ مختلف، فهرسٌ
// مقلوب، مزوِّدٌ لا يُعاد جلبُه — تُسقط اختباراً هنا.
//
// ⚠️ **ولا `db.close()`**: مؤقّتُ drift ينتظر في المنطقة الوهمية فيعلّق.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/data/providers/quick_sale_policy_providers.dart';
import 'package:ural_erp/domain/entities/cart_item_entity.dart';
import 'package:ural_erp/domain/models/quick_sale_policy.dart';
import 'package:ural_erp/domain/usecases/sales/hold_order_usecase.dart';
import 'package:ural_erp/presentation/pos_picpos/widgets/picpos_payment_methods.dart';

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

  /// يكتب الإعداداتِ ثمّ يُعيد بناءَ السياسة **كما تفعل شاشةُ الإعدادات**
  /// (‏حفظٌ ثمّ `ref.invalidate`)، ويرجع القيمَ كما تصل نقطةَ القرار.
  Future<QuickSalePolicyValues> save(Map<String, String> settings) async {
    await db.saveSettings(settings);
    container.invalidate(quickSalePolicyProvider);
    return container.read(quickSalePolicyProvider.future);
  }

  // ══════════════════════════════════════════════════════════════════════
  // holdmax — pos_hold_max_orders
  // ══════════════════════════════════════════════════════════════════════
  group('holdmax — سقفُ الفواتير المعلّقة', () {
    /// ينشئ فاتورةً معلّقةً حقيقيّةً عبر **حالةِ الاستعمال نفسِها** التي
    /// يناديها زرُّ «تعليق» في شاشة الكاشير.
    Future<void> holdOne(int productId, String tag) async {
      final res = await container.read(holdOrderUseCaseProvider).executeHold(
            HoldOrderRequest(
              items: [
                CartItemEntity(
                  productId: productId,
                  productName: 'صنف $tag',
                  productCode: 'P$tag',
                  quantity: 1,
                  unitPrice: 10,
                ),
              ],
              subtotal: 10,
              discountPercent: 0,
              customerName: tag,
            ),
          );
      expect(res, isNotNull, reason: 'التعليقُ نفسُه أخفق — لا علاقةَ للسياسة');
    }

    test('سقفٌ ٥ — خمسُ فواتيرَ تمرّ والسادسةُ تُرفض على قاعدةٍ حقيقيّة',
        () async {
      final productId = await db.insertProduct(
        ProductsCompanion.insert(
          code: 'HOLD-1',
          name: 'صنف تعليق',
          salePrice: const Value(10),
        ),
      );

      // اشتراكٌ واحدٌ يبقى حيّاً طوالَ الاختبار: `heldOrdersProvider`
      // هو `autoDispose`، وإغلاقُ الاشتراك بين قياسَين يُتلفه فيعود
      // ببثٍّ أوّلَ قديم.
      final sub = container.listen(heldOrdersProvider, (_, _) {});
      addTearDown(sub.close);

      /// نفسُ المزوِّد الذي يقرأه `_holdOrder` بالحرف — بانتظارِ بثِّ
      /// drift لا بقراءةٍ فوريّة.
      Future<int> heldCount(int expected) async {
        for (var i = 0; i < 200; i++) {
          final v = container.read(heldOrdersProvider).value;
          if (v != null && v.length == expected) return v.length;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return container.read(heldOrdersProvider).value?.length ?? -1;
      }

      // المديرُ يختار «٥» — الفهرسُ ٠ في التصميم.
      final policy = await save({'pos_hold_max_orders': '0'});
      final cap = quickSaleHoldCap(policy);
      expect(cap, 5, reason: 'الإعدادُ لم يصل — والباقي بلا معنى');

      for (var i = 1; i <= 5; i++) {
        final before = await heldCount(i - 1);
        expect(before, i - 1,
            reason: 'المزوِّدُ لم يلحق بالقاعدة قبل الفاتورة رقم $i');
        expect(
          quickSaleCanHoldMore(current: before, cap: cap),
          isTrue,
          reason: 'الفاتورةُ رقم $i يجب أن تُقبل (المعلَّقُ الآن $before)',
        );
        await holdOne(productId, 'H$i');
      }

      final now = await heldCount(5);
      expect(now, 5, reason: 'خمسُ فواتيرَ فعليّةٍ في القاعدة');
      expect(
        quickSaleCanHoldMore(current: now, cap: cap),
        isFalse,
        reason: 'السادسةُ يجب أن تُرفض — الوصولُ للحدّ يمنع لا تجاوزُه',
      );
    });

    test('«بلا حد» تُبقي البابَ مفتوحاً عند العشرين', () async {
      final policy = await save({'pos_hold_max_orders': '3'});
      expect(quickSaleHoldCap(policy), isNull);
      expect(
        quickSaleCanHoldMore(current: 20, cap: quickSaleHoldCap(policy)),
        isTrue,
        reason: '«بلا حد» ليست صفراً — وصفرٌ كان سيمنع كلَّ تعليق',
      );
    });

    test('تغييرُ الإعداد بعد قراءةٍ سابقةٍ يصل فوراً — محاكاةُ الحفظ', () async {
      final first = await save({'pos_hold_max_orders': '2'});
      expect(quickSaleHoldCap(first), 20);

      // المديرُ يعود ويشدّه إلى ٥.
      final second = await save({'pos_hold_max_orders': '0'});
      expect(quickSaleHoldCap(second), 5,
          reason: 'قيمةٌ قديمةٌ مخزَّنةٌ في مزوِّدٍ لا يُبطَل = إعدادٌ ميّت');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // maxqty — pos_max_line_quantity
  // ══════════════════════════════════════════════════════════════════════
  group('maxqty — أقصى كميّةٍ في السطر', () {
    /// الشرطُ الحرفيُّ في `picpos_pos_operations.dart:1313` و`:617`.
    bool rejected(double qty, double? maxQty) => maxQty != null && qty > maxQty;

    test('سقفٌ ٩٩ — ٩٩ تمرّ و١٠٠ تُرفض', () async {
      final policy = await save({'pos_max_line_quantity': '0'});
      final maxQty = quickSaleMaxLineQty(policy);
      expect(maxQty, 99);
      expect(rejected(99, maxQty), isFalse,
          reason: 'المساواةُ مسموحة — «أقصى» تشمل الحدَّ نفسَه');
      expect(rejected(99.5, maxQty), isTrue);
      expect(rejected(100, maxQty), isTrue);
    });

    test('«بلا حد» لا ترفض ألفاً', () async {
      final policy = await save({'pos_max_line_quantity': '3'});
      expect(quickSaleMaxLineQty(policy), isNull);
      expect(rejected(1000, quickSaleMaxLineQty(policy)), isFalse);
    });

    test('والافتراضُ في قاعدةٍ جديدةٍ ٩٩٩ لا «بلا حد»', () async {
      final policy = await container.read(quickSalePolicyProvider.future);
      expect(quickSaleMaxLineQty(policy), 999);
      expect(rejected(1000, quickSaleMaxLineQty(policy)), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // diffmax — pos_shift_diff_threshold
  // ══════════════════════════════════════════════════════════════════════
  group('diffmax — فرقُ الوردية', () {
    test('حدٌّ ٢٠ — العجزُ ٢٥ يطلب سبباً كما الزيادةُ ٢٥', () async {
      final policy = await save({'pos_shift_diff_threshold': '1'});
      final limit = quickSaleShiftDiffLimit(policy);
      expect(limit, 20);

      expect(
        quickSaleShiftDiffNeedsReason(difference: 25, limit: limit),
        isTrue,
        reason: 'الزيادةُ فوق الحدّ',
      );
      expect(
        quickSaleShiftDiffNeedsReason(difference: -25, limit: limit),
        isTrue,
        reason: 'العجزُ ٢٥ هو الأخطرُ محاسبيّاً — مالٌ ناقصٌ بلا تفسير. '
            'وإهمالُ الإشارة يُعفيه.',
      );
      expect(
        quickSaleShiftDiffNeedsReason(difference: 20, limit: limit),
        isFalse,
        reason: 'المساواةُ تمرّ — «فوق الحدّ» لا «عنده»',
      );
      expect(
        quickSaleShiftDiffNeedsReason(difference: -20, limit: limit),
        isFalse,
      );
    });

    test('«بلا حد» تُمرّر ألفاً بلا سبب', () async {
      final policy = await save({'pos_shift_diff_threshold': '3'});
      expect(quickSaleShiftDiffLimit(policy), isNull);
      expect(
        quickSaleShiftDiffNeedsReason(
            difference: -1000, limit: quickSaleShiftDiffLimit(policy)),
        isFalse,
      );
    });

    test('حدٌّ ٥ وهو أشدُّ الخيارات يمسك فرقَ ٥٫٠١', () async {
      final policy = await save({'pos_shift_diff_threshold': '0'});
      final limit = quickSaleShiftDiffLimit(policy);
      expect(limit, 5);
      expect(quickSaleShiftDiffNeedsReason(difference: -5.01, limit: limit),
          isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // copies / after / drawer — §٤ الطباعة
  // ══════════════════════════════════════════════════════════════════════
  group('الطباعة', () {
    test('copies — «٣ نسخ» تعني ثلاثَ دوراتٍ في حلقة الطباعة', () async {
      final policy = await save({'pos_receipt_copies': '2'});
      expect(quickSaleReceiptCopies(policy), 3);

      // نفسُ الحلقة في `picpos_pos_operations.dart:1786`.
      var printed = 0;
      for (var i = 0; i < quickSaleReceiptCopies(policy); i++) {
        printed++;
      }
      expect(printed, 3);
    });

    test('copies — لا يكون صفراً أبداً مهما فسدت القيمة', () async {
      for (final raw in ['-1', '9', 'نص', '']) {
        final policy = await save({'pos_receipt_copies': raw});
        expect(quickSaleReceiptCopies(policy), greaterThanOrEqualTo(1),
            reason: 'قيمةٌ «$raw» أعطت صفراً — بيعةٌ بلا إيصال');
      }
    });

    test('drawer — مطفأٌ فالدرجُ لا يُفتح ولو كان الدفعُ نقديّاً', () async {
      final policy = await save({'pos_open_drawer_on_print': 'false'});
      // نفسُ التعبير في `picpos_pos_operations.dart:1774`.
      bool opens(String method) =>
          policy.isOn(kQuickSaleRows.firstWhere((r) => r.id == 'drawer')) &&
          method == 'cash';
      expect(opens('cash'), isFalse);
      expect(opens('card'), isFalse);
    });

    test('drawer — مضاءٌ فنقديٌّ يفتح وبطاقةٌ لا', () async {
      final policy = await save({'pos_open_drawer_on_print': 'true'});
      bool opens(String method) =>
          policy.isOn(kQuickSaleRows.firstWhere((r) => r.id == 'drawer')) &&
          method == 'cash';
      expect(opens('cash'), isTrue);
      expect(opens('card'), isFalse,
          reason: 'بيعةُ بطاقةٍ لا نقدَ فيها — فتحُ الدرج يعرّض النقدَ بلا سبب');
    });

    test('after — الخياراتُ الثلاثةُ تُترجَم إلى وجهاتٍ مختلفة', () async {
      expect(
          quickSaleAfterPrintAction(await save({'pos_after_print_action': '0'})),
          QuickSaleAfterPrintAction.newInvoice);
      expect(
          quickSaleAfterPrintAction(await save({'pos_after_print_action': '1'})),
          QuickSaleAfterPrintAction.stay);
      expect(
          quickSaleAfterPrintAction(await save({'pos_after_print_action': '2'})),
          QuickSaleAfterPrintAction.lockScreen);
    });

    test('after — الافتراضُ «فاتورةٌ جديدة» في قاعدةٍ بكر', () async {
      final policy = await container.read(quickSalePolicyProvider.future);
      expect(quickSaleAfterPrintAction(policy),
          QuickSaleAfterPrintAction.newInvoice);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // skipdlg / defmethod / quickamt — مسارُ الدفع
  // ══════════════════════════════════════════════════════════════════════
  group('مسارُ الدفع', () {
    QuickSaleRow row(String id) => kQuickSaleRows.firstWhere((r) => r.id == id);

    test('skipdlg مطفأٌ فحوارُ الدفع يظهر ولو كانت الطريقةُ واحدة', () async {
      final policy =
          await save({'pos_skip_payment_dialog_single_method': 'false'});
      final skip = policy.isOn(row('skipdlg'));
      expect(skip, isFalse);
      // نفسُ السطر في `picpos_pos_operations.dart:1635`.
      final fastPath = skip ? singlePaymentMethodFastPath({'cash'}) : null;
      expect(fastPath, isNull,
          reason: 'إطفاءُ المِزلاج يجب أن يُلغيَ المسارَ السريع');
    });

    test('skipdlg مضاءٌ فطريقةٌ واحدةٌ تتخطّى الحوار', () async {
      final policy =
          await save({'pos_skip_payment_dialog_single_method': 'true'});
      final skip = policy.isOn(row('skipdlg'));
      final fastPath = skip ? singlePaymentMethodFastPath({'cash'}) : null;
      expect(fastPath, 'cash');
    });

    test('skipdlg مضاءٌ لكن الطرقُ اثنتان فالحوارُ يبقى', () async {
      final policy =
          await save({'pos_skip_payment_dialog_single_method': 'true'});
      final skip = policy.isOn(row('skipdlg'));
      expect(
          skip ? singlePaymentMethodFastPath({'cash', 'card'}) : null, isNull);
    });

    test('defmethod — الفهارسُ الأربعةُ ترجع رموزَ المحرّك', () async {
      expect(
          quickSaleDefaultPaymentMethod(
              await save({'pos_default_payment_method': '0'})),
          'cash');
      expect(
          quickSaleDefaultPaymentMethod(
              await save({'pos_default_payment_method': '1'})),
          'card');
      expect(
          quickSaleDefaultPaymentMethod(
              await save({'pos_default_payment_method': '2'})),
          'click');
      expect(
          quickSaleDefaultPaymentMethod(
              await save({'pos_default_payment_method': '3'})),
          'credit');
    });

    test('quickamt مطفأٌ فلوحُ المبالغ السريعة يُمرَّر false للحوار', () async {
      final policy = await save({'pos_quick_amounts_enabled': 'false'});
      expect(policy.isOn(row('quickamt')), isFalse);
    });

    test('quickamt مضاءٌ فيُمرَّر true', () async {
      final policy = await save({'pos_quick_amounts_enabled': 'true'});
      expect(policy.isOn(row('quickamt')), isTrue);
    });

    test('mgrlimit — «١٠٠٠» تطلب تأكيداً عند ١٠٠٠٫٠١ لا عند ١٠٠٠', () async {
      final policy = await save({'pos_manager_confirm_above': '0'});
      final above = quickSaleManagerConfirmAbove(policy);
      expect(above, 1000);
      // نفسُ الشرط في `picpos_pos_operations.dart:1569`.
      expect(above != null && 1000.01 > above, isTrue);
      expect(above != null && 1000 > above, isFalse);
    });

    test('mgrlimit — «بلا حد» لا تطلب تأكيداً لمليون', () async {
      final policy = await save({'pos_manager_confirm_above': '3'});
      final above = quickSaleManagerConfirmAbove(policy);
      expect(above, isNull);
      expect(above != null && 1000000 > above, isFalse,
          reason: 'null تعني «بلا حد» لا صفراً — وصفرٌ كان يطلب موافقةً '
              'لكلّ فاتورة');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // unknown — مصيرُ الباركود المجهول
  // ══════════════════════════════════════════════════════════════════════
  group('unknown — الباركودُ المجهول', () {
    test('«ارفض» تُترجَم رفضاً لا إنشاءَ صنف', () async {
      final policy = await save({'pos_unknown_barcode_action': '2'});
      expect(quickSaleUnknownBarcodeAction(policy),
          QuickSaleUnknownBarcodeAction.reject,
          reason: 'فهرسٌ يُقرأ خطأً يقلب «ارفض» إلى «أنشئ صنفاً» — أوسعُ '
              'بابٍ في هذه الشاشة');
    });

    test('«بحثٌ بالاسم» وسطاً', () async {
      expect(
        quickSaleUnknownBarcodeAction(
            await save({'pos_unknown_barcode_action': '1'})),
        QuickSaleUnknownBarcodeAction.nameSearch,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // priceedit — §٤
  // ══════════════════════════════════════════════════════════════════════
  group('priceedit', () {
    test('«ممنوع» تُترجَم منعاً', () async {
      final policy = await save({'pos_price_edit_policy': '0'});
      expect(quickSalePriceEditPolicy(policy), QuickSalePriceEditPolicy.blocked);
    });

    test('«مسموح» لا تمنع', () async {
      final policy = await save({'pos_price_edit_policy': '2'});
      expect(quickSalePriceEditPolicy(policy),
          isNot(QuickSalePriceEditPolicy.blocked));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // دورةٌ كاملةٌ لكلّ مفتاح
  // ══════════════════════════════════════════════════════════════════════
  group('كلُّ مفتاحٍ في السياسة يُقرأ من القاعدة كما كُتب', () {
    test('كتابةٌ ثمّ مزوِّدٌ ثمّ قراءة، لكلِّ صفوف الشاشة', () async {
      final written = <String, String>{};
      for (final r in kQuickSaleRows) {
        written[r.settingKey] = r.kind == QuickSaleControl.toggle
            ? 'true'
            : r.kind == QuickSaleControl.number
                ? (r.defaultNumber ?? 1).toString()
                : '0';
      }
      final policy = await save(written);
      for (final r in kQuickSaleRows) {
        expect(policy.raw[r.settingKey], written[r.settingKey],
            reason: 'المفتاحُ «${r.settingKey}» (${r.id}) لم يعد من القاعدة');
      }
    });
  });
}
