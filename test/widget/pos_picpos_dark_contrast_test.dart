// حارسُ تباينٍ لبلاغ المالك: أزرارُ الصفّ السفليّ في «البيع السريع»
// («مرتجع سريع»، «استبدال»، «تعليق»، «حفظ فقط»، «مصروف»…) كان نصُّها
// `AppColors.primaryDark` ثابتاً فلا يُرى على الكرت الداكن.
//
// يستعمل `test/support/contrast_audit.dart` (ثيم التطبيق الحقيقي، فاتحاً
// وداكناً). **وضعٌ واحد لكلِّ اختبار** — نفسُ درس `picpos_pos_dark_mode_test`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/config/brand.dart';
import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_items_table.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_one_time_customer.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_payment_panel.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_top_bar.dart';

import '../support/contrast_audit.dart';

class _FakeCart extends CartController {
  @override
  CartState build() => CartState(items: [
        for (var i = 1; i <= 2; i++)
          CartItemEntity(
            productId: i,
            productName: 'صنف$i',
            productCode: 'P$i',
            quantity: 2,
            unitPrice: 20,
            itemType: i == 2 ? CartItemType.returned : CartItemType.normal,
          ),
      ]);
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
  cartControllerProvider.overrideWith(_FakeCart.new),
  authProvider.overrideWith(_Auth.new),
  heldOrdersProvider.overrideWith((ref) => Stream.value(const [])),
  currentUserPermissionsProvider
      .overrideWith((ref) async => const ['system_admin']),
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

Widget _panel() => PicPosPaymentPanel(
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
    );

Widget _table() => PicPosItemsTable(
      selectedIndex: 0,
      onSelect: (_) {},
      onRemove: (_) {},
    );

Widget _topBar() => PicPosTopBar(
      onHeldOrders: () {},
      onBack: () {},
      onCloseShift: () {},
      onSwitchUser: () {},
      onBookings: () {},
      showBackButton: true,
    );

void main() {
  final surfaces = <String, (double, double, Widget Function())>{
    'لوحة الدفع وأزرار الأسفل': (662, 700, _panel),
    'جدول الأصناف': (900, 400, _table),
    'شريط الأعلى': (1200, 64, _topBar),
  };

  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final e in surfaces.entries) {
      // شريطُ الأعلى مرسومٌ على تدرّج هويّة العلامة بنصٍّ أبيض في الوضعَين.
      // على تدرّج UralCash الافتراضيّ (الفيروزيّ) تقيس الشرائحُ ٤٫٢٦:١ — وهو
      // خارج الشاشة المقصودة: `pos_picpos` شاشةُ PicPos وحدَها. فيُقاس تحت
      // `--dart-define=APP_BRAND=picpos` فقط.
      final skipBar = e.key == 'شريط الأعلى' && !Brand.isPicPos
          ? 'يُقاس بنكهة PicPos فقط: --dart-define=APP_BRAND=picpos'
          : null;
      testWidgets('${e.key} — بلا مخالفات تباين (${brightness.name})',
          skip: skipBar != null,
          (tester) async {
        // خطُّ الاختبار الاحتياطيّ أطول من خطّ المنتج فيُبلَّغ overflow بمقدار
        // بكسل في أزرار الصفّ السفليّ — مسألةُ تخطيطٍ لا تباين، وتغطّيها
        // `picpos_payment_panel_layout_test`. نتجاهلها هنا فقط.
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          if (d.exceptionAsString().contains('overflowed')) return;
          prev?.call(d);
        };
        addTearDown(() => FlutterError.onError = prev);

        final (w, h, build) = e.value;
        await tester.pumpWidget(auditApp(
          brightness: brightness,
          overrides: _overrides,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: w, height: h, child: build()),
            ),
          ),
        ));
        await tester.pump();
        await tester.pump();

        // حارسٌ ضدّ النجاح الفارغ: لا بدّ أن الأداةَ رأت نصوصاً.
        expect(find.byType(RichText), findsWidgets);

        final v = auditContrast(tester);
        // يُفكَّك الشجرُ لإنهاء مؤقّتات الساعة في الشريط.
        final report = describeViolations(v);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(v, isEmpty, reason: report);
      });
    }
  }

  testWidgets('الأداةُ تكشف حبراً داكناً على كرتٍ داكن (اختبار الأداة نفسها)',
      (tester) async {
    await tester.pumpWidget(auditApp(
      brightness: Brightness.dark,
      home: Scaffold(
        body: Container(
          color: const Color(0xFF121C2E),
          child: const Text('x', style: TextStyle(color: Color(0xFF012258))),
        ),
      ),
    ));
    final v = auditContrast(tester);
    expect(v, hasLength(1));
    expect(v.single.ratio, lessThan(3));
  });
}
