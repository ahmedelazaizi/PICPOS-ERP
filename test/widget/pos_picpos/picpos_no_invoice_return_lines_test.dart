// بند ٤ — سطرُ المرتجع بلا فاتورة في جدول السلّة + بطاقةُ السقف في الإعدادات.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/core/utils/number_utils.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/models/no_invoice_return_policy.dart';
import 'package:picpos_erp/domain/models/quick_sale_policy.dart';
import 'package:picpos_erp/presentation/pos/providers/cart_controller.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_items_table.dart';
import 'package:picpos_erp/presentation/settings_picpos/widgets/no_invoice_return_cap_card.dart';

CartItemEntity line(int id, double price, double qty, {bool returned = false}) =>
    CartItemEntity(
      productId: id,
      productName: 'صنف$id',
      productCode: 'P$id',
      quantity: qty,
      unitPrice: price,
      itemType: returned ? CartItemType.returned : CartItemType.normal,
    );

/// سلّةٌ ثابتة بلا قاعدة بيانات: `testWidgets` يعمل في FakeAsync فلا يُنجز Drift.
class _FakeCart extends CartController {
  final List<CartItemEntity> initial;
  _FakeCart(this.initial);

  @override
  CartState build() => CartState(items: initial);
}

void main() {
  Future<void> pumpTable(
    WidgetTester tester,
    List<String> permissions, {
    List<CartItemEntity>? items,
    ValueChanged<int>? onRemove,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        cartControllerProvider.overrideWith(() => _FakeCart(items ??
            [
              line(1, 20, 2), // سطر بيع: ٤٠
              line(2, 30, 1, returned: true), // سطر مرتجع: ٣٠
            ])),
        posCartItemScaleProvider.overrideWith((ref) async => 1.0),
        currentUserPermissionsProvider.overrideWith((ref) async => permissions),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 400,
            child: PicPosItemsTable(
              selectedIndex: null,
              onSelect: (_) {},
              onRemove: onRemove ?? (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  bool priceReadOnly(WidgetTester tester, int index, double price) {
    final cell = find.byKey(ValueKey('price-$index-$price'));
    expect(cell, findsOneWidget);
    return tester
        .widget<TextField>(
            find.descendant(of: cell, matching: find.byType(TextField)))
        .readOnly;
  }

  group('جدول السلّة', () {
    testWidgets('سطرُ المرتجع موسومٌ «مرتجع» ومجموعُه بإشارة ناقص', (tester) async {
      await pumpTable(tester, ['system_admin']);
      expect(find.byKey(const ValueKey('return-line-tag')), findsOneWidget,
          reason: 'وسمٌ واحدٌ فقط — لسطر المرتجع لا لسطر البيع');
      expect(find.text('مرتجع'), findsOneWidget);
      expect(find.text('-${NumberUtils.formatCurrency(30)}'), findsOneWidget);
      expect(find.text(NumberUtils.formatCurrency(40)), findsOneWidget,
          reason: 'سطر البيع بلا إشارة');
    });

    testWidgets('سطرُ المرتجع قابلٌ للحذف (زرُّ الإلغاء يستدعي onRemove)',
        (tester) async {
      var removed = -1;
      await pumpTable(
        tester,
        ['system_admin'],
        items: [line(2, 30, 1, returned: true)],
        onRemove: (i) => removed = i,
      );
      await tester.tap(find.byTooltip('إلغاء الصنف'));
      expect(removed, 0);
    });

    testWidgets('سعرُ المرتجع بصلاحيته: pos_price_edit وحدَها لا تفتحه',
        (tester) async {
      await pumpTable(tester, [PermissionCodes.posPriceEdit]);
      expect(priceReadOnly(tester, 0, 20), isFalse, reason: 'سعر البيع مفتوح');
      expect(priceReadOnly(tester, 1, 30), isTrue,
          reason: 'سعر المرتجع مقفل بلا pos_return_price_edit');
    });

    testWidgets('pos_return_price_edit وحدَها تفتح سعر المرتجع لا سعر البيع',
        (tester) async {
      await pumpTable(tester, [PermissionCodes.posReturnPriceEdit]);
      expect(priceReadOnly(tester, 0, 20), isTrue);
      expect(priceReadOnly(tester, 1, 30), isFalse);
    });

    testWidgets('مدير النظام يفتح الاثنين', (tester) async {
      await pumpTable(tester, ['system_admin']);
      expect(priceReadOnly(tester, 0, 20), isFalse);
      expect(priceReadOnly(tester, 1, 30), isFalse);
    });

    testWidgets('الجدول الفارغ يعرض نصَّ البدء كما كان', (tester) async {
      await pumpTable(tester, const [], items: const []);
      expect(find.text('امسح باركود أو اكتب كود الصنف للبدء'), findsOneWidget);
    });
  });

  group('بطاقة سقف المرتجع في إعدادات البيع السريع', () {
    Future<Map<String, String>> pumpCard(
      WidgetTester tester,
      QuickSalePolicyValues values,
    ) async {
      final written = <String, String>{};
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 700,
              child: NoInvoiceReturnCapCard(
                values: values,
                onChanged: written.addAll,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      return written;
    }

    testWidgets('تعرض الافتراضيَّ ٥٠٠ عند غياب المفتاح', (tester) async {
      await pumpCard(tester, const QuickSalePolicyValues({}));
      expect(find.text('500'), findsOneWidget);
      expect(find.text('سقف قيمة المرتجع بلا فاتورة'), findsOneWidget);
    });

    testWidgets('تعرض المحفوظَ', (tester) async {
      await pumpCard(
          tester, const QuickSalePolicyValues({kNoInvoiceReturnCapKey: '1250'}));
      expect(find.text('1250'), findsOneWidget);
    });

    testWidgets('سحبُ المنزلق يكتب المفتاحَ الصحيح', (tester) async {
      final written = await pumpCard(tester, const QuickSalePolicyValues({}));
      final slider = find.byKey(const ValueKey('no-invoice-return-cap-slider'));
      await tester.drag(slider, const Offset(-120, 0));
      await tester.pump();
      expect(written.keys, contains(kNoInvoiceReturnCapKey));
      final v = double.parse(written[kNoInvoiceReturnCapKey]!);
      expect(v, inInclusiveRange(0, kNoInvoiceReturnCapSliderMax));
      expect(v % kNoInvoiceReturnCapStep, 0,
          reason: 'خطوةُ المنزلق ${kNoInvoiceReturnCapStep.toInt()}');
    });
  });
}
