import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/repositories/restaurant_repository.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../domain/models/split_plan.dart';
import '../../../data/providers/providers.dart';
import '../../pos/providers/cart_controller.dart';
import '../../pos/providers/checkout_controller.dart';

/// نتيجةُ محاولة بناء خطّةٍ حيّةً أثناء الكتابة — إمّا خطّةٌ صالحة أو رسالةُ
/// الرفض من [SplitPlanException] نفسِها، لا نسخةٌ مُعاد صياغتُها هنا.
typedef _Preview = ({SplitPlan? plan, String? error});

const List<SplitMode> _tabModes = [
  SplitMode.equal,
  SplitMode.byAmounts,
  SplitMode.byItems,
];

/// الإجماليُّ بعد الخصم — مرآةٌ خفيفةٌ لـ`TableSessionService.effectiveTotal`
/// لعرضٍ فوريٍّ من الطلب المحمَّل أصلاً، على غرار الدالّة نفسِها في
/// `table_card_widget.dart`. هذه نسخةٌ للعرض الحيّ فقط؛ التحقّقُ الرسميُّ
/// يبقى في `TableCheckoutCoordinator.buildSplitPlan` وقت التنفيذ الفعليّ.
double _effectiveTotal(TableOrder order) {
  if (order.discountType == null || order.discountValue <= 0) {
    return order.total;
  }
  final discount = order.discountType == 'percent'
      ? order.total * order.discountValue / 100
      : order.discountValue;
  final net = order.total - discount;
  return net < 0 ? 0 : net;
}

/// شاشةُ تقسيم الفاتورة — لا نقلَ أصنافٍ إلى طاولةٍ أخرى.
///
/// ثلاثُ طرقٍ لتقسيم حساب طاولةٍ واحدةٍ على عدّة دافعين، وكلٌّ منها يبني
/// [SplitPlan] عبر `TableCheckoutCoordinator.buildSplitPlan`:
/// - **بالتساوي**: الإجماليُّ ÷ عدد الحصص (مبدئيّاً عددُ ضيوف الطلب).
/// - **بمبلغ**: الكاشيرُ يكتب حصّةَ كلّ دافع، والمتبقّي يظهر حيّاً.
/// - **بالأصناف**: كلُّ بندٍ يُسنَد إلى دافعٍ بعينه.
///
/// الفرقُ الجوهريّ الذي يجب أن يراه الكاشير قبل التأكيد: التقسيمُ بالأصناف
/// وحدَه يُصدر فاتورةً مستقلّةً لكلّ دافع (`producesSeparateInvoices`)؛
/// بالتساوي وبمبلغ تبقى الفاتورةُ واحدةً لكلّ الأصناف، ولكلّ دافعٍ إيصالُ
/// حصّته فقط — فلا تُصدَر كميّاتٌ كسريّةٌ على فاتورة زبون.
class SplitTableDialog extends ConsumerStatefulWidget {
  /// الطاولةُ صاحبةُ الفاتورة المرادُ تقسيمُها.
  final RestaurantTable sourceTable;

  /// يُستخدَم لقراءة الطلب النشط وبنودِه فقط. التنفيذُ الفعليُّ — بناءُ
  /// الخطّة وتسويةُ حصصِها — يمرّ عبر `tableCheckoutCoordinatorProvider`،
  /// لا عبر هذا المستودع.
  final IRestaurantRepository restaurantRepo;

  const SplitTableDialog({
    super.key,
    required this.sourceTable,
    required this.restaurantRepo,
  });

  @override
  ConsumerState<SplitTableDialog> createState() => _SplitTableDialogState();
}

class _SplitTableDialogState extends ConsumerState<SplitTableDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  bool _processing = false;

  TableOrder? _order;
  List<TableOrderItem> _orderItems = const [];
  final Map<int, ProductEntity?> _productCache = {};
  double _total = 0;

  /// عددُ الحصص — مشتركٌ بين الألسنة الثلاثة، مبدئيّاً عددُ ضيوف الطلب.
  int _ways = 2;
  final List<TextEditingController> _amountControllers = [];

  /// `itemId → فهرسُ الدافع` (٠-based). بندٌ غيرُ موجودٍ هنا = غيرُ مُسنَد.
  final Map<int, int> _itemAssignment = {};

  double _paidSoFar = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _amountControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final order = await widget.restaurantRepo
        .getActiveOrderForTable(widget.sourceTable.id);
    if (order == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final items = await widget.restaurantRepo.getTableOrderItems(order.id);
    final productRepo = ref.read(productRepositoryProvider);
    for (final item in items) {
      if (!_productCache.containsKey(item.productId)) {
        _productCache[item.productId] =
            await productRepo.getProductById(item.productId);
      }
    }
    if (!mounted) return;
    setState(() {
      _order = order;
      _orderItems = items;
      _total = _effectiveTotal(order);
      _paidSoFar = order.paidAmount;
      _ways = order.guestCount;
      _resizeAmountControllers(_ways);
      _loading = false;
    });
  }

  void _resizeAmountControllers(int ways) {
    while (_amountControllers.length < ways) {
      _amountControllers.add(TextEditingController(text: '0'));
    }
    while (_amountControllers.length > ways) {
      _amountControllers.removeLast().dispose();
    }
  }

  void _setWays(int newWays) {
    if (newWays < 1 || _processing) return;
    setState(() {
      _ways = newWays;
      _resizeAmountControllers(newWays);
      _itemAssignment.removeWhere((_, owner) => owner >= newWays);
    });
  }

  double get _amountsRemaining {
    final entered = _amountControllers.fold<double>(
        0, (s, c) => s + (double.tryParse(c.text.trim()) ?? 0));
    return _total - entered;
  }

  /// محاولةُ بناء خطّةٍ حيّةً من الحالة الحالية — بلا نداءٍ للقاعدة، لعرضٍ
  /// فوريٍّ أثناء الكتابة. الخطّةُ الفعليّةُ وقت التنفيذ تُبنى من جديدٍ عبر
  /// `coordinator.buildSplitPlan`.
  _Preview _previewFor(SplitMode mode) {
    try {
      switch (mode) {
        case SplitMode.equal:
          return (plan: SplitPlan.equal(total: _total, ways: _ways), error: null);
        case SplitMode.byAmounts:
          final amounts = _amountControllers
              .map((c) => double.tryParse(c.text.trim()) ?? 0)
              .toList();
          return (
            plan: SplitPlan.byAmounts(total: _total, amounts: amounts),
            error: null,
          );
        case SplitMode.byItems:
          final items = [
            for (final i in _orderItems)
              SplitItem(itemId: i.id, quantity: i.quantity, lineTotal: i.total),
          ];
          return (
            plan: SplitPlan.byItems(
              items: items,
              assignment: _itemAssignment,
              ways: _ways,
            ),
            error: null,
          );
      }
    } on SplitPlanException catch (e) {
      return (plan: null, error: e.message);
    }
  }

  /// تنفيذُ الخطّة: يبني النسخةَ الرسميّةَ عبر المنسّق، ثم يملأ السلّةَ
  /// ويدفع ويسوّي كلَّ حصّةٍ بالترتيب.
  ///
  /// بالأصناف: لكلّ حصّةٍ فاتورتُها الخاصّة — سلّةٌ بأصنافها هي فقط، دفعٌ،
  /// ثم تسوية. بالتساوي وبمبلغ: فاتورةٌ واحدةٌ بكلّ أصناف الطلب، ثم تُسوَّى
  /// كلُّ الحصص على نفس رقم الفاتورة — فلا تتكرّر الأصنافُ الكسريّة على
  /// فاتورةٍ منفصلة.
  Future<void> _confirm(SplitMode mode) async {
    final order = _order;
    if (order == null || _processing) return;
    final preview = _previewFor(mode);
    if (preview.plan == null) return;

    setState(() {
      _processing = true;
      _paidSoFar = order.paidAmount;
    });

    final coordinator = ref.read(tableCheckoutCoordinatorProvider);
    final cartNotifier = ref.read(cartControllerProvider.notifier);
    final checkoutCtrl = ref.read(checkoutControllerProvider.notifier);
    final productRepo = ref.read(productRepositoryProvider);

    Future<ProductEntity?> resolveProduct(int productId) async {
      if (_productCache.containsKey(productId)) return _productCache[productId];
      final p = await productRepo.getProductById(productId);
      _productCache[productId] = p;
      return p;
    }

    // يملأ السلّة بالأصناف المُمرَّرة (كميّةً كاملةً أو مُسنَدة)، يدفع، ويعيد
    // رقمَ الفاتورة الناتجة.
    Future<int> payAndGetInvoiceId(
      List<TableOrderItem> items,
      Map<int, double> quantities,
    ) async {
      cartNotifier.clearCart();
      for (final item in items) {
        final qty = quantities[item.id] ?? item.quantity;
        final product = await resolveProduct(item.productId);
        if (product == null) continue; // صنفٌ محذوف — يُتخطّى كما في مسار التحصيل العادي
        cartNotifier.addItem(product, quantity: qty, customPrice: item.unitPrice);
      }
      final cartTotal = ref.read(cartControllerProvider).total;
      final success =
          await checkoutCtrl.processPayment(method: 'cash', total: cartTotal);
      if (!success) {
        throw Exception(
            ref.read(checkoutControllerProvider).error ?? 'فشل الدفع');
      }
      final invoiceId = ref.read(checkoutControllerProvider).lastInvoiceId;
      if (invoiceId == null) {
        throw Exception('تعذّر الحصول على رقم الفاتورة');
      }
      return invoiceId;
    }

    try {
      final plan = await coordinator.buildSplitPlan(
        orderId: order.id,
        mode: mode,
        ways: _ways,
        assignment: mode == SplitMode.byItems ? Map.of(_itemAssignment) : null,
        amounts: mode == SplitMode.byAmounts
            ? _amountControllers
                .map((c) => double.tryParse(c.text.trim()) ?? 0)
                .toList()
            : null,
      );

      if (plan.producesSeparateInvoices) {
        for (final part in plan.parts) {
          final relevantItems = _orderItems
              .where((i) => part.itemQuantities.containsKey(i.id))
              .toList();
          final invoiceId =
              await payAndGetInvoiceId(relevantItems, part.itemQuantities);
          await coordinator.settlePart(
              orderId: order.id, part: part, invoiceId: invoiceId);
          if (mounted) setState(() => _paidSoFar += part.amount);
        }
      } else {
        final invoiceId = await payAndGetInvoiceId(_orderItems, const {});
        for (final part in plan.parts) {
          await coordinator.settlePart(
              orderId: order.id, part: part, invoiceId: invoiceId);
          if (mounted) setState(() => _paidSoFar += part.amount);
        }
      }

      if (!mounted) return;
      AppToast.show(context, 'تم تقسيم الفاتورة بنجاح', type: ToastType.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'تعذّر إتمام التقسيم: $e', type: ToastType.error);
        setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.columns, color: AppColors.info),
            const SizedBox(width: 8),
            Expanded(child: Text('تقسيم فاتورة ${widget.sourceTable.name}')),
          ],
        ),
        content: SizedBox(
          width: 560,
          height: 600,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _order == null
                  ? const Center(
                      child: Text('لا يوجد طلبٌ نشطٌ على هذه الطاولة'),
                    )
                  : _buildBody(),
        ),
        actions: _loading || _order == null
            ? [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق'),
                ),
              ]
            : _buildActions(),
      ),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _waysStepper(),
            const Divider(height: 20),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              tabs: const [
                Tab(
                  icon: Icon(PhosphorIconsBold.usersThree, size: 18),
                  text: 'بالتساوي',
                ),
                Tab(
                  icon: Icon(PhosphorIconsBold.coins, size: 18),
                  text: 'بمبلغ',
                ),
                Tab(
                  icon: Icon(PhosphorIconsBold.listBullets, size: 18),
                  text: 'بالأصناف',
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _equalTabView(),
                  _amountsTabView(),
                  _itemsTabView(),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _invoiceNoteBanner(),
          ],
        ),
        if (_processing) _processingOverlay(),
      ],
    );
  }

  Widget _waysStepper() {
    return Row(
      children: [
        const Text('عددُ الحصص: ', style: TextStyle(fontWeight: FontWeight.bold)),
        IconButton(
          icon: const Icon(PhosphorIconsBold.minus, size: 16),
          onPressed:
              _ways > 1 && !_processing ? () => _setWays(_ways - 1) : null,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$_ways', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        IconButton(
          icon: const Icon(PhosphorIconsBold.plus, size: 16),
          onPressed: !_processing ? () => _setWays(_ways + 1) : null,
        ),
        const Spacer(),
        Text(
          'الإجماليُّ: ${_total.toStringAsFixed(AppConstants.decimalPlaces)} '
          '${AppConstants.currencySymbolEn}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _equalTabView() {
    final preview = _previewFor(SplitMode.equal);
    if (preview.error != null) return _centeredError(preview.error!);
    final plan = preview.plan!;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: plan.parts.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final part = plan.parts[i];
        return ListTile(
          leading: const Icon(PhosphorIconsBold.user, size: 18),
          title: Text(part.label),
          trailing: Text(
            '${part.amount.toStringAsFixed(AppConstants.decimalPlaces)} '
            '${AppConstants.currencySymbolEn}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }

  Widget _amountsTabView() {
    final remaining = _amountsRemaining;
    final isSettled = remaining.abs() < 0.0005;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _amountControllers.length,
            itemBuilder: (ctx, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: TextField(
                controller: _amountControllers[i],
                enabled: !_processing,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'ضيف ${i + 1}',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isSettled ? AppColors.success : AppColors.warning)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'المتبقّي: ${remaining.toStringAsFixed(AppConstants.decimalPlaces)} '
            '${AppConstants.currencySymbolEn}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSettled ? AppColors.successDark : AppColors.warningDark,
            ),
          ),
        ),
      ],
    );
  }

  Widget _itemsTabView() {
    if (_orderItems.isEmpty) {
      return const Center(child: Text('لا توجد أصنافٌ في الطلب'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _orderItems.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final item = _orderItems[i];
        final product = _productCache[item.productId];
        final owner = _itemAssignment[item.id];
        return ListTile(
          dense: true,
          title: Text(product?.name ?? 'صنف #${item.productId}'),
          subtitle: Text(
            '${item.quantity.toStringAsFixed(0)} × '
            '${item.unitPrice.toStringAsFixed(AppConstants.decimalPlaces)} = '
            '${item.total.toStringAsFixed(AppConstants.decimalPlaces)}',
          ),
          trailing: DropdownButton<int>(
            value: owner,
            hint: const Text('لمن؟'),
            underline: const SizedBox.shrink(),
            items: [
              for (var g = 0; g < _ways; g++)
                DropdownMenuItem(value: g, child: Text('ضيف ${g + 1}')),
            ],
            onChanged: _processing
                ? null
                : (v) => setState(() {
                      if (v == null) {
                        _itemAssignment.remove(item.id);
                      } else {
                        _itemAssignment[item.id] = v;
                      }
                    }),
          ),
        );
      },
    );
  }

  Widget _centeredError(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      );

  /// التمييزُ الجوهريّ الذي يجب أن يراه الكاشير نصّاً قبل التأكيد: فاتورةٌ
  /// واحدةٌ أم فاتورةٌ لكلّ دافع؟ يُستهلَك `plan.producesSeparateInvoices`
  /// مباشرةً، لا يُعاد اشتقاقُه هنا.
  Widget _invoiceNoteBanner() {
    final preview = _previewFor(_tabModes[_tabController.index]);
    if (preview.plan == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(PhosphorIconsBold.warning, color: AppColors.error, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                preview.error ?? '',
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    final plan = preview.plan!;
    final message = plan.producesSeparateInvoices
        ? 'سيصدر لكلّ ضيفٍ فاتورةٌ مستقلّةٌ بأصنافه — ${plan.parts.length} فواتيرَ منفصلة.'
        : 'الفاتورةُ واحدةٌ لكلّ الأصناف، ولكلّ دافعٍ إيصالُ حصّته — '
            'فاتورةٌ واحدة و${plan.parts.length} إيصالات.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.receipt, color: AppColors.info, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _processingOverlay() {
    final progress = _total > 0 ? (_paidSoFar / _total).clamp(0.0, 1.0) : 0.0;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 12),
                Text(
                  'دُفع ${_paidSoFar.toStringAsFixed(AppConstants.decimalPlaces)} '
                  'من ${_total.toStringAsFixed(AppConstants.decimalPlaces)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions() {
    final mode = _tabModes[_tabController.index];
    final preview = _previewFor(mode);
    final canConfirm = preview.plan != null && !_processing;
    return [
      TextButton(
        onPressed: _processing ? null : () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      ElevatedButton.icon(
        onPressed: canConfirm ? () => _confirm(mode) : null,
        icon: _processing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(PhosphorIconsBold.checkCircle),
        label: const Text('تأكيد التقسيم'),
      ),
    ];
  }
}
