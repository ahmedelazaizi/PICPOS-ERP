// جردُ تباينٍ موسَّع (فاتحاً/داكناً) لشاشاتٍ ولافتاتٍ وحواراتٍ خارج الصفّ
// السفليّ: لافتتا المرتجع/الاستبدال، ترويسةُ الفاتورة، إعداداتُ العرض،
// الودجتاتُ العامّة، لوحةُ dashboard_picpos. يستعمل `contrast_audit.dart`.
// **وضعٌ واحد لكلّ اختبار** (درس `picpos_pos_dark_mode_test`). ما لا يُركَّب
// هنا مسجَّلٌ في التقرير لا في الاختبار.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/config/brand.dart';
import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/dashboard_filter_provider.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/models/exchange_settlement.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_display_settings.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_exchange_mode_banner.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_invoice_header.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_return_mode_banner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/presentation/dashboard_picpos/screens/dashboard_picpos_screen.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';
import 'package:picpos_erp/presentation/pos/providers/pos_controller.dart';
import 'package:picpos_erp/presentation/pos/widgets/cart/cart_totals_panel.dart';
import 'package:picpos_erp/presentation/pos/widgets/cart_item_tile.dart';
import 'package:picpos_erp/presentation/pos/widgets/pos_edit_invoice_dialog.dart';
import 'package:picpos_erp/presentation/pos/widgets/pos_previous_invoices_dialog.dart';
import 'package:picpos_erp/presentation/pos/widgets/customer_selector_v2.dart';
import 'package:picpos_erp/presentation/widgets/common/app_kpi_card.dart';
import 'package:picpos_erp/presentation/widgets/getting_started_checklist.dart';
import 'package:picpos_erp/presentation/widgets/notifications/notification_panel.dart';
import 'package:picpos_erp/presentation/widgets/notifications/providers/notification_provider.dart';
import 'package:picpos_erp/presentation/widgets/period_close_checklist.dart';
import 'package:picpos_erp/presentation/widgets/summary_card.dart';

import '../support/contrast_audit.dart';

class _Surface {
  final String name;
  final double w;
  final double h;
  final Widget Function() build;
  final List<Override> overrides;
  final Future<void> Function(WidgetTester)? before;
  final bool picposOnly;

  /// قاعدةٌ في الذاكرة لودجتات تقرأ المستودعات مباشرةً.
  final bool useDb;
  const _Surface(this.name, this.w, this.h, this.build,
      {this.overrides = const [],
      this.before,
      this.picposOnly = false,
      this.useDb = false});
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

db.NotificationData _note(int i, String type, bool read) => db.NotificationData(
      id: i,
      userId: 1,
      title: 'عنوان $type',
      body: 'نصّ الإشعار $type',
      type: type,
      isRead: read,
      createdAt: DateTime(2026, 1, 1),
    );

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

db.SalesInvoiceData _invoice() => db.SalesInvoiceData(
      id: 1,
      invoiceNumber: 'INV-1',
      warehouseId: 1,
      userId: 1,
      invoiceDate: DateTime(2026, 1, 1),
      subtotal: 100,
      discount: 0,
      tax: 16,
      total: 116,
      paid: 116,
      paidUnallocated: 0,
      roundingAdjustment: 0,
      cashPaid: 116,
      bankPaid: 0,
      clickPaid: 0,
      paymentMethod: 'cash',
      saleType: 'retail',
      status: 'completed',
      deliveryFee: 0,
      isLocked: false,
      isDeleted: false,
      updatedAt: DateTime(2026, 1, 1),
      rowVersion: 1,
      createdAt: DateTime(2026, 1, 1),
    );

final _session = <Override>[
  authProvider.overrideWith(_Auth.new),
  currentUserPermissionsProvider
      .overrideWith((ref) async => const ['system_admin']),
];

final _common = <Override>[
  posCartItemScaleProvider.overrideWith((ref) async => 1.0),
  posBottomPanelScaleProvider.overrideWith((ref) async => 1.0),
  posButtonHeightProvider.overrideWith((ref) async => 32.0),
  posButtonFontSizeProvider.overrideWith((ref) async => 12.0),
  paymentButtonHeightProvider.overrideWith((ref) async => 36.0),
  allCustomersProvider.overrideWith((ref) => Stream.value(const [])),
  allWarehousesProvider.overrideWith((ref) => Stream.value(const [])),
];

List<_Surface> _surfaces() => [
      _Surface('لافتة المرتجع', 700, 80,
          () => const PicPosReturnModeBanner(invoiceNumber: 'INV-1')),
      for (final d in ExchangeCashDirection.values)
        _Surface(
            'لافتة الاستبدال (${d.name})',
            900,
            100,
            () => PicPosExchangeModeBanner(
                  invoiceNumber: 'INV-1',
                  refundTotal: 100,
                  replacementTotal: 114,
                  direction: d,
                  difference: 14,
                )),
      _Surface('ترويسة الفاتورة', 1000, 80,
          () => PicPosInvoiceHeader(onPickCustomer: () {}, onShowLastInvoice: () {}),
          overrides: _common),
      _Surface('إعدادات العرض (حوار)', 800, 700,
          () => const Center(child: PicPosDisplaySettingsButton()),
          overrides: _common, before: (t) async {
        await t.tap(find.byType(PicPosDisplaySettingsButton));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
      }),
      // KpiStyle.flat لا يُركَّب: Border غيرُ موحَّد + borderRadius يُسقط assert
      // عند الرسم (عيبُ تخطيطٍ سابق، غيرُ مستعمَل في أيّ شاشة) — يُبلَّغ في التقرير.
      for (final s in [KpiStyle.gradient])
        _Surface(
            'AppKpiCard (${s.name})',
            300,
            140,
            () => AppKpiCard(
                  icon: Icons.attach_money,
                  label: 'المبيعات',
                  value: '1,200',
                  subtitle: 'اليوم',
                  trend: -3.5,
                  color: const Color(0xFF0EA5E9),
                  style: s,
                )),
      _Surface(
          'قائمة تحقّق إقفال الفترة',
          700,
          700,
          () => PeriodCloseChecklist(
              items: PeriodCloseChecklist.getDefaultCloseChecklist(
            verifyTrialBalance: () async => true,
            verifyPendingEntries: () async => false,
            verifyBankReconciliation: () async => true,
          ))),
      _Surface('لوحة الإشعارات', 420, 600, () => const NotificationPanel(),
          overrides: [
            ..._session,
            latestNotificationsProvider.overrideWith((ref) => Stream.value([
                  for (final (i, t) in ['info', 'warning', 'error', 'success']
                      .indexed)
                    _note(i + 1, t, i.isEven),
                ])),
          ]),
      _Surface('قائمة البدء', 700, 700, () => const GettingStartedChecklist(),
          overrides: _session, useDb: true),
      _Surface('منتقي العملاء v2', 500, 400, () => const CustomerSelectorV2(),
          overrides: [..._session, ..._common],
          useDb: true, before: (t) async {
        await t.tap(find.byType(TextField).first);
        await t.pump(const Duration(milliseconds: 300));
      }),
      _Surface('حوار تعديل الفاتورة', 900, 700,
          () => PosEditInvoiceDialog(invoice: _invoice()),
          overrides: [..._session, ..._common], useDb: true),
      _Surface(
          'حوار الفواتير السابقة',
          1000,
          700,
          () => PosPreviousInvoicesDialog(
                onEdit: (_) {},
                onReprint: (_) {},
                onPrintKitchen: (_) {},
                onReturn: (_) {},
              ),
          overrides: [..._session, ..._common],
          useDb: true),
      _Surface(
          'لوحة مجاميع السلة',
          520,
          800,
          () => Consumer(
                builder: (context, ref, _) => CartTotalsPanel(
                  posState: ref.watch(posControllerProvider),
                  posController: ref.read(posControllerProvider.notifier),
                  scaleFactor: 1.0,
                  onOpenDrawer: () {},
                  onPreviousInvoices: () {},
                  onExpense: () {},
                  onSaveQuotation: () {},
                  onSave: () {},
                  onCheckout: () {},
                  onSaveAndPrint: () {},
                  buildTaxToggle: (c, k, s) => const SizedBox.shrink(),
                  buildDiscountButton: (r, c, k, s, ctx) => const SizedBox.shrink(),
                ),
              ),
          overrides: [
            ..._session,
            ..._common,
            cartControllerProvider.overrideWith(_FakeCart.new),
          ],
          useDb: true),
      _Surface(
          'بند السلة الموسَّع (لوحة المعدِّلات)',
          520,
          700,
          () => Consumer(
                builder: (context, ref, _) => CartItemTile(
                  item: ref.watch(cartControllerProvider).items.first,
                  index: 0,
                  onRemove: () {},
                  onQuantityChanged: (_) {},
                ),
              ),
          overrides: [
            ..._session,
            ..._common,
            cartControllerProvider.overrideWith(_FakeCart.new),
          ],
          useDb: true, before: (t) async {
        await t.tap(find.byType(CartItemTile));
        await t.pump(const Duration(milliseconds: 300));
      }),
      // الجولة 7ب: ودجتات lib/presentation العامة بعد استبدال ثوابت AppColors.
      _Surface('بطاقة ملخّص (SummaryCard)', 360, 120,
          () => const Row(children: [SummaryCard(title: 'الرصيد', value: '1,200', icon: Icons.account_balance, color: Color(0xFF0369A1))])),
      _Surface('لوحة dashboard_picpos', 1280, 900,
          () => const DashboardPicposScreen(),
          overrides: [
            ..._session,
            dashboardKpiProvider.overrideWith((ref) async => const DashboardKpi(
                revenue: 12000, netProfit: 3000, invoiceCount: 40)),
            lowStockProductsProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          useDb: true,
          picposOnly: true),
    ];

void main() {
  // قاعدةٌ واحدةٌ للملف، تُفتح (وتُبذَر) خارج الساعة الوهميّة — فتحُها داخل كلّ
  // اختبار علّق الاختبارات اللاحقة حتى مهلة العشر دقائق. لا تُغلق (انظر أعلاه).
  late db.AppDatabase sharedDb;
  setUpAll(() async {
    sharedDb = db.AppDatabase.forTesting();
    await sharedDb.customSelect('select 1').get();
    // لا شبكة في الاختبار: خطوطُ Google تُعلَّق عشر دقائق إن حاولت الجلب.
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting();
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final s in _surfaces()) {
      testWidgets('${s.name} — بلا مخالفات تباين (${brightness.name})',
          skip: s.picposOnly && !Brand.isPicPos, (tester) async {
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final msg = d.exceptionAsString();
          // overflow: مسألةُ تخطيط؛ google_fonts: خطُّ الاختبار الاحتياطيّ.
          if (msg.contains('overflowed') || msg.contains('google_fonts')) {
            return;
          }
          prev?.call(d);
        };
        addTearDown(() => FlutterError.onError = prev);

        // القاعدةُ لا تُغلق (`close()` ينتظر مؤقّتاً فيعلّق) — كاختبار booking.
        final testDb = s.useDb ? sharedDb : null;
        final overrides = [
          ...s.overrides,
          if (testDb != null) databaseProvider.overrideWithValue(testDb),
        ];
        await tester.pumpWidget(auditApp(
          brightness: brightness,
          overrides: overrides,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: s.w, height: s.h, child: s.build()),
            ),
          ),
        ));
        await tester.pump();
        if (s.useDb) {
          // استعلاماتُ drift غير متزامنةٍ حقيقيّاً — خارج الساعة الوهميّة.
          for (var i = 0; i < 10; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        await s.before?.call(tester);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(RichText), findsWidgets);
        final v = auditContrast(tester);
        final report = describeViolations(v);
        await tester.pumpWidget(const SizedBox.shrink());
        // مؤقّتات تنظيف تدفّقات drift/Riverpod بعد التفكيك.
        await tester.pump(const Duration(seconds: 2));
        expect(v, isEmpty, reason: report);
      });
    }
  }
}
