import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/cart_item_entity.dart';
import '../../../domain/usecases/sales/sales_usecases.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../domain/repositories/offers_repository.dart';
import '../../../domain/repositories/i_products_repository.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/utils/number_utils.dart';
import '../../../services/invoice_generator.dart';
import '../../../domain/usecases/sales/hold_order_usecase.dart';
import '../../../application/services/cart_pricing_service.dart';
import '../widgets/modifier_selection_dialog.dart';
import 'checkout_controller.dart';

/// نتيجة [CartController.applyOffer].
///
/// ── ليه مش `void` ──────────────────────────────────────────────────────────
/// كل حالات الرفض كانت بترجع `void` وتكتفي بـ`debugPrint`، والواجهة كانت
/// بتخمّن اللي حصل من فرق عدد الأصناف قبل/بعد — فأي رفض بيطلع بنفس رسالة
/// «العرض مضاف بالفعل» حتى لو السبب مختلف تماماً. الكاشير بيقف قدام شاشة
/// بتقول حاجة غلط، أو ما بتقولش حاجة أصلاً.
enum ApplyOfferOutcome {
  /// اتضاف للسلة فعلاً.
  added,

  /// نفس العرض مضاف يدوياً قبل كده.
  alreadyInCart,

  /// العرض من غير أصناف صالحة للتسعير.
  noItems,

  /// سعر العرض ≥ مجموع أسعار بيع أصنافه — عرض مقلوب، اترفض.
  notADiscount,
}

/// بادئة سطر العرض **التلقائي** — كل جولة تطبيق بتصفّره وتعيد حسابه.
String get kAutoOfferNotePrefix => tr('عرض:');

/// بادئة سطر العرض **اليدوي** — إنسان طبّقه، فما بيتلمسش.
///
/// ⚠️ `'عرض (يدوي):'` **ما بيبدأش** بـ`'عرض:'` — بعد «عرض» بييجي « (» مش «:».
/// اللي بيسأل «هل ده سطر عرض؟» بـ`startsWith(kAutoOfferNotePrefix)` لوحدها
/// بيرجّع false للسطر اليدوي فيعامله كسطر أساس عادي. ده كان مصدر عطل ٣-٣.
String get kManualOfferNotePrefix => tr('عرض (يدوي):');

/// هل السطر ده سطر عرض بأي شكل — تلقائي أو يدوي؟
///
/// ده السؤال اللي كل حلقات التطبيق عايزة تسأله: «هل السطر ده متسعّر بعرض
/// خلاص فما ينفعش أعيد تسعيره / أعدّه ككمية أساس؟». ستة مواضع كانت بتسأله
/// بفلتر أضيق (التلقائي بس)، فسطر الخصم اليدوي كان بيتكتب فوقه، وملاحظته
/// بتتحوّل لـ`عرض:` فالجولة اللي بعدها بتصفّره لسعر الأساس ⇒ الخصم اليدوي
/// يتدمّر نهائياً والعميل يتحمّل زيادة.
bool isOfferLineNote(String? note) =>
    note != null &&
    (note.startsWith(kAutoOfferNotePrefix) ||
        note.startsWith(kManualOfferNotePrefix));

/// يبني نص `CartItemEntity.note` المركّب من المعدِّلات + الملاحظة اليدوية.
///
/// ── ليه دالة واحدة ─────────────────────────────────────────────────────────
/// نفس التركيب كان مكرَّر حرفياً في `updateItemModifiers` و`updateItemNote`.
/// أي مسار تالت بيكتب `note` مباشرة (زي ما كان بيحصل في شاشة خدمة الطاولات)
/// بيمسح المعدِّلات من النص من غير ما يمسحها من `item.modifiers` — فالفاتورة
/// المطبوعة بتخسر الإضافات والمطبخ بيحضّر الطلب غلط. الحقل `itemNote` هو
/// **مصدر الملاحظة اليدوية الوحيد**، و`note` مخرج مشتق بيتبني هنا بس.
///
/// النص الناتج بيتقرا كمان في `templated_invoice_service.dart` اللي بيحوّل
/// `📝 ` لـ«ملاحظة: » و` | ` لسطر جديد — فالبادئة جزء من العقد مش تزيين.
String? composeCartItemNote(
  List<SelectedModifier> modifiers,
  String? itemNote,
) {
  final parts = <String>[];
  for (final m in modifiers) {
    if (m.isOption) {
      // Include quantity level label (قليل/بدون/كثير) when set
      final levelLabel = m.quantityLevel.label;
      final optionText =
          levelLabel.isNotEmpty ? '$levelLabel ${m.itemName}' : m.itemName;
      parts.add('(${m.groupName}: $optionText)');
    } else {
      parts.add('+${m.itemName}${m.extraPrice > 0 ? ' ${m.extraPrice.toStringAsFixed(0)} ${AppConstants.currencySymbolEn}' : ''}');
    }
  }
  if (itemNote != null && itemNote.isNotEmpty) {
    parts.add('📝 $itemNote');
  }
  return parts.isNotEmpty ? parts.join(' | ') : null;
}

class CartState {
  final List<CartItemEntity> items;
  final List<CartItemEntity> deletedItems;

  // Sale Session Data
  final double discountPercent;
  final bool taxEnabled;
  final double taxRate;
  final int? selectedCustomerId;
  final String? selectedCustomerName;
  final double deliveryFee;
  final int? deliveryCompanyId;
  final int? courierId;
  final String? deliveryStatus;
  final String? orderNote;
  final String paymentMethod;
  final int? bankSafeId; // Selected bank safe for bank payments (multi-branch)
  final String priceLevel;
  final int? linkedQuotationId;

  // Phase 3: Kitchen order type
  final String orderType; // 'internal' (داخلي) or 'delivery' (توصيل)

  // Phase 4: Delivery platform order number
  final String? platformOrderNumber;

  // Phase 4: Ad-hoc customer info (text-only, not saved to DB customer table)
  final String? adhocCustomerName;
  final String? adhocCustomerPhone;
  final String? adhocCustomerNote;

  // Multi-payment split amounts
  final double splitCashAmount;
  final double splitBankAmount;
  final double splitClickAmount;

  /// يسمح بإضافة صنف مخزونه صفر أو أقل **لهذه الفاتورة فقط**.
  ///
  /// ── ليه علم مستقل ────────────────────────────────────────────────────────
  /// تخطي «غير متوفر» كان مربوط بـ `paymentMethod == 'credit'`: الكاشير كان
  /// بيضغط «آجل» قبل السحب فيتخطى الرفض. ده كان **أثر جانبي** لقرار تاني خالص
  /// — «إزاي بتتدفع» و«مسموح أبيع بالسالب» حاجتين مختلفتين، ولمّا شاشة PicPos
  /// شالت أزرار طرق الدفع من اللوحة (طلب ٢) القدرة دي ضاعت معاها.
  ///
  /// العلم ده بيرجّعها باسمها الصريح. وبيتصفّر تلقائياً مع `clearCart` لأنها
  /// بتبني `CartState` جديدة — فهو صلاحية **لفاتورة واحدة**، مش مود بيفضل
  /// مفتوح على التِل.
  ///
  /// شرط `credit` القديم **باقي** في الحارس: كاشير UralCash لسه عنده أزرار
  /// الطرق وده مسار شغّال عنده، ومش من حقنا نشيله.
  final bool allowOversell;

  const CartState({
    this.items = const [],
    this.deletedItems = const [],
    this.discountPercent = 0,
    this.taxEnabled = false,
    this.taxRate = 0.16,
    this.selectedCustomerId,
    this.selectedCustomerName,
    this.deliveryFee = 0,
    this.deliveryCompanyId,
    this.courierId,
    this.deliveryStatus,
    this.orderNote,
    this.paymentMethod = 'cash',
    this.bankSafeId,
    this.priceLevel = 'retail',
    this.linkedQuotationId,
    this.orderType = 'internal',
    this.platformOrderNumber,
    this.adhocCustomerName,
    this.adhocCustomerPhone,
    this.adhocCustomerNote,
    this.splitCashAmount = 0,
    this.splitBankAmount = 0,
    this.splitClickAmount = 0,
    this.allowOversell = false,
  });

  /// Would the POS stock guard refuse adding [product] to this cart?
  ///
  /// Lives on the STATE, not the controller, so it is a pure function of
  /// (product, cart, install setting) and testable without a ProviderContainer.
  /// [CartController.addItem] and the PicPos "may I oversell?" prompt both read
  /// it, which is what keeps the offer and the guard from disagreeing about
  /// what is blocked.
  ///
  /// Pass [globalNegativeSales] from `enableNegativeSalesProvider`.
  bool blocksAdd(
    ProductEntity product, {
    required bool globalNegativeSales,
  }) {
    return product.trackInventory &&
        !product.allowNegativeSale &&
        !globalNegativeSales &&
        product.currentStock <= 0 &&
        // UralCash workflow: pre-selecting «آجل» unlocks the oversell. Kept as
        // it is — that till still has its payment buttons.
        paymentMethod != 'credit' &&
        // PicPos workflow: an explicit, per-invoice permission.
        !allowOversell;
  }

  /// Computed: Financial Totals using domain logic
  InvoiceTotals get totals => CalculateInvoiceTotalsUseCase().execute(
    items: items,
    invoiceDiscountPercent: discountPercent,
    taxPercent: taxEnabled ? taxRate * 100 : 0,
    taxEnabled: taxEnabled,
  );

  double get subtotal => totals.subtotal;
  double get total => totals.total + deliveryFee;
  bool get isNegative => total < 0;

  // Sentinel for distinguishing "not provided" from "set to null"
  static const _unset = Object();

  CartState copyWith({
    List<CartItemEntity>? items,
    List<CartItemEntity>? deletedItems,
    double? discountPercent,
    bool? taxEnabled,
    double? taxRate,
    Object? selectedCustomerId = _unset,
    Object? selectedCustomerName = _unset,
    double? deliveryFee,
    Object? deliveryCompanyId = _unset,
    Object? courierId = _unset,
    Object? deliveryStatus = _unset,
    Object? orderNote = _unset,
    String? paymentMethod,
    Object? bankSafeId = _unset,
    String? priceLevel,
    Object? linkedQuotationId = _unset,
    String? orderType,
    Object? platformOrderNumber = _unset,
    Object? adhocCustomerName = _unset,
    Object? adhocCustomerPhone = _unset,
    Object? adhocCustomerNote = _unset,
    double? splitCashAmount,
    double? splitBankAmount,
    double? splitClickAmount,
    bool? allowOversell,
  }) {
    return CartState(
      items: items ?? this.items,
      deletedItems: deletedItems ?? this.deletedItems,
      discountPercent: discountPercent ?? this.discountPercent,
      taxEnabled: taxEnabled ?? this.taxEnabled,
      taxRate: taxRate ?? this.taxRate,
      selectedCustomerId: selectedCustomerId == _unset ? this.selectedCustomerId : selectedCustomerId as int?,
      selectedCustomerName: selectedCustomerName == _unset ? this.selectedCustomerName : selectedCustomerName as String?,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      deliveryCompanyId: deliveryCompanyId == _unset ? this.deliveryCompanyId : deliveryCompanyId as int?,
      courierId: courierId == _unset ? this.courierId : courierId as int?,
      deliveryStatus: deliveryStatus == _unset ? this.deliveryStatus : deliveryStatus as String?,
      orderNote: orderNote == _unset ? this.orderNote : orderNote as String?,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      bankSafeId: bankSafeId == _unset ? this.bankSafeId : bankSafeId as int?,
      priceLevel: priceLevel ?? this.priceLevel,
      linkedQuotationId: linkedQuotationId == _unset ? this.linkedQuotationId : linkedQuotationId as int?,
      orderType: orderType ?? this.orderType,
      platformOrderNumber: platformOrderNumber == _unset ? this.platformOrderNumber : platformOrderNumber as String?,
      adhocCustomerName: adhocCustomerName == _unset ? this.adhocCustomerName : adhocCustomerName as String?,
      adhocCustomerPhone: adhocCustomerPhone == _unset ? this.adhocCustomerPhone : adhocCustomerPhone as String?,
      adhocCustomerNote: adhocCustomerNote == _unset ? this.adhocCustomerNote : adhocCustomerNote as String?,
      splitCashAmount: splitCashAmount ?? this.splitCashAmount,
      splitBankAmount: splitBankAmount ?? this.splitBankAmount,
      splitClickAmount: splitClickAmount ?? this.splitClickAmount,
      allowOversell: allowOversell ?? this.allowOversell,
    );
  }
}

/// Record of the most-recent scale-weight add for a product in the cart.
/// Used to detect when the cashier registers the SAME weight for the SAME
/// product within a short window (likely forgot to change weight on scale).
class _RecentWeight {
  final double weightKg;
  final DateTime at;
  _RecentWeight(this.weightKg, this.at);
}

class CartController extends Notifier<CartState> {
  final _addToCartUseCase = AddToCartUseCase();
  bool _isApplyingOffers = false; // Guard against recursive offer application
  final _removeFromCartUseCase = RemoveFromCartUseCase();
  final _updateQuantityUseCase = UpdateCartQuantityUseCase();
  final _updatePriceUseCase = UpdateCartPriceUseCase();

  /// Tracks the last scale-weight add per product for duplicate-detection.
  /// Cleared on clearCart(). Entries expire after 30 seconds.
  final Map<int, _RecentWeight> _lastWeightByProduct = {};

  /// Duplicate-weight threshold: readings within 1g of the last reading for
  /// the same product count as "same weight" (standard scale readings are
  /// discrete to 5-10g, so 1g tolerance catches exact-match only).
  static const double _weightDuplicateTolerance = 0.001; // 1 gram

  /// Time window: if more than this has elapsed since the last weight add,
  /// the cashier is probably weighing a new item even at the same reading.
  static const Duration _weightDuplicateWindow = Duration(seconds: 30);

  /// Returns true if [product.id] was added with this exact [weightKg] within
  /// the last 30 seconds. ALWAYS updates the tracker (so the next check sees
  /// this newest reading). Used by POS to show a non-blocking "duplicate
  /// weight" warning — the add itself is NOT blocked.
  bool isDuplicateWeightAdd(int productId, double weightKg) {
    final now = DateTime.now();
    final last = _lastWeightByProduct[productId];
    final isDup = last != null &&
        now.difference(last.at) <= _weightDuplicateWindow &&
        (weightKg - last.weightKg).abs() < _weightDuplicateTolerance;
    _lastWeightByProduct[productId] = _RecentWeight(weightKg, now);
    return isDup;
  }
  // final _clearCartUseCase = ClearCartUseCase(); // Not currently used — clearCart() uses direct state reset

  @override
  CartState build() {
    // Watch for default tax rate and update state when it's available
    // This ensures that even if the cart is already open, change in settings will reflect
    ref.listen(posDefaultTaxRateProvider, (prev, next) {
      if (next is AsyncData<double>) {
        state = state.copyWith(taxRate: next.value);
      }
    });

    // Try to get initial value if already loaded
    final initialTax = ref.read(posDefaultTaxRateProvider).value ?? 0.16;

    return CartState(taxRate: initialTax);
  }

  /// Would the stock guard refuse [product]? Delegates to [CartState.blocksAdd]
  /// so callers that only hold the controller don't need to reach for `state`.
  bool isBlockedByStock(
    ProductEntity product, {
    required bool globalNegativeSales,
  }) =>
      state.blocksAdd(product, globalNegativeSales: globalNegativeSales);

  /// يفتح/يقفل السماح بالبيع بالسالب لهذه الفاتورة. اقرا [CartState.allowOversell].
  void setAllowOversell(bool value) {
    if (state.allowOversell == value) return;
    state = state.copyWith(allowOversell: value);
    if (value) {
      _logAction('cart_allow_oversell', 0,
          tr('سمح ببيع أصناف غير متوفرة في هذه الفاتورة'), 0);
    }
  }

  void addItem(
    ProductEntity product, {
    double quantity = 1,
    double? customPrice,
    bool forceNewEntry = false,
    bool mergeWeight = false,
    double? taxRate,
    String? note,
  }) {
    // Stock validation: block adding if out of stock and negative sale disabled
    // Exception: allow for credit payment (آجل) and exchange mode
    // Cluster 024 / Issue 2 — also honour the install-wide
    // `enable_negative_sales` setting. The previous guard only checked the
    // per-product flag, so even with the global toggle ON the operator
    // couldn't add an out-of-stock item from the POS grid.
    final globalNegativeSales =
        ref.read(enableNegativeSalesProvider).value ?? false;
    if (state.blocksAdd(product, globalNegativeSales: globalNegativeSales)) {
      return; // Silently refuse — product card already shows "غير متوفر"
    }

    // الكميات **موجبة دايماً**. الاتجاه بييجي من `saleType` على المستند
    // (`sales_mutations_dao.dart:311`) — مش من إشارة السطر. كان فيه هنا
    // `state.isExchangeMode ? -quantity.abs() : quantity` وده كان بيقلب
    // اتجاه المخزون: سالب × مستند مرتجع = المخزون ينقص بدل ما يزيد.
    final finalQuantity = quantity;

    // Resolve effective price based on the customer's price level
    final effectivePrice = _resolvePrice(product);

    final updatedItems = _addToCartUseCase.execute(
      currentCart: state.items,
      productId: product.id,
      productName: product.name,
      productCode: product.code,
      unitPrice: effectivePrice,
      quantity: finalQuantity,
      customPrice: customPrice ?? effectivePrice,
      taxRate: taxRate ?? product.taxRate,
      taxExempt: product.taxExempt,
      categoryId: product.categoryId,
      isSoldByWeight: product.isSoldByWeight,
      forceNewEntry: forceNewEntry,
      mergeWeight: mergeWeight,
    );
    state = state.copyWith(items: updatedItems);

    // Clear previous checkout errors when user modifies cart
    ref.read(checkoutControllerProvider.notifier).clearError();

    // Activity log - non-blocking
    _logAction(
      'cart_add',
      product.id,
      tr('إضافة للسلة: {p0} × {quantity}', {'p0': product.name, 'quantity': quantity}),
      (customPrice ?? effectivePrice) * quantity,
    );

    // Auto-apply offers after adding item
    _tryAutoApplyOffers();
  }

  /// Resolve the effective sale price based on the current customer's price level.
  /// Falls back to salePrice if the specific price is 0 or unset.
  static double resolveProductPrice(ProductEntity product, String level) {
    double resolved;
    switch (level) {
      case 'wholesale':
        resolved = product.wholesalePrice;
        break;
      case 'talabat':
        resolved = product.priceTalabat;
        break;
      case 'careem':
        resolved = product.priceCareem;
        break;
      case 'ashyae':
        resolved = product.priceAshyae;
        break;
      default:
        resolved = product.salePrice;
    }
    // Fall back to salePrice if the resolved price is 0 (unset)
    return resolved > 0 ? resolved : product.salePrice;
  }

  double _resolvePrice(ProductEntity product) {
    return resolveProductPrice(product, state.priceLevel);
  }

  void updatePrice(int index, double newPrice) {
    if (index < 0 || index >= state.items.length) return;
    final item = state.items[index];
    final oldPrice = item.effectivePrice;

    final updatedItems = _updatePriceUseCase.execute(
      currentCart: state.items,
      index: index,
      newPrice: newPrice,
    );
    state = state.copyWith(items: updatedItems);

    if (oldPrice != newPrice) {
      _logAction(
        'price_edit',
        item.productId,
        tr('تعديل سعر: {p0}', {'p0': item.productName}),
        newPrice * item.quantity,
      );
    }
  }

  /// ⛔ `toggleItemType` اتشالت مع «وضع الاستبدال» — كانت بتخزّن كمية سالبة
  /// للسطر المرتجع، وده كان بيقلب اتجاه المخزون. المرتجع بقى عبر
  /// `convertToQuickReturn` بكميات موجبة.

  /// Debounced auto-apply wrapper — prevents recursive calls.
  /// If called while already running, schedules a re-run after completion.
  bool _pendingAutoApply = false;
  int _autoApplyGeneration = 0; // tracks which snapshot we started with

  void _tryAutoApplyOffers() {
    if (_isApplyingOffers) {
      // كل نداء هنا معناه إن السلة اتغيّرت **جوّه** نافذة الـ await بتاعة الجولة
      // الشغّالة، فلقطتها بقت قديمة. رفع الجيل هو اللي بيخلّي حارس القِدَم
      // (:509 و:545) يضرب فعلاً فترجع الجولة من غير ما تكتب — من غير الرفع ده
      // كانت بتكتب لقطتها القديمة فوق الحالة الحالية وتمسح الكمية اللي اتضافت.
      // الدمج بالـ productId ما بيحميش من ده لأن الصنف نفسه موجود في اللقطة،
      // اللي اتغيّر هو كميته.
      ++_autoApplyGeneration;
      _pendingAutoApply = true; // will re-run after current completes
      return;
    }
    _isApplyingOffers = true;
    _pendingAutoApply = false;
    _autoApplyOffers().whenComplete(() {
      _isApplyingOffers = false;
      if (_pendingAutoApply) {
        _pendingAutoApply = false;
        _tryAutoApplyOffers(); // re-run with latest state
      }
    });
  }

  /// هل السلة اتغيّرت من ساعة ما اللقطة [snapshotRef] اتاخدت؟
  ///
  /// ── ليه مقارنة هوية القايمة، مش تبليغ من كل mutator ────────────────────
  /// رفع الجيل من `_tryAutoApplyOffers` بيغطّي الأربع مسارات اللي بتناديه بس.
  /// لكن **١٤ دالة** في الكلاس ده بتبدّل `state.items` — `clearCart` و
  /// `updatePrice` و`applyOffer` و`retrieveHeldOrder` و`loadFromQuotation`
  /// وغيرهم — ومفيش فيهم واحد بيبلّغ. أخطرهم `clearCart`: الكاشير يمسح السلة
  /// والجولة الشغّالة تكتب اللقطة اللي قبل المسح، فالسلة الممسوحة **ترجع**
  /// بأسعارها الأساسية. وفي `applyOffer` سطور العرض اليدوي بتتبلع في دمج
  /// الـ productId فالعرض يتطبّق وبعدين يختفي.
  ///
  /// أي مسار بيبدّل الأصناف بيحط List **جديدة** في `copyWith`، والمسارات اللي
  /// بتغيّر حاجة تانية بس (ضريبة، عميل، طريقة دفع) بتمرّر نفس القايمة. يعني
  /// مقارنة الهوية بتمسك كل المسارات — الموجودة والجاية — من غير ما أي واحد
  /// فيهم يفتكر يعمل حاجة. حراسة معتمدة على انضباط ١٤ نقطة نداء بتصدّي مع
  /// أول مسار جديد.
  ///
  /// لما تضرب بنجدول إعادة: الجولة بترجع من غير كتابة، والإعادة بتحسب من
  /// حالة طازجة. الإعادة بتاخد لقطتها بنفسها فما بتبطّلش نفسها — مفيش حلقة.
  bool _cartChangedSince(List<CartItemEntity> snapshotRef) {
    if (identical(state.items, snapshotRef)) return false;
    _pendingAutoApply = true;
    return true;
  }

  /// Core offer auto-application logic for the main POS.
  /// Resets old auto-applied items to base price, then re-evaluates all active offers.
  Future<void> _autoApplyOffers() async {
    try {
      // ISS-06: Route through offersRepositoryProvider instead of direct DB access
      final offersRepo = ref.read(offersRepositoryProvider);
      final productRepo = ref.read(productRepositoryProvider);
      final generation = ++_autoApplyGeneration;

      // 1) Take a snapshot of current items for processing.
      // `snapshotRef` هي هوية القايمة نفسها وقت اللقطة — بنقارن بيها قبل أي
      // كتابة عشان نعرف إذا كان حد بدّل السلة أثناء الـ await. اقرا
      // [_cartChangedSince].
      final snapshotRef = state.items;
      final snapshotItems = List<CartItemEntity>.from(snapshotRef);

      // Classify: auto-applied items have 'عرض:' prefix; manual have 'عرض (يدوي):'
      bool isAutoApplied(String? n) {
        if (n == null) return false;
        // الترتيب مقصود: اليدوي يتفحص الأول. البادئتين مش متداخلتين
        // (`'عرض (يدوي):'` ما بيبدأش بـ`'عرض:'`) فالترتيب مش شرط للصحة،
        // لكنه بيخلّي «اليدوي يفوز» مقروء في الكود.
        if (n.startsWith(kManualOfferNotePrefix)) return false; // manual — keep
        if (n.startsWith(kAutoOfferNotePrefix)) return true; // auto — reset
        return false;
      }

      // Reset auto-applied items to their base (unitPrice) instead of stripping them.
      // This preserves quantities so adding more of an offer-discounted product
      // never loses previously-added units.
      // (copyWith cannot set note=null, so we reconstruct the entity without it.)
      final baseItems = snapshotItems.map((i) {
        if (!isAutoApplied(i.note)) return i;
        return CartItemEntity(
          productId: i.productId,
          categoryId: i.categoryId,
          productName: i.productName,
          productCode: i.productCode,
          barcode: i.barcode,
          quantity: i.quantity,
          unitPrice: i.unitPrice,
          customPrice: i.unitPrice, // restore base price
          discountPercent: i.discountPercent,
          taxRate: i.taxRate,
          taxAmount: i.taxAmount,
          itemNote: i.itemNote, // keep cashier's manual note
          isSoldByWeight: i.isSoldByWeight,
          itemType: i.itemType,
          modifiers: i.modifiers,
          selectedUnitId: i.selectedUnitId,
          selectedUnitName: i.selectedUnitName,
          quantityInBase: i.quantityInBase,
          taxExempt: i.taxExempt,
          // note omitted → defaults to null (offer note cleared)
        );
      }).toList();

      // 2) Fetch active offers with date + time-window filtering
      final activeOffers = await offersRepo.getActiveOffers();
      debugPrint('[AutoApplyOffers] baseItems=${baseItems.length}, activeOffers=${activeOffers.length}');

      // Check if generation is stale (a newer auto-apply was triggered)
      if (generation != _autoApplyGeneration) return;
      if (_cartChangedSince(snapshotRef)) return;

      if (activeOffers.isEmpty) {
        final hadAutoItems = snapshotItems.any((i) => isAutoApplied(i.note));
        if (hadAutoItems) {
          state = state.copyWith(items: baseItems);
        }
        return;
      }

      final List<CartItemEntity> resultItems = List.from(baseItems);
      final Set<int> appliedOfferIds = {};

      for (final offer in activeOffers) {
        // Time window check
        if (!offersRepo.isOfferWithinTimeWindow(offer)) continue;
        // Usage limit check
        if (offer.maxUses != null && offer.currentUses >= offer.maxUses!) continue;

        switch (offer.offerType) {
          case 'bundle':
            await _applyBundleOffer(offersRepo, productRepo, offer, resultItems, appliedOfferIds);
            break;
          case 'buy_x_get_y':
            await _applyBuyXGetYOffer(offersRepo, productRepo, offer, resultItems, appliedOfferIds);
            break;
          case 'percentage':
            await _applyPercentageOffer(offersRepo, productRepo, offer, resultItems, appliedOfferIds);
            break;
          case 'fixed_discount':
            await _applyFixedDiscountOffer(offersRepo, productRepo, offer, resultItems, appliedOfferIds);
            break;
        }
      }

      // Check if generation is stale
      if (generation != _autoApplyGeneration) return;
      if (_cartChangedSince(snapshotRef)) return;

      // 3) اتشال: خطوة دمج كانت بتحاول تتعايش مع تغيّر السلة أثناء الـ await
      // بإنها تضيف الأصناف اللي مش في اللقطة، بمقارنة `productId` بس. ودي كانت
      // **هي نفسها** مصدر العطل: صنف موجود في اللقطة وكميته زادت كان بيتخطّى،
      // وسطور العرض اليدوي كانت بتتبلع.
      //
      // دلوقتي [_cartChangedSince] فوق بيضمن إن `state.items` نفس القايمة
      // بالهوية — يعني مفيش أي صنف اتضاف أو اتغيّر بعد اللقطة، والدمج بقى
      // ميت بالبرهان. التعايش اتشال ومحلّه إعادة حساب من حالة طازجة، وده
      // صحيح دايماً مش في حالات معيّنة.
      state = state.copyWith(items: resultItems);
    } catch (e, st) {
      debugPrint('[AutoApplyOffers] ERROR: $e');
      debugPrint('[AutoApplyOffers] Stack: $st');
      AppLogger.instance.warning('Auto-apply offers error: $e');
    }
  }

  /// Bundle offer: all offer items must be in cart with ≥ required qty.
  /// Adjusts prices proportionally to reach the bundle price.
  Future<void> _applyBundleOffer(
    IOffersRepository offersRepo,
    IProductRepository productRepo,
    Offer offer,
    List<CartItemEntity> items,
    Set<int> appliedOfferIds,
  ) async {
    final offerItems = await offersRepo.getOfferItems(offer.id);
    if (offerItems.isEmpty) return;

    // Build qty map of base cart items (excluding any offer items)
    final cartQtyMap = <int, double>{};
    for (final item in items) {
      if (isOfferLineNote(item.note)) continue;
      cartQtyMap[item.productId] = (cartQtyMap[item.productId] ?? 0) + item.quantity;
    }

    // Check if all offer items exist in cart with sufficient qty
    int multiplier = 999999;
    for (final oi in offerItems) {
      final cartQty = cartQtyMap[oi.productId] ?? 0;
      if (cartQty < oi.quantity) return; // Not enough — can't apply
      final times = (cartQty / oi.quantity).floor();
      if (times < multiplier) multiplier = times;
    }
    if (multiplier <= 0) return;

    // Calculate normal total price for one set.
    // الأصناف بتتجاب **مرة واحدة**: الكود القديم كان بينده `getProductById`
    // مرتين لكل صنف (مرة للمجموع ومرة للتطبيق) جوّه دالة أصلاً بتستنى.
    double totalNormalPrice = 0;
    final resolved = <({OfferItem oi, ProductEntity product})>[];
    for (final oi in offerItems) {
      final product = await productRepo.getProductById(oi.productId);
      if (product == null) continue; // صنف مش موجود → سطوره ما بتتلمسش خالص
      totalNormalPrice += product.salePrice * oi.quantity;
      resolved.add((oi: oi, product: product));
    }
    if (totalNormalPrice <= 0 || offer.offerPrice >= totalNormalPrice) return;

    final factor = offer.offerPrice / totalNormalPrice;

    // المسار ده كان بيكتب `salePrice * factor` **خام** — لا تقريب لدقة العملة
    // ولا توزيع للباقي. يعني انحراف الـ٩٫٩٩٩ اللي اتصلح في المسار اليدوي كان
    // لسه حيّ هنا، والمسار ده هو اللي بيتاخد لما الكاشير يسحب أصناف الحزمة
    // بدل ما يدوس على كارت العرض — أي الحالة الأشيع.
    //
    // المجموع المستهدف = سعر العرض × عدد الأطقم، لأن كل طقم بيتحاسب بسعر العرض.
    final quantities =
        resolved.map((r) => r.oi.quantity * multiplier).toList();
    final unitPrices = resolved
        .map((r) => NumberUtils.roundCurrency(r.product.salePrice * factor))
        .toList();
    CartPricingService.settleBundleRemainder(
      quantities: quantities,
      unitPrices: unitPrices,
      maxUnitPrices: resolved.map((r) => r.product.salePrice).toList(),
      target: offer.offerPrice * multiplier,
    );

    // Apply proportional price to matching cart items
    for (var r = 0; r < resolved.length; r++) {
      final oi = resolved[r].oi;
      final offerUnitPrice = unitPrices[r];
      final totalOfferQty = quantities[r];

      // Find matching cart items and adjust their price
      double remaining = totalOfferQty;
      for (int i = 0; i < items.length && remaining > 0; i++) {
        final item = items[i];
        if (item.productId != oi.productId) continue;
        if (isOfferLineNote(item.note)) continue;

        if (item.quantity <= remaining) {
          // Entire item at offer price
          items[i] = item.copyWith(
            customPrice: offerUnitPrice,
            note: tr('عرض: {p0}{p1}', {'p0': offer.name, 'p1': multiplier > 1 ? ' x$multiplier' : ''}),
          );
          remaining -= item.quantity;
        } else {
          // Split: part at offer, part at regular
          items[i] = item.copyWith(quantity: remaining, customPrice: offerUnitPrice,
            note: tr('عرض: {p0}{p1}', {'p0': offer.name, 'p1': multiplier > 1 ? ' x$multiplier' : ''}),
          );
          items.insert(i + 1, item.copyWith(quantity: item.quantity - remaining));
          remaining = 0;
        }
      }
    }
    appliedOfferIds.add(offer.id);
  }

  /// Buy X Get Y: if product qty >= buyQuantity, add getQuantity free items.
  Future<void> _applyBuyXGetYOffer(
    IOffersRepository offersRepo,
    IProductRepository productRepo,
    Offer offer,
    List<CartItemEntity> items,
    Set<int> appliedOfferIds,
  ) async {
    if (offer.buyQuantity == null || offer.getQuantity == null) return;
    final offerItems = await offersRepo.getOfferItems(offer.id);
    if (offerItems.isEmpty) return;

    for (final oi in offerItems) {
      // Count quantity of this product in cart (base items only)
      double cartQty = 0;
      for (final item in items) {
        if (item.productId == oi.productId && !isOfferLineNote(item.note)) {
          cartQty += item.quantity;
        }
      }

      final sets = (cartQty / offer.buyQuantity!).floor();
      if (sets <= 0) continue;
      final freeQty = sets * offer.getQuantity!;

      final product = await productRepo.getProductById(oi.productId);
      if (product == null) continue;

      // Add free items
      items.add(CartItemEntity(
        productId: product.id,
        categoryId: product.categoryId,
        productName: product.name,
        productCode: product.code,
        barcode: product.barcode,
        unitPrice: product.salePrice,
        quantity: freeQty.toDouble(),
        customPrice: 0, // Free!
        taxExempt: product.taxExempt,
        isSoldByWeight: product.isSoldByWeight,
        note: tr('عرض: {p0} (مجاني)', {'p0': offer.name}),
      ));
      appliedOfferIds.add(offer.id);
    }
  }

  /// Percentage discount: apply % off to matching products/categories.
  Future<void> _applyPercentageOffer(
    IOffersRepository offersRepo,
    IProductRepository productRepo,
    Offer offer,
    List<CartItemEntity> items,
    Set<int> appliedOfferIds,
  ) async {
    if (offer.discountValue == null || offer.discountValue! <= 0) return;
    final discountFactor = 1 - (offer.discountValue! / 100);

    bool applied = false;
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (isOfferLineNote(item.note)) continue;

      bool matches = false;
      // Category match
      if (offer.categoryId != null && item.categoryId == offer.categoryId) {
        matches = true;
      }
      // Product-level match via offer items
      if (!matches) {
        final offerItems = await offersRepo.getOfferItems(offer.id);
        if (offerItems.any((oi) => oi.productId == item.productId)) {
          matches = true;
        }
      }
      // Min quantity check
      if (matches && offer.minQuantity != null && item.quantity < offer.minQuantity!) {
        matches = false;
      }

      if (matches) {
        items[i] = item.copyWith(
          customPrice: item.effectivePrice * discountFactor,
          note: tr('عرض: {p0} (-{p1}%)', {'p0': offer.name, 'p1': offer.discountValue!.toStringAsFixed(0)}),
        );
        applied = true;
      }
    }
    if (applied) appliedOfferIds.add(offer.id);
  }

  /// Fixed discount: subtract a fixed amount from matching product prices.
  Future<void> _applyFixedDiscountOffer(
    IOffersRepository offersRepo,
    IProductRepository productRepo,
    Offer offer,
    List<CartItemEntity> items,
    Set<int> appliedOfferIds,
  ) async {
    if (offer.discountValue == null || offer.discountValue! <= 0) return;

    bool applied = false;
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (isOfferLineNote(item.note)) continue;

      bool matches = false;
      if (offer.categoryId != null && item.categoryId == offer.categoryId) {
        matches = true;
      }
      if (!matches) {
        final offerItems = await offersRepo.getOfferItems(offer.id);
        if (offerItems.any((oi) => oi.productId == item.productId)) {
          matches = true;
        }
      }
      if (matches && offer.minQuantity != null && item.quantity < offer.minQuantity!) {
        matches = false;
      }

      if (matches) {
        final newPrice = (item.effectivePrice - offer.discountValue!).clamp(0.0, double.infinity);
        items[i] = item.copyWith(
          customPrice: newPrice,
          note: tr('عرض: {p0} (-{p1})', {'p0': offer.name, 'p1': offer.discountValue!.toStringAsFixed(AppConstants.decimalPlaces)}),
        );
        applied = true;
      }
    }
    if (applied) appliedOfferIds.add(offer.id);
  }

  /// نقطة نداء يدوية للتطبيق التلقائي للعروض.
  ///
  /// بتعدّي على [_tryAutoApplyOffers] مش على `_autoApplyOffers` مباشرة: النداء
  /// المباشر كان بيتخطّى حارس `_isApplyingOffers`، فيقدر يشتغل بالتوازي مع
  /// جولة شغّالة — جولتين بلقطتين مختلفتين بيتسابقوا على الكتابة. الدالة دي
  /// مش مستعملة حالياً في أي مكان، فده فخ منصوب لأول واحد ينادي عليها.
  ///
  /// ⚠️ رجعت `void` بدل `Future<void>` عن قصد: الطلب بيتجدول ومش بيتنفّذ فوراً
  /// (لو في جولة شغّالة بيستنى نهايتها)، فـ`Future` كان هيوعد بانتظار مش
  /// بيحصل. النتيجة بتوصل عبر `state` زي أي تغيير تاني في السلة.
  void autoApplyMatchingOffers() => _tryAutoApplyOffers();

  void convertToQuickReturn() {
    if (state.items.isEmpty) return;

    // Keep quantities POSITIVE — saleType='return' handles the reversal
    final updatedItems = state.items.map((item) {
      return item.copyWith(
        itemType: CartItemType.returned,
        quantity: item.quantity.abs(), // positive for return invoices
      );
    }).toList();

    state = state.copyWith(items: updatedItems);
  }

  Future<ApplyOfferOutcome> applyOffer(Offer offer) async {
    // P5 (Issue #5): Idempotent guard — if this exact offer was already added
    // manually, refuse to add it again. Without this, every press of the
    // offer card produced another set of items in the cart, silently
    // doubling/tripling the discount the cashier intended.
    final manualNote = tr('عرض (يدوي): {p0}', {'p0': offer.name});
    final alreadyApplied = state.items.any((i) => i.note == manualNote);
    if (alreadyApplied) {
      debugPrint('[applyOffer] offer "${offer.name}" already in cart — skipping duplicate manual add');
      return ApplyOfferOutcome.alreadyInCart;
    }

    final cartPricingService = ref.read(cartPricingServiceProvider);

    OfferRejection? rejection;
    final pricedItems = await cartPricingService.calculateOfferItems(
      ApplyOfferRequest(offer: offer),
      onRejected: (r) => rejection = r,
    );
    if (pricedItems.isEmpty) {
      debugPrint('[applyOffer] offer "${offer.name}" produced 0 priced items — '
          'reason=${rejection?.reason}');
      // الفرق بين «مقلوب» و«فاضي» لازم يوصل للواجهة: الأول غلطة في بيانات
      // العرض محتاجة تصليح، والتاني عرض ناقص. رسالة واحدة عامة كانت بتخلّي
      // الاتنين شكلهم واحد قدام الكاشير.
      return rejection?.reason == OfferRejectionReason.notADiscount
          ? ApplyOfferOutcome.notADiscount
          : ApplyOfferOutcome.noItems;
    }

    // B3: offer items arrive as plain mapped rows without the raw
    // `tax_exempt` flag — re-read it through the repository.
    final exemptIds = (await ref
            .read(productRepositoryProvider)
            .getProductsByIds(
                pricedItems.map((p) => p.product.id).toList()))
        .where((p) => p.taxExempt)
        .map((p) => p.id)
        .toSet();

    // Batch-add all offer items atomically (no per-item auto-apply)
    final newItems = <CartItemEntity>[];
    for (final pricedItem in pricedItems) {
      final product = pricedItem.product;
      newItems.add(CartItemEntity(
        productId: product.id,
        categoryId: product.categoryId,
        productName: product.name,
        productCode: product.code,
        barcode: product.barcode,
        unitPrice: product.salePrice,
        quantity: pricedItem.quantity,
        customPrice: pricedItem.customPrice,
        taxRate: exemptIds.contains(product.id) ? 0 : product.taxRate,
        taxExempt: exemptIds.contains(product.id),
        isSoldByWeight: product.isSoldByWeight,
        note: manualNote,
      ));
    }

    // Add all items at once — no auto-apply since items are already priced
    state = state.copyWith(items: [...state.items, ...newItems]);
    return ApplyOfferOutcome.added;
  }

  void removeFromCart(int index) {
    if (index < 0 || index >= state.items.length) return;
    final item = state.items[index];
    final updatedItems = _removeFromCartUseCase.execute(
      currentCart: state.items,
      index: index,
    );
    final updatedDeleted = [...state.deletedItems, item];
    state = state.copyWith(items: updatedItems, deletedItems: updatedDeleted);

    _logAction(
      'cart_remove',
      item.productId,
      tr('إزالة من السلة: {p0} × {p1}', {'p0': item.productName, 'p1': item.quantity}),
      item.total,
    );

    // Re-evaluate offers after removing item
    _tryAutoApplyOffers();
  }

  void updateQuantity(int index, double quantity) {
    if (index < 0 || index >= state.items.length) return;
    final item = state.items[index];
    final updatedItems = _updateQuantityUseCase.execute(
      currentCart: state.items,
      index: index,
      newQuantity: quantity,
    );
    state = state.copyWith(items: updatedItems);

    // Re-evaluate offers after quantity change
    _tryAutoApplyOffers();

    _logAction(
      'pos_item_qty_change',
      item.productId,
      tr('تغيير كمية: {p0} إلى {quantity}', {'p0': item.productName, 'quantity': quantity}),
      item.effectivePrice * quantity,
    );
  }

  void setDiscount(double percent) {
    state = state.copyWith(discountPercent: percent);
  }

  /// Set discount percentage for a specific cart item
  void setItemDiscount(int index, double percent) {
    if (index < 0 || index >= state.items.length) return;
    final item = state.items[index];
    final updatedItems = List<CartItemEntity>.from(state.items);
    updatedItems[index] = item.copyWith(discountPercent: percent.clamp(0, 100));
    state = state.copyWith(items: updatedItems);

    _logAction(
      'item_discount',
      item.productId,
      tr('خصم على صنف: {p0} — {p1}%', {'p0': item.productName, 'p1': percent.toStringAsFixed(0)}),
      item.subtotal * (percent / 100),
    );
  }

  void toggleTax(bool enabled) {
    state = state.copyWith(taxEnabled: enabled);
  }

  void setTaxRate(double rate) {
    state = state.copyWith(taxRate: rate);
  }

  void setCustomer(int? id, String? name) {
    state = state.copyWith(selectedCustomerId: id, selectedCustomerName: name);
  }

  void setOrderNote(String? note) {
    state = state.copyWith(orderNote: note);
  }

  void setDelivery(
    double fee, {
    int? companyId,
    int? courierId,
    String? status,
  }) {
    state = state.copyWith(
      deliveryFee: fee,
      deliveryCompanyId: companyId,
      courierId: courierId,
      deliveryStatus: status,
    );
  }

  void setPaymentMethod(String method) {
    state = state.copyWith(
      paymentMethod: method,
      // Reset split amounts when changing payment method
      splitCashAmount: 0,
      splitBankAmount: 0,
      splitClickAmount: 0,
    );
  }

  void setBankSafe(int? safeId) {
    state = state.copyWith(bankSafeId: safeId);
  }

  void setPriceLevel(String level) {
    if (state.priceLevel == level) return;
    state = state.copyWith(priceLevel: level);
    // Automatically recalculate prices for all items in cart
    recalculateAllPrices();
  }

  /// Recalculates prices for all items in the cart based on current price level.
  /// Only updates items that haven't been manually edited or are part of an offer.
  Future<void> recalculateAllPrices() async {
    if (state.items.isEmpty) return;

    final productRepo = ref.read(productRepositoryProvider);
    final updatedItems = List<CartItemEntity>.from(state.items);
    bool changed = false;

    for (int i = 0; i < updatedItems.length; i++) {
      final item = updatedItems[i];
      
      // Skip items that are part of an offer (notes starting with 'عرض:')
      if (isOfferLineNote(item.note)) continue;
      
      // Fetch fresh product info to get prices for all levels
      final product = await productRepo.getProductById(item.productId);
      if (product == null) continue;

      final newPrice = resolveProductPrice(product, state.priceLevel);
      if (item.unitPrice != newPrice || item.customPrice != newPrice) {
        updatedItems[i] = item.copyWith(
          unitPrice: newPrice,
          customPrice: newPrice, // Reset custom price to level default
        );
        changed = true;
      }
    }

    if (changed) {
      state = state.copyWith(items: updatedItems);
      // Also re-apply offers as price changes might affect bundle calculations
      _tryAutoApplyOffers();
    }
  }

  // Phase 3: Set order type (internal/delivery) for kitchen printing
  void setOrderType(String type) {
    state = state.copyWith(orderType: type);
  }

  // Phase 4: Set platform order number
  void setPlatformOrderNumber(String? orderNumber) {
    state = state.copyWith(platformOrderNumber: orderNumber);
  }

  // Phase 4: Set ad-hoc customer info (text only, not saved to DB)
  void setAdhocCustomer({String? name, String? phone, String? note}) {
    state = state.copyWith(
      adhocCustomerName: name,
      adhocCustomerPhone: phone,
      adhocCustomerNote: note,
    );
  }

  // Multi-payment: set split amounts
  void setSplitCashAmount(double amount) {
    state = state.copyWith(splitCashAmount: amount);
  }

  void setSplitBankAmount(double amount) {
    state = state.copyWith(splitBankAmount: amount);
  }

  void setSplitClickAmount(double amount) {
    state = state.copyWith(splitClickAmount: amount);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ITEM-LEVEL MODIFIERS & NOTES (POS-1/POS-2)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update modifiers (addons/options) for a specific cart item
  void updateItemModifiers(int index, List<SelectedModifier> modifiers) {
    if (index < 0 || index >= state.items.length) return;
    final item = state.items[index];

    // Calculate extra price from addons
    final extraPrice = modifiers.fold<double>(0, (sum, m) => sum + m.extraPrice);
    final newCustomPrice = item.unitPrice + extraPrice;

    // شيل آخر معدِّل من صنف بلا ملاحظة يدوية ⇒ النص المركّب المفروض يبقى
    // فاضي. من غير `clearNote` كان بيفضل بالمعدِّلات القديمة رغم إن
    // `modifiers` بقت فاضية، فالمطبوع بيقول غير اللي في السلة.
    final composed = composeCartItemNote(modifiers, item.itemNote);
    final updatedItems = List<CartItemEntity>.from(state.items);
    updatedItems[index] = item.copyWith(
      modifiers: modifiers,
      note: composed,
      clearNote: composed == null,
      customPrice: newCustomPrice,
    );
    state = state.copyWith(items: updatedItems);
  }

  /// Update manual note for a specific cart item
  void updateItemNote(int index, String? note) {
    if (index < 0 || index >= state.items.length) return;
    final item = state.items[index];

    final composed = composeCartItemNote(item.modifiers, note);
    final updatedItems = List<CartItemEntity>.from(state.items);
    updatedItems[index] = item.copyWith(
      itemNote: note,
      clearItemNote: note == null || note.isEmpty,
      note: composed,
      clearNote: composed == null,
    );
    state = state.copyWith(items: updatedItems);
  }

  /// Update the selected unit for a cart item (UOM switching)
  /// Adjusts price to the unit's sale price and sets quantityInBase
  /// for correct base-unit stock deduction and COGS calculation.
  void updateItemUnit(int index, {
    required int unitId,
    required String unitName,
    required double quantityInBase,
    required double unitSalePrice,
  }) {
    if (index < 0 || index >= state.items.length) return;
    final item = state.items[index];

    final updatedItems = List<CartItemEntity>.from(state.items);
    updatedItems[index] = item.copyWith(
      selectedUnitId: unitId,
      selectedUnitName: unitName,
      quantityInBase: quantityInBase,
      customPrice: unitSalePrice,
    );
    state = state.copyWith(items: updatedItems);

    _logAction(
      'unit_change',
      item.productId,
      tr('تغيير وحدة: {p0} → {unitName} (×{quantityInBase})', {'p0': item.productName, 'unitName': unitName, 'quantityInBase': quantityInBase}),
      unitSalePrice * item.quantity,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELD ORDERS (Suspended Sales)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String?> holdOrder({String? customerName}) async {
    if (state.items.isEmpty) return null;

    final holdOrderUseCase = ref.read(holdOrderUseCaseProvider);
    final holdNum = await holdOrderUseCase.executeHold(
      HoldOrderRequest(
        items: state.items,
        subtotal: state.subtotal,
        discountPercent: state.discountPercent,
        customerId: state.selectedCustomerId,
        customerName: customerName,
      ),
    );

    if (holdNum != null) {
      clearCart();
    }
    return holdNum;
  }

  /// Retrieve held order and restore it to active cart
  Future<void> retrieveHeldOrder(int id) async {
    final holdOrderUseCase = ref.read(holdOrderUseCaseProvider);
    final response = await holdOrderUseCase.executeRetrieve(id);

    if (response != null) {
      state = state.copyWith(
        items: response.items,
        selectedCustomerId: response.customerId,
        selectedCustomerName: response.customerName,
        discountPercent: response.discountPercent,
      );
    }
  }

  Future<void> loadFromQuotation(
    QuotationWithDetailsDto quotationDetails,
  ) async {
    final productRepo = ref.read(productRepositoryProvider);
    final List<CartItemEntity> cartItems = [];

    for (final item in quotationDetails.items) {
      final product = await productRepo.getProductById(item.item.productId);
      if (product != null) {
        cartItems.add(
          CartItemEntity(
            productId: product.id,
            productName: product.name,
            productCode: product.code,
            barcode: product.barcode,
            unitPrice: item.item.unitPrice,
            quantity: item.item.quantity,
            customPrice: null,
            isSoldByWeight: product.isSoldByWeight,
            // Spec 135 BUG-B (secondary) — preserve the quotation line's tax.
            // Previously dropped, so converting a taxed quotation to a POS
            // sale silently zeroed the tax. Fall back to the product's own
            // rate when the quotation line had none.
            // B3: an exempt product is 0 % whatever the quotation carried.
            taxRate: product.taxExempt
                ? 0
                : (item.item.taxRate > 0 ? item.item.taxRate : product.taxRate),
            taxAmount: product.taxExempt ? 0 : item.item.taxAmount,
            taxExempt: product.taxExempt,
          ),
        );
      }
    }

    state = state.copyWith(
      items: cartItems,
      selectedCustomerId: quotationDetails.quotation.customerId,
      selectedCustomerName: quotationDetails.customerName,
      discountPercent: quotationDetails.quotation.discount,
      orderNote: quotationDetails.quotation.notes ?? '',
      linkedQuotationId: quotationDetails.quotation.id,
    );
  }

  void clearCart() {
    if (state.items.isEmpty) {
      ref.read(checkoutControllerProvider.notifier).clearError();
      return;
    }

    // Clear previous checkout errors when user clears cart
    ref.read(checkoutControllerProvider.notifier).clearError();
    final total = state.total;
    state = CartState(
      taxEnabled: state.taxEnabled,
      taxRate: state.taxRate,
      // Keep layout-neutral settings
    );
    _lastWeightByProduct.clear();  // reset duplicate-weight tracking
    _logAction('cart_clear', 0, tr('مسح السلة بالكامل'), total);
  }

  void _logAction(
    String action,
    int entityId,
    String description,
    double amount,
  ) {
    try {
      final activityLogRepo = ref.read(activityLogRepositoryProvider);
      final auth = ref.read(authProvider);
      activityLogRepo.logActivity(
        userId: auth.user?.id,
        userName: auth.user?.displayName ?? 'Admin',
        action: action,
        entityType: action.contains('offer') ? 'offer' : 'product',
        entityId: entityId,
        description: description,
        amount: amount,
      );
    } catch (_) {}
  }

  /// Delete held order
  Future<void> deleteHeldOrder(int id) async {
    final holdOrderUseCase = ref.read(holdOrderUseCaseProvider);
    await holdOrderUseCase.executeDelete(id);
  }

  /// Generate Work Orders for categories (Kitchen/Preparation tickets)
  Future<int> generateWorkOrders() async {
    if (state.items.isEmpty) return 0;

    final productRepo = ref.read(productRepositoryProvider);

    // Group cart items by category
    final Map<int?, List<CartItemEntity>> itemsByCategory = {};
    for (final item in state.items) {
      final product = await productRepo.getProductById(item.productId);
      final categoryId = product?.categoryId;

      if (!itemsByCategory.containsKey(categoryId)) {
        itemsByCategory[categoryId] = [];
      }
      itemsByCategory[categoryId]!.add(item);
    }

    // Get category names
    final categoriesAsync = ref.read(visibleCategoriesProvider);
    final categories = categoriesAsync.value ?? [];
    final categoryMap = {for (var c in categories) c.id: c.name};

    final now = DateTime.now();
    final orderNumber =
        'WO${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    int printedCount = 0;
    for (final entry in itemsByCategory.entries) {
      final categoryId = entry.key;
      final categoryItems = entry.value;
      final categoryName = categoryId != null
          ? (categoryMap[categoryId] ?? tr('غير مصنف'))
          : tr('غير مصنف');

      final invoiceItems = categoryItems
          .map(
            (item) => InvoiceItem(
              name: item.productName,
              quantity: item.quantity,
              price: item.effectivePrice,
              total: item.total,
              note: item.note,
            ),
          )
          .toList();

      try {
        await InvoiceGenerator.printWorkOrderReceipt(
          orderNumber: '$orderNumber-${printedCount + 1}',
          date: now,
          categoryName: categoryName,
          items: invoiceItems,
          orderType: state.orderType,
          orderNotes: state.orderNote, // <-- ADDED
          customerName: state.adhocCustomerName ?? state.selectedCustomerName, // <-- ADDED
          // ISS-06: Raw DB access retained — printing utilities require the
          // database instance to resolve printer settings and receipt templates.
          db: ref.read(databaseProvider),
        );
        printedCount++;
      } catch (e) {
        AppLogger.instance.warning(
          'Failed to print work order for $categoryName: $e',
        );
      }
    }
    return printedCount;
  }
}

final cartControllerProvider = NotifierProvider<CartController, CartState>(
  CartController.new,
);
