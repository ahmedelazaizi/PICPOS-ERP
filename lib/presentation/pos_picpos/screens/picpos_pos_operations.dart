part of 'picpos_pos_screen.dart';

/// Operations for the PicPos POS screen.
///
/// ── Why this is a separate, trimmed copy ──────────────────────────────────
/// The UralCash screen's orchestration lives in `pos_main_operations.dart`
/// (799 lines) as a PRIVATE mixin bound to `ConsumerState<PosScreenV2>` that
/// reaches into the state with `(this as _PosScreenV2State)._barcodeFocus` in
/// 28 places. It cannot be called from another class without rewriting it —
/// and rewriting it would mean editing UralCash's most critical screen, which
/// HANDOFF §5 forbids.
///
/// So this is a deliberate, scoped copy: only the flows a `lite` till needs.
/// Dropped entirely — kitchen printing, delivery, offers, table orders,
/// modifiers, quotations, exchange/return conversion. What remains is the
/// money path: add, checkout, save, print, drawer.
///
/// One thing this copy does NOT inherit: the cast-to-concrete-state trick.
/// The mixin declares what it needs as abstract getters, so the coupling is a
/// contract instead of a downcast.
///
/// **If you fix a bug in the payment or save path here, check whether
/// `pos_main_operations.dart` has the same bug.** That is the price of the
/// copy, and it was accepted knowingly.
///
/// ── الفروق المقصودة عن `pos_main_operations.dart` ─────────────────────────
/// المسارين بقوا شبه توأمين بعد توحيد الدفع (طلبين ١ و ٢)، فالفروق الباقية
/// **كلها مقصودة** ومش سهو نسخ:
///
/// | | PicPos (هنا) | UralCash (`pos_main_operations.dart`) |
/// |---|---|---|
/// | تحقّق الفترة المالية قبل الدفع | ✔ | ✘ |
/// | توست تسوية فروقات التقريب | ✔ | ✘ |
/// | `printKitchenOrders` | ✘ (مفيش مطبخ في lite) | ✔ |
/// | ديالوج تحصيل النقدية | ✔ | ✔ |
/// | «حفظ» بيفتح الدرج | ✘ عن قصد | ✔ |
/// | أزرار طرق الدفع في اللوحة | ✘ (الديالوج بس) | ✔ |
/// | `allowedMethods` على ديالوج الدفع | ✔ | ✘ (`null` = الكل) |
/// | تعديل فاتورة مرحّلة مبوَّب بصلاحية | ✔ | ✘ (بلا بوابة) |
/// | تخطي «غير متوفر» | سؤال صريح → `allowOversell` | ضغط «آجل» قبل السحب |
///
/// أي صف جديد في الجدول ده لازم يكون قرار، مش نتيجة.

/// فحص صريح قبل فتح ديالوج الميزان — نفس الفحص الموجود في
/// `pos_main_operations.dart` (`canOpenPosWeightDialog`)، لكن مكرَّر هنا بدل
/// ما يتشارك، لأن الملفين مكتبتين مختلفتين (`part of` جذور مختلفة) ومفيش
/// نقطة مشتركة موجودة أصلاً بينهم غير النسخ الصريح المقصود لهذا الفورك (زي
/// ما موثّق في تعليق رأس الملف).
@visibleForTesting
bool canOpenPosWeightDialog(List<String> permissions) {
  final isAdmin =
      permissions.contains('system_admin') || permissions.contains('*');
  return isAdmin || permissions.contains(PermissionCodes.posWeightDialog);
}

/// نسخة أعلى مستوى بتقرا الصلاحيات من `ref` وتعرض توست الرفض — سطر واحد
/// في نقطة الاستدعاء (زي `pos_main_operations.dart`).
@visibleForTesting
Future<bool> ensurePosWeightDialogPermission(
  WidgetRef ref,
  BuildContext context,
) async {
  final permissions =
      ref.read(currentUserPermissionsProvider).asData?.value ??
          const <String>[];
  if (canOpenPosWeightDialog(permissions)) return true;
  if (context.mounted) {
    showPosToast(context, ref, 'ليس لديك صلاحية استخدام الميزان',
        type: PosNotificationType.error);
  }
  return false;
}

// ── صلاحياتُ السلّة ────────────────────────────────────────────────────────
//
// بلاغٌ ميدانيّ (2026-08-11): «رفعتُ التحديد عن حذف صنف من السلة، ودخلتُ
// بالكاشير، فحذف الصنفَ ولم يظهر حوارُ كلمة المرور».
//
// الأربعةُ محروسةٌ في `pos/widgets/cart_item_tile.dart` و`cart_view.dart` —
// وهذه الشاشةُ توأمٌ كُتب من جديدٍ **ولا يستوردهما** (‏السببُ موثَّقٌ في
// `picpos_payment_panel.dart:11`). فنُقل السلوكُ ولم تُنقل الحراسة: لم يكن
// ثمّة تجاوزٌ للصلاحية بل **غيابُ نقطةِ فحصٍ من الأساس**.
//
// دوالُّ قرارٍ خالصةٌ قصداً — تُختبر بلا شجرةِ ودجت، والوصلُ محروسٌ في
// `picpos_permission_parity_test`. ومديرُ النظام يمرّ بلا كودٍ صريحٍ لأن هذه
// ليست عملياتٍ ماليةً حرجة، تماماً كـ`canOpenPosWeightDialog` فوق.

bool _isAdmin(List<String> p) =>
    p.contains('system_admin') || p.contains('*');

/// حذفُ صنفٍ من السلة (`pos_remove_item`).
@visibleForTesting
bool canRemoveCartItem(List<String> permissions) =>
    _isAdmin(permissions) ||
    permissions.contains(PermissionCodes.posRemoveItem);

/// تفريغُ السلة بالكامل (`pos_clear_cart`).
@visibleForTesting
bool canClearCart(List<String> permissions) =>
    _isAdmin(permissions) || permissions.contains(PermissionCodes.posClearCart);

/// تعديلُ سعر صنفٍ في البيع (`pos_price_edit`).
@visibleForTesting
bool canEditCartPrice(List<String> permissions) =>
    _isAdmin(permissions) || permissions.contains(PermissionCodes.posPriceEdit);

/// تعديلُ كميةِ صنفٍ في السلة (`pos_quantity_edit`).
@visibleForTesting
bool canEditCartQuantity(List<String> permissions) =>
    _isAdmin(permissions) ||
    permissions.contains(PermissionCodes.posQuantityEdit);

// ── وضعُ المرتجع: دوالُّ قرارٍ خالصة (المهمّة ٧، جولةُ إصلاح ١) ─────────────
//
// خالصةٌ عمداً — بلا `BuildContext` ولا `WidgetRef` — كي تُختبر بلا شجرة
// ودجت ولا `ProviderContainer`، نفسُ نمط `canOpenPosWeightDialog` أعلاه.

/// «مرتجعٌ كامل» فقط حين استُنفد المتاحُ الحاليّ (‏`ReturnableLine.
/// availableQty`، القيمةُ نفسُها التي يسقُف بها `PosReturnMode.setQty`) على
/// **كلّ** سطرٍ في [mode]، **و**لا صنفَ مكرَّراً على أكثرَ من سطرٍ في نفس
/// الفاتورة. سطرٌ لم يُطلَب منه شيءٌ ومتاحُه > 0 يمنع الوصفَ «كامل» — قد يكون
/// الكاشيرُ استبعده عمداً بـ`clearQty` لا أنه نسِيَه.
///
/// ⚠️ **تصحيحٌ (جولةُ إصلاح ٢) لتعليقٍ سابقٍ زعم اتجاهَ أمانٍ مقلوباً:**
/// `ReturnableLine.alreadyReturnedQty` (‏`_showQuickReturn`) يأتي من استعلامٍ
/// بمفتاح `productId` بينما `soldQty` بمفتاح **السطر**. فاتورةٌ فيها نفسُ
/// الصنف على أكثرَ من سطرٍ (مثلاً ٥ + ٤) ومرتجعٌ سابقٌ ٣ (بمفتاح المنتَج، لا
/// بمفتاح أيّ سطر) تُنسِب الـ٣ لِـ**كلّ** سطرٍ منفصلاً — فقياسٌ فعليّ
/// (‏`requestedTotal=3, trueRemaining=6`) أثبت أن مقارنةً ساذجةً بين
/// `requestedQty` الظاهرة ومتاحِ كلّ سطرٍ **تُبالغ**، لا تُقلّل: «تحديد الكلّ»
/// كانت تُرجع `true` بينما ٣ وحداتٍ حقيقيّةً لم تُطلَب أصلاً، فتُختم
/// الفاتورةُ `'returned'` نهائياً (`processSalesReturn`) وتفقد الثلاثةَ
/// للأبد (`getInvoicesForReturn` تستبعد المرتجَعةَ بالكامل أبداً). المشكلةُ
/// الحقيقيّةُ ليست «تحفّظاً» بل **مقارنةً بين مفتاحَين مختلفَين لا يجوز
/// مقارنتُهما إطلاقاً**. فالحمايةُ الوحيدةُ الصحيحة: **رفضُ الختم `true`
/// كلّياً** كلَّما تكرَّر `productId` على أكثرَ من سطرٍ في نفس الفاتورة — لا
/// محاولةَ حسابٍ «أدقّ» فوق مفتاحَين متعارضَين. الإصلاحُ الجذريّ (استعلامٌ
/// بمفتاح السطر) يحتاج تعديلَ طبقة المستودع (‏`returns_repository_impl.
/// dart:109`) — خارج ملفّات هذه المهمّة، فلم يُصلَح هنا.
@visibleForTesting
bool computeIsFullReturn(PosReturnMode mode) {
  final linesPerProduct = <int, int>{};
  for (final line in mode.linesByItemId.values) {
    linesPerProduct[line.productId] = (linesPerProduct[line.productId] ?? 0) + 1;
  }
  // صنفٌ على أكثرَ من سطرٍ ⇒ `alreadyReturnedQty` غيرُ موثوقةٍ لأيٍّ منها
  // (مفتاحٌ مختلفٌ عن `soldQty`) ⇒ لا يجوز الختمُ `true` إطلاقاً.
  if (linesPerProduct.values.any((count) => count > 1)) return false;

  return mode.linesByItemId.values.every((line) {
    final requested = mode.requestedQty[line.invoiceItemId] ?? 0;
    return (requested - line.availableQty).abs() < 0.001;
  });
}

/// يبحث عن أوّل سطرٍ في [mode] يخصّ [productId] ولا يزال له متاحٌ فوق ما
/// طُلِب منه فعلاً — نقطةُ القرار الخالصة وراء حقل البحث/الباركود في
/// `_QuickReturnLinesEditorDialog`. يرجع `null` حين يكون الصنفُ خارجَ
/// الفاتورة أصلاً (‏`PosReturnMode.canAcceptProduct` ترفضه) أو حين تكون كلُّ
/// أسطره المطابقة قد بلغت سقفَها.
///
/// فاتورةٌ فيها نفسُ الصنف على أكثرَ من سطر: يرجع أوّلَ سطرٍ لسه له مكانٌ —
/// فمسحةٌ متكرّرةٌ لنفس الباركود تملأ الأسطرَ واحداً تلو الآخر بدل أن تتكدّس
/// كلّها على أوّل سطرٍ وترفضَ بلا سببٍ ظاهر بعد استنفاده.
@visibleForTesting
ReturnableLine? findReturnableLineForProduct(PosReturnMode mode, int productId) {
  if (!mode.canAcceptProduct(productId)) return null;
  for (final line in mode.linesByItemId.values) {
    if (line.productId != productId) continue;
    final requested = mode.requestedQty[line.invoiceItemId] ?? 0;
    if (requested < line.availableQty - 0.0005) return line;
  }
  return null;
}

/// يحسب الكميّةَ التاليةَ عند زيادة سطرٍ خطوةً واحدة (‏[step])، **محدودةً
/// بالمتاح فلا تتجاوزه أبداً** — القلبُ الحسابيُّ وراء زرّ «+» وحقلِ
/// البحث/الباركود في `_QuickReturnLinesEditorDialog` (المتطلَّبُ ٥، جولةُ
/// إصلاح ٢). يرجع `null` حين لا مجالَ للزيادة إطلاقاً (‏الكميةُ الحاليّةُ
/// بلغت المتاحَ أصلاً).
///
/// ⚠️ بلا هذا القصّ: سطرٌ متاحُه كسريّ (‏٢٫٥ لصنفٍ موزون) عند `current=2`
/// يطلب `2+1=3` فترفضها `PosReturnMode.setQty` **بلا أثرٍ ولا رسالة** — وهو
/// بالضبط ما كان يحدث قبل هذا الاستخراج.
@visibleForTesting
double? nextIncrementedQty(
  ReturnableLine line,
  double currentQty, {
  double step = 1,
}) {
  final available = line.availableQty;
  if (currentQty >= available - 0.0005) return null;
  return (currentQty + step <= available + 0.0005)
      ? currentQty + step
      : available;
}

/// وضعُ المرتجع يمنع أيَّ مدخلٍ يكتب على سلّة البيع أو يحذف بياناتٍ لا رجعةَ
/// فيها — نقطةُ القرارِ الموحَّدة وراء حرّاس `_handleProductTap`
/// (‏شبكةُ الأصناف)، `_searchBarcode` (‏حقلُ الباركود الرئيسيّ)، و
/// `_showHeldOrders` (‏الفواتيرُ المعلَّقة، جولةُ إصلاح ٢ — مانعٌ ١: استرجاعُ
/// طلبٍ معلَّقٍ يحذفه من القاعدة نهائياً، وحفظُ المرتجع يمحو السلّةَ بعده).
///
/// دالّةٌ واحدةٌ خالصةٌ لثلاثتها كي تفشل معاً وتُصلَح معاً: طفرةٌ على هذا
/// الشرط تُسقِط اختبارَ الثلاثة، لا واحداً ينساه إعادةُ كتابةٍ لاحقة.
@visibleForTesting
bool blocksCartMutation(PosReturnMode? mode) => mode != null;

/// ── الإضافةُ السريعة لصنفٍ غير مسجَّل ─────────────────────────────────────
///
/// بلاغُ مالكٍ (2026-08-17): «ديالوج الإضافة السريعة كان عامله في Ural بس
/// انت مجبتهوش معاك كمنطق عمل». الديالوج نفسُه (`QuickAddProductDialog`)
/// موجودٌ ومكتملٌ من قبل — الناقصُ كان توصيلُه بمسار مسح الباركود في هذه
/// الشاشة (‏`_searchBarcode` تحت)، لا بناءٌ من الصفر.
///
/// دالّةُ قرارٍ خالصةٌ عمداً — نفسُ نمط `blocksCartMutation` فوق — كي تُختبر
/// بلا شجرة ودجت. الشروطُ تطابق `pos_main_operations.dart:380-382` زائدَ
/// حراسةَ وضع المرتجع الخاصّة بهذه الشاشة:
///  1. الباركودُ غيرُ مسجَّلٍ فعلاً (`errorKind == notFound`) — لا صنفٌ
///     معطَّل (`inactive`)، ولا باركودُ ميزانٍ فشل تحليلُه (`invalidScale`،
///     القيد الخامس من بلاغ المالك)، ولا خطأٌ آخر (`general`).
///  2. ليس في وضع مرتجع — `blocksCartMutation` نفسُها التي تحرس
///     `_handleProductTap`/`_showHeldOrders` فوق، فلا يفتح الديالوجُ
///     ويكتب على سلّة بيعٍ أثناء تحرير مرتجع.
@visibleForTesting
bool shouldOfferQuickAdd(PicposBarcodeSearchErrorKind? errorKind, PosReturnMode? mode) =>
    errorKind == PicposBarcodeSearchErrorKind.notFound && !blocksCartMutation(mode);

mixin _PicPosOperations on ConsumerState<PicPosPosScreen> {
  // ── Contract the screen must satisfy ───────────────────────────────────
  TextEditingController get barcodeController;
  FocusNode get barcodeFocus;
  int? get selectedIndex;
  set selectedIndex(int? value);

  // ── وضعُ المرتجع (المهمّة ٧) ──────────────────────────────────────────
  //
  // `PosReturnMode` (‏`posReturnModeProvider`) خالصةٌ عمداً: تحمل `invoiceId`
  // (رقمٌ) و`ReturnableLine` لكلّ سطر — لا كائنَ `SalesInvoiceData` ولا
  // `ProductEntity` (‏راجع تعليقَ رأس `pos_return_mode.dart`). ومسارُ الحفظ
  // (‏`processSalesReturn`) يحتاج الاثنين معاً: الفاتورةَ الأصليّةَ نفسَها
  // و`productCache` مفتاحُه `productId`. فهذان محليّان في الشاشة، يُضبَطان
  // معاً مع الوضع في `_showQuickReturn` ويُفرَّغان معاً معه في
  // `_processQuickReturnSave`/`_cancelQuickReturn` — لا مصدرَ حقيقةٍ ثانياً
  // لنفس البيانات، فقط بياناتٌ إضافيّةٌ لا مكانَ لها في النموذج الخالص.
  SalesInvoiceData? _returnInvoice;
  Map<int, ProductEntity> _returnProductCache = const {};

  /// رقمُ الفاتورة المعروض في الترويسة الحمراء — نصٌّ، لا الكائن نفسُه، لأن
  /// `PicPosReturnModeBanner` عديمةُ الحالة ولا تعرف `data/database`.
  String? get _returnInvoiceNumber => _returnInvoice?.invoiceNumber;

  /// نظائرُ ما فوق لوضع الاستبدال — منفصلةٌ عمداً لا مُعادُ استعمالها: الوضعان
  /// حصريّان، لكنّ تشاركَ الحقلَين كان يجعل إلغاءَ أحدهما يمسح بياناتِ الآخر
  /// لو تسرّبت حالةٌ، ويُخفي أيَّ خلطٍ خلف حقلٍ واحد.
  SalesInvoiceData? _exchangeInvoice;
  Map<int, ProductEntity> _exchangeProductCache = const {};

  String? get _exchangeInvoiceNumber => _exchangeInvoice?.invoiceNumber;

  /// يُعيد المؤشرَ إلى حقل الباركود — ما لم يُطفئ المديرُ «التركيز الدائم».
  ///
  /// ⚠️ **قراءةٌ متزامنةٌ بـ`asData?.value` لا `await`.** هذه الدالّةُ تُنادى بعد
  /// كلِّ إضافةٍ وحذفٍ وإغلاقِ نافذة، فجعلُها `async` كان يُدخل إطارَ انتظارٍ
  /// في أسخنِ مسارٍ في الشاشة. و`null` (‏السياسةُ لم تُحمَّل بعد) تعني
  /// **الإرجاع** — وهو السلوكُ القائمُ قبل هذا الإعداد، فلا يتبدّل شيءٌ في
  /// أوّلِ إطاراتِ الشاشة.
  void _refocusScanner() {
    if (!mounted) return;
    final policy = ref.read(quickSalePolicyProvider).asData?.value;
    if (policy != null &&
        !policy.isOn(kQuickSaleRows.firstWhere((r) => r.id == 'focus'))) {
      return;
    }
    barcodeFocus.requestFocus();
  }

  // ── Shift open enforcement ─────────────────────────────────────────────
  //
  // منسوخ حرفياً من `pos_main_dialogs.dart` (`_PosMainDialogsMixin._ensureShiftOpen`)
  // — كان مفقوداً من فورك PicPos POS، فالكاشير في PicPos ما كانش بيشوف ديالوج
  // بدء الوردية عند الدخول زي UralCash (شاشة UralCash POS بتنادي `_ensureShiftOpen`
  // من `initState`؛ الفورك فوّتها فبقى يعتمد على حارس MainScreen وحده اللي بيتخطّى
  // المدير). أي إصلاح منطقي هنا يتصلّح في المصدر أولاً ثم patch (مصيدة النسخ §٥.٥).
  // يشارك `shiftDialogPromptedUserIds` (حارس الجلسة المشترك) مع حارس MainScreen
  // فمفيش ديالوج مزدوج — أول واحد يفتح بيقيّد المستخدم والتاني بيتخطّى.
  Future<void> _ensureShiftOpen() async {
    try {
      final treasuryRepo = ref.read(treasuryRepositoryProvider);
      final authState = ref.read(authProvider);
      final userId = authState.user?.id ?? 1;

      // Spec 135 NOTE 2 (req 4) — a system-admin login does NOT auto-open its
      // own shift. The admin enters through the previous cashier's OPEN shift
      // (via the closing dialog) to reconcile balances, close it, and record
      // the variances. Cashiers keep the auto-open behaviour below.
      if (authState.isOriginallyAdmin) {
        unawaited(DiagnosticLogger.log('SHIFT-GUARD',
            '_ensureShiftOpen skipped for system admin userId=$userId — '
            'admin attaches to an existing open shift to reconcile/close, '
            'not a new auto-opened shift'));
        return;
      }

      // ── وردياتٌ متزامنةٌ لنفس المستخدم (طلبُ المالك 2026-08-14) ─────────
      //
      // الفحصُ المحليُّ **قبل** السحب، والسحبُ بعده. الترتيبُ هو المميِّز:
      // صفٌّ موجودٌ محلياً سلفاً = ورديتي على هذا الجهاز (إعادةُ تشغيلٍ،
      // فأكمِل كما كان الحال دائماً)؛ صفٌّ لا يظهر إلا بعد السحب = فُتحت
      // على طرفٍ آخر ⇒ نبّه وامنع.
      //
      // ولا عمودَ يغني عن هذا: `posTerminalId` يبقى `null` متى لم تُسجَّل
      // الطرفيّةُ محلياً (`treasury_dao.dart:346-360`)، و`originClientId` لا
      // يُكتب في مسار الفتح إطلاقاً.
      final currentShift = await treasuryRepo.getCurrentOpenShift(userId);

      // نظيرُ `app_main_screen.dart:1339` يسحب `shifts` قبل فحصه، وهذه
      // النسخةُ **كانت لا تسحب** — فالجهازُ الثاني يجهل ورديةَ الأوّل
      // فيفتح ثانيةً صامتة. هذا هو الثقبُ بعينه.
      ShiftData? afterPull = currentShift;
      final isClientMode = NetworkService.instance.isClient;
      if (currentShift == null && isClientMode) {
        try {
          await DeltaPullService.instance.pullTable('shifts');
          afterPull = await treasuryRepo.getCurrentOpenShift(userId);
        } catch (e) {
          // تعذُّرُ السحب لا يمنع الفتح: تِلٌّ مقطوعُ الشبكة يجب أن يبيع.
          // والسيرفرُ يرفض الازدواجَ من جهته على أيّ حال (Feature 048 v130).
          debugPrint('[ShiftGuard] pull shifts failed (non-fatal): $e');
        }
      }

      final gate = decideShiftOpenGate(
        hasLocalOpenShift: currentShift != null,
        hasOpenShiftAfterPull: afterPull != null,
        isClient: isClientMode,
      );

      unawaited(DiagnosticLogger.log('SHIFT-GUARD',
          '_ensureShiftOpen check userId=$userId '
          'openShiftId=${currentShift?.id} '
          'afterPullShiftId=${afterPull?.id} gate=${gate.name} '
          'alreadyPrompted=${shiftDialogPromptedUserIds.contains(userId)} '
          'callSite=PicPosPosScreen.initState'));

      if (gate == ShiftOpenGate.alreadyOpenHere) return;

      if (gate == ShiftOpenGate.openOnAnotherTerminal) {
        final blocked = await _handleShiftOpenedElsewhere(afterPull!);
        if (blocked) return; // مُنِع أو انصرف — لا فتحَ هنا
      }

      // Feature 012 / Issue C-SHIFT-LOOP: same-session guard. Once we
      // have already prompted this user in this session, refuse to do
      // it again — even if the lookup transiently returns null. The
      // user will use the manual "فتح الوردية" affordance from the
      // treasury screen if they truly need to reopen.
      if (shiftDialogPromptedUserIds.contains(userId)) {
        unawaited(DiagnosticLogger.log('SHIFT-GUARD',
            '⚠ suppressed re-prompt for userId=$userId '
            '(already prompted in this session) — likely upstream '
            'overwrite of local open-shift row, see ShiftSyncStrategy'));
        return;
      }
      shiftDialogPromptedUserIds.add(userId);

      // Feature 006 #2: properly await the setting future so we don't race
      // the FutureProvider's first load. `ref.read(...).value` returned
      // null on cold-start (provider still loading) and the `?? true`
      // fallback masked toggled-off setups; switch to `.future` so we read
      // the persisted value, not the in-flight AsyncValue.
      final shiftDialogEnabled =
          await ref.read(posShiftDialogEnabledProvider.future);

      double opening = 0;
      if (!shiftDialogEnabled) {
        opening = 0;
      } else {
        if (!mounted) return;
        final userName = authState.user?.displayName ?? 'كاشير';
        final picked = await showDialog<double>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PosOpeningBalanceDialog(userName: userName),
        );
        opening = picked ?? 0; // Cancel → treat as 0
      }

      // Spec 008 / FR-004: resolve the operating branch so multi-branch
      // users open the shift on their CURRENT branch, not always the
      // first user_branch_access row. Single-branch users get the same
      // value as before (their only branch).
      int? scopedBranchId;
      try {
        final scope = await ref.read(branchScopeProvider.future);
        scopedBranchId = scope.primaryBranchId;
        // Full-access admins (system admin) have primaryBranchId=null;
        // fall back to getUserBranchId so the shift close can find the
        // correct safes and the shift reports show the right branch.
        if (scopedBranchId == null) {
          final db = ref.read(databaseProvider);
          final uid = authState.user?.id ?? userId;
          scopedBranchId = await db.getUserBranchId(uid);
        }
      } catch (e) {
        debugPrint('openShift: BranchScope lookup failed (non-fatal): $e');
      }

      // Write locally first so the cashier can work immediately even while
      // offline. The local shift ID anchors the rest of the session.
      await treasuryRepo.openShift(userId, opening, branchId: scopedBranchId);

      // Look up the local shift id/globalId we just created and forward them
      // to the mirror call so close-shift later resolves by globalId (R9 fix
      // for the recurring "Shift not found" 500 / DEAD-LETTER on every close).
      int? localShiftId;
      String? localShiftGlobalId;
      try {
        final activeShift = await treasuryRepo.getCurrentOpenShift(userId);
        localShiftId = activeShift?.id;
        localShiftGlobalId = activeShift?.globalId;
      } catch (e) {
        debugPrint('openShift: could not fetch local shift id (non-fatal): $e');
      }
      unawaited(DiagnosticLogger.log('SHIFT',
          'New shift opened (PicPosPosScreen._ensureShiftOpen) '
          'userId=$userId localShiftId=$localShiftId '
          'globalId=$localShiftGlobalId opening=$opening '
          'branchId=$scopedBranchId'));

      // Mirror to server so close-shift later has a matching row there.
      try {
        await ClientWriteInterceptor.openShift(userId, opening,
            localShiftId: localShiftId,
            branchId: scopedBranchId,
            globalId: localShiftGlobalId);
      } catch (e) {
        debugPrint('openShift server mirror failed (non-fatal, will queue): $e');
      }
    } catch (e, st) {
      // Feature 006 #2: surface the failure instead of swallowing it, so the
      // operator sees WHY the auto-open failed (unmapped CoA cash accounts,
      // missing branch row, or a server-mirror failure) rather than "broken".
      debugPrint('Error ensuring shift open: $e\n$st');
      unawaited(DiagnosticLogger.log(
        'SHIFT-OPEN-FAIL',
        '_ensureShiftOpen threw: $e',
      ));
      if (mounted) {
        final msg = e.toString();
        final shortMsg = msg.length > 200 ? '${msg.substring(0, 200)}…' : msg;
        AppToast.show(
          context,
          'تعذّر فتح الوردية تلقائياً: $shortMsg',
          type: ToastType.warning,
        );
      }
    }
  }

  /// يفتح شاشةَ الحجوزات فوق نقطة البيع — طلبُ المالك 2026-08-23.
  ///
  /// ⚠️ **دفعٌ فوق الشاشة لا استبدالٌ لها**: السلّةُ القائمةُ تبقى كما هي،
  /// والرجوعُ يعيد الكاشيرَ إليها بلا فقدِ سطر. واستبدالُ المسار كان
  /// سيُفرِّغ سلّةً نصفَ مكتملةٍ بلا سؤال.
  ///
  /// وهو أيضاً ما يجعل التفويترَ يعمل: الحوارُ يرفع علامةَ الحجز ثمّ يعود
  /// المستخدمُ إلى **نفس** جلسة نقطة البيع فيُتِمّ البيع.
  Future<void> _openBookings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BookingsPicPosScreen()),
    );
  }

  /// Hand the till to another cashier. وردية الخارج بتفضل مفتوحة — الديالوج
  /// بيبلّغ بيها بس (`notifyOpenShift`)، ونفس الإشعار بيتنادى عند الخروج.
  Future<void> _switchUser() async {
    // A cart in progress belongs to the outgoing cashier; make them decide
    // what to do with it before the session changes underneath them.
    if (ref.read(cartControllerProvider).items.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('السلة غير فارغة'),
            content: const Text(
              'فيه أصناف في السلة لسه ما اتحفظتش. تحويل المستخدم هيمسحها. '
              'تحب تكمّل؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('رجوع'),
              ),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('مسح وتحويل'),
              ),
            ],
          ),
        ),
      );
      if (discard != true || !mounted) return;
    }

    final switched = await PicposSwitchUserDialog.show(context, ref);
    if (!mounted) return;
    if (switched) {
      setState(() => selectedIndex = null);
      showPosToast(
        context,
        ref,
        'تم التحويل إلى ${ref.read(authProvider).effectiveUser?.displayName ?? 'المستخدم الجديد'}',
        type: PosNotificationType.success,
      );

      // ── فتح وردية الكاشير الجديد ─────────────────────────────────────────
      // `_ensureShiftOpen` بتتنادى من `initState` بس، والشاشة **مابتعملش
      // remount** لما التحويل بيحصل في مكانه. فمن غير النداء ده الكاشير الجاي
      // بيقف على تِل **بلا وردية مفتوحة ومحدش بينبّهه**، ومبيعاته تقع بره أي
      // نافذة وردية — يعني تقرير الإغلاق ما يشوفهاش وقائمة «الفواتير السابقة»
      // بترتد لليوم التقويمي.
      //
      // بلا `await` قبل التوست عشان الكاشير يشوف تأكيد التحويل الأول ثم يتصرّف
      // في الوردية.
      await _ensureShiftOpen();
      if (!mounted) return;
      _refocusScanner();
    }
  }

  // ── Adding items ───────────────────────────────────────────────────────

  /// Tapping a card in the product grid.
  ///
  /// `cartController.addItem` owns the price level, the stock guard and the
  /// negative-sale policy, so there is nothing to decide here. It refuses
  /// silently for an out-of-stock item (the card already renders «غير متوفر»),
  /// which is why the cart length is compared before and after rather than
  /// assuming the add landed.
  ///
  /// A weighed item cannot be added on a tap alone — it has no quantity until
  /// something weighs it. PicPos used to add it as quantity 1, i.e. one
  /// kilogram of whatever the cashier tapped, while still rendering the scale
  /// badge on the card. The weight prompt below closes that gap; it is the
  /// same `PosDialogs.showWeightInput` UralCash uses, which short-circuits
  /// silently when a live scale is connected and stable.
  Future<void> _handleProductTap(ProductEntity product) async {
    // وضعُ المرتجع (المهمّة ٧، جولةُ إصلاح ١): لمسُ الشبكة أثناء المرتجع كان
    // يضيف صنفاً **مبيعاً حقيقياً** بسعر شاشة الأصناف إلى سلّةٍ لا علاقةَ لها
    // بالمرتجع (السلّةُ لا تُكتَب من محرِّر أسطر المرتجع عمداً) ثم يُهمَل
    // صامتاً عند الحفظ — بلاغُ المراجع C2. رفضٌ صريحٌ برسالةٍ ظاهرة بدل
    // إهمالٍ صامت. `blocksCartMutation` مُختبَرةٌ في
    // `picpos_quick_return_lines_test.dart`.
    if (blocksCartMutation(ref.read(posReturnModeProvider))) {
      showPosToast(
        context,
        ref,
        'أنت في وضع المرتجع — أنهِ الحفظَ أو الإلغاءَ قبل إضافة صنفٍ للبيع',
        type: PosNotificationType.warning,
      );
      return;
    }
    // سؤال «غير متوفر» **أول حاجة**، قبل الميزان وقبل منتقي الوحدة: لو الكاشير
    // قال لا، ما يكونش وزن الصنف واختار وحدته على الفاضي. الفحص ده مكرَّر في
    // `_addToCart` كخط دفاع تاني، ومش بيسأل مرتين — أول موافقة بتفتح
    // `allowOversell` فالنداء التاني ما بيبقى متوقّف أصلاً.
    if (!await _ensureOversellAllowed(product)) {
      _refocusScanner();
      return;
    }
    if (!mounted) return;

    if (product.isSoldByWeight) {
      if (!await ensurePosWeightDialogPermission(ref, context)) {
        _refocusScanner();
        return;
      }
      final weight = await PosDialogs.showWeightInput(context, ref, product);
      // null = cashier cancelled. Adding nothing is the correct outcome.
      if (weight == null || weight <= 0) {
        _refocusScanner();
        return;
      }
      if (!mounted) return;
      await _addProductWithUnits(product, quantity: weight);
      return;
    }

    // «سؤال عن الكمية قبل الإضافة» — §٤. بعد فرع الوزن عمداً: الصنفُ
    // الموزونُ يسأل عن وزنه سلفاً، وسؤالُه مرّتين تكرارٌ لا دقّة.
    final quantity = await _askLineQuantity(product);
    if (quantity == null || !mounted) return;
    await _addProductWithUnits(product, quantity: quantity);
  }

  /// كميّةُ السطر قبل الإضافة — `null` تعني «ألغى الكاشيرُ فلا يُضاف شيء».
  ///
  /// ⚠️ **تنتظر السياسةَ ولا تخمّنها.** كانت تقرأ `asData?.value` متزامناً
  /// فترجع `null` قبل أن يسخن المزوِّدُ ⇒ لا يظهر الحوارُ أبداً. والمزوِّدُ
  /// مُسخَّنٌ الآن بـ`ref.watch` في بناء الشاشة، لكنّ `await` هنا يجعل
  /// الصحّةَ مستقلّةً عن ترتيب المسارات لا معتمدةً عليه.
  Future<double?> _askLineQuantity(ProductEntity product) async {
    final policy = await ref.read(quickSalePolicyProvider.future);
    if (!mounted) return null;
    if (!policy.isOn(kQuickSaleRows.firstWhere((r) => r.id == 'askqty'))) {
      return 1;
    }

    // نفسُ سقف «أقصى كمية في السطر» المطبَّق في حوار تعديل السطر — وإلّا
    // قَبِلَ بابُ الدخولِ رقماً يرفضه بابُ التعديل، وهو تناقضٌ يراه
    // الكاشيرُ خطأً في النظام لا حدّاً مقصوداً.
    final maxQty = quickSaleMaxLineQty(policy);
    final qty = await PicPosNumericKeypadDialog.show(
      context,
      title: product.name,
      initialValue: 1,
      decimals: 0,
      min: 1,
      max: maxQty,
    );
    if (!mounted) return null;
    if (qty == null || qty <= 0) {
      _refocusScanner();
      return null;
    }
    return qty;
  }

  /// Adds [product] to the cart, offering the unit picker first when the
  /// product is sold in more than one packaging unit.
  Future<void> _addProductWithUnits(
    ProductEntity product, {
    double quantity = 1,
  }) async {
    final units =
        await ref.read(productRepositoryProvider).getProductUnits(product.id);
    if (!mounted) return;

    if (units.length > 1) {
      final selectedUnit = await UnitSelectionDialog.show(
        context,
        productName: product.name,
        units: units,
      );
      // Cancelling the unit picker cancels the whole add — guessing a unit
      // would silently price the line wrong.
      if (selectedUnit == null) {
        _refocusScanner();
        return;
      }
      if (!mounted) return;

      final unitPrice = selectedUnit.salePrice > 0
          ? selectedUnit.salePrice
          : product.salePrice;
      await _addToCart(product, quantity: quantity, customPrice: unitPrice);
      if (!mounted) return;

      final cartItems = ref.read(cartControllerProvider).items;
      if (cartItems.isNotEmpty) {
        ref.read(cartControllerProvider.notifier).updateItemUnit(
              cartItems.length - 1,
              unitId: selectedUnit.id,
              unitName: selectedUnit.unitName,
              quantityInBase: selectedUnit.quantityInBase,
              unitSalePrice: unitPrice,
            );
      }
      return;
    }

    await _addToCart(product, quantity: quantity);
  }

  /// The actual cart write, plus the selection/rejection bookkeeping the
  /// PicPos cart relies on.
  Future<void> _addToCart(
    ProductEntity product, {
    double quantity = 1,
    double? customPrice,
  }) async {
    // ── الرفض بسبب المخزون: نسأل بدل ما نرفض في الصمت ──────────────────────
    // القدرة على بيع صنف غير متوفر كانت موجودة عن طريق ضغط «آجل» قبل السحب
    // (اقرا `CartState.allowOversell`). أزرار الطرق اتشالت من اللوحة، فالمسار
    // ده رجع هنا **صريحاً**: بنسأل في اللحظة اللي الرفض بيحصل فيها، فالقدرة
    // بقت مكتشَفة بدل ما تكون معرفة شفهية.
    if (!await _ensureOversellAllowed(product)) {
      _refocusScanner();
      return;
    }
    if (!mounted) return;

    // Live-scale duplicate-weight guard. Only for the tap → weight-dialog
    // flow: two identical PRE-PRINTED labels are two legitimate weighings,
    // so `searchBarcode` deliberately skips this check. Here, the same
    // (product, weight) twice within 30s usually means the cashier forgot to
    // change the item on the scale.
    bool shouldWarnDuplicate = false;
    if (product.isSoldByWeight && quantity > 0) {
      shouldWarnDuplicate = ref
          .read(picposSearchControllerProvider.notifier)
          .checkAndWarnDuplicateWeight(
            productId: product.id,
            productName: product.name,
            weightKg: quantity,
          );
    }

    final before = ref.read(cartControllerProvider).items.length;
    final stacking = resolveStackingFlags(
      isSoldByWeight: product.isSoldByWeight,
      preventStacking: ref.read(preventItemStackingProvider).value ?? false,
    );
    ref.read(cartControllerProvider.notifier).addItem(
          product,
          quantity: quantity,
          forceNewEntry: stacking.forceNewEntry,
          mergeWeight: stacking.mergeWeight,
          customPrice: customPrice,
        );
    final items = ref.read(cartControllerProvider).items;
    if (items.length > before) {
      setState(() => selectedIndex = items.length - 1);
    } else if (items.length == before) {
      // Either merged into an existing line, or refused. Select the line the
      // product is on so the cashier sees what changed either way.
      final idx = items.lastIndexWhere((i) => i.productId == product.id);
      if (idx != -1) {
        setState(() => selectedIndex = idx);
      } else {
        // مش رفض مخزون — ده اتعامل معاه فوق قبل الإضافة. أي رفض تاني (سعر
        // صفر مرفوض من الـ use case مثلاً) بيوصل هنا.
        showPosToast(context, ref, 'تعذّرت إضافة الصنف',
            type: PosNotificationType.error);
      }
    }
    _refocusScanner();

    // Raised AFTER the add so the cart reflects reality when the cashier
    // acknowledges. The item stays in the cart either way — the popup only
    // makes sure a repeated weight cannot go unnoticed.
    if (shouldWarnDuplicate && mounted) {
      final msg = ref.read(picposSearchControllerProvider).duplicateWeightWarning;
      // Cleared immediately so a follow-up add with a new weight doesn't
      // re-trigger the popup from stale state.
      ref
          .read(picposSearchControllerProvider.notifier)
          .clearDuplicateWeightWarning();
      if (msg != null) _showDuplicateWeightDialog(msg);
    }
  }

  /// يتأكد إن [product] مسموح إضافته رغم إن مخزونه صفر أو أقل.
  ///
  /// `true` = كمّل الإضافة (مش مرفوض أصلاً، أو الكاشير سمح). `false` = وقف.
  ///
  /// ── ليه في اللحظة دي مش في إعداد ─────────────────────────────────────────
  /// المسار القديم كان «اضغط آجل قبل ما تسحب» — معرفة شفهية، ومربوطة بقرار
  /// مالي مالوش علاقة. والسؤال في لحظة الرفض هو أوضح مكان ممكن يتحط فيه:
  /// الكاشير شايف الصنف اللي اتوقف، وشايف الرصيد الحقيقي، وبياخد القرار وهو
  /// عارف نتيجته.
  ///
  /// السماح بيفضل مفتوح **لباقي الفاتورة** (`CartState.allowOversell`)، فمفيش
  /// سؤال متكرر على كل صنف في نفس البيعة. و`clearCart` بيصفّره.
  ///
  /// المحلات اللي البيع بالسالب عندها روتين بتفتح `enable_negative_sales` على
  /// مستوى التركيب — ساعتها الحارس ما بيوقفش أصلاً وما بيظهرش أي سؤال.
  Future<bool> _ensureOversellAllowed(ProductEntity product) async {
    final cart = ref.read(cartControllerProvider.notifier);
    final globalNegativeSales =
        ref.read(enableNegativeSalesProvider).value ?? false;

    if (!cart.isBlockedByStock(product,
        globalNegativeSales: globalNegativeSales)) {
      return true;
    }
    if (!mounted) return false;

    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(children: [
            Icon(PhosphorIconsBold.warningDiamond,
                color: AppColors.warning, size: 24),
            SizedBox(width: 8),
            Expanded(child: Text('الصنف غير متوفر')),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name, style: PicPosText.v(context, 15)),
              const SizedBox(height: 6),
              Text(
                'الرصيد الحالي: ${NumberUtils.formatQuantity(product.currentStock)}',
                style: PicPosText.v(context, 13, color: AppColors.error),
              ),
              const Divider(height: 18),
              Text(
                'تسمح بالبيع بالسالب في هذه الفاتورة؟ الرصيد هيبقى سالب '
                'ولازم جرد يصحّحه.',
                style: PicPosText.l(context, 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('لا', style: PicPosText.l(context, 14)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              child: const Text('نعم، اسمح بالسالب'),
            ),
          ],
        ),
      ),
    );

    if (approved != true) return false;
    cart.setAllowOversell(true);
    return true;
  }

  /// Blocking popup for a repeated live-scale weight. The single button just
  /// acknowledges — the cart keeps the item.
  Future<void> _showDuplicateWeightDialog(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          icon: const Icon(PhosphorIconsBold.warning,
              color: AppColors.warning, size: 44),
          title: const Text(
            'تنبيه: نفس الوزن',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
    _refocusScanner();
  }

  /// Barcode / internal-code entry. Delegates wholesale to the shared
  /// search controller, which owns scale-label parsing, unit barcodes, offer
  /// barcodes and the client-mode server fallback. Re-implementing any of
  /// that here would be a second, weaker copy of the hardest code in the POS.
  Future<void> _searchBarcode(String barcode) async {
    if (barcode.trim().isEmpty) return;

    // وضعُ المرتجع: نفسُ رفض `_handleProductTap` أعلاه — حقلُ الباركود
    // الرئيسيّ يضيف لسلّة بيعٍ، ومحرِّرُ أسطر المرتجع له حقلُ بحثٍ خاصٌّ به
    // يمرّ بـ`canAcceptProduct` (‏`_QuickReturnLinesEditorDialog`).
    if (blocksCartMutation(ref.read(posReturnModeProvider))) {
      showPosToast(
        context,
        ref,
        'أنت في وضع المرتجع — أنهِ الحفظَ أو الإلغاءَ قبل إضافة صنفٍ للبيع',
        type: PosNotificationType.warning,
      );
      barcodeController.clear();
      return;
    }

    // إجمالي الكميات قبل السحب — اقرا `_scanWasRefused` تحت.
    final qtyBefore = _totalCartQuantity();

    // §٤ `askqty` على مسار المسح — قرارُ المالك 2026-08-29.
    //
    // ⚠️ **الحقنُ عند كلّ مسحةٍ لا مرّةً في `initState`**: المتحكّمُ يعيش
    // أطولَ من الشاشة، فخطّافٌ محقونٌ مرّةً يبقى معلّقاً على شاشةٍ مفكّكةٍ
    // ويفتح حواراً على سياقٍ ميّت. والحقنُ هنا يجعل الخطّافَ دائماً ملكَ
    // الشاشة الحيّة، وكلفتُه إسنادُ دالّةٍ لا أكثر.
    final search = ref.read(picposSearchControllerProvider.notifier);
    search.askQuantity = _askLineQuantity;
    await search.searchBarcode(barcode);

    if (!mounted) return;
    final searchState = ref.read(picposSearchControllerProvider);
    final error = searchState.error;
    if (error != null) {
      if (shouldOfferQuickAdd(
          searchState.errorKind, ref.read(posReturnModeProvider))) {
        await _handleUnknownBarcode(barcode, error);
      } else {
        showPosToast(context, ref, error, type: PosNotificationType.error);
        ref.read(picposSearchControllerProvider.notifier).clearSearchResults();
      }
    } else if (_totalCartQuantity() == qtyBefore) {
      await _handleSilentlyRefusedScan(barcode);
    } else {
      // Successful add — select the last line so F6/F8 act on what was just
      // scanned, which is what the cashier expects.
      final items = ref.read(cartControllerProvider).items;
      if (items.isNotEmpty) setState(() => selectedIndex = items.length - 1);
    }

    barcodeController.clear();
    _refocusScanner();
  }

  /// باركودٌ غيرُ مسجَّلٍ — والسياسةُ تقرّر ما يحدث (§٤ `unknown`).
  ///
  /// ثلاثةُ مسالكَ في التصميم، وأثرُها ليس تجميليّاً:
  ///
  ///   • **صنفٌ سريع** — السلوكُ القائمُ قبل التوصيل، وهو الافتراض.
  ///   • **بحثٌ بالاسم** — يُسقط الباركودَ في حقل بحث الشبكة
  ///     (`PosProductSelectionPanel`) فيرشّح الكاشيرُ بصرياً. مفيدٌ حين
  ///     يكون الباركودُ ممسوحاً أو الملصقُ من مورّدٍ آخر.
  ///   • **تحذيرٌ ورفض** — لا صنفَ يُخلَق. وهذا هو البابُ الذي يُغلَق:
  ///     الإضافةُ السريعةُ تخلق صنفاً بسعرٍ يكتبه الكاشيرُ بلا كارتٍ ولا
  ///     تكلفة، فيدخل المخزونَ برصيدٍ ومتوسّطِ تكلفةٍ مخترعَين.
  ///
  /// ⚠️ ونغمةُ الخطأ مضروبةٌ سلفاً: `searchBarcode` تعزفها حين تضع
  /// `error`، فلا تُعاد هنا في مسار الرفض.
  Future<void> _handleUnknownBarcode(String barcode, String error) async {
    final policy = await ref.read(quickSalePolicyProvider.future);
    if (!mounted) return;
    final action = quickSaleUnknownBarcodeAction(policy);

    switch (action) {
      case QuickSaleUnknownBarcodeAction.quickAdd:
        await _offerQuickAdd(barcode);

      case QuickSaleUnknownBarcodeAction.nameSearch:
        // حقلُ بحث الشبكة يزامن نفسَه من `posControllerProvider`، فالكتابةُ
        // في الحالة تصل النصَّ المعروضَ فوراً (`pos_product_search_field`).
        ref.read(posControllerProvider.notifier).setSearchQuery(barcode);
        ref.read(picposSearchControllerProvider.notifier).clearSearchResults();
        if (mounted) {
          showPosToast(
            context,
            ref,
            'باركود غير مسجَّل — ابحث بالاسم في الشبكة',
            type: PosNotificationType.info,
          );
        }

      case QuickSaleUnknownBarcodeAction.reject:
        ref.read(picposSearchControllerProvider.notifier).clearSearchResults();
        if (mounted) {
          showPosToast(context, ref, error, type: PosNotificationType.error);
        }
    }
  }

  /// باركودٌ غيرُ مسجَّل (`shouldOfferQuickAdd` تأكّدت: `errorKind ==
  /// notFound` وليس وضعَ مرتجع). يعرض تأكيداً، يشترط صلاحيةَ `products_add`
  /// — نفسُ شرط `pos_main_operations.dart:423-429` — ثم يفتح
  /// `QuickAddProductDialog` ويُعيد مسحَ **نفس** الباركود بدل الإضافة
  /// بالمعرِّف مباشرة: تماماً كما يفعل المسارُ القديم
  /// (`pos_main_operations.dart:442-446`)، فالمتحكّمُ المشترك هو اللي يضيف
  /// الصنفَ المُنشأ حديثاً بمساره الطبيعيّ (وحداتٌ، وزنٌ، تكديسٌ…).
  ///
  /// كلُّ خروجٍ مبكر (رفضُ التأكيد، رفضُ الصلاحية، إلغاءُ الديالوج) يمسح
  /// حالةَ الخطأ المعلَّقة بنفس ما تفعله فرعُ الخطأ العامّ في `_searchBarcode`
  /// فوق — بدل ما تبقى رسالةُ «غير مسجَّل» عالقةً بلا داعٍ.
  Future<void> _offerQuickAdd(String barcode) async {
    final shouldAdd = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.warningCircle,
                  color: AppColors.warning, size: 28),
              SizedBox(width: 8),
              Expanded(child: Text('صنف غير معرف')),
            ],
          ),
          content: Text(
            'الباركود "$barcode" غير مسجل في النظام.\n'
            'هل تريد إضافته كصنف جديد؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لا'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success),
              child: const Text('نعم — إضافة سريعة'),
            ),
          ],
        ),
      ),
    );

    if (shouldAdd != true) {
      if (mounted) {
        ref.read(picposSearchControllerProvider.notifier).clearSearchResults();
      }
      return;
    }
    if (!mounted) return;

    if (!await ensurePermission(
        ref, context, PermissionCodes.productsAdd,
        actionName: 'إضافة صنف جديد')) {
      if (mounted) {
        ref.read(picposSearchControllerProvider.notifier).clearSearchResults();
      }
      return;
    }
    if (!mounted) return;

    final newProductId = await QuickAddProductDialog.show(context, barcode);
    if (!mounted) return;
    if (newProductId == null) {
      ref.read(picposSearchControllerProvider.notifier).clearSearchResults();
      return;
    }

    await ref
        .read(picposSearchControllerProvider.notifier)
        .searchBarcode(barcode);
    if (!mounted) return;
    final items = ref.read(cartControllerProvider).items;
    if (items.isNotEmpty) setState(() => selectedIndex = items.length - 1);
  }

  double _totalCartQuantity() => ref
      .read(cartControllerProvider)
      .items
      .fold<double>(0, (sum, i) => sum + i.quantity);

  /// مسحة رجعت «نجاح» ومغيّرتش السلة.
  ///
  /// ── إزاي عرفنا ───────────────────────────────────────────────────────────
  /// متحكّم البحث المشترك بينادي `addItem` ثم يزمّر نجاح **بلا ما يتأكد** إن
  /// الإضافة نزلت (٦ مواضع نداء فيه، كلها بنفس الشكل). فصنف مخزونه صفر بيتمسح،
  /// الزمّور يقول تم، والسلة زي ما هي. باج قائم مشترك مع UralCash، بس بقى باين
  /// أكتر هنا بعد ما مسار الضغط على الكارت بقى بيسأل.
  ///
  /// المقارنة بإجمالي **الكميات** مش عدد السطور: الدمج في سطر موجود («منع
  /// تراكم الأصناف» مقفول) بيزوّد كمية وما بيزوّدش سطر.
  ///
  /// ── وليه لازم نتحقّق قبل ما نتكلّم ────────────────────────────────────────
  /// «السلة ما اتغيرتش» **مش** معناها رفض مخزون بالضرورة: `applyOffer` بترجع
  /// بلا إضافة لو العرض مضاف قبل كده أو لو ما طلّعش أصناف. فتوست «الصنف غير
  /// متوفر» على مسح باركود عرض مرتين كان هيبقى كذب. فبندوّر على الصنف بنفسنا
  /// ونتأكد إنه **فعلاً** متوقّف بالمخزون قبل أي كلام.
  ///
  /// ولو الكاشير سمح، بنعيد نداء `searchBarcode` بنفس الباركود بدل ما نضيف
  /// إحنا: المتحكّم ده بيفهم باركود الميزان وباركود الوحدات والعروض، وإعادة
  /// النداء بتستفيد من ده كله. مرة واحدة بس — مفيش لوب.
  Future<void> _handleSilentlyRefusedScan(String barcode) async {
    final blocked = await _blockedProductForBarcode(barcode);
    // مش رفض مخزون (عرض مكرّر، باركود مالوش صنف، …) — المتحكّم اتعامل معاه.
    if (blocked == null || !mounted) return;

    if (!await _ensureOversellAllowed(blocked)) return;
    if (!mounted) return;

    await ref.read(picposSearchControllerProvider.notifier).searchBarcode(barcode);
    if (!mounted) return;
    final items = ref.read(cartControllerProvider).items;
    if (items.isNotEmpty) setState(() => selectedIndex = items.length - 1);
  }

  /// يرجّع الصنف اللي الباركود ده بيشاور عليه **لو** حارس المخزون بيوقفه، وإلا
  /// `null`.
  ///
  /// ── باركود الميزان ───────────────────────────────────────────────────────
  /// باركود الميزان (EAN-13 بيبدأ بـ `2` وجواه الـ PLU والوزن مدسوسين) **عمره
  /// ما بيتطابق خام** مع باركود صنف أو كوده — الرقم اللي على الملصق بيتغيّر مع
  /// كل وزنة. فبنفكّه الأول بـ [ScaleBarcodeHandler.tryParse]، وهو **نفس**
  /// المُفكِّك اللي متحكّم البحث المشترك بيستعمله: بيقرأ بروفايل الميزان من
  /// الإعدادات، ويجرّب الـ PLU بالكود وبالباركود وبـ `getProductByScalePlu`.
  /// إعادة استخدامه معناها إن الصنف اللي بنسأل عنه هو **بالظبط** الصنف اللي
  /// المتحكّم حاول يضيفه ورفضه — نسخة تانية من التفكيك كانت هتفتح باب إننا
  /// نسأل عن صنف والرفض حصل لصنف تاني.
  ///
  /// `tryParse` قراءة بحتة (بيرجّع نتيجة، والإضافة شغل المستدعي) فنداؤه هنا على
  /// مسار الفشل مالوش أي أثر جانبي.
  ///
  /// ولو مش باركود ميزان بيرجع `null` بسرعة، وساعتها بندوّر بالباركود ثم بالكود
  /// — نفس أول خطوتين في المتحكّم.
  Future<ProductEntity?> _blockedProductForBarcode(String barcode) async {
    try {
      final code = barcode.trim();
      ProductEntity? product;

      final scaleResult = await ScaleBarcodeHandler.tryParse(
        RepositoryBarcodeAdapter(ref),
        code,
      );
      product = scaleResult?.product;
      product ??= await ref.read(productRepositoryProvider)
          .getProductByBarcode(code);
      product ??=
          await ref.read(productRepositoryProvider).getProductByCode(code);
      if (product == null) return null;

      final globalNegativeSales =
          ref.read(enableNegativeSalesProvider).value ?? false;
      final blocked = ref.read(cartControllerProvider).blocksAdd(
            product,
            globalNegativeSales: globalNegativeSales,
          );
      return blocked ? product : null;
    } catch (e) {
      debugPrint('[PicPos-Scan] تعذّر التحقّق من سبب الرفض: $e');
      return null;
    }
  }

  // ── Line operations (F6 / F8) ──────────────────────────────────────────

  /// يطلب موافقةَ مسؤولٍ حين ينقص المستخدمَ الكودُ — ويرجع `false` لو رُفض.
  ///
  /// اختيارُ المالك (2026-08-12): **حوارُ كلمة المرور على كلّ رفض**، لا على
  /// المالية الحرجة وحدَها. فالفعلُ الممنوع يمرّ بموافقة مسؤولٍ حاضرٍ يملك
  /// الصلاحيةَ بنفسه — و`requestManagerApproval` يشترط ذلك ولا يكتفي بأنه
  /// مدير. والموافقةُ وحيدةُ الاستعمال ولا تُصعّد الجلسة.
  Future<bool> _ensureCartPermission(
    bool Function(List<String>) can,
    String permission,
    String actionName,
  ) async {
  // ⚠️ **المشروطُ يُفحَص قبل المِلك، والترتيبُ هو الميزةُ كلُّها.**
  //    الصلاحيةُ المشروطةُ **ممنوحةٌ** فعلاً — صفُّها في `role_permissions`
  //    — فلو فُحص المِلكُ أوّلاً لعاد `true` ولما سُئل مسؤولٌ أبداً، وصار
  //    «مشروط» مِزلاجاً لا يفعل شيئاً. وهو ما كان واقعاً على شاشة الكاشير:
  //    `ensurePermission` تحترمه و`_ensure` هنا لا تحترمه، فستّةَ عشرَ
  //    كوداً على أخطرِ شاشةٍ كانت تمرّ بلا حوار.
  //    (‏بلاغُ المراجعة الأمنيّة 2026-08-30 · النمطُ من `permission_guard`)
    final perms = ref.read(currentUserPermissionsProvider).asData?.value ??
        const <String>[];
    if (!PermissionCodes.isConditionalIn(perms, permission) && can(perms)) {
      return true;
    }
    if (!mounted) return false;
    return requestManagerApproval(
      context,
      actionName: actionName,
      permission: permission,
    );
  }

  Future<void> _removeAt(int index) async {
    final items = ref.read(cartControllerProvider).items;
    if (index < 0 || index >= items.length) return;
    if (!await _ensureCartPermission(
      canRemoveCartItem,
      PermissionCodes.posRemoveItem,
      'حذف صنف من السلة',
    )) {
      return;
    }
    if (!mounted) return;

    // «حذف سطر يتطلب مصادقة» — §٤.
    //
    // ⚠️ **طبقةٌ فوق الصلاحية لا بديلٌ عنها.** `pos_remove_item` تقول «من
    // يملك الحذف»، وهذا الإعدادُ يقول «حتّى المالكُ للصلاحية يُصادَق عليه
    // في كلِّ مرّة» — وهو ما يترك أثراً باسم من صادق. فالفحصان متتاليان
    // لا متبادلان.
    final policy = await ref.read(quickSalePolicyProvider.future);
    if (!mounted) return;
    final delAuthRow =
        kQuickSaleRows.firstWhere((r) => r.id == 'delauth');
    if (policy.isOn(delAuthRow)) {
      final approved = await requestManagerApproval(
        context,
        actionName: 'حذف سطر من الفاتورة',
        permission: PermissionCodes.posRemoveItem,
      );
      if (!approved) return;
      if (!mounted) return;
    }

    ref.read(cartControllerProvider.notifier).removeFromCart(index);
    final remaining = ref.read(cartControllerProvider).items.length;
    setState(() {
      selectedIndex = remaining == 0
          ? null
          : (index >= remaining ? remaining - 1 : index);
    });
    _refocusScanner();
  }

  void _deleteSelected() {
    final idx = selectedIndex;
    if (idx == null) {
      showPosToast(context, ref, 'اختر صنفاً أولاً',
          type: PosNotificationType.info);
      return;
    }
    _removeAt(idx);
  }

  Future<void> _editSelected() async {
    final idx = selectedIndex;
    final items = ref.read(cartControllerProvider).items;
    if (idx == null || idx >= items.length) {
      showPosToast(context, ref, 'اختر صنفاً أولاً',
          type: PosNotificationType.info);
      return;
    }
    await _showLineEditDialog(idx, items[idx]);
    _refocusScanner();
  }

  /// Line editor for F6.
  ///
  /// Deliberately NOT the shared `EditCartItemDialog` — that one takes a drift
  /// `Product` plus its `ProductUnit` list and needs two repository round-trips
  /// to open. Everything editable on a lite till (quantity, price, line
  /// discount) is already on the `CartItemEntity`, so this opens instantly and
  /// touches no repository.
  Future<void> _showLineEditDialog(int index, CartItemEntity item) async {
    final qtyCtl =
        TextEditingController(text: NumberUtils.formatQuantity(item.quantity));
    final priceCtl =
        TextEditingController(text: item.effectivePrice.toString());
    final discCtl =
        TextEditingController(text: item.discountPercent.toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(item.productName,
              style: const TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyCtl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'الكمية', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'السعر', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: discCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'الخصم %', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      final cart = ref.read(cartControllerProvider.notifier);
      final qty = double.tryParse(qtyCtl.text.trim());
      final price = double.tryParse(priceCtl.text.trim());
      final disc = double.tryParse(discCtl.text.trim());
      // كلٌّ على حدة: الحوارُ يعدّل الثلاثةَ معاً، فمن يملك تعديلَ الكمية
      // ولا يملك تعديلَ السعر يجب أن يمرّ الأولُ ويُستأذَن في الثاني — لا
      // أن يسقط الاثنان ولا أن يمرّا معاً.
      final current = ref.read(cartControllerProvider).items[index];
      if (qty != null && qty > 0 && qty != current.quantity) {
        // «أقصى كمية في السطر الواحد» — §٤: حاجزُ أمانٍ ضدّ الأخطاء
        // المطبعيّة في لوحة الأرقام (‏«١٠٠» تصير «١٠٠٠» بضغطةٍ زائدة).
        //
        // ⚠️ **يُفحَص قبل الصلاحية عمداً**: الرقمُ الخاطئُ خطأٌ لا تصرّفٌ
        // يُستأذَن فيه، فإظهارُ حوارِ مصادقةٍ ثمّ رفضُ الرقم يُتعب المستخدمَ
        // مرّتين.
        final policy = await ref.read(quickSalePolicyProvider.future);
        if (!mounted) return;
        final maxQty = quickSaleMaxLineQty(policy);
        if (maxQty != null && qty > maxQty) {
          showPosToast(
            context,
            ref,
            'الكميةُ تتجاوز الحدَّ المسموح (${maxQty.toStringAsFixed(0)})',
            type: PosNotificationType.error,
          );
          return;
        }

        if (await _ensureCartPermission(
          canEditCartQuantity,
          PermissionCodes.posQuantityEdit,
          'تعديل الكمية',
        )) {
          cart.updateQuantity(index, qty);
        }
      }
      if (price != null && price >= 0 && price != current.effectivePrice) {
        // §٤ `priceedit` — «ممنوع» قبل أيّ حوارِ مصادقة.
        if (await priceEditBlockedByPolicy(ref)) {
          if (mounted) {
            showPosToast(context, ref, kPriceEditBlockedMessage,
                type: PosNotificationType.error);
          }
        } else if (await _ensureCartPermission(
          canEditCartPrice,
          PermissionCodes.posPriceEdit,
          'تعديل سعر الصنف',
        )) {
          cart.updatePrice(index, price);
        }
      }
      if (disc != null &&
          disc >= 0 &&
          disc <= 100 &&
          disc != current.discountPercent) {
        // البابُ الثاني للخصم — الأولُ خليةُ «الخصم ٪» في الجدول. وكان هذا
        // الفرعُ **بلا فحص** بينما جاراه فوقه محروسان، فمن رُفع عنه الخصمُ
        // كان يطبّقه من هنا. (مقيسٌ 2026-08-13)
        // §٤ `disccap` — والسقفُ قبل الصلاحية (‏حوارٌ واحدٌ لا اثنان).
        final verdict = await ensureDiscountWithinPolicy(
            ref, context, disc,
            scope: 'line_edit_discount');
        if (verdict != DiscountPolicyOutcome.allowed) {
          final msg = discountPolicyMessage(verdict);
          if (msg != null && mounted) {
            showPosToast(context, ref, msg, type: PosNotificationType.error);
          }
          return;
        }
        if (!mounted) return;
        if (await ensureCartDiscountPermission(ref, context,
            scope: 'line_edit_discount')) {
          cart.setItemDiscount(index, disc);
        }
      }
    }

    qtyCtl.dispose();
    priceCtl.dispose();
    discCtl.dispose();
  }

  // ── Invoice-level discount ─────────────────────────────────────────────

  Future<void> _editInvoiceDiscount() async {
    // «الخصم المعتمد» في بلاغ المالك — البابُ الثالث لـ`pos_discount`، وكان
    // مفتوحاً كالبابَين الآخرَين. والاستئذانُ **قبل** فتح الحوار لا بعده:
    // لا يُطلب من الكاشير أن يكتب نسبةً ثم يُرفض.
    if (!await ensureCartDiscountPermission(ref, context,
        scope: 'invoice_discount')) {
      return;
    }
    if (!mounted) return;
    final current = ref.read(cartControllerProvider).discountPercent;
    final controller =
        TextEditingController(text: current == 0 ? '' : current.toString());
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('خصم الفاتورة'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'نسبة الخصم %',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) =>
                Navigator.pop(ctx, double.tryParse(v.trim()) ?? current),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                  ctx, double.tryParse(controller.text.trim()) ?? current),
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null && result >= 0 && result <= 100) {
      // §٤ `disccap` على خصم الفاتورة كلِّها.
      //
      // ⚠️ **هنا الفحصُ بعد الحوار لا قبله**، خلافاً للبابين الآخرين: القيمةُ
      // لا تُعرف إلّا بعد أن يكتبها الكاشير. وفحصُ الصلاحية يبقى قبل الحوار
      // كما كان (‏لا يُطلب منه أن يكتب نسبةً ثمّ يُرفض لأنه لا يملك الخصمَ
      // أصلاً)، فمن لا يملك الصلاحيةَ **ويتجاوز السقفَ** يرى حوارَين —
      // وهما قراران مختلفان فعلاً: «أتخصم أصلاً؟» ثمّ «أتتجاوز الحدَّ؟».
      final verdict = await ensureDiscountWithinPolicy(
          ref, context, result,
          scope: 'invoice_discount');
      if (verdict != DiscountPolicyOutcome.allowed) {
        final msg = discountPolicyMessage(verdict);
        if (msg != null && mounted) {
          showPosToast(context, ref, msg, type: PosNotificationType.error);
        }
        _refocusScanner();
        return;
      }
      if (!mounted) return;
      ref.read(cartControllerProvider.notifier).setDiscount(result);
    }
    _refocusScanner();
  }

  // ── مسار الدفع الموحَّد (F4 دفع · F2 حفظ) ───────────────────────────────

  /// `دفع F4` — حفظ + طباعة + فتح الدرج (طلب ١).
  Future<void> _handleCheckout() => _processPaymentAndSave(printAfter: true);

  /// `حفظ F2` — حفظ فقط: بلا طباعة وبلا درج.
  Future<void> _saveOnly() => _processPaymentAndSave(printAfter: false);

  /// المسار الوحيد اللي أي فاتورة بيع بتخرج منه من شاشة PicPos.
  ///
  /// ── ليه مسار واحد بدل مسارين ──────────────────────────────────────────
  /// كان فيه `_handleCheckout` (بديالوج دفع) و `_saveInvoice` (بلا ديالوج،
  /// بترحّل بـ `cartState.paymentMethod` مباشرة). التقسيم ده كان سليم وقت ما
  /// كان صف طرق الدفع موجود في اللوحة، لأن الكاشير كان بيختار الطريقة هناك
  /// قبل ما يضغط حفظ.
  ///
  /// بعد ما الصف اتشال (طلب ٢) بقت `cart.paymentMethod` هي الافتراضي `'cash'`
  /// لكل فاتورة غير منصات — فـ«حفظ» كانت هترحّل **كل** المبيعات نقدي، بما فيها
  /// بيعة بطاقة، بلا أي إشارة للكاشير. فالمسارين اتوحّدوا: الاتنين بيمرّوا
  /// بالديالوج، والفرق الوحيد بينهم بقى [printAfter].
  ///
  /// ── الفروق المقصودة عن `pos_main_operations._processPaymentAndSave` ────
  /// • هنا فيه تحقّق فترة مالية قبل الدفع — UralCash مالهاش.
  /// • هنا فيه توست تسوية التقريب — UralCash مالهاش.
  /// • مفيش `printKitchenOrders` — مفيش موديول مطبخ في lite.
  /// • `حفظ` هنا **ما بيفتحش الدرج**؛ في UralCash بيفتحه. الزرين لازم يفرقوا،
  ///   ودرج بيفتح بلا فلوس بيدرّب الكاشير إنه يتجاهل الركلة.
  Future<void> _processPaymentAndSave({required bool printAfter}) async {
    // وضعُ المرتجع (المهمّة ٧): يأخذ المسارَ **كلَّه** — لا فحصَ سلّةٍ فارغة
    // (فاتورةُ المرتجع ليست سلّةَ بيع)، ولا فترةً ماليّةً هنا (`processSalesReturn`
    // يتحقّق منها بنفسه)، ولا طباعةً ولا درجاً؛ `printAfter` بلا أثرٍ في هذا
    // الفرع عمداً — طباعةُ إيصال مرتجعٍ لها مسارُها الخاصُّ في شاشة
    // «مرتجعات المبيعات»، وليست جزءاً من هذه المهمّة.
    // الاستبدالُ **قبل** المرتجع: الوضعان حصريّان بالبناء (كلٌّ يعطّل زرَّ
    // الآخر)، والترتيبُ هنا حارسٌ إضافيٌّ لا شرطٌ — لو تسرّبت حالةٌ تحمل
    // الاثنين، فالاستبدالُ هو الأشملُ ويحفظ الشقَّين معاً.
    final exchangeMode = ref.read(posExchangeModeProvider);
    if (exchangeMode != null) {
      await _processExchangeSave(exchangeMode);
      return;
    }

    final returnMode = ref.read(posReturnModeProvider);
    if (returnMode != null) {
      await _processQuickReturnSave(returnMode);
      return;
    }

    final cartState = ref.read(cartControllerProvider);
    if (cartState.items.isEmpty) {
      showPosToast(context, ref, 'الفاتورة فارغة',
          type: PosNotificationType.info);
      return;
    }
    if (!await _validateCartBeforeCheckout(cartState)) return;

    // «إلزام اختيار عميل قبل الدفع» — §٤.
    //
    // ⚠️ **لا يمسُّ الآجل**: البيعُ الآجلُ يطلب عميلاً دائماً بحكم كونه ديناً
    // على أحد، ويحرسه مسارُه الخاصُّ بغضّ النظر عن هذا الإعداد. وهذا الإعدادُ
    // يخصُّ البيعَ النقديَّ وحدَه — متجرٌ يريد سجلَّ عملاءَ كاملاً.
    final policy = await ref.read(quickSalePolicyProvider.future);
    if (!mounted) return;
    final requireCustomer =
        policy.isOn(kQuickSaleRows.firstWhere((r) => r.id == 'reqcust'));
    if (requireCustomer && cartState.selectedCustomerId == null) {
      showPosToast(
        context,
        ref,
        'اختر عميلاً قبل الدفع — الإعداد يُلزم بذلك',
        type: PosNotificationType.error,
      );
      return;
    }

    // Selling into a closed fiscal year would post a journal entry into a
    // locked period. Fail before taking the customer's money, not after.
    try {
      await ref.read(fiscalPeriodValidationProvider(
        (date: DateTime.now(), operation: 'بيع'),
      ).future);
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(children: [
              Icon(Icons.lock_clock, color: AppColors.error, size: 26),
              SizedBox(width: 8),
              Text('السنة المالية مغلقة'),
            ]),
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('موافق'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    // بوابة `pos_save` — منقولة من UralCash. الفورك ده كان **بلا أي إنفاذ**
    // لصلاحية الحفظ: سحب الصلاحية من الكاشير ما كانش بيمنعه من إتمام بيعة.
    if (!await _userHasPermissionFresh(PermissionCodes.posSave)) {
      if (!mounted) return;
      final approved = await requestManagerApproval(
        context,
        actionName: 'حفظ فاتورة البيع السريع',
        permission: PermissionCodes.posSave,
      );
      if (!approved) return;
    }
    if (!mounted) return;

    final total = cartState.total;

    // §٤ `mgrlimit` — حاجزُ أمانٍ على الفواتير الكبيرة.
    //
    // ⚠️ **قبل أيّ حوارِ دفعٍ وقبل الترحيل**: الغرضُ أن يراها مسؤولٌ قبل أن
    // تصير قيداً، لا أن تُصادَق بعد أن دخلت الدفاتر. و`null` من المترجِم
    // تعني «بلا حد» لا صفراً — والخلطُ بينهما كان سيطلب موافقةً لكلّ فاتورة.
    final limitPolicy = await ref.read(quickSalePolicyProvider.future);
    if (!mounted) return;
    final confirmAbove = quickSaleManagerConfirmAbove(limitPolicy);
    if (confirmAbove != null && total > confirmAbove) {
      final okBig = await requestManagerApproval(
        context,
        actionName:
            'فاتورة ${total.toStringAsFixed(2)} — فوق حدّ ${confirmAbove.toStringAsFixed(0)}',
        // ⚠️ **لا `posDiscount` هنا.** استعمالُه كان يفتح عطبَين معاً:
        // كاشيرٌ يملك الخصمَ يصير مؤهَّلاً للمصادقة على فاتورةٍ كبيرة،
        // **والإذنُ الممنوحُ يدخل `ManagerApprovalCache` تحت `pos_discount`**
        // فيستهلكه فحصُ خصمٍ لاحقٌ في نفس الدقيقة بلا سؤال. والافتراضُ
        // `approve_high_value_return` مخصَّصٌ لهذا المعنى بالضبط.
      );
      if (!okBig) {
        if (mounted) {
          showPosToast(context, ref, 'أُلغيت البيعة — لم يُصادَق على المبلغ',
              type: PosNotificationType.warning);
        }
        _refocusScanner();
        return;
      }
      if (!mounted) return;
    }

    // شركات التوصيل بتتحاسب آجل. القيد ده كان عايش كـ `creditOnly` في صف طرق
    // الدفع في اللوحة؛ الصف اتشال، فالقيد نزل هنا — على مسار الكتابة، فما
    // يقدرش يتفوّت.
    final isPlatform =
        ['talabat', 'careem', 'ashyae'].contains(cartState.priceLevel);
    final isCredit = cartState.paymentMethod == 'credit';

    // ── ليه متغيّرات مفكوكة ومش كائن `PaymentResult` ──────────────────────
    // الشاشة بتستورد `pos_dialogs.dart` بـ `hide PaymentResult`، فالنوع نفسه
    // مش قابل للتسمية هنا. ومسار المنصات مالوش داعي يبني كائن من الأساس —
    // قيمه كلها معروفة مقدماً. فالمتغيّرات المفكوكة بتحل الاتنين.
    final String method;
    final double paidTotal;
    final double? cashAmount;
    final double? bankAmount;
    final double? clickAmount;
    final int? resultCustomerId;

    if (isPlatform && isCredit) {
      method = 'credit';
      paidTotal = total;
      cashAmount = 0;
      bankAmount = 0;
      clickAmount = 0;
      resultCustomerId = cartState.selectedCustomerId;
    } else {
      final allowed = await _allowedPaymentMethods(isPlatform: isPlatform);

      // ── المسارُ السريع: طريقةٌ واحدةٌ مؤشَّرة ⇒ بلا حوار ────────────────
      // طلبُ المالك 2026-08-14: «بطريقةٍ أسهل وأسرع». وأسرعُها ألّا يُسأل
      // الكاشيرُ حين لا بديلَ أمامه. والقيمُ هنا **ليست اختصاراً**: الحوارُ
      // نفسُه يرجع `total` كاملاً و`cash/bank/click = null` لكلّ طريقةٍ عدا
      // `multiple` و`credit` (مقيسٌ في `pos_payment_dialogs.dart:390-410`)،
      // وهما وحدَهما مستثنيان في `singlePaymentMethodFastPath`.
      //
      // وما يُفقَد هو اختيارُ عميلٍ **من داخل** الحوار — وله بابُه في السلّة
      // (`_pickCustomer`)، ومنه تأتي `cartState.selectedCustomerId`.
      // §٤ `skipdlg`: المسارُ السريعُ كان **دائمَ التشغيل**، وصار مشروطاً.
      // والافتراضُ مضاءٌ في التصميم، و`null` (‏السياسةُ لم تُقرأ بعد) تعني
      // السلوكَ القائم — فلا تتغيّر بيعةٌ واحدةٌ حتّى يُطفئه المديرُ عمداً.
      final policy = await ref.read(quickSalePolicyProvider.future);
      if (!mounted) return;
      final skipDialog =
          policy.isOn(kQuickSaleRows.firstWhere((r) => r.id == 'skipdlg'));
      final fastPath =
          skipDialog ? singlePaymentMethodFastPath(allowed) : null;
      if (fastPath != null) {
        method = fastPath;
        paidTotal = total;
        cashAmount = null;
        bankAmount = null;
        clickAmount = null;
        resultCustomerId = cartState.selectedCustomerId;
      } else {
        final result = await PosDialogs.showPaymentDialog(
          context,
          totalAmount: total,
          // §٤ `defmethod`. ومنصّاتُ التوصيل تبقى `credit` قسراً: قيدُ
          // عملٍ لا تفضيلُ عرضٍ، وسياسةُ الشاشة لا تنقضه.
          initialMethod: isPlatform
              ? 'credit'
              : quickSaleDefaultPaymentMethod(policy),
          allowedMethods: allowed,
        );
        if (result == null || !mounted) {
          _refocusScanner();
          return;
        }
        method = result.method;
        paidTotal = result.total;
        cashAmount = result.cashAmount;
        bankAmount = result.bankAmount;
        clickAmount = result.clickAmount;
        resultCustomerId = result.customerId;
      }
    }

    // لازم تتكتب على السلة: شاشة العميل (CFD) وشيب الصندوق وفحص «غير متوفر
    // على الآجل» كلهم بيقروا من `cart.paymentMethod`. الفورك ده كان ناسيها،
    // فالسلة والفاتورة المرحّلة كانوا بيختلفوا.
    ref.read(cartControllerProvider.notifier).setPaymentMethod(method);

    // عرض الفكة للعميل (طلب ٢). الصندوق الأخضر «الباقي للعميل (فكة)» جوه
    // ديالوج الدفع متعشّش في فرع `multiple` بس، فمسار النقدي مالوش أي عرض
    // للفكة. نفس حل UralCash: ديالوج تحصيل النقدية بخانة المستلم وأزرار الفئات.
    if (method == 'cash') {
      // §٤ `quickamt` — يُمرَّر من هنا لا يُقرَأ داخلَ الحوار: الحوارُ
      // مشترَكٌ مع UralCash، فالسياسةُ تُحقَن عند نداء PicPos وحدَه.
      //
      // وقراءةٌ مستقلّةٌ عن قراءة `skipdlg` فوق عمداً: تلك تعيش في فرع
      // «ليست منصّةً آجلة» وحدَه، وهذا المسارُ يصله النقديُّ من الفرعين.
      final cashPolicy = await ref.read(quickSalePolicyProvider.future);
      if (!mounted) return;
      final confirmed = await PosCashTenderingDialog.show(
        context,
        totalAmount: total,
        showQuickAmounts: cashPolicy.isOn(
          kQuickSaleRows.firstWhere((r) => r.id == 'quickamt'),
        ),
      );
      if (confirmed != true || !mounted) {
        _refocusScanner();
        return;
      }
    }

    final bankSafeId = await _ensureBankSafeSelected(
      method,
      bankAmount: bankAmount,
      clickAmount: clickAmount,
    );
    if (!mounted) return;

    // ح‑١ (مواصفة 2026-08-18): بيعةٌ نقديّةٌ بلا ورديّةٍ على الدرج تُرفَض،
    // فنعرض فتحَها ونعيد المحاولةَ مرّةً — لا رسالةٌ حمراءُ لا مخرجَ منها.
    // ويُصيب هذا مديرَ النظام تحديداً: `_ensureShiftOpen` يتخطّاه عمداً
    // (Spec 135 NOTE 2) فيصل إلى هنا بلا ورديّة.
    bool success = false;
    final outcome = await runWithOpenShiftPrompt(
      context: context,
      ref: ref,
      subtitleBuilder: (amount) =>
          'البيعة تُدخل ${amount.toStringAsFixed(2)} نقداً إلى الدرج.',
      attempt: () async => success = await ref
          .read(checkoutControllerProvider.notifier)
          .processPayment(
            method: method,
            total: paidTotal,
            cashAmount: cashAmount,
            bankAmount: bankAmount,
            clickAmount: clickAmount,
            bankSafeId: bankSafeId,
            customerId: resultCustomerId ?? cartState.selectedCustomerId,
          ),
    );

    if (!mounted) return;
    if (outcome != ShiftPromptOutcome.completed) {
      showPosToast(
        context,
        ref,
        outcome == ShiftPromptOutcome.cancelledByUser
            ? 'أُلغيت البيعة — لم تُفتَح وردية'
            : 'تعذّر فتح الوردية، فلم تُحفَظ الفاتورة',
        type: PosNotificationType.error,
      );
      return;
    }
    if (!success) {
      final err =
          ref.read(checkoutControllerProvider).error ?? 'فشل حفظ الفاتورة';
      showPosToast(context, ref, err, type: PosNotificationType.error);
      _refocusScanner();
      return;
    }

    setState(() => selectedIndex = null);
    // Surface the auto-balance rounding adjustment, same as the UralCash
    // screen — a silent sub-piaster fix is still a fix the operator should
    // be able to see when reconciling.
    final adj = JournalEntryDiagnostics.lastRoundingAdjustment;
    if (adj.abs() > 0.001) {
      showPosToast(
        context,
        ref,
        'تمت تسوية فروقات تقريب ${adj.abs().toStringAsFixed(3)}',
        type: PosNotificationType.info,
      );
    }
    SystemSound.play(SystemSoundType.click);
    barcodeController.clear();

    final printPolicy = await ref.read(quickSalePolicyProvider.future);
    if (!mounted) return;

    // §٤ `autoprint` — قرارُ المالك 2026-08-30: «F4 يوقف الطباعة».
    //
    // كان `printAfter` يُحسَم بالزرِّ وحدَه (`دفع` ⇒ `true` ثابتاً)، ولا
    // يُستشار `auto_print_receipt` إطلاقاً — فالصفُّ موسومٌ «منفَّذ» وهو
    // لا يمنع طباعةَ فاتورةٍ واحدة. وقارئاه الوحيدان في المستودع كانا
    // سندَ مصروفاتٍ وشاشةَ العتاد، أي موديولاً آخر.
    // (‏بلاغُ اختبارات الوظائف 2026-08-30 · D2)
    //
    // ⚠️ والإطفاءُ يمنع **الطباعةَ وحدَها**: الحفظُ والترحيلُ وحركةُ
    // الخزنة تقع كما هي. و`_saveOnly` (F2) يبقى بلا طباعةٍ كما كان.
    final autoPrint = printPolicy
        .isOn(kQuickSaleRows.firstWhere((r) => r.id == 'autoprint'));

    if (printAfter && autoPrint) {
      // الدرج بيتركل **بالتوازي** مع الطباعة مش بعدها: الركلة بتروح للطابعة
      // على نفس المنفذ، وتسلسلهم كان بيضيف زمن ميت على مسار حرج.
      //
      // §٤ `drawer` — ويضيّق التوصيلُ سلوكاً كان أوسع: الدرجُ كان يُركَل
      // في **كلّ** بيعةٍ مطبوعة، والتصميمُ يقول «يفتح في الدفع النقدي
      // فقط». وهو الصواب: بيعةُ بطاقةٍ لا نقدَ فيها تُدخِله، ففتحُ الدرج
      // يعرّض النقدَ بلا سبب. و`null` تُبقي السلوكَ القائم.
      final openDrawer = printPolicy
              .isOn(kQuickSaleRows.firstWhere((r) => r.id == 'drawer')) &&
          method == 'cash';
      final drawerFuture =
          openDrawer ? _openCashDrawerQuietly() : Future<void>.value();

      final invoiceId = ref.read(checkoutControllerProvider).lastInvoiceId;

      // §٤ `copies`. والتوقّفُ عند أوّلِ إخفاقٍ مقصود: سببُ الإخفاق ورقٌ
      // ناقصٌ أو طابعةٌ صامتة، وكلاهما لا يُشفى بمحاولةٍ ثانيةٍ فوراً —
      // وتكرارُها يُغرق الكاشيرَ بثلاث رسائل تحذيرٍ عن عطبٍ واحد.
      final copies = quickSaleReceiptCopies(printPolicy);
      var printed = false;
      if (invoiceId != null && await _hasReceiptPrinter()) {
        for (var i = 0; i < copies; i++) {
          printed = await _tryPrintReceipt(invoiceId);
          if (!printed || !mounted) break;
        }
      }

      await drawerFuture;
      if (mounted) {
        showPosToast(
          context,
          ref,
          printed ? 'تم حفظ وطباعة الفاتورة' : 'تم حفظ الفاتورة',
          type: PosNotificationType.success,
        );
      }
    } else {
      showPosToast(context, ref, 'تم حفظ الفاتورة',
          type: PosNotificationType.success);
    }

    await _applyAfterInvoiceAction(printPolicy);
  }

  /// وجهةُ الشاشة بعد إغلاق الفاتورة — §٤ `after`.
  ///
  /// يُنادى على **مساري** الحفظ (‏بطباعةٍ وبدونها): نصُّ التصميم «وجهة
  /// الشاشة مباشرة بعد إغلاق الفاتورة»، والحفظُ بلا طباعةٍ إغلاقٌ أيضاً.
  ///
  /// و`null` — أي السياسةُ لم تُقرأ — تعني السلوكَ القائم: إعادةُ التركيز
  /// على الماسح وحدَها.
  Future<void> _applyAfterInvoiceAction(
    QuickSalePolicyValues policy,
  ) async {
    final action = quickSaleAfterPrintAction(policy);

    switch (action) {
      case QuickSaleAfterPrintAction.newInvoice:
        _refocusScanner();

      case QuickSaleAfterPrintAction.stay:
        // السلّةُ أُفرغت في الترحيل، فـ«البقاء عليها» يعني إبقاءَ الفاتورة
        // **معروضةً** للمراجعة وإعادة الطباعة — وهذا ما يفعله حوارُ آخرِ
        // فاتورة. ولا سلّةَ تُستعاد: استعادتُها تفتح بابَ بيعِها مرّتين.
        if (mounted) await PicPosLastInvoiceDialog.show(context);
        if (mounted) _refocusScanner();

      case QuickSaleAfterPrintAction.lockScreen:
        // «تتطلب دخول كاشير من جديد» — وحوارُ تحويل المستخدم هو مسارُ
        // ذلك في PicPos: يشترط بيانات دخولٍ ولا يُغلَق باللمس خارجَه.
        if (mounted) await PicposSwitchUserDialog.show(context, ref);
        if (mounted) _refocusScanner();
    }
  }

  /// هل فيه طابعة إيصالات مضبوطة فعلاً؟
  ///
  /// ── ليه الفحص ده موجود ────────────────────────────────────────────────────
  /// `printInvoice` **مابيرميش** لما مفيش طابعة مضبوطة — بيسقط على
  /// `Printing.layoutPdf` اللي بيفتح **ديالوج الطباعة بتاع النظام**
  /// (`printer_resolver.dart:32` وتعليقه: «caller will show print dialog»).
  ///
  /// ده كان مقبول وقت ما الطباعة كانت زرار منفصل الكاشير بيختاره. بعد طلب ١
  /// بقت الطباعة جزء من `دفع` — أي **كل بيعة**. فعلى تركيب لسه ما ضبطش طابعته
  /// (أو محل مالوش طابعة إيصالات أصلاً) كل بيعة كانت هتتوقف على ديالوج طباعة
  /// لازم حد يقفله باليد. ده مش تعطيل للقرار، ده حماية له: «دفع بيطبع» تفضل
  /// صح لما فيه طابعة، وتفضل صامتة لما مفيش.
  ///
  /// المرجع هو `pos_receipt` في مستودع الطابعات — نفس المفتاح اللي
  /// `PrinterResolver.resolveReceiptPrinter` بيسأل عنه، فمفيش مصدر تاني للحقيقة.
  Future<bool> _hasReceiptPrinter() async {
    try {
      final printer = await ref
          .read(printersRepositoryProvider)
          .getActivePrinterByPurpose('pos_receipt');
      if (printer == null) {
        debugPrint('[PicPos-Print] مفيش طابعة إيصالات مضبوطة — تم تخطي الطباعة');
      }
      return printer != null;
    } catch (e) {
      // فشل قراءة الإعداد ما يصحّش يمنع الطباعة — نحاول ونسيب معالج الخطأ يتصرّف.
      debugPrint('[PicPos-Print] تعذّر فحص الطابعة: $e — هنحاول الطباعة');
      return true;
    }
  }

  /// يطبع الإيصال ويرجّع هل نجح. الفاتورة **مترحّلة** بالفعل قبل النداء ده.
  ///
  /// فشل الطباعة تحذير، **لا تراجع** — إلغاء بيعة محصَّلة عشان ورق ناقص أسوأ
  /// بكتير من إيصال مش مطبوع.
  Future<bool> _tryPrintReceipt(int invoiceId) async {
    try {
      await ref.read(posControllerProvider.notifier).printInvoice(invoiceId);
      return true;
    } catch (e) {
      debugPrint('[PicPos-Print] فشلت طباعة الفاتورة #$invoiceId: $e');
      if (mounted) {
        showPosToast(context, ref,
            '⚠️ الحفظ تم، لكن فشلت الطباعة (تأكد من الورق)',
            type: PosNotificationType.warning);
      }
      return false;
    }
  }

  /// فحص صلاحية طازة — منقول من `pos_main_operations._userHasPermissionFresh`.
  ///
  /// بيستهلك توكن موافقة المدير المرتبط بالفعل الأول (فالكاشير ما يتسألش كلمة
  /// المرور مرتين لنفس الزر)، وبعدها بيبطّل كاش الصلاحيات عشان تغيير المدير
  /// يسري بلا تسجيل خروج، وبيحترم تخطي مدير النظام إلا للعمليات المالية
  /// الحرجة. **مش** بيقرأ أي علم ترقية جلسة: كلمة مرور واحدة ما يصحّش تفتح كل
  /// الأفعال المحمية لباقي الجلسة.
  Future<bool> _userHasPermissionFresh(String permissionCode) async {
    if (ManagerApprovalCache.instance.consume(permissionCode)) return true;

    ref.invalidate(currentUserPermissionsProvider);
    final codes = await ref.read(currentUserPermissionsProvider.future);

    // المشروطُ لا يمرّ بالمِلك — نفسُ قاعدة `_ensureCartPermission` أعلاه.
    if (PermissionCodes.isConditionalIn(codes, permissionCode)) return false;

    if (codes.contains(permissionCode)) return true;

    final isSystemAdmin =
        codes.contains('system_admin') || codes.contains('*');
    final isCriticalFin =
        PermissionCodes.criticalFinancialOps.contains(permissionCode);
    return isSystemAdmin && !isCriticalFin;
  }

  /// يعالج «ورديةٌ مفتوحةٌ على طرفٍ آخر». يرجع `true` إن وجب **عدمُ** الفتح.
  ///
  /// ثلاثةُ مخارج، وكلُّها مقصودة:
  ///   • إغلاقُ المفتوحة → شاشةُ الإغلاق (محروسةٌ بـ`pos_shift_close` عندها).
  ///   • فتحٌ بإذن مدير → `pos_shift_open` بموافقة مسؤولٍ يملكها، **ويُسجَّل**.
  ///   • إلغاء → شاشةُ البيع بلا وردية، وهو ما طلبه المالك: «لا يقبل».
  Future<bool> _handleShiftOpenedElsewhere(ShiftData existing) async {
    if (!mounted) return true;

    final authState = ref.read(authProvider);
    final choice = await showPicposShiftConflictDialog(
      context,
      shiftId: existing.id,
      startedAt: existing.startTime,
      userName: authState.user?.displayName ??
          authState.user?.username ??
          'المستخدم الحالي',
    );
    if (!mounted) return true;

    switch (choice) {
      case ShiftConflictChoice.cancel:
        return true;

      case ShiftConflictChoice.closeExisting:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ShiftClosePicposScreen()),
        );
        // لا نفتح تلقائياً بعد العودة: قد يكون أغلقها وقد يكون انصرف. وفتحٌ
        // صامتٌ هنا يعيد بالضبط السلوكَ الذي جاء هذا العملُ ليمنعه.
        return true;

      case ShiftConflictChoice.overrideOpen:
        final approved = await requestManagerApproval(
          context,
          actionName: 'فتح وردية ثانية لنفس المستخدم',
          permission: PermissionCodes.posShiftOpen,
        );
        if (!approved || !mounted) return true;

        // التجاوزُ يُكتب. مخرجُ طوارئٍ لا يُراجَع يصير باباً خلفياً.
        try {
          await ref.read(activityLoggerProvider).log(
                userId: authState.user?.id,
                userName: authState.user?.displayName ?? 'مستخدم',
                action: 'shift_open_override',
                entityType: 'shifts',
                entityId: existing.id,
                description:
                    'فُتحت وردية ثانية بإذن مدير رغم وردية مفتوحة #${existing.id} '
                    'على طرف آخر بدأت ${existing.startTime}',
              );
        } catch (e) {
          debugPrint('[ShiftGuard] override log failed (non-fatal): $e');
        }
        return false; // امضِ في الفتح
    }
  }

  /// طرق الدفع المسموح بها للمستخدم الحالي.
  ///
  /// أكواد الصلاحيات دي كانت بتُنفَّذ بـ `PermissionGuard` حوالين كل زر طريقة
  /// في لوحة الدفع. الأزرار اتشالت (طلب ٢)، فالإنفاذ نزل هنا — نقطة الاختيار
  /// الوحيدة الباقية. مفيش واحدة من الخمس في `criticalFinancialOps`، فتخطي
  /// مدير النظام مُعاد بالحرف زي `PermissionGuard`.
  ///
  /// ── القرارُ نفسُه خرج إلى [resolveAllowedPaymentMethods] ─────────────────
  /// ما بقي هنا هو **القراءةُ** وحدَها. والسببُ أن الذيلَ الفاشلَ مفتوحاً كان
  /// يعيش داخل `catch` في `State` فلا يبلغه اختبار: أيُّ خطأِ قراءةٍ كان
  /// يمنح الطرقَ الخمسَ كلَّها. الآن `null` تعني «تعذّرت القراءة» والدالّةُ
  /// الخالصةُ تُقفِل على النقديّ — ومقيسٌ في
  /// `test/unit/picpos_payment_methods_test.dart`.
  Future<Set<String>> _allowedPaymentMethods({
    required bool isPlatform,
  }) async {
    // الإعدادُ يُقرأ ولو كان العميلُ منصّةً أو تعذّرت الصلاحيات — القراءتان
    // مستقلّتان، وفشلُ إحداهما لا يُسقط الأخرى.
    Set<String>? enabledBySetting;
    try {
      enabledBySetting =
          await ref.read(posEnabledPaymentMethodsProvider.future);
    } catch (_) {
      // إعدادٌ غيرُ مقروء = بلا تضييق. الصلاحيةُ وحدَها تحكم عندئذٍ.
      enabledBySetting = null;
    }

    List<String>? codes;
    try {
      codes = await ref.read(currentUserPermissionsProvider.future);
    } catch (_) {
      codes = null; // ← الفشلُ يُقفِل، ولا يرجع الخمسةَ كما كان
    }

    return resolveAllowedPaymentMethods(
      permissions: codes,
      enabledBySetting: enabledBySetting,
      isPlatformCustomer: isPlatform,
    );
  }

  /// يضمن إن فاتورة بنكية ليها خزنة بنك محدَّدة **قبل** الترحيل.
  ///
  /// اختيار البنك كان عايش في صف طرق الدفع في اللوحة، والصف اتشال. لو اعتمدنا
  /// على الشيب في اللوحة وحده، كاشير اختار «بطاقة» من الديالوج ومحدَّدش بنك
  /// كانت الفاتورة تترحّل على الخزنة الافتراضية بلا ما حدّ يقصد. فالضمانة نزلت
  /// على مسار الكتابة: واحدة → تلقائي، أكتر → نسأل، ولا شيء → `null` ويتولّى
  /// الـ DAO الاحتياطي (نفس سلوك UralCash بالحرف).
  ///
  /// ── ليه المبالغ داخلة في القرار ──────────────────────────────────────────
  /// `card` و `click` المفردين بيرجّعوا مبالغ `null` من الديالوج (الـ DAO
  /// بيستنتج التوزيع من الطريقة نفسها)، فالطريقة لوحدها هي الإشارة. أما `mixed`
  /// فبيرجّع أرقام حقيقية — وتقسيم **نقدي بالكامل** مالوش أي جزء بنكي، فسؤال
  /// الكاشير «اختر البنك» فيه كان هيبقى سؤال بلا معنى.
  Future<int?> _ensureBankSafeSelected(
    String method, {
    double? bankAmount,
    double? clickAmount,
  }) async {
    final isBank = method == 'card' ||
        method == 'click' ||
        (method == 'mixed' &&
            ((bankAmount ?? 0) > 0 || (clickAmount ?? 0) > 0));
    if (!isBank) return ref.read(cartControllerProvider).bankSafeId;

    final safes = await ref.read(branchBankSafesProvider.future);
    final current = ref.read(cartControllerProvider).bankSafeId;

    if (safes.isEmpty) return null;
    if (safes.length == 1) {
      ref.read(cartControllerProvider.notifier).setBankSafe(safes.first.id);
      return safes.first.id;
    }
    if (current != null && safes.any((s) => s.id == current)) return current;
    if (!mounted) return null;

    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('اختر الحساب البنكي'),
          children: [
            for (final safe in safes)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, safe.id),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsBold.bank,
                        size: 16, color: AppColors.info),
                    const SizedBox(width: 8),
                    Expanded(child: Text(safe.name)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      ref.read(cartControllerProvider.notifier).setBankSafe(picked);
    }
    return picked;
  }

  /// Blocks nothing outright — zero price or zero quantity is sometimes
  /// deliberate (a giveaway line, a correction). It just refuses to let it
  /// happen silently.
  Future<bool> _validateCartBeforeCheckout(CartState cartState) async {
    final zeroPrice = <String>[];
    final zeroQty = <String>[];
    for (final item in cartState.items) {
      if (item.effectivePrice <= 0) zeroPrice.add(item.productName);
      if (item.quantity <= 0) zeroQty.add(item.productName);
    }
    if (zeroPrice.isEmpty && zeroQty.isEmpty) return true;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 26),
            SizedBox(width: 8),
            Text('أصناف بدون قيمة'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (zeroPrice.isNotEmpty) ...[
                const Text('أصناف بسعر صفر:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.error)),
                ...zeroPrice.map((n) => Text('• $n',
                    style: const TextStyle(fontSize: 13))),
                const SizedBox(height: 8),
              ],
              if (zeroQty.isNotEmpty) ...[
                const Text('أصناف بكمية صفر:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.error)),
                ...zeroQty.map((n) => Text('• $n',
                    style: const TextStyle(fontSize: 13))),
              ],
              const Divider(),
              const Text('هل تريد المتابعة؟',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لا، تعديل الفاتورة'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white),
              child: const Text('نعم، متابعة'),
            ),
          ],
        ),
      ),
    );
    return proceed == true;
  }

  // ── Cancel the whole invoice (ESC) ─────────────────────────────────────

  Future<void> _cancelInvoice() async {
    // وضعُ المرتجع (المهمّة ٧): سلّتُه فارغةٌ عادةً (‏الكاشيرُ لم يُضِف
    // أصنافَ بيعٍ)، فالفرعُ العاديُّ تحته كان سيعود فوراً بلا شيءٍ — ويحبس
    // الكاشيرَ في وضع المرتجع بلا مخرجٍ سوى إتمام الحفظ. `ESC` و«مسح الكل»
    // كلاهما يصل هنا؛ نفسُ التأكيدِ المزدوج المعتاد قبل أيّ إلغاء.
    // وضعُ الاستبدال يحتاج نفسَ المخرج: بلا هذا الفرع يُحبَس الكاشيرُ فيه
    // بلا سبيلٍ سوى إتمام الحفظ — نفسُ العطب الذي عولج للمرتجع فوق.
    final exchangeModeToCancel = ref.read(posExchangeModeProvider);
    if (exchangeModeToCancel != null) {
      final ok = await AppConfirmDialog.show(
        context,
        title: 'إلغاء الاستبدال',
        message: 'سيُلغى وضعُ الاستبدال بلا حفظ، **وتُفرَّغ سلّةُ البديل**. '
            'متأكد؟',
        confirmLabel: 'إلغاء الاستبدال',
        isDangerous: true,
      );
      if (!ok || !mounted) return;
      _cancelExchange();
      _refocusScanner();
      return;
    }

    final returnMode = ref.read(posReturnModeProvider);
    if (returnMode != null) {
      final ok = await AppConfirmDialog.show(
        context,
        title: 'إلغاء المرتجع',
        message: 'سيُلغى وضعُ المرتجع الحاليّ بلا حفظ. متأكد؟',
        confirmLabel: 'إلغاء المرتجع',
        isDangerous: true,
      );
      if (!ok || !mounted) return;
      _cancelQuickReturn();
      _refocusScanner();
      return;
    }

    final items = ref.read(cartControllerProvider).items;
    if (items.isEmpty) {
      _refocusScanner();
      return;
    }
    final ok = await AppConfirmDialog.show(
      context,
      title: 'إلغاء الفاتورة',
      message: 'سيتم مسح كل الأصناف. متأكد؟',
      confirmLabel: 'إلغاء الفاتورة',
      isDangerous: true,
    );
    if (!ok || !mounted) return;
    if (!await _ensureCartPermission(
      canClearCart,
      PermissionCodes.posClearCart,
      'تفريغ السلة',
    )) {
      return;
    }
    if (!mounted) return;
    ref.read(cartControllerProvider.notifier).clearCart();
    setState(() => selectedIndex = null);
    barcodeController.clear();
    _refocusScanner();
  }

  // ── Side-panel operations ──────────────────────────────────────────────

  Future<void> _pickCustomer() async {
    // `pos_customer_select` كان محروساً في `pos/widgets/cart/
    // cart_totals_panel.dart` وحدَه — شاشةٌ لا يصل إليها PicPos.
    if (!await ensureSelectCustomerPermission(ref, context)) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => const PosCustomerSelectionDialog(),
    );
    _refocusScanner();
  }

  Future<void> _showHeldOrders() async {
    // وضعُ المرتجع (جولةُ إصلاح ٢ — مانعٌ ١): `HeldOrdersDialog.onRetrieve`
    // يستدعي `retrieveHeldOrder`، و`executeRetrieve` في
    // `hold_order_usecase.dart` **يحذف الطلبَ المعلَّق من القاعدة** فور
    // تحميله في السلّة — ولا استرجاعَ بعدها. فمسارُ الكارثة: كاشيرٌ في وضع
    // مرتجعٍ يفتح «معلّقة» ← الطلبُ يُحذف وتدخل أصنافُه سلّةً لا علاقةَ لها
    // بالمرتجع ← «دفع/حفظ» (مفعَّلٌ الآن بفضل إصلاح C1) يحفظ المرتجعَ ثم
    // `clearCart()` تمحو ما استُرجع ⇒ الطلبُ المعلَّق ضائعٌ نهائياً بلا بيعٍ
    // ولا رسالة. الأزرارُ الثلاثة (لوحةُ الدفع، الشريطُ العلويّ) معطَّلةٌ
    // بصرياً أيضاً؛ هذا الحارسُ خطُّ الدفاع الأخير عند أيّ مدخلٍ ثالثٍ يُنسى.
    if (blocksCartMutation(ref.read(posReturnModeProvider))) {
      showPosToast(
        context,
        ref,
        'أنت في وضع المرتجع — أنهِ الحفظَ أو الإلغاءَ قبل فتح الفواتير المعلّقة',
        type: PosNotificationType.warning,
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => HeldOrdersDialog(
        onRetrieve: (orderId) async {
          await ref
              .read(cartControllerProvider.notifier)
              .retrieveHeldOrder(orderId);
          if (mounted) setState(() => selectedIndex = null);
        },
      ),
    );
    _refocusScanner();
  }

  Future<void> _holdOrder() async {
    final items = ref.read(cartControllerProvider).items;
    if (items.isEmpty) {
      showPosToast(context, ref, 'الفاتورة فارغة',
          type: PosNotificationType.info);
      return;
    }
    // `pos_hold_order` كان محروساً في `pos/widgets/pos_header.dart` وحدَه —
    // ملفٌّ لا تبلغه شاشةُ PicPos. وأخفاه الحارسُ البنيويُّ لأن الكودَ مذكورٌ
    // في `api_sales_handler.dart` (سطحُ HTTP) وفي قائمةِ منحٍ في
    // `migrations/epoch_3.dart` — وكلاهما ليس شاشة.
    if (!await ensureHoldOrderPermission(ref, context)) return;
    if (!mounted) return;

    // سقفُ «أقصى عدد فواتير معلّقة» — §٤.
    //
    // ⚠️ **الوصولُ للحدّ يمنع، لا تجاوزُه**: عشرُ فواتيرَ معلّقةٍ وسقفٌ عشرةٌ
    // يعني أنّ الحادية عشرةَ مرفوضة. و«بلا حد» تُمثَّل بـ`null` لا بصفر —
    // والخلطُ بينهما كان سيمنع كلَّ تعليق.
    final policy = await ref.read(quickSalePolicyProvider.future);
    if (!mounted) return;
    final cap = quickSaleHoldCap(policy);
    final heldNow = ref.read(heldOrdersProvider).value?.length ?? 0;
    if (!quickSaleCanHoldMore(current: heldNow, cap: cap)) {
      showPosToast(
        context,
        ref,
        'بلغتَ الحدَّ الأقصى للفواتير المعلّقة ($cap) — أنهِ فاتورةً معلّقةً أوّلاً',
        type: PosNotificationType.error,
      );
      return;
    }

    final err = await ref.read(cartControllerProvider.notifier).holdOrder();
    if (!mounted) return;
    if (err == null) {
      setState(() => selectedIndex = null);
      showPosToast(context, ref, 'تم تعليق الفاتورة',
          type: PosNotificationType.success);
    } else {
      showPosToast(context, ref, err, type: PosNotificationType.error);
    }
    _refocusScanner();
  }

  Future<void> _showExpenses() async {
    // ليس عرضاً بريئاً: الحوارُ فيه زرُّ «إضافة مصروف» يفتح `PosExpenseDialog`
    // فيكتب سندَ صرفٍ نقديّ ⇒ مالٌ يخرج من الدرج. و`pos_expense` كان محروساً
    // في `pos/widgets/cart/cart_totals_panel.dart` وحدَه — لا تبلغه PicPos.
    if (!await ensureAddExpensePermission(ref, context)) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => const PosPreviousExpensesDialog(),
    );
    _refocusScanner();
  }

  /// «الفاتورة السابقة» — زر صف الأزرار، و F3، ورقم الفاتورة في الترويسة،
  /// كلهم بيوصّلوا هنا.
  ///
  /// ⚠️ **البابُ الثاني لـ`pos_previous_invoices`** — وهو سببُ بلاغ المالك
  /// «الفواتير السابقة لا تعمل». الحوارُ يعرض أصنافَ الفاتورة السابقة
  /// وكمياتِها وأسعارَها وإجماليَها، أي **نفسَ ما تحرسه** `_showPreviousInvoices`
  /// بالضبط — وكان مفتوحاً من ثلاثة مداخل بلا فحص، بينما البابُ الأولُ محروس.
  /// فمن رفع التحديدَ رأى المنعَ على الزرّ الصغير «فواتير» ولم يره على الزرّ
  /// الكبير «الفاتورة السابقة». (مقيسٌ 2026-08-13)
  Future<void> _showLastInvoice() async {
    if (!await ensurePreviousInvoicesPermission(ref, context)) return;
    if (!mounted) return;
    await PicPosLastInvoiceDialog.show(context);
    _refocusScanner();
  }

  Future<void> _showPreviousInvoices() async {
    // `pos_previous_invoices` — ليست عرضاً بريئاً: تكشف مبيعاتِ الورديات
    // الأخرى وأسعارَها وعملاءَها.
    if (!await ensurePreviousInvoicesPermission(ref, context)) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => PosPreviousInvoicesDialog(
        // ⚠️ بابٌ ثانٍ لإعادة الطباعة: زرُّ إعادة الطباعة في حوار «آخر
        // فاتورة» محروسٌ بـ`pos_print` (`picpos_last_invoice_dialog.dart:125`)
        // وهذا المسارُ كان يطبع بلا فحص. والطباعةُ التلقائيةُ بعد البيع
        // (`_tryPrintReceipt`) تبقى بلا حراسةٍ عن قصد: جزءٌ من إتمام بيعةٍ
        // مأذونةٍ سلفاً.
        onReprint: (id) async {
          if (!await ensurePermission(ref, context, PermissionCodes.posPrint,
              actionName: 'إعادة طباعة فاتورة')) {
            return;
          }
          if (!mounted) return;
          await ref.read(posControllerProvider.notifier).printInvoice(id);
        },
        onEdit: _editPostedInvoice,
        // No kitchen module in lite.
        onPrintKitchen: (_) {},
      ),
    );
    _refocusScanner();
  }

  // ── وضعُ المرتجع: زرُّ «مرتجع سريع» (المهمّة ٧) ─────────────────────────

  /// زرُّ «مرتجع سريع» في لوحة الدفع — يفتح مُحدِّدَ فاتورةٍ، ثم **سطحَ
  /// اختيار أسطر** (‏`_QuickReturnLinesEditorDialog`) يعرض كلَّ سطرٍ بمباعه
  /// ومرتجعه السابق ومتاحه وسعره، ويترك للكاشير ضبطَ الكميّات (تبدأ صفراً)
  /// قبل التأكيد. لا تعبئةَ تلقائيّةً كاملة — راجعةُ المراجع C1–C3 (جولةُ
  /// إصلاح ١) رفضت التصميمَ الأصليّ («ضغطةٌ واحدةٌ تُرجع الفاتورةَ كلَّها
  /// بلا رؤيةٍ ولا تحكّم»).
  ///
  /// بعد التأكيد فقط يُضبط `posReturnModeProvider` (فتظهر الترويسةُ الحمراء
  /// ويتحوَّل مسارُ الحفظ في `_processPaymentAndSave`، وتُقفَل إضافةُ أصنافٍ
  /// للسلّة — `_handleProductTap`/`_searchBarcode` أعلاه).
  Future<void> _showQuickReturn() async {
    // ملاحظةٌ صغيرة (جولةُ إصلاح ٢): الزرُّ نفسُه معطَّلٌ في اللوحة حين وضعُ
    // المرتجع فعّالٌ بالفعل (‏`picpos_payment_panel.dart`)، فهذا خطُّ دفاعٍ
    // ثانٍ فقط — بلا هذا الفحص، إعادةُ استدعاءٍ (مثلاً من اختصار كيبورد
    // مستقبليّ) كانت ستستبدل فاتورةً وكمياتٍ ضُبطت بعنايةٍ صامتاً.
    if (ref.read(posReturnModeProvider) != null) {
      showPosToast(
        context,
        ref,
        'أنت في وضع المرتجع بالفعل — أنهِ الحفظَ أو الإلغاءَ أوّلاً',
        type: PosNotificationType.info,
      );
      return;
    }

    // `pos_return` كان محروساً في النظير القديم وحدَه (`pos/widgets/
    // pos_header.dart:320,384`) — ملفٌّ لا تبلغه شاشةُ PicPos. بوّابةُ دخولٍ
    // خشنة: مَن لا يملكه لا يدخل وضعَ المرتجع أصلاً — قبل حتى اختيار فاتورة.
    if (!await ensureQuickReturnPermission(ref, context)) return;
    if (!mounted) return;

    // `sales_return_create` — نفسُ صلاحيّة الشاشة المستقلّة
    // (`sales_returns_picpos_screen.dart`)، وبنفس نمط بوّابةِ `posSave`:
    // فحصٌ طازج ثم موافقةُ مسؤول. بوّابةٌ ثانيةٌ أدقّ من `pos_return`
    // فوق — تخصّ إنشاءَ مستند المرتجع نفسه، لا مجرّد الدخول في وضعه.
    if (!await _userHasPermissionFresh(PermissionCodes.salesReturnCreate)) {
      if (!mounted) return;
      final approved = await requestManagerApproval(
        context,
        actionName: 'إنشاء مرتجع مبيعات',
        permission: PermissionCodes.salesReturnCreate,
      );
      if (!approved) return;
    }
    if (!mounted) return;

    // I3 (جولةُ إصلاح ١): وضعُ المرتجع لا يكتب على `cartController` عمداً،
    // فسلّةُ بيعٍ قيدَ التحضير تبقى كما هي أثناء التحرير — لكنّ
    // `_processQuickReturnSave` يمسحها بـ`clearCart()` بعد نجاح الحفظ (نفسُ
    // سلوك أيّ حفظٍ ناجح في هذه الشاشة). الكاشيرُ يستحقّ تحذيراً صريحاً قبل
    // أن يدخل مساراً ينتهي بمسح ما بدأه، لا مسحاً صامتاً لاحقاً.
    if (ref.read(cartControllerProvider).items.isNotEmpty) {
      final proceed = await AppConfirmDialog.show(
        context,
        title: 'سلّةُ بيعٍ قيدَ التحضير',
        message:
            'في السلّة أصنافُ بيعٍ لم تُحفَظ بعد. الدخولُ في وضع المرتجع '
            'يبقيها كما هي أثناء التحرير، لكنّ حفظَ المرتجع سيُفرغها. '
            'متابعة؟',
        confirmLabel: 'متابعة المرتجع',
        isDangerous: true,
      );
      if (!proceed || !mounted) return;
    }

    final invoice = await showDialog<SalesInvoiceData>(
      context: context,
      builder: (_) => const _QuickReturnInvoicePickerDialog(),
    );
    if (invoice == null || !mounted) return;

    final returnsRepo = ref.read(returnsRepositoryProvider);
    final productRepo = ref.read(productRepositoryProvider);

    final items = await returnsRepo.getSalesInvoiceItems(invoice.id);
    if (!mounted) return;
    if (items.isEmpty) {
      showPosToast(context, ref, 'لا توجد أصنافٌ في هذه الفاتورة',
          type: PosNotificationType.info);
      return;
    }

    final productIds = items.map((it) => it.productId).toSet().toList();
    final results = await Future.wait([
      productRepo.getProductsByIds(productIds),
      returnsRepo.getReturnedQuantitiesForInvoice(invoice.id),
    ]);
    if (!mounted) return;
    final products = results[0] as List<ProductEntity>;
    final returnedByProduct = results[1] as Map<int, double>;

    final productCache = <int, ProductEntity>{
      for (final p in products) p.id: p,
    };
    final nameById = <int, String>{for (final p in products) p.id: p.name};

    // ⚠️ قيدٌ معروف (I2؛ نصُّه صُحِّح في جولة إصلاح ٢ — راجع `computeIsFullReturn`
    // أدناه لتفصيلٍ كامل): `returnedByProduct` من `getReturnedQuantitiesForInvoice`
    // مجموعٌ **بمفتاح `productId`** (‏`inventory_dao.dart` يجمع بـGROUP BY
    // productId)، بينما `soldQty` هنا بمفتاح **السطر** (‏`item.quantity`).
    // فاتورةٌ فيها نفسُ الصنف على أكثرَ من سطرٍ تُنسِب كامل المرتجَع السابق
    // لكلّ سطرٍ من سطورها **مستقلّاً** — مقارنةٌ بين مفتاحَين مختلفَين لا
    // يجوز الوثوقُ بناتجها. قياسٌ فعليّ أثبت أن هذا يجعل `computeIsFullReturn`
    // **تُبالغ** (تختم «كاملٌ» بينما وحداتٌ حقيقيّةٌ لم تُطلَب)، لا تُقلّل —
    // فالدالّةُ تلك ترفض الختمَ `true` كلّياً عند أيّ تكرارٍ لِـ`productId`
    // بدل محاولة حسابٍ فوق مفتاحَين متعارضَين. الإصلاحُ الجذريّ (استعلامٌ
    // بمفتاح السطر `invoiceItemId`) يحتاج تعديلَ طبقة المستودع
    // (‏`returns_repository_impl.dart:109`) — خارج نطاق ملفّات هذه المهمّة.
    final lines = [
      for (final item in items)
        ReturnableLine(
          invoiceItemId: item.id,
          productId: item.productId,
          productName: nameById[item.productId] ?? 'صنف #${item.productId}',
          soldQty: item.quantity,
          alreadyReturnedQty: returnedByProduct[item.productId] ?? 0,
          unitPrice: item.unitPrice,
          // مبلغُ الاسترداد (`PosReturnMode.refundTotal`) يُبنى على هذا لا
          // على unitPrice — راجع توثيق `ReturnableLine.lineTotal`.
          lineTotal: item.total,
        ),
    ];

    // الكميّاتُ تبدأ صفراً (قرارُ مالكٍ، مهمّةٌ ٦) — لا تعبئةَ تلقائية.
    // `_QuickReturnLinesEditorDialog` هو مَن يملأها، سطراً سطراً، عبر
    // `setQty`/`clearQty` تحت رؤية الكاشير وتحكّمه.
    //
    // `invoiceTotal`/`invoiceDeliveryFee` من ترويسة الفاتورة — نفسُ
    // مدخلَي `ReturnsRepositoryImpl._calculateReturnTotal`، فمبلغُ
    // الاسترداد المعروض (`mode.refundTotal`) يطابق ما يُصرف فعلياً عند
    // الحفظ بالضبط.
    final mode = PosReturnMode.fromLines(
      invoiceId: invoice.id,
      lines: lines,
      invoiceTotal: invoice.total,
      invoiceDeliveryFee: invoice.deliveryFee,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _QuickReturnLinesEditorDialog(
        mode: mode,
        invoiceNumber: invoice.invoiceNumber,
      ),
    );
    if (confirmed != true || !mounted) return;

    // حمايةٌ دفاعيّة: المحرِّرُ يمنع التأكيدَ بلا كميةٍ واحدةٍ فأكثر، فهذا لا
    // يجب أن يُرى فعلياً.
    if (mode.requestedQty.values.every((q) => q <= 0)) {
      showPosToast(context, ref, 'لا توجد كمياتٌ محدَّدةٌ للإرجاع',
          type: PosNotificationType.info);
      return;
    }

    setState(() {
      _returnInvoice = invoice;
      _returnProductCache = productCache;
    });
    ref.read(posReturnModeProvider.notifier).state = mode;
    _refocusScanner();
  }

  /// يُنهي وضعَ المرتجع بلا حفظ — يفرّغ الحالةَ المحليّةَ والمزوِّدَ معاً.
  void _cancelQuickReturn() {
    ref.read(posReturnModeProvider.notifier).state = null;
    setState(() {
      _returnInvoice = null;
      _returnProductCache = const {};
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  // الاستبدال — المردودُ وبديلُه
  // ══════════════════════════════════════════════════════════════════════

  /// يفتح وضعَ الاستبدال: نفسُ مُحدِّد الفاتورة ومحرِّرِ الأسطر، يليهما وسمُ
  /// العيب لكلِّ سطر.
  ///
  /// **وبخلاف `_showQuickReturn` لا يحذّر من سلّةٍ عامرة:** السلّةُ هنا هي
  /// سلّةُ البديل، فامتلاؤها هو الحالةُ المقصودةُ لا تعارضاً.
  Future<void> _showExchange() async {
    if (ref.read(posExchangeModeProvider) != null ||
        ref.read(posReturnModeProvider) != null) {
      showPosToast(context, ref,
          'أنت في وضعٍ قائمٍ بالفعل — أنهِ الحفظَ أو الإلغاءَ أوّلاً',
          type: PosNotificationType.info);
      return;
    }

    // `pos_exchange` — كودٌ مبذورٌ منذ البداية وظلّ مسجَّلاً «بلا ميزة» في
    // `permission_enforcement_registry`. الميزةُ وصلت الآن فيُنفَذ الكودُ
    // ويُشطب سطرُه، وهو ما أمسكه الحارسُ المعاكسُ فورَ وصول السطح.
    if (!await _userHasPermissionFresh(PermissionCodes.posExchange)) {
      if (!mounted) return;
      final approved = await requestManagerApproval(
        context,
        actionName: 'استبدال المنتجات',
        permission: PermissionCodes.posExchange,
      );
      if (!approved) return;
    }
    if (!mounted) return;

    // الاستبدالُ يرتجع **ويبيع**، فالصلاحيتان معاً — ونفسُ بابِ الاستئذان
    // الذي يسلكه المرتجع السريع حين تنقص صلاحيةُ المرتجع.
    if (!await ensureQuickReturnPermission(ref, context)) return;
    if (!mounted) return;
    if (!await _userHasPermissionFresh(PermissionCodes.salesReturnCreate)) {
      if (!mounted) return;
      final approved = await requestManagerApproval(
        context,
        actionName: 'إنشاء استبدال',
        permission: PermissionCodes.salesReturnCreate,
      );
      if (!approved) return;
    }
    if (!mounted) return;

    final invoice = await showDialog<SalesInvoiceData>(
      context: context,
      builder: (_) => const _QuickReturnInvoicePickerDialog(),
    );
    if (invoice == null || !mounted) return;

    final returnsRepo = ref.read(returnsRepositoryProvider);
    final productRepo = ref.read(productRepositoryProvider);

    final items = await returnsRepo.getSalesInvoiceItems(invoice.id);
    if (!mounted) return;
    if (items.isEmpty) {
      showPosToast(context, ref, 'لا توجد أصنافٌ في هذه الفاتورة',
          type: PosNotificationType.info);
      return;
    }

    final productIds = items.map((it) => it.productId).toSet().toList();
    final results = await Future.wait([
      productRepo.getProductsByIds(productIds),
      returnsRepo.getReturnedQuantitiesForInvoice(invoice.id),
    ]);
    if (!mounted) return;
    final products = results[0] as List<ProductEntity>;
    final returnedByProduct = results[1] as Map<int, double>;

    final productCache = <int, ProductEntity>{
      for (final p in products) p.id: p,
    };
    final nameById = <int, String>{for (final p in products) p.id: p.name};

    final mode = PosExchangeMode.fromLines(
      invoiceId: invoice.id,
      invoiceTotal: invoice.total,
      invoiceDeliveryFee: invoice.deliveryFee,
      lines: [
        for (final item in items)
          ReturnableLine(
            invoiceItemId: item.id,
            productId: item.productId,
            productName: nameById[item.productId] ?? 'صنف #${item.productId}',
            soldQty: item.quantity,
            alreadyReturnedQty: returnedByProduct[item.productId] ?? 0,
            unitPrice: item.unitPrice,
            lineTotal: item.total,
          ),
      ],
    );

    // محرِّرُ الأسطر نفسُه — يعمل على `returnLeg` مباشرةً، فلا نسخةَ ثانيةً
    // من سياج الكمية ولا من حساب المرتجع.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _QuickReturnLinesEditorDialog(
        mode: mode.returnLeg,
        invoiceNumber: invoice.invoiceNumber,
      ),
    );
    if (confirmed != true || !mounted) return;

    if (!mode.hasReturnSelection) {
      showPosToast(context, ref, 'لا توجد كمياتٌ محدَّدةٌ للاستبدال',
          type: PosNotificationType.info);
      return;
    }

    // وسمُ العيب **لكلِّ سطر** (قرارُ المالك (ب)) — خطوةٌ منفصلةٌ لا تلمس
    // محرِّرَ المرتجع المشحون، فلا تُخاطر بمسارٍ يعمل.
    final marked = await _markDamagedLines(mode);
    if (!marked || !mounted) return;

    setState(() {
      _exchangeInvoice = invoice;
      _exchangeProductCache = productCache;
    });
    ref.read(posExchangeModeProvider.notifier).state = mode;
    _refocusScanner();
  }

  /// يعرض الأسطرَ المختارةَ ليُوسَم المعيبُ منها. الافتراضُ **سليم**: وسمُ
  /// العيب يُتلف المخزونَ فلا يكون افتراضاً صامتاً.
  Future<bool> _markDamagedLines(PosExchangeMode mode) async {
    final selected = mode.effectiveReturnQuantities.keys.toList();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('هل من صنفٍ تالف؟'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'الموسومُ تالفاً لا يعود إلى المخزون القابل للبيع.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final itemId in selected)
                          SwitchListTile(
                            dense: true,
                            title: Text(
                              mode.linesByItemId[itemId]?.productName ??
                                  'صنف #$itemId',
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              'الكمية ${mode.requestedQty[itemId]}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            value: mode.isDamaged(itemId),
                            onChanged: (v) =>
                                setLocal(() => mode.setDamaged(itemId, v)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('متابعة'),
              ),
            ],
          ),
        ),
      ),
    );
    return result == true;
  }

  /// يُنهي وضعَ الاستبدال — **ويُفرّغ الشقَّين معاً**.
  ///
  /// **ولماذا تُفرَّغ سلّةُ البديل كذلك:** أصنافُها أُضيفت بوصفها بديلاً عن
  /// مرتجَعٍ مختار. وإبقاؤها بعد زوال الوضع يحوّلها صامتاً إلى سلّةِ بيعٍ
  /// عاديّة، فيبيع الكاشيرُ البديلَ بثمنٍ كاملٍ ولم يُرتجَع شيءٌ أصلاً — نصفُ
  /// استبدالٍ يُحفظ بالخطأ. والمخرجُ الوحيدُ إلى هنا هو `ESC`/«مسح الكل» خلف
  /// تأكيدٍ صريحٍ يقول إن السلّة ستُفرَّغ، فلا مسحَ صامت.
  ///
  /// ويُنادى كذلك بعد الحفظ الناجح — والسلّةُ حينها مُفرَّغةٌ سلفاً.
  void _cancelExchange() {
    ref.read(posExchangeModeProvider.notifier).state = null;
    ref.read(cartControllerProvider.notifier).clearCart();
    setState(() {
      _exchangeInvoice = null;
      _exchangeProductCache = const {};
    });
  }

  /// مسارُ حفظ الاستبدال — الفرعُ الذي يأخذه `_processPaymentAndSave` حين
  /// يكون `posExchangeModeProvider` غيرَ `null`.
  Future<void> _processExchangeSave(PosExchangeMode mode) async {
    final invoice = _exchangeInvoice;
    if (invoice == null || invoice.id != mode.invoiceId) {
      showPosToast(context, ref, 'تعذّر تحديد الفاتورة الأصليّة للاستبدال',
          type: PosNotificationType.error);
      _cancelExchange();
      return;
    }

    final returnQuantities = mode.effectiveReturnQuantities;
    if (returnQuantities.isEmpty) {
      showPosToast(context, ref, 'لا توجد كمياتٌ محدَّدةٌ للاستبدال',
          type: PosNotificationType.info);
      return;
    }

    final cartState = ref.read(cartControllerProvider);
    if (cartState.items.isEmpty) {
      showPosToast(context, ref, 'أضِف أصنافَ البديل إلى السلّة أوّلاً',
          type: PosNotificationType.info);
      return;
    }

    final auth = ref.read(authProvider);
    final userId = auth.user?.id ?? 0;
    final userName = auth.user?.displayName ?? 'مستخدم';

    // نفسُ مصادر مسار البيع (`CheckoutController`): المخزنُ الفعّال، والفرعُ
    // من الفرع الفعّال، ومركزُ التكلفة من المخزن ثم الفرع. تُقرأ هنا لأن
    // `processExchange` يستقبلها صراحةً — والمصدرُ واحدٌ لا اجتهادٌ ثانٍ.
    final warehouseId = await ref.read(activeWarehouseIdProvider.future);
    if (!mounted) return;
    final branch = await ref.read(branchRepositoryProvider).getActiveBranch();
    if (!mounted) return;

    ExchangeResult result;
    try {
      result = await ref.read(exchangeRepositoryProvider).processExchange(
            originalInvoice: invoice,
            returnQuantities: returnQuantities,
            returnProductCache: _exchangeProductCache,
            replacementItems: cartState.items,
            warehouseId: warehouseId,
            userId: userId,
            userName: userName,
            damagedItemIds: mode.effectiveDamagedItemIds,
            customerId: cartState.selectedCustomerId,
            taxPercent: cartState.taxRate * 100,
            taxEnabled: cartState.taxEnabled,
            // ⚠️ **صفرٌ دائماً.** تمريرُ الفرق خصماً يجعل تقريرَ المبيعات
            // يعرض تنزيلاً لم يحدث — ممنوعٌ صراحةً في المواصفة. الفرقُ
            // يُسوّى نقداً على الدرج لا على سطر الفاتورة.
            discountPercent: 0,
            branchId: branch?.id,
          );
    } catch (e) {
      if (mounted) {
        showPosToast(context, ref, 'فشل الاستبدال: $e',
            type: PosNotificationType.error);
      }
      return;
    }

    if (!mounted) return;

    final invoiceNumber = invoice.invoiceNumber;
    // يُفرّغ الشقَّين معاً — السلّةُ داخلَه، فلا نداءَ ثانٍ لـ`clearCart`.
    _cancelExchange();
    setState(() => selectedIndex = null);
    barcodeController.clear();

    // **الرقمُ المعروضُ بعد الحفظ هو أثرُ الدرج المقيسُ داخل المعاملة**، لا
    // فرقُ الإجماليَّين. فاتورةٌ أصليّةٌ بنكيّةٌ تُردّ إلى قناتها بينما البديلُ
    // يُقبض نقداً كاملاً — وعرضُ الفرق حينها يكذب على الكاشير.
    final settlementText = switch (result.direction) {
      ExchangeCashDirection.collect =>
        'حُصِّل ${NumberUtils.formatCurrency(result.difference)}',
      ExchangeCashDirection.refund =>
        'رُدّ ${NumberUtils.formatCurrency(result.difference)}',
      ExchangeCashDirection.none => 'بلا فرق',
    };
    showPosToast(context, ref,
        'تم استبدال فاتورة $invoiceNumber — $settlementText',
        type: PosNotificationType.success);
    _refocusScanner();
  }

  /// مسارُ حفظ المرتجع — الفرعُ الذي يأخذه `_processPaymentAndSave` كلُّه
  /// حين يكون `posReturnModeProvider` غيرَ `null`. المسارُ الإلزاميّ
  /// `returnsRepository.processSalesReturn` **لا** `ProcessSalesReturnUseCase`
  /// — الأخيرُ بلا سقفِ كميةٍ في `_validate` (مقيسٌ، لا مفترَض)، فاستعمالُه
  /// كان سيفتح ثغرةَ إرجاعٍ زائد.
  Future<void> _processQuickReturnSave(PosReturnMode mode) async {
    final invoice = _returnInvoice;
    if (invoice == null || invoice.id != mode.invoiceId) {
      // لا يجب أن يحدث: الوضعُ والفاتورةُ يُضبَطان معاً في `_showQuickReturn`
      // ويُفرَّغان معاً في `_cancelQuickReturn`/هنا. حماية دفاعيّة فقط.
      showPosToast(context, ref, 'تعذّر تحديد الفاتورة الأصليّة للمرتجع',
          type: PosNotificationType.error);
      _cancelQuickReturn();
      return;
    }

    // إسقاطُ الأصفار: `PosReturnMode.fromLines` تبدأ كلَّ سطرٍ صفراً
    // (قرارُ مالكٍ، مهمّةٌ ٦)، و`processSalesReturn` يعتبر أيَّ سطرٍ غيرَ
    // مذكورٍ = لا إرجاعَ له.
    final returnQuantities = <int, double>{
      for (final entry in mode.requestedQty.entries)
        if (entry.value > 0) entry.key: entry.value,
    };

    if (returnQuantities.isEmpty) {
      showPosToast(context, ref, 'لا توجد كمياتٌ محدَّدةٌ للإرجاع',
          type: PosNotificationType.info);
      return;
    }

    final auth = ref.read(authProvider);
    final userId = auth.user?.id ?? 0;
    final userName = auth.user?.displayName ?? 'مستخدم';

    bool success;
    try {
      success = await ref.read(returnsRepositoryProvider).processSalesReturn(
            invoice: invoice,
            returnQuantities: returnQuantities,
            productCache: _returnProductCache,
            userId: userId,
            userName: userName,
            // I2 (جولةُ إصلاح ١): محسوبةٌ لا مثبَّتة — `true` زائفةٌ كانت
            // ستختم الفاتورةَ `'returned'` (‏`processSalesReturn` تفعل هذا
            // صراحةً حين `isFullReturn`) فتستبعدها `getInvoicesForReturn`
            // أبداً حتى لو تبقّى فيها مرتجعٌ لم يُطلَب. انظر `computeIsFullReturn`.
            isFullReturn: computeIsFullReturn(mode),
          );
    } catch (e) {
      if (mounted) {
        showPosToast(context, ref, 'فشل حفظ المرتجع: $e',
            type: PosNotificationType.error);
      }
      return;
    }

    if (!mounted) return;
    if (!success) {
      showPosToast(context, ref, 'تعذّر حفظ المرتجع — راجع الكمياتِ المحدَّدة',
          type: PosNotificationType.error);
      return;
    }

    final invoiceNumber = invoice.invoiceNumber;
    _cancelQuickReturn();
    ref.read(cartControllerProvider.notifier).clearCart();
    setState(() => selectedIndex = null);
    barcodeController.clear();
    showPosToast(context, ref, 'تم حفظ مرتجع فاتورة $invoiceNumber',
        type: PosNotificationType.success);
    _refocusScanner();
  }

  /// تعديل **طريقة دفع** فاتورة مرحّلة + ملاحظاتها (طلب ٥).
  ///
  /// ── إيه اللي بيتعدَّل وإيه اللي لأ ────────────────────────────────────────
  /// طريقة الدفع والملاحظات والتقسيم بس. **الأصناف والكميات لأ** — تصحيحها
  /// طريقه مردود مبيعات، وده اللي كانت الشاشة دي بتقوله في توست قبل الطلب ده.
  /// الحاجة اللي كانت ناقصة فعلاً هي الحالة الشائعة: الكاشير اختار «نقدي» وهو
  /// كان لازم «بطاقة»، والفاتورة كلها صح ما عدا ده.
  ///
  /// ── ليه بوابة صلاحية إجبارية ─────────────────────────────────────────────
  /// الفعل ده **بيحرّك فلوس ويعيد كتابة دفتر الأستاذ**: الـ DAO بيحذف القيد
  /// القديم ويسجّل واحد جديد وينقل أرصدة الخزن
  /// (`sales_mutations_dao.updateSalesInvoicePayment`). ده مش فعل كاشير عادي،
  /// فبيمر بنفس فحص الصلاحية الطازة اللي الحفظ بيمر بيه، وإلا موافقة مدير.
  ///
  /// تحقّق الفترة المالية موجود جوه الـ DAO أصلاً فمش بنكرّره هنا.
  Future<void> _editPostedInvoice(SalesInvoiceData invoice) async {
    if (!await _userHasPermissionFresh(PermissionCodes.posEditInvoice)) {
      if (!mounted) return;
      final approved = await requestManagerApproval(
        context,
        actionName: 'تعديل طريقة دفع فاتورة مرحّلة',
        permission: PermissionCodes.posEditInvoice,
      );
      if (!approved) return;
    }
    if (!mounted) return;
    await PosEditInvoiceDialog.show(context, invoice: invoice);
    _refocusScanner();
  }

  /// Drawer printer resolution mirrors the UralCash screen: a drawer-specific
  /// printer wins, then the receipt printer, then the OS default. Tills often
  /// have the drawer wired to the receipt printer's kick port, so the fallback
  /// is the common case rather than an error path.
  Future<String> _drawerPrinterName() async {
    try {
      final settings = ref.read(settingsRepositoryProvider);
      final drawer = await settings.getSetting('cash_drawer_printer');
      if (drawer != null && drawer.isNotEmpty) return drawer;
      final receipt = await settings.getSetting('receipt_printer');
      return receipt ?? 'Default';
    } catch (_) {
      return 'Default';
    }
  }

  /// زر `الدرج` الصريح — الكاشير طلب الفتح، ففشله لازم يقول.
  Future<void> _openDrawer() async {
    // الفتحُ اليدويُّ يفتح الدرجَ **بلا بيعة** — وهو ما يُراقَب. والركلةُ
    // التلقائيةُ على مسار الدفع (`_openCashDrawerQuietly`) لا تُحرَس عن قصد:
    // جزءٌ من إتمام بيعةٍ مأذونةٍ سلفاً، وحراستُها توقف الكاشيرَ في منتصف كلّ
    // فاتورة.
    if (!await ensureOpenCashDrawerPermission(ref, context)) return;
    if (!mounted) return;
    try {
      await CashDrawerService()
          .openDrawer(printerName: await _drawerPrinterName());
      final user = ref.read(authProvider).user;
      await ref.read(activityLoggerProvider).logCashDrawerOpen(
            user?.id ?? 0,
            user?.displayName ?? 'مستخدم',
          );
    } catch (e) {
      if (mounted) {
        showPosToast(context, ref, 'تعذّر فتح الدرج: $e',
            type: PosNotificationType.error);
      }
    }
    _refocusScanner();
  }

  /// الركلة الصامتة على مسار `دفع`.
  ///
  /// ── ليه صامتة ────────────────────────────────────────────────────────────
  /// الفاتورة اتحصّلت واتطبعت خلاص. توست أحمر عن الدرج على تِل مالوش درج أصلاً
  /// (وده تركيب شائع) كان معناه تحذير مع **كل** بيعة، والكاشير بيتعلّم يتجاهل
  /// التوستات كلها — بما فيها اللي بتقول إن الطباعة فشلت. الفشل بيتسجّل في
  /// `debugPrint` وخلاص. زر `الدرج` الصريح فوق هو اللي بيبلّغ.
  Future<void> _openCashDrawerQuietly() async {
    try {
      await CashDrawerService()
          .openDrawer(printerName: await _drawerPrinterName());
    } catch (e) {
      debugPrint('[PicPos-Drawer] فشل تشغيل الدرج: $e');
    }
  }
}

/// مُحدِّدُ الفاتورة لِـ«مرتجع سريع» — يسرد فواتير قابلةً للإرجاع (‏نفسُ
/// استبعاد `returnsRepository.getInvoicesForReturn`: مرحّلةٌ، غيرُ ملغاة،
/// غيرُ مرتجعةٍ بالكامل سلفاً) بلا سقفٍ زمنيّ — قرارُ المالك 2026-08-16
/// نفسُه المتَّبَع في شاشة «مرتجعات المبيعات» المستقلّة
/// (‏`sales_returns_picpos_logic.dart`): الإرجاعُ جائزٌ بعد فترةٍ، وسقفُ
/// أيامٍ كان يُخفي فاتورةً أقدمَ منه.
///
/// ويستبعد فواتيرَ التوصيل (‏`deliveryStatus` غيرُ فارغ) — I1، جولةُ إصلاح
/// ١: `getInvoicesForReturn` نفسُها لا تفلترها، والشاشةُ المستقلّةُ
/// (‏`sales_return_provider.selectInvoice`) ترفضها صراحةً («لا يمكن إرجاع
/// فواتير التوصيل»)؛ فبلا هذا الفلتر كان مسارُ «مرتجع سريع» يفتح ما تقفله
/// الشاشةُ المستقلّةُ عمداً.
///
/// يرجع الفاتورةَ المختارةَ عبر `Navigator.pop(context, invoice)`، أو
/// `null` عند الإلغاء.
class _QuickReturnInvoicePickerDialog extends ConsumerStatefulWidget {
  const _QuickReturnInvoicePickerDialog();

  @override
  ConsumerState<_QuickReturnInvoicePickerDialog> createState() =>
      _QuickReturnInvoicePickerDialogState();
}

class _QuickReturnInvoicePickerDialogState
    extends ConsumerState<_QuickReturnInvoicePickerDialog> {
  String _query = '';
  late final Future<List<SalesInvoiceData>> _invoicesFuture;

  // `future:` مبنيّةٌ **مرّةً واحدةً** في `initState` لا داخل `build` —
  // لو بُنيت داخل `build` كانت ستُعاد مع كلّ `setState` (كلّ ضغطةٍ في خانة
  // البحث)، فيرجع `FutureBuilder` إلى `ConnectionState.waiting` ويومض
  // مؤشّرَ تحميلٍ على كلّ حرف يكتبه الكاشير. الفلترةُ نفسُها محليّةٌ
  // (‏`_query`) فوق نتيجةٍ واحدةٍ مسحوبة.
  @override
  void initState() {
    super.initState();
    _invoicesFuture = ref
        .read(returnsRepositoryProvider)
        .getInvoicesForReturn(
          fromDate: DateTime(2000),
          toDate: DateTime.now(),
        )
        .then((invoices) => invoices
            .where((inv) =>
                inv.deliveryStatus == null || inv.deliveryStatus!.isEmpty)
            .toList());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.arrowUUpLeft, color: AppColors.error),
            SizedBox(width: 8),
            Text('اختر فاتورةً للمرتجع'),
          ],
        ),
        content: SizedBox(
          width: 480,
          height: 480,
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  hintText: 'بحث برقم الفاتورة',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<SalesInvoiceData>>(
                  future: _invoicesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                          child: Text('تعذّر التحميل: ${snapshot.error}'));
                    }
                    var invoices = snapshot.data ?? const <SalesInvoiceData>[];
                    if (_query.isNotEmpty) {
                      final q = _query.toLowerCase();
                      invoices = invoices
                          .where((inv) =>
                              inv.invoiceNumber.toLowerCase().contains(q))
                          .toList();
                    }
                    if (invoices.isEmpty) {
                      return const Center(
                        child: Text('لا توجد فواتيرُ قابلةٌ للإرجاع'),
                      );
                    }
                    return ListView.separated(
                      itemCount: invoices.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final inv = invoices[i];
                        return ListTile(
                          leading: const Icon(PhosphorIconsBold.receipt,
                              color: AppColors.info),
                          title: Text('فاتورة #${inv.invoiceNumber}'),
                          subtitle: Text(inv.total.toStringAsFixed(2)),
                          onTap: () => Navigator.pop(context, inv),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }
}

/// سطحُ اختيار أسطر المرتجع — يظهر بعد اختيار الفاتورة في `_showQuickReturn`
/// (المهمّة ٧، جولةُ إصلاح ١: يُغلق ما رفضه المراجعُ في C1–C3). الكاشيرُ لم
/// يكن يرى ما سيُرجَع ولا يتحكّم فيه، وسلّةُ البيع كانت دوماً فارغةً فأزرارُ
/// الدفع/الحفظ معطَّلة — راجع تعليقَ `_showQuickReturn`.
///
/// عمداً **لا** يكتب على `cartController` — قرارُ المراجع الصريح: «سلّةُ
/// البيع تقود الإجماليّاتِ والدفعَ والمخزون، وحشوُها بأسطرِ مرتجعٍ يخلط
/// مسارَين. واللوحةُ المخصَّصةُ أسلم». كلُّ الحالة هنا محليّةٌ لهذا الحوار
/// وحدَه، فوق [PosReturnMode] المُمرَّر (كائنٌ متغيّرٌ داخلياً — نفسُ
/// المرجع، لا نسخة).
///
/// يحقّق المطلوبَ السبعة في المراجعة:
///  ١. كلُّ سطرٍ يعرض الاسمَ والمباعَ والمرتجعَ سابقاً و**المتاح** والسعر.
///  ٢. الكميّاتُ تبدأ صفراً وتُضبط بعنصرِ تحكّم (‏+/- أو كيبوردٌ رقميّ لمسيّ).
///  ٣. كلُّ تعديلٍ يمرّ بـ`PosReturnMode.setQty`/`clearQty` — لا كتابةَ
///     مباشرةً في `requestedQty`.
///  ٤. السعرُ من `unitPriceOf`، لا من أيّ مصدرٍ آخر.
///  ٥. حقلُ البحث/الباركود يمرّ بـ`findReturnableLineForProduct` (خالصةٌ،
///     تستعمل `canAcceptProduct` داخلياً) ويرفض غيرَ المطابق برسالةٍ ظاهرة.
///  ٦. مبلغُ الاسترداد (`_refundTotal`) ظاهرٌ ويُعاد حسابُه مع كلّ تعديل.
///  ٧. «تأكيد المرتجع» يعمل بالماوس/اللمس دوماً، ومعطَّلٌ فقط حين تكون كلُّ
///     الكميّات أصفاراً (‏`_hasAnyQty`).
class _QuickReturnLinesEditorDialog extends ConsumerStatefulWidget {
  final PosReturnMode mode;
  final String invoiceNumber;

  const _QuickReturnLinesEditorDialog({
    required this.mode,
    required this.invoiceNumber,
  });

  @override
  ConsumerState<_QuickReturnLinesEditorDialog> createState() =>
      _QuickReturnLinesEditorDialogState();
}

class _QuickReturnLinesEditorDialogState
    extends ConsumerState<_QuickReturnLinesEditorDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  PosReturnMode get _mode => widget.mode;

  /// ٦: مبلغُ الاسترداد المعروض — يفوّض لـ`PosReturnMode.refundTotal`
  /// (‏نفسُ صيغة `ReturnsRepositoryImpl._calculateReturnTotal` بالحرف عبر
  /// `calculateReturnRefundTotal` المشتركة)، **لا** `Σ qty × unitPrice`.
  /// العطبُ المقيسُ في مراجعة 2026-08-16: `unitPrice` سعرُ البيع قبل
  /// الضريبة وقبل خصم السطر، بينما المصروفُ فعلياً من الدرج مبنيٌّ على
  /// `item.total` (شاملَ الضريبة وصافياً من الخصم) — فاتورةٌ بضريبة ١٤٪
  /// كانت تعرض أقلَّ ممّا يخرج من الدرج فعلياً بمقدار الضريبة تماماً.
  /// `unitPriceOf` **يبقى بلا تغيير** لعرض سعر السطر في `_buildLineRow` —
  /// هذا التغييرُ في مجموع الاسترداد وحدَه.
  double get _refundTotal => _mode.refundTotal;

  bool get _hasAnyQty => _mode.requestedQty.values.any((q) => q > 0);

  /// حقلُ البحث/الباركود — ٥: يمرّ بـ`findReturnableLineForProduct`
  /// (‏`canAcceptProduct` داخلياً) ويرفض غيرَ المطابق برسالةٍ ظاهرة، لا
  /// بإهمالٍ صامت.
  Future<void> _resolveSearch(String input) async {
    final code = input.trim();
    if (code.isEmpty) return;

    ProductEntity? product;
    try {
      product =
          await ref.read(productRepositoryProvider).getProductByBarcode(code);
      product ??=
          await ref.read(productRepositoryProvider).getProductByCode(code);
    } catch (_) {
      product = null;
    }

    _searchController.clear();
    if (!mounted) return;

    if (product == null) {
      showPosToast(context, ref, 'لم يُعثر على صنفٍ بهذا الباركود/الكود',
          type: PosNotificationType.warning);
      return;
    }

    final line = findReturnableLineForProduct(_mode, product.id);
    if (line == null) {
      final inInvoice = _mode.canAcceptProduct(product.id);
      showPosToast(
        context,
        ref,
        inInvoice
            ? 'كلُّ كمية «${product.name}» المتاحة للإرجاع طُلِبت بالفعل'
            : '«${product.name}» ليس ضمن أصناف هذه الفاتورة',
        type: PosNotificationType.warning,
      );
      return;
    }

    _increment(line);
  }

  /// ٣: نقطةُ الكتابة الوحيدة على `requestedQty` — دوماً عبر `setQty` أو
  /// `clearQty`، أبداً بكتابةٍ مباشرةٍ في الخريطة.
  ///
  /// ⚠️ المتطلَّبُ ٥ (جولةُ إصلاح ٢): **كلُّ** رفضٍ من `setQty` يُظهر توستاً
  /// يذكر المتاحَ — لا إهمالٌ صامت، حتى من نقطة استدعاءٍ تظنّ القيمةَ
  /// صالحةً سلفاً (‏دفاعٌ في العمق: `_increment` تحسب هدفاً محدوداً
  /// فلا يُفترَض بلوغُ هذا الفرع منه، والكيبورد يحصر القيمةَ بـ`min`/`max`
  /// بنفسه — لكن كلاهما يبقى مغطّى هنا احتياطاً).
  void _setQty(ReturnableLine line, double qty) {
    if (qty <= 0) {
      setState(() => _mode.clearQty(line.invoiceItemId));
      return;
    }
    final ok = _mode.setQty(line.invoiceItemId, qty);
    if (!ok) {
      showPosToast(
        context,
        ref,
        'الكميةُ مرفوضة — أقصى متاحٍ لـ«${line.productName}» '
        '${line.availableQty.toStringAsFixed(2)}',
        type: PosNotificationType.error,
      );
      return;
    }
    setState(() {});
  }

  /// يزيد كميّةَ [line] خطوةً واحدة عبر [nextIncrementedQty] (‏القصُّ على
  /// المتاح خالصٌ ومُختبَرٌ هناك). أسلمُ تطبيقٍ للمتطلَّب ٥ هو ألّا يقعَ
  /// الرفضُ إطلاقاً حين يكون العنصرُ تحت تحكّم البرنامج (زرّ «+» أو مسحةُ
  /// باركود)، لا اختيارَ الكاشير حرفياً — فيُظهر توستاً بدل الرفض الصامت
  /// حين لا مجالَ للزيادة.
  void _increment(ReturnableLine line) {
    final current = _mode.requestedQty[line.invoiceItemId] ?? 0;
    final target = nextIncrementedQty(line, current);
    if (target == null) {
      showPosToast(
        context,
        ref,
        'بلغتَ الحدَّ الأقصى المتاح لـ«${line.productName}» '
        '(${line.availableQty.toStringAsFixed(2)})',
        type: PosNotificationType.warning,
      );
      return;
    }
    _setQty(line, target);
  }

  Future<void> _editQtyViaKeypad(ReturnableLine line) async {
    final current = _mode.requestedQty[line.invoiceItemId] ?? 0;
    final result = await PicPosNumericKeypadDialog.show(
      context,
      title: 'كميةُ إرجاع «${line.productName}»',
      initialValue: current,
      decimals: 3,
      min: 0,
      max: line.availableQty,
    );
    if (result == null || !mounted) return;
    _setQty(line, result);
  }

  /// اختصارٌ اختياريّ — ليس بديلاً عن التحكّم سطراً سطراً، بل نقطةَ بدءٍ
  /// سريعة تبقى قابلةً للتعديل بعدها (تمرّ بـ`setQty` مثل أيّ تعديلٍ آخر).
  void _selectAllFull() {
    setState(() {
      for (final line in _mode.linesByItemId.values) {
        _mode.setQty(line.invoiceItemId, line.availableQty);
      }
    });
  }

  void _clearAll() {
    setState(() {
      for (final line in _mode.linesByItemId.values) {
        _mode.clearQty(line.invoiceItemId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = _mode.linesByItemId.values.toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.arrowUUpLeft, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'أصنافُ الإرجاع — فاتورة #${widget.invoiceNumber}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'باركود أو كود الصنف — يزيد الكميةَ سطراً بسطر',
                  isDense: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(PhosphorIconsBold.barcode, size: 18),
                ),
                onSubmitted: _resolveSearch,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _selectAllFull,
                    icon: const Icon(PhosphorIconsBold.checkCircle, size: 16),
                    label: const Text('تحديد الكلّ (مرتجعٌ كامل)'),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _hasAnyQty ? _clearAll : null,
                    icon: const Icon(PhosphorIconsBold.xCircle, size: 16),
                    label: const Text('تصفيرُ الكلّ'),
                  ),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: lines.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _buildLineRow(lines[i]),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Text('مبلغُ الاسترداد',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(
                      _refundTotal.toStringAsFixed(2),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          // ٧: يعمل بالماوس/اللمس دوماً — لا يعتمد على سلّة البيع إطلاقاً،
          // ومعطَّلٌ فقط حين تكون كلُّ الكميّات أصفاراً.
          ElevatedButton.icon(
            onPressed: _hasAnyQty ? () => Navigator.pop(context, true) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(PhosphorIconsBold.check, size: 18),
            label: const Text('تأكيد المرتجع'),
          ),
        ],
      ),
    );
  }

  Widget _buildLineRow(ReturnableLine line) {
    final qty = _mode.requestedQty[line.invoiceItemId] ?? 0;
    final atMax = qty >= line.availableQty - 0.0005;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.productName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                // ١: المباع، المرتجعُ سابقاً، المتاح، السعر — الأربعةُ معاً.
                Text(
                  'مباع ${line.soldQty.toStringAsFixed(2)} · مرتجعٌ سابقاً '
                  '${line.alreadyReturnedQty.toStringAsFixed(2)} · متاح '
                  '${line.availableQty.toStringAsFixed(2)} · السعر '
                  '${_mode.unitPriceOf(line.invoiceItemId).toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsBold.minusCircle, size: 20),
            // `pos_item_minus` — كان محروساً في النظير القديم وحدَه
            // (`pos/widgets/cart_item_tile.dart:302`) على زرِّ «−» لكمية
            // صنفٍ في سلّة البيع. جدولُ PicPos أُعيدت كتابتُه بلا مِسطرةِ
            // خطوةٍ لتلك السلّة، فهذا أوّلُ سطحٍ حيٍّ للكود في PicPos.
            onPressed: qty > 0
                ? () async {
                    if (!await ensureDecrementReturnLinePermission(
                        ref, context)) {
                      return;
                    }
                    _setQty(line, qty - 1);
                  }
                : null,
          ),
          InkWell(
            onTap:
                line.availableQty > 0 ? () => _editQtyViaKeypad(line) : null,
            child: Container(
              width: 48,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: context.picposHairline),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                qty == qty.truncateToDouble()
                    ? qty.toStringAsFixed(0)
                    : qty.toStringAsFixed(2),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsBold.plusCircle, size: 20),
            // `pos_item_plus` — نفسُ قصّة `pos_item_minus` فوق، على زرِّ «+»
            // (`cart_item_tile.dart:381`).
            onPressed: !atMax
                ? () async {
                    if (!await ensureIncrementReturnLinePermission(
                        ref, context)) {
                      return;
                    }
                    _increment(line);
                  }
                : null,
          ),
          if (qty > 0)
            IconButton(
              icon: const Icon(PhosphorIconsBold.x,
                  size: 16, color: AppColors.error),
              tooltip: 'استبعادُ الصنف من المرتجع',
              onPressed: () => _setQty(line, 0),
            ),
        ],
      ),
    );
  }
}
