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
import '../../../services/split_settlement_runner.dart';
import '../../../services/table_checkout_coordinator.dart';
import '../../pos/providers/cart_controller.dart';
import '../../pos/providers/checkout_controller.dart';
import '../../pos/widgets/payment_sheet.dart';

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

  /// ما سُوِّي فعلاً من حصص: `التسمية → المبلغ`. يُقرأ عند الفتح من
  /// `TableOrderPayments` عبر المنسّق، ويُستعمل لشيئين: إعلامُ الكاشير بما
  /// سُوِّي بالاسم والمبلغ، وتعبئةُ خانات «بمبلغ» بما سُوِّي بدل صفرٍ يجب
  /// تخمينُه.
  Map<String, double> _settledShares = const {};

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
    // ما سُوِّي من حصصٍ سابقاً — تُقرأ قبل بناء الخانات لأن الخانات تُعبَّأ
    // منها.
    final settled = await ref
        .read(tableCheckoutCoordinatorProvider)
        .settledShares(order.id);
    if (!mounted) return;
    setState(() {
      _order = order;
      _orderItems = items;
      _total = _effectiveTotal(order);
      _paidSoFar = order.paidAmount;
      _settledShares = settled;
      // التقسيمُ يحتاج دافعَين على الأقل، وطلبُ ضيفٍ واحدٍ شرعيٌّ تماماً —
      // ففتحُ الشاشة على رسالة خطأٍ لأن `guestCount == 1` عيبُ عرضٍ لا
      // عيبُ بيانات. الحدُّ الأدنى اثنان، وللكاشير أن يزيد.
      _ways = order.guestCount < 2 ? 2 : order.guestCount;
      _resizeAmountControllers(_ways);
      _loading = false;
    });
  }

  /// هل سُوِّيت حصّةٌ من هذا الحساب بالفعل؟ **للإعلام لا للقفل.**
  ///
  /// كان هذا قفلاً: تُعطَّل معه خاناتُ المبالغ وقوائمُ أصحاب البنود. و
  /// `TableOrderPayments` يحفظ التسميةَ والمبلغَ ولا يحفظ تركيبةَ الخطّة،
  /// فإعادةُ فتح الشاشة تبدأ بتركيبةٍ فارغة — لا إسنادَ بنودٍ، وخاناتٌ
  /// صفريّة. قفلُ ما لم يُستعَد يعني أن التركيبةَ التي أنتجت الحصصَ
  /// المسوّاةَ لا يمكن التعبيرُ عنها ثانيةً، فتعلق الطاولةُ بلا مخرج:
  /// «بالأصناف» يرمي «بلا صاحب»، و«بمبلغ» يعاين خطأً، و«بالتساوي» يعطي
  /// مبلغاً آخر لحصّةٍ مسوّاةٍ فيرفضه المنسّق، والتحصيلُ من شاشة الطاولة
  /// يرفض للفارق، والإغلاقُ يرفض لأن الطلبَ ليس مدفوعاً بالكامل.
  ///
  /// والأمانُ لم يكن في القفل أصلاً: `TableCheckoutCoordinator.unsettledParts`
  /// يقارن مبلغَ كلِّ حصّةٍ سُوِّيت بما تجعله الخطّةُ الحاليّة بوحداتٍ صحيحة،
  /// ويرفض أيَّ اختلافٍ أو أيَّ تسميةٍ مسوّاةٍ غابت عن الخطّة. فإعادةُ إدخال
  /// **نفسِ** التركيبة تمرّ، وإدخالُ تركيبةٍ أخرى يُرفَض برسالةٍ تحمل
  /// الرقمين. القفلُ كان يمنع الأولى ولا يضيف شيئاً إلى الثانية.
  bool get _partlySettled => _paidSoFar > 0;

  /// خاناتُ «بمبلغ» تُعبَّأ بما سُوِّي لتلك الحصّة إن سُوِّي — الكاشيرُ
  /// يستأنف ولا يخمّن. وما لم يُسوَّ يبدأ صفراً كما كان.
  void _resizeAmountControllers(int ways) {
    while (_amountControllers.length < ways) {
      final settled = _settledShares[splitPartLabel(_amountControllers.length)];
      _amountControllers.add(TextEditingController(
        text: settled == null
            ? '0'
            : settled.toStringAsFixed(AppConstants.decimalPlaces),
      ));
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

  /// تسامحُ المقارنات النقديّة الحيّة (فروقُ التقريب لا فروقٌ حقيقيّة).
  static const double _amountEpsilon = 0.0005;

  /// تنفيذُ الخطّة عبر [SplitSettlementRunner].
  ///
  /// الحلقةُ نفسُها — الاستئنافُ لا إعادةُ البدء، والفحصُ القبليُّ الذي
  /// يقارن سلّةَ الشحن بحصّة الخطّة قبل أيّ ترحيل — تعيش في الخدمة لتكون
  /// قابلةً للقيادة بمنفذٍ وهميّ. ما يبقى هنا هو الوصلُ بالعالم: السلّة،
  /// ورقةُ الدفع، والتوستات.
  Future<void> _confirm(SplitMode mode) async {
    final order = _order;
    if (order == null || _processing) return;
    final preview = _previewFor(mode);
    if (preview.plan == null) return;
    final previewSum =
        preview.plan!.parts.fold<double>(0, (s, p) => s + p.amount);

    setState(() {
      _processing = true;
      _paidSoFar = order.paidAmount;
    });

    final port = _DialogSplitPort(this, order.id, mode);
    try {
      final result =
          await SplitSettlementRunner(port).run(previewSum: previewSum);
      if (!mounted) return;

      switch (result.status) {
        case SplitRunStatus.success:
          AppToast.show(context, 'تم تقسيم الفاتورة بنجاح',
              type: ToastType.success);
          Navigator.pop(context, true);
        case SplitRunStatus.alreadyComplete:
          AppToast.show(context, 'التقسيمُ مكتملٌ بالفعل — كلُّ الحصص مسوّاة',
              type: ToastType.info);
          Navigator.pop(context, true);
        case SplitRunStatus.aborted:
          AppToast.show(context, result.message ?? 'تعذّر إتمام التقسيم',
              type: ToastType.error);
          setState(() => _processing = false);
        case SplitRunStatus.reconcileNeeded:
          await _logReconcileNeeded(result);
          if (!mounted) return;
          AppToast.show(
            context,
            '⚠️ فاتورة #${result.orphanInvoiceId} صدرت ورُحِّلت لكن لم '
            'تُسجَّل على ${widget.sourceTable.name} — راجع الطاولةَ يدويّاً',
            type: ToastType.error,
          );
          setState(() => _processing = false);
      }
    } on StateError catch (e) {
      // رفضُ المنسّق لتركيبةٍ تخالف ما سُوِّي — رسالتُه تحمل التسميةَ
      // والرقمين وما يجب فعله، فتُعرَض كما هي لا مغلَّفةً بـ«Bad state:».
      if (mounted) {
        AppToast.show(context, e.message, type: ToastType.error);
        setState(() => _processing = false);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'تعذّر إتمام التقسيم: $e', type: ToastType.error);
        setState(() => _processing = false);
      }
    }
  }

  /// أثرٌ دائمٌ للفجوة: فاتورةٌ رُحِّلت (محاسبةً ومخزوناً) ولم تُسجَّل دفعتُها
  /// على الطلب. نفسُ اسم الفعل ونفسُ الحقول التي يكتبها مسارُ التحصيل
  /// العاديّ، فيظهر الاثنان في `TableLogSheet` سواءً بسواء — التوستُ يزول
  /// والسطرُ يبقى.
  Future<void> _logReconcileNeeded(SplitRunResult result) async {
    try {
      final user = ref.read(authProvider).user;
      await ref.read(activityLogRepositoryProvider).logActivity(
            userId: user?.id,
            userName: user?.displayName ?? 'مجهول',
            action: 'table_payment_reconcile_needed',
            entityType: 'table',
            entityId: widget.sourceTable.id,
            description:
                'فاتورةٌ #${result.orphanInvoiceId} صدرت ورُحِّلت في تقسيم '
                '${widget.sourceTable.name}، لكن تعذّر تسجيلُ دفعتها — '
                'يحتاج تسويةً يدويّة. ${result.message ?? ''}',
            amount: result.orphanAmount,
          );
    } catch (_) {}
  }

  /// تقدُّمُ التسوية على شريط الانتظار.
  void _bumpPaid(double amount) {
    if (mounted) setState(() => _paidSoFar += amount);
  }

  Future<ProductEntity?> _resolveProduct(int productId) async {
    if (_productCache.containsKey(productId)) return _productCache[productId];
    final p = await ref.read(productRepositoryProvider).getProductById(productId);
    _productCache[productId] = p;
    return p;
  }

  /// يملأ السلّة بالأصناف الحيّة — لا المخبَّأة عند فتح الشاشة — ويعيد
  /// إجماليَّها كما سيُشحَن.
  Future<double> _fillCart(
    int orderId,
    Map<int, double>? itemQuantities,
  ) async {
    final cartNotifier = ref.read(cartControllerProvider.notifier);
    cartNotifier.clearCart();
    final freshItems = await widget.restaurantRepo.getTableOrderItems(orderId);
    for (final item in freshItems) {
      if (itemQuantities != null && !itemQuantities.containsKey(item.id)) {
        continue;
      }
      final qty = itemQuantities?[item.id] ?? item.quantity;
      final product = await _resolveProduct(item.productId);
      // صنفٌ محذوف يُتخطّى، فينقص إجماليُّ السلّة عن حصّة الخطّة —
      // والفحصُ القبليُّ في الحلقة يوقف التحصيلَ قبل أيّ ترحيل.
      if (product == null) continue;
      cartNotifier.addItem(product, quantity: qty, customPrice: item.unitPrice);
    }
    return ref.read(cartControllerProvider).total;
  }

  /// طريقةُ الدفع تُسأل، لا تُفترَض. كانت مثبَّتةً على `'cash'` فكان دافعٌ
  /// بالبطاقة يُقيَّد على خزنة النقد بصمت.
  Future<int?> _payFilledCart(double chargeTotal) async {
    if (!mounted) return null;
    final cartState = ref.read(cartControllerProvider);
    final result = await showModalBottomSheet<PaymentResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: PaymentSheet(
          total: chargeTotal,
          subtotal: cartState.subtotal,
          discount: cartState.totals.totalDiscount,
          tax: cartState.totals.taxAmount,
          onConfirm: (paymentResult) => Navigator.pop(ctx, paymentResult),
          onCancel: () => Navigator.pop(ctx),
        ),
      ),
    );
    if (result == null) return null;

    final checkoutCtrl = ref.read(checkoutControllerProvider.notifier);
    final success = await checkoutCtrl.processPayment(
      method: result.method,
      total: chargeTotal,
      cashAmount: result.cashAmount,
      bankAmount: result.bankAmount,
      bankSafeId: ref.read(cartControllerProvider).bankSafeId,
      customerId: result.customerId,
    );
    if (!success) {
      throw Exception(ref.read(checkoutControllerProvider).error ?? 'فشل الدفع');
    }
    final invoiceId = ref.read(checkoutControllerProvider).lastInvoiceId;
    if (invoiceId == null) {
      throw Exception('تعذّر الحصول على رقم الفاتورة');
    }
    return invoiceId;
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
            if (_partlySettled) _partlySettledBanner(),
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

  /// ما سُوِّي يُقال بالاسم والمبلغ — لا يُترك للكاشير أن يخمّنه.
  ///
  /// التركيبةُ لا تُحفَظ مع الدفعات، فإعادةُ فتح الشاشة تبدأ فارغة. هذا
  /// السطرُ يعطي الكاشيرَ ما يكفي لإعادة إدخالها: كم حُصِّل، وأيُّ الحصص
  /// انتهت وبكم. وإن أخطأ فالمنسّقُ يرفض برسالةٍ تحمل الرقمين — لا يبتلع.
  Widget _partlySettledBanner() {
    final done = [
      for (final entry in _settledShares.entries)
        '${entry.key}: '
            '${entry.value.toStringAsFixed(AppConstants.decimalPlaces)}',
    ].join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.info, color: AppColors.warning, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${done.isEmpty ? 'حُصِّل من هذا الحساب' : 'هذا الحسابُ مقسَّمٌ ومُحصَّلٌ جزئيّاً:'} '
                  '${_paidSoFar.toStringAsFixed(AppConstants.decimalPlaces)} '
                  'من ${_total.toStringAsFixed(AppConstants.decimalPlaces)} '
                  '${AppConstants.currencySymbolEn}.',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
                if (done.isNotEmpty)
                  Text('الحصصُ المسوّاة — $done',
                      style: const TextStyle(fontSize: 12)),
                Text(
                  done.isEmpty
                      // تحصيلٌ بلا تسمية (من شاشة الطاولة لا من التقسيم):
                      // لا حصّةَ تُقارَن به، والخطّةُ تُبنى على الإجماليّ
                      // كاملاً — فالتنبيهُ هنا أن التقسيمَ قد لا يستقيم.
                      ? 'هذا التحصيلُ ليس حصّةَ تقسيم، فلا تُقابله تسميةٌ '
                          'تُستأنَف. راجِع المتبقّي من شاشة الطاولة قبل '
                          'التقسيم.'
                      : 'أعِد إدخال نفسِ التركيبة التي سُوِّيت عليها هذه '
                          'الحصص ثم أكمِل الباقي. تركيبةٌ مخالفةٌ تُرفَض قبل '
                          'إصدار أيّ فاتورة، فلا يضيع مالٌ بصمت.',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _waysStepper() {
    final editable = !_processing;
    return Row(
      children: [
        const Text('عددُ الحصص: ', style: TextStyle(fontWeight: FontWeight.bold)),
        IconButton(
          icon: const Icon(PhosphorIconsBold.minus, size: 16),
          onPressed: _ways > 1 && editable ? () => _setWays(_ways - 1) : null,
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
          onPressed: editable ? () => _setWays(_ways + 1) : null,
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
    final isSettled = remaining.abs() < _amountEpsilon;
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

/// وصلُ الحلقة بالعالم: المنسّقُ للخطّة والتسوية، والسلّةُ وورقةُ الدفع
/// للشحن. لا منطقَ قرارٍ هنا — كلُّه في [SplitSettlementRunner].
class _DialogSplitPort implements SplitSettlementPort {
  _DialogSplitPort(this._state, this._orderId, this._mode);

  final _SplitTableDialogState _state;
  final int _orderId;
  final SplitMode _mode;

  TableCheckoutCoordinator get _coordinator =>
      _state.ref.read(tableCheckoutCoordinatorProvider);

  @override
  Future<SplitPlan> buildPlan() => _coordinator.buildSplitPlan(
        orderId: _orderId,
        mode: _mode,
        ways: _state._ways,
        assignment:
            _mode == SplitMode.byItems ? Map.of(_state._itemAssignment) : null,
        amounts: _mode == SplitMode.byAmounts
            ? _state._amountControllers
                .map((c) => double.tryParse(c.text.trim()) ?? 0)
                .toList()
            : null,
      );

  @override
  Future<List<SplitPart>> unsettledParts(SplitPlan plan) =>
      _coordinator.unsettledParts(orderId: _orderId, plan: plan);

  @override
  Future<int?> settledInvoiceId() => _coordinator.settledInvoiceId(_orderId);

  @override
  Future<void> settlePart(SplitPart part, int invoiceId) => _coordinator
      .settlePart(orderId: _orderId, part: part, invoiceId: invoiceId);

  @override
  Future<double> fillCart(Map<int, double>? itemQuantities) =>
      _state._fillCart(_orderId, itemQuantities);

  @override
  Future<int?> payFilledCart(double chargeTotal) =>
      _state._payFilledCart(chargeTotal);

  @override
  void onPartSettled(SplitPart part) => _state._bumpPaid(part.amount);
}
