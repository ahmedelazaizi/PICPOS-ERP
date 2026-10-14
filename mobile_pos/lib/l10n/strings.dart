import 'package:flutter/widgets.dart';
import 'package:picpos_ui/picpos_ui.dart';

/// Arabic (default) + English strings of PicPos كاشير.
abstract final class S {
  static const table = L10nTable({
    'appTitle': ('PicPos كاشير', 'PicPos Cashier'),
    'navSale': ('البيع', 'Sale'),
    'navHeld': ('المعلّقة', 'Held'),
    'navShift': ('الوردية', 'Shift'),
    'navReturns': ('المرتجعات', 'Returns'),
    'navSettings': ('الإعدادات', 'Settings'),
    'saleSub': ('الأصناف والسلة والدفع', 'Items, cart and payment'),
    'heldSub': ('الطلبات المعلّقة على هذا الجهاز', 'Orders held on this tablet'),
    'shiftSub': ('فتح الوردية وإغلاقها وجرد الدرج', 'Open, close and count the drawer'),
    'returnsSub': ('مرتجع برقم الفاتورة', 'Return by invoice number'),
    'settingsSub': ('اللغة والمظهر والطابعة والربط', 'Language, theme, printer and pairing'),
    'items': ('الأصناف', 'Items'),
    'itemsMsg': ('هذه معاينة فقط؛ عرض الأصناف والبحث غير متاح.', 'Preview only. Items and search are not available.'),
    'scanOrSearch': ('امسح الباركود أو ابحث عن صنف', 'Scan a barcode or search an item'),
    'cart': ('السلة', 'Cart'),
    'cartEmpty': ('السلة فارغة', 'Cart is empty'),
    'subtotal': ('المجموع', 'Subtotal'),
    'tax': ('الضريبة', 'Tax'),
    'total': ('الإجمالي', 'Total'),
    'pay': ('الدفع', 'Pay'),
    'comingTitle': ('قيد الإنشاء', 'Coming soon'),
    'heldComing': ('هذه معاينة فقط؛ الطلبات المعلّقة غير متاحة.', 'Preview only. Held orders are not available.'),
    'shiftComing': ('هذه معاينة فقط؛ إدارة الورديات غير متاحة.', 'Preview only. Shift management is not available.'),
    'returnsComing': ('هذه معاينة فقط؛ المرتجعات غير متاحة.', 'Preview only. Returns are not available.'),
    'printer': ('الطابعة', 'Printer'),
    'printerMsg': ('هذه معاينة فقط؛ إعداد الطابعة غير متاح.', 'Preview only. Printer setup is not available.'),
    'pairing': ('الربط', 'Pairing'),
    'openPairing': ('شاشة الربط', 'Pairing screen'),
    'about': ('حول التطبيق', 'About'),
    'version': ('الإصدار {v}', 'Version {v}'),
    'pairTitle': ('ربط جهاز الكاشير', 'Pair this cashier tablet'),
    'pairSub': ('بجهاز المكتب الرئيسي عبر شبكة المحل', 'With the main desktop over the shop network'),
    'pairStep1': ('على جهاز المكتب: «ربط جهاز كاشير» واختر الفرع.', 'On the desktop: “Pair cashier device” and choose the branch.'),
    'pairStep2': ('امسح رمز QR الظاهر على الشاشة.', 'Scan the QR code shown on the screen.'),
    'pairStep3': ('أكّد الفرع ورقم الجهاز ثم اضبط الطابعة.', 'Confirm the branch and terminal, then set up the printer.'),
    'scanQr': ('مسح رمز QR', 'Scan QR code'),
    'manualEntry': ('أو أدخل الرمز يدوياً', 'Or enter the code manually'),
    'serverAddress': ('عنوان جهاز المكتب', 'Desktop address'),
    'pairingCode': ('رمز الربط', 'Pairing code'),
    'pair': ('ربط', 'Pair'),
    'previewOnly': ('معاينة فقط — الربط غير متاح حالياً', 'Preview only — pairing is not available yet'),
    'previewStatus': ('معاينة فقط', 'Preview only'),
    'previewApp': ('معاينة التطبيق', 'Preview the app'),
  });

  static Tr of(BuildContext context) => Tr.of(context, table);
}
