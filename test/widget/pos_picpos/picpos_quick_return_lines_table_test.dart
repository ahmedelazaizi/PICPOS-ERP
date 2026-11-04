// «سلّة المرتجع» في عمود الفاتورة — عيبُ التحقّق الحيّ final3 (2026-11-03):
// بعد «تأكيد المرتجع» كان العمودُ يعرض جدولَ سلّة البيع الفارغة، فلا يرى
// الكاشيرُ بنودَ الفاتورة ولا يعدّلها. يقيس هذا الملفّ:
//  ١. اللوحةُ تعرض بنودَ `PosReturnMode` بكميّاتها ومتاحها ومبلغَ الاسترداد.
//  ٢. «+»/«−»/«استبعاد» تمرّ بنسخةٍ جديدةٍ في `posReturnModeProvider`، فيتحدّث
//     العرضُ **وزرُّ «دفع» في لوحة الدفع** معاً (تعديلُ الكائن في مكانه لا
//     يُخطر أحداً).
//  ٣. الشاشةُ موصولةٌ فعلاً: عمودُ الفاتورة يختار اللوحةَ في وضع المرتجع،
//     والشبكةُ/حقلُ المسح يوجَّهان للمرتجع لا للرفض الشامل (فحصُ مصدر —
//     الشاشةُ الكاملة لا تُضخّ في اختبارٍ بلا قاعدةٍ وورديّة).
//  ٤. لا مخالفاتِ تباين فاتحاً وداكناً.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/models/returnable_line.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';
import 'package:picpos_erp/presentation/pos_picpos/providers/pos_return_mode_provider.dart';
import 'package:picpos_erp/presentation/pos_picpos/screens/picpos_pos_screen.dart'
    as picpos;
import 'package:picpos_erp/presentation/pos_picpos/state/pos_return_mode.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_one_time_customer.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_payment_panel.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_quick_return_lines_table.dart';

import '../../support/contrast_audit.dart';

const _almond = ReturnableLine(
  invoiceItemId: 7,
  productId: 4,
  productName: 'لوز انصاص',
  soldQty: 2,
  alreadyReturnedQty: 0,
  unitPrice: 6.99,
  lineTotal: 13.98,
);

PosReturnMode _mode() => PosReturnMode.fromLines(
  invoiceId: 7,
  lines: const [_almond],
  invoiceTotal: 13.98,
);

class _EmptyCart extends CartController {
  @override
  CartState build() => CartState();
}

class _Auth extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    isAuthenticated: true,
    userWithRole: db.UserWithRole(
      user: db.User(
        id: 1,
        username: 'tester',
        passwordHash: '',
        passwordSalt: '',
        displayName: 'كاشير',
        defaultScreen: '0',
        isLocked: false,
        isActive: true,
        discountLimitIsPercent: true,
        forcePasswordChange: false,
        createdAt: DateTime(2026, 1, 1),
        rowVersion: 1,
      ),
    ),
  );
}

final _overrides = <Override>[
  cartControllerProvider.overrideWith(_EmptyCart.new),
  authProvider.overrideWith(_Auth.new),
  heldOrdersProvider.overrideWith((ref) => Stream.value(const [])),
  currentUserPermissionsProvider.overrideWith(
    (ref) async => const ['system_admin'],
  ),
  showAddCustomerInPOSProvider.overrideWith((ref) async => true),
  showOrderTypeInPOSProvider.overrideWith((ref) async => true),
  posDefaultTaxRateProvider.overrideWith((ref) async => 0.16),
  posBottomPanelScaleProvider.overrideWith((ref) async => 1.0),
  posCartItemScaleProvider.overrideWith((ref) async => 1.0),
  posButtonHeightProvider.overrideWith((ref) async => 32.0),
  posButtonFontSizeProvider.overrideWith((ref) async => 12.0),
  showSubtotalInPOSProvider.overrideWith((ref) async => true),
  showTaxButtonInPOSProvider.overrideWith((ref) async => true),
  showDiscountButtonInPOSProvider.overrideWith((ref) async => true),
  showDrawerButtonInPOSProvider.overrideWith((ref) async => true),
  showExpenseButtonInPOSProvider.overrideWith((ref) async => true),
  showSaveOnlyInPOSProvider.overrideWith((ref) async => true),
  showHoldButtonInPOSProvider.overrideWith((ref) async => true),
  showReturnButtonInPOSProvider.overrideWith((ref) async => true),
  showExchangeButtonInPOSProvider.overrideWith((ref) async => true),
  branchCashSafesProvider.overrideWith((ref) async => []),
  branchBankSafesProvider.overrideWith((ref) async => []),
  posCashCustomerIdProvider.overrideWith((ref) async => null),
];

/// نسخةٌ مصغّرةٌ من وصل الشاشة: اللوحةُ تقرأ المزوِّد وتكتب نسخاً جديدة عبر
/// الدوالّ نفسِها التي تستعملها `_PicPosQuickReturnCartOps`.
class _Harness extends ConsumerWidget {
  const _Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(posReturnModeProvider)!;
    void apply(ReturnableLine l, double q) {
      final next = picpos.setQuickReturnLineQty(mode, l.invoiceItemId, q);
      if (next != null) ref.read(posReturnModeProvider.notifier).state = next;
    }

    return PicPosQuickReturnLinesTable(
      mode: mode,
      onIncrement: (l) {
        final t = picpos.nextIncrementedQty(
          l,
          mode.requestedQty[l.invoiceItemId] ?? 0,
        );
        if (t != null) apply(l, t);
      },
      onDecrement: (l) =>
          apply(l, (mode.requestedQty[l.invoiceItemId] ?? 0) - 1),
      onEditQty: (_) {},
      onRemove: (l) => apply(l, 0),
    );
  }
}

/// [withPanel]: لوحةُ الدفع لاختبار الوصل؛ تُستبعد من تدقيق التباين لأنّها
/// ليست من هذا التغيير (‏ملاحظتها في التقرير: «معلقة» المعطَّل في الداكن).
Widget _app(
  PosReturnMode mode, {
  Brightness brightness = Brightness.light,
  bool withPanel = true,
}) => auditApp(
  brightness: brightness,
  overrides: [..._overrides, posReturnModeProvider.overrideWith((ref) => mode)],
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 662,
        height: 900,
        child: Column(
          children: [
            const SizedBox(height: 260, child: _Harness()),
            if (withPanel)
              Expanded(
                child: PicPosPaymentPanel(
                  onCheckout: () {},
                  onSave: () {},
                  onLastInvoice: () {},
                  onEditDiscount: () {},
                  onPickCustomer: () {},
                  onPreviousInvoices: () {},
                  onOpenDrawer: () {},
                  onExpense: () {},
                  onHold: () {},
                  onHeldOrders: () {},
                  onQuickReturn: () {},
                  onExchange: () {},
                ),
              ),
          ],
        ),
      ),
    ),
  ),
);

String _qty(WidgetTester t) => (t.widget<Text>(
  find.byKey(const ValueKey('picpos_quick_return_qty_7')),
)).data!;

String _refund(WidgetTester t) => (t.widget<Text>(
  find.byKey(const ValueKey('picpos_quick_return_refund_total')),
)).data!;

String _paymentTotal(WidgetTester t) => (t.widget<Text>(
  find.byKey(const ValueKey('picpos_payment_panel_total')),
)).data!;

bool _payEnabled(WidgetTester t) => t
    .widget<ElevatedButton>(
      find.ancestor(
        of: find.textContaining('استرداد'),
        matching: find.byType(ElevatedButton),
      ),
    )
    .enabled;

void _ignoreOverflow() {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
}

void main() {
  testWidgets(
    'بعد «تحديد الكلّ» تظهر بنود الفاتورة بكميّاتها ويُعدَّل الدفع معها',
    (tester) async {
      _ignoreOverflow();
      final full = _mode()..setQty(_almond.invoiceItemId, 2);
      await tester.pumpWidget(_app(full));
      await tester.pump();
      await tester.pump();

      expect(find.text('لوز انصاص'), findsOneWidget);
      expect(_qty(tester), '2');
      expect(_refund(tester), '13.98');
      expect(_paymentTotal(tester), _refund(tester));
      expect(find.text('المبلغ المسترد'), findsOneWidget);
      expect(find.text('استرداد 13.98'), findsOneWidget);
      expect(_payEnabled(tester), isTrue);

      await tester.tap(find.byTooltip('استبعادُ الصنف من المرتجع'));
      await tester.pump();
      await tester.pump();
      expect(_qty(tester), '0');
      expect(_refund(tester), '0.00');
      expect(_paymentTotal(tester), _refund(tester));
      expect(find.text('استرداد 0.00'), findsOneWidget);
      // قبل النسخ: تعديلٌ في المكان لا يُخطر اللوحةَ فيبقى «دفع» مفعَّلاً على صفر.
      expect(_payEnabled(tester), isFalse);

      // «+» مسقوفٌ بالمتاح: مرّتان ثم يتعطّل.
      // بالترتيب في الصفّ: «−» (0) ثم «+» (1).
      await tester.tap(find.byType(IconButton).at(1));
      await tester.pump();
      await tester.tap(find.byType(IconButton).at(1));
      await tester.pump();
      expect(_qty(tester), '2');
      expect(_payEnabled(tester), isTrue);
      expect(
        tester.widget<IconButton>(find.byType(IconButton).at(1)).onPressed,
        isNull,
      );
    },
  );

  testWidgets('لوحة الداكن تعرض مبلغ الاسترداد المحدّث في الإجمالي وزر الدفع', (
    tester,
  ) async {
    _ignoreOverflow();
    final full = _mode()..setQty(_almond.invoiceItemId, 2);
    await tester.pumpWidget(_app(full, brightness: Brightness.dark));
    await tester.pump();
    await tester.pump();

    expect(find.text('المبلغ المسترد'), findsOneWidget);
    expect(_refund(tester), '13.98');
    expect(_paymentTotal(tester), _refund(tester));
    expect(find.text('استرداد 13.98'), findsOneWidget);

    await tester.tap(find.byType(IconButton).first);
    await tester.pump();
    await tester.pump();
    expect(_refund(tester), '6.99');
    expect(_paymentTotal(tester), _refund(tester));
    expect(find.text('استرداد 6.99'), findsOneWidget);
  });

  test('الشاشة تعرض لوحة المرتجع وتوجّه البطاقة/المسح إليه', () {
    String src(String f) =>
        File('lib/presentation/pos_picpos/screens/$f').readAsStringSync();
    expect(src('picpos_pos_screen.dart'), contains('returnMode != null'));
    expect(
      src('picpos_pos_screen.dart'),
      contains('_buildQuickReturnTable(returnMode)'),
    );
    expect(
      src('picpos_pos_product_entry.dart'),
      contains('_addProductToQuickReturn(returnMode!, product.id'),
    );
    expect(
      src('picpos_pos_barcode_scan.dart'),
      contains('await _addBarcodeToQuickReturn(barcode);'),
    );
  });

  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('لوحة المرتجع بلا مخالفات تباين (${b.name})', (tester) async {
      _ignoreOverflow();
      await tester.pumpWidget(
        _app(_mode()..setQty(7, 1), brightness: b, withPanel: false),
      );
      await tester.pump();
      await tester.pump();
      final v = auditContrast(tester);
      final report = describeViolations(v);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(v, isEmpty, reason: report);
    });
  }
}
