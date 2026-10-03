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
    'itemsMsg': ('شبكة الأصناف والبحث والباركود تصل في المرحلة M-5.', 'Items grid, search and barcode arrive in M-5.'),
    'scanOrSearch': ('امسح الباركود أو ابحث عن صنف', 'Scan a barcode or search an item'),
    'cart': ('السلة', 'Cart'),
    'cartEmpty': ('السلة فارغة', 'Cart is empty'),
    'subtotal': ('المجموع', 'Subtotal'),
    'tax': ('الضريبة', 'Tax'),
    'total': ('الإجمالي', 'Total'),
    'pay': ('الدفع', 'Pay'),
    'comingTitle': ('قيد الإنشاء', 'Coming soon'),
    'heldComing': ('الطلبات المعلّقة تصل في المرحلة M-6.', 'Held orders arrive in M-6.'),
    'shiftComing': ('فتح الوردية وإغلاقها يصلان في المرحلة M-5.', 'Opening and closing shifts arrive in M-5.'),
    'returnsComing': ('المرتجعات تصل في المرحلة M-6.', 'Returns arrive in M-6.'),
    'printer': ('الطابعة', 'Printer'),
    'printerMsg': ('بلوتوث أو شبكة (IP:9100)، ورق 58/80 مم، فتح الدرج — المرحلة M-5.',
        'Bluetooth or network (IP:9100), 58/80 mm paper, drawer kick — phase M-5.'),
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
    'previewOnly': ('معاينة — الربط يُفعَّل في المرحلة M-5', 'Preview — pairing is enabled in M-5'),
    'previewApp': ('معاينة التطبيق', 'Preview the app'),
  });

  static Tr of(BuildContext context) => Tr.of(context, table);
}
