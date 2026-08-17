// بلاغُ مالكٍ (2026-08-17): «ديالوج اضافة سريعة للاصناف فى حالة قراءة
// باركود صنف غير مسجل — الامر ده كنت عامله فى ural بس انت مجبتهوش معاك
// كمنطق عمل». `QuickAddProductDialog` كان موجوداً ومكتملاً بالفعل
// (`lib/presentation/pos/dialogs/quick_add_product_dialog.dart`) ومُستدعىً
// من مسار البيع القديم (`pos_main_operations.dart:442`)، لكن **صفرَ**
// استدعاءٍ له في `lib/presentation/pos_picpos/` — توصيلٌ ناقصٌ لا منطقٌ
// مفقود.
//
// ── ما يقيسه هذا الملفّ ──────────────────────────────────────────────────
// `shouldOfferQuickAdd` — دالّةُ القرار الخالصة وراء فتح الديالوج من
// `_searchBarcode` في `picpos_pos_operations.dart`. تفتح **فقط** حين:
//   1. الباركودُ غيرُ مسجَّلٍ فعلاً (`errorKind == notFound`) — لا صنفٌ
//      معطَّل، ولا باركودُ ميزانٍ فشل تحليلُه (`invalidScale`)، ولا خطأٌ
//      عامّ (`general`).
//   2. ليس في وضع مرتجع (‏`blocksCartMutation`، القيدُ الأوّل من بلاغ
//      المالك).
//
// اختبارُ فتح الديالوج فعلياً يحتاج شجرةَ ودجت كاملة + `ProviderScope` +
// تمويهَ `productRepositoryProvider`/`currentUserPermissionsProvider`، وهو
// هشٌّ ومكلفٌ مقابل قيمةٍ أقلّ من اختبار دالّة القرار الخالصة مباشرة —
// نفسُ المفاضلة الموثّقة في `picpos_quick_return_lines_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/returnable_line.dart';
import 'package:ural_erp/presentation/pos/providers/pos_search_controller.dart'
    show BarcodeSearchErrorKind;
import 'package:ural_erp/presentation/pos_picpos/screens/picpos_pos_screen.dart'
    as picpos;
import 'package:ural_erp/presentation/pos_picpos/state/pos_return_mode.dart';

void main() {
  PosReturnMode buildReturnMode() {
    const line = ReturnableLine(
      invoiceItemId: 1,
      productId: 10,
      productName: 'لوز',
      soldQty: 5,
      alreadyReturnedQty: 0,
      unitPrice: 20,
    );
    return PosReturnMode.fromLines(invoiceId: 1, lines: [line]);
  }

  group('shouldOfferQuickAdd', () {
    test('باركودٌ غيرُ مسجَّلٍ فعلاً وليس وضعَ مرتجع ⇒ يفتح', () {
      expect(
        picpos.shouldOfferQuickAdd(BarcodeSearchErrorKind.notFound, null),
        isTrue,
      );
    });

    test('باركودُ ميزانٍ فشل تحليلُه (`invalidScale`) ⇒ لا يفتح — القيد '
        'الخامس من بلاغ المالك', () {
      expect(
        picpos.shouldOfferQuickAdd(BarcodeSearchErrorKind.invalidScale, null),
        isFalse,
      );
    });

    test('صنفٌ معطَّل (`inactive`) ⇒ لا يفتح — لا يجوز اقتراحُ تكرارِه', () {
      expect(
        picpos.shouldOfferQuickAdd(BarcodeSearchErrorKind.inactive, null),
        isFalse,
      );
    });

    test('خطأٌ عامّ (`general`) ⇒ لا يفتح', () {
      expect(
        picpos.shouldOfferQuickAdd(BarcodeSearchErrorKind.general, null),
        isFalse,
      );
    });

    test('بلا خطأٍ إطلاقاً (`errorKind == null`) ⇒ لا يفتح', () {
      expect(picpos.shouldOfferQuickAdd(null, null), isFalse);
    });

    test('باركودٌ غيرُ مسجَّلٍ **أثناء وضع مرتجع** ⇒ لا يفتح — القيدُ '
        'الأوّل من بلاغ المالك، `blocksCartMutation` نفسُها التي تحرس '
        '`_handleProductTap`/`_showHeldOrders`', () {
      expect(
        picpos.shouldOfferQuickAdd(
            BarcodeSearchErrorKind.notFound, buildReturnMode()),
        isFalse,
      );
    });
  });
}
