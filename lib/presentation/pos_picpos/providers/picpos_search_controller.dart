import 'package:ural_erp/core/i18n/tr.dart';
// متحكّمُ بحثِ الباركود — نسخةُ PicPos.
//
// ═══ لماذا نسخةٌ لا استعمالٌ للمشترَك ═══
//
// الأصلُ `pos/providers/pos_search_controller.dart` يخدم شاشةَ UralCash
// وشاشةَ الطاولات، والعملُ على UralCash موقوفٌ منذ 2026-08-22. و«سؤال عن
// الكمية قبل الإضافة» (§٤ `askqty`) يحتاج التدخّلَ **قبل** الإضافة للسلّة —
// أي داخلَ هذا المتحكّم بالضبط. فتعديلُ الأصل كان سيغيّر شاشتَين مجمّدتَين.
//
// ⚠️ **ولا رمزَ مشترَكٌ بين النسختين**: حتّى `BarcodeSearchErrorKind` مستقلٌّ
// هنا (`PicposBarcodeSearchErrorKind`). نوعٌ مشترَكٌ واحدٌ كان يكفي ليجعل
// تعديلاً في PicPos يرتدَّ على UralCash عبر تغييرِ قيمةٍ في التعداد.
//
// ═══ الفروقُ المقصودةُ عن الأصل — أربعةٌ لا أكثر ═══
//
//   ١. `askQuantity` — خطّافٌ تحقنه الشاشةُ ليسأل عن الكمية قبل الإضافة.
//   ٢. `_addItemWithUnit` تقبل `quantity` وتمرّرها لـ`cart.addItem`.
//   ٣. مواضعُ إضافةِ الصنف العاديّ تستشير الخطّافَ أوّلاً.
//   ٤. بوّابةُ وضع العميل تمرّ بـ`isClientModeProvider` لا باستيراد
//      `data/database/sync_interceptor.dart` مباشرةً — `presentation_db_
//      import_guard` يمنع ملفَّ عرضٍ **جديداً** من ذلك، والأصلُ في القائمة
//      البيضاء فسُمح له وحدَه. والقيمةُ **نفسُها**: المزوِّدُ يُرجع
//      `SyncInterceptor.isClientMode` حرفيّاً، فالطريقُ وحدَه تبدّل.
//
// وما عدا ذلك منسوخٌ كما هو عمداً: مسارُ الميزان، وتحذيرُ الوزن المكرّر،
// ونغماتُ النجاح والخطأ، ومنعُ التكديس — كلُّها سلوكٌ مقيسٌ ومُختبَر.
import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../domain/usecases/sales/add_to_cart_usecase.dart'
    show resolveStackingFlags;
import '../../../services/server_proxy.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:shared_preferences/shared_preferences.dart';
import '../../pos/services/scale_barcode_handler.dart';
import '../../pos/providers/cart_controller.dart';

// Spec 116 — diagnostic breadcrumbs قبل كل عملية حساسة في barcode chain.
// لو حدث crash native، آخر سطر [BARCODE-STEP] في diagnostic.log يُحدّد
// الخطوة فيمكن تشخيص السبب الجذري في Spec 117 (راجع specs/116/research.md).
void _logBarcodeStep(String step, String details) {
  unawaited(
    DiagnosticLogger.log('BARCODE-STEP', '$step: $details')
        .catchError((_) {}),
  );
}

/// Feature 013 / Issue BARCODE-INACTIVE — typed reason for a barcode
/// search that did not result in adding a product to the cart. The POS
/// barcode handler uses this to decide whether to show the quick-add
/// dialog (only on [notFound]) or just a toast (everything else).
enum PicposBarcodeSearchErrorKind {
  /// The barcode is genuinely unknown — show the quick-add prompt.
  notFound,

  /// The product exists but is marked inactive — show explanatory toast,
  /// do NOT prompt to create a duplicate.
  inactive,

  /// Scale barcode (length 13, leading 2) whose PLU number doesn't
  /// match any product. Different fix path from a normal "not found".
  invalidScale,

  /// Any other failure (server error, lookup exception, etc.). Show the
  /// error string but do not prompt to create a new product.
  general,
}

class PicposSearchState {
  final bool isSearchActive;
  final List<ProductEntity> searchResults;
  final String? error;
  final PicposBarcodeSearchErrorKind? errorKind;
  /// Warning raised when the cashier tries to add the SAME (product,
  /// weight) pair twice within 30s via the LIVE digital-scale flow
  /// (product tap → weight dialog → counter scale). The UI layer renders
  /// this as a blocking popup dialog and clears the flag via
  /// `clearDuplicateWeightWarning()`.
  ///
  /// IMPORTANT: never set from the barcode-scan path — scale-label scans
  /// are legitimately allowed to have identical (product, weight) pairs.
  final String? duplicateWeightWarning;

  const PicposSearchState({
    this.isSearchActive = false,
    this.searchResults = const [],
    this.error,
    this.errorKind,
    this.duplicateWeightWarning,
  });

  PicposSearchState copyWith({
    bool? isSearchActive,
    List<ProductEntity>? searchResults,
    String? error,
    PicposBarcodeSearchErrorKind? errorKind,
    String? duplicateWeightWarning,
    bool clearDuplicateWarning = false,
    bool clearError = false,
  }) {
    return PicposSearchState(
      isSearchActive: isSearchActive ?? this.isSearchActive,
      searchResults: searchResults ?? this.searchResults,
      error: clearError ? null : (error ?? this.error),
      errorKind: clearError ? null : (errorKind ?? this.errorKind),
      duplicateWeightWarning: clearDuplicateWarning
          ? null
          : (duplicateWeightWarning ?? this.duplicateWeightWarning),
    );
  }
}

class PicposSearchController extends Notifier<PicposSearchState> {
  @override
  PicposSearchState build() => const PicposSearchState();

  final AudioPlayer _audioPlayer = AudioPlayer();

  // Spec 116 (L2) — audio play قد يُسبّب async error من audioplayers plugin
  // (concurrency على rapid scan، audio device contention). نُشير على
  // الـ Future بـ .catchError لمنع unhandled async error من صعوده.
  // الـ try/catch sync يبقى للـ exceptions اللحظية (asset غير موجود مثلاً).
  void _safePlay(String asset, String tagDetail) {
    try {
      final f = _audioPlayer.play(AssetSource(asset));
      f.catchError((Object e, StackTrace st) {
        unawaited(
          DiagnosticLogger.log(
            'AUDIO-PLAY-FAIL',
            '$tagDetail asset=$asset async error=$e\n$st',
          ).catchError((_) {}),
        );
      });
    } catch (e, st) {
      unawaited(
        DiagnosticLogger.log(
          'AUDIO-PLAY-FAIL',
          '$tagDetail asset=$asset sync error=$e\n$st',
        ).catchError((_) {}),
      );
    }
  }

  void _playSuccessBeep() {
    _logBarcodeStep('audio', 'success-beep');
    _safePlay('audio/barcode_beep.wav', 'success-beep');
  }

  void _playErrorBeep() {
    _logBarcodeStep('audio', 'error-beep');
    _safePlay('audio/error_beep.wav', 'error-beep');
  }

  /// Audible alert for duplicate weight — reuses the error beep so the
  /// cashier immediately hears something different from the success beep.
  void _playDuplicateWeightBeep() {
    _logBarcodeStep('audio', 'duplicate-weight-beep');
    _safePlay('audio/error_beep.wav', 'duplicate-weight-beep');
  }

  /// يضيف صنفاً بباركود **وحدةِ تغليف** ويثبّت التحويلَ على السطر الذي تأثّر
  /// فعلاً — لا على أوّل سطرٍ لنفس الصنف.
  ///
  /// كان الموضعان يناديان `addItem` ثم `indexWhere((i) => i.productId == …)`،
  /// و`indexWhere` يرجّع **أوّل** مطابقة. و`AddToCartUseCase` لا يدمج حين
  /// يختلف السعر (سعرُ الكرتونة ≠ سعرُ القطعة) فيُلحق سطراً جديداً — فينزل
  /// التحويلُ والسعرُ على سطر القطعة القديم بدل المُلحَق.
  ///
  /// مقيس: امسح قطعة ← قطعة ← كرتونة ⇒ الإجمالي **١٥٠ بدل ٦٠** (زيادةُ ٩٠
  /// على العميل) و**٢٥ وحدةً تُخصم بدل ١٤** (١١ وحدةً وهمية تخرج من المحل).
  ///
  /// ولـ`addItem` ثلاثةُ مآلات، والدالةُ تميّزها:
  /// * أُلحق سطرٌ جديد ⇒ الهدفُ آخرُ سطر.
  /// * اندمج في سطرٍ قائم ⇒ الهدفُ سطرُ الدمج (أوّلُ مطابقةٍ نمت كميّتُها).
  /// * **رُفض صامتاً** (حارسُ المخزون في `addItem` يرجع بلا أثر) ⇒ لا سطرَ
  ///   يُوسَم إطلاقاً. بدون هذا الفرق كان الرفضُ يَسِم سطراً قديماً بوحدةٍ
  ///   وسعرٍ لم يطلبهما أحد.
  /// خطّافُ «سؤال عن الكمية قبل الإضافة» (§٤ `askqty`) على مسار المسح.
  ///
  /// ⚠️ **لماذا خطّافٌ لا قراءةُ سياسةٍ هنا**: هذا `Notifier` بلا
  /// `BuildContext`، فلا يفتح حواراً. والشاشةُ تملك السياقَ ولوحةَ
  /// الأرقام، فهي تحقن الدالّةَ وتبقى القرارُ عندها.
  ///
  /// و`null` مآلان مختلفان: الحقلُ غيرُ محقونٍ ⇒ وحدةٌ واحدةٌ (‏السلوكُ
  /// القائم)، والدالّةُ ترجع `null` ⇒ **ألغى الكاشيرُ فلا يُضاف شيء**.
  Future<double?> Function(ProductEntity product)? askQuantity;

  /// كميّةُ السطر لصنفٍ ممسوح — `null` تعني إلغاءً صريحاً.
  Future<double?> _resolveScanQuantity(ProductEntity product) async {
    final ask = askQuantity;
    if (ask == null) return 1;
    // الموزونُ يحمل وزنَه في الباركود أو يمرّ بمسار الميزان — وسؤالُه عن
    // «كم عدداً» سؤالٌ بلا معنى، ويهدم قراءةَ الميزان حين تكون صحيحة.
    if (product.isSoldByWeight) return 1;
    return ask(product);
  }

  void _addItemWithUnit({
    required ProductEntity product,
    required int unitId,
    required String unitName,
    required double quantityInBase,
    required double unitPrice,
    required bool forceNewEntry,
    required bool mergeWeight,
    double quantity = 1,
  }) {
    final cart = ref.read(cartControllerProvider.notifier);
    final before = ref.read(cartControllerProvider).items;
    final firstIdx = before.indexWhere((i) => i.productId == product.id);
    final beforeQty = firstIdx == -1 ? null : before[firstIdx].quantity;

    cart.addItem(
      product,
      quantity: quantity,
      customPrice: unitPrice,
      forceNewEntry: forceNewEntry,
      mergeWeight: mergeWeight,
    );

    final after = ref.read(cartControllerProvider).items;
    final int target;
    if (after.length > before.length) {
      target = after.length - 1;
    } else if (beforeQty != null && after[firstIdx].quantity > beforeQty) {
      target = firstIdx;
    } else {
      return; // رفضٌ صامت — لا شيء أُضيف
    }

    cart.updateItemUnit(
      target,
      unitId: unitId,
      unitName: unitName,
      quantityInBase: quantityInBase,
      unitSalePrice: unitPrice,
    );
  }

  /// Called by the UI after it has shown the duplicate-weight popup, to
  /// clear the state flag so the next add doesn't re-trigger on stale
  /// data.
  void clearDuplicateWeightWarning() {
    if (state.duplicateWeightWarning != null) {
      state = state.copyWith(clearDuplicateWarning: true);
    }
  }

  /// Public entry-point ONLY for the live digital-scale flow
  /// (`_addProductToCart` after the weight input dialog returns).
  ///
  /// Checks `cartController.isDuplicateWeightAdd(productId, weightKg)` —
  /// if true, plays the alert beep and stores a warning message on
  /// `state.duplicateWeightWarning`. The UI layer picks it up and
  /// renders a blocking popup ("تنبيه: نفس الوزن" with a "متابعة" button).
  ///
  /// DO NOT call from the barcode-scan path. Pre-weighed scale labels
  /// can legitimately have duplicate (product, weight) pairs.
  ///
  /// Returns `true` if a duplicate was detected (caller still proceeds
  /// with the add — the popup is advisory, not rejecting).
  bool checkAndWarnDuplicateWeight({
    required int productId,
    required String productName,
    required double weightKg,
  }) {
    final cartCtl = ref.read(cartControllerProvider.notifier);
    final isDup = cartCtl.isDuplicateWeightAdd(productId, weightKg);
    if (isDup) {
      _playDuplicateWeightBeep();
      state = state.copyWith(
        duplicateWeightWarning:
            tr('نفس الوزن ({p0} كجم) تم إضافته لصنف "{productName}" من قبل — غيّر الوزن على الميزان لتجنب التكرار.', {'p0': weightKg.toStringAsFixed(3), 'productName': productName}),
      );
    }
    return isDup;
  }

  /// Search for a product by barcode — exact match only.
  ///
  /// Flow:
  /// 1. Scale barcode (starts with '2', 13 digits) → parse weight/price
  /// 2. Exact barcode match (products table + product_barcodes table)
  /// 3. Exact internal code match
  /// 4. Offer barcode match
  /// 5. If nothing found → error (NO name search — that's separate in the grid)
  Future<void> searchBarcode(String barcode) async {
    // Spec 116 (L1) \u2014 defensive wrap \u0639\u0644\u0649 \u0627\u0644\u0645\u0633\u062A\u0648\u0649 method. \u0623\u064A Dart exception
    // \u0645\u0646 DB lookups\u060C cart adds\u060C scale parsing\u060C \u0623\u0648 dialog logic \u064A\u064F\u0644\u062A\u0642\u0637 \u0647\u0646\u0627
    // \u0648\u0644\u0627 \u064A\u0635\u0639\u062F \u0644\u064A\u0643\u0633\u0631 \u0627\u0644\u0640 POS. \u0627\u0644\u0640 exception \u064A\u064F\u0633\u062C\u064E\u0651\u0644 \u0628\u0640 [BARCODE-CRASH] \u0648
    // state.error \u064A\u064F\u062D\u0648\u064E\u0651\u0644 \u0625\u0644\u0649 \u062A\u0648\u0633\u062A \u0639\u0631\u0628\u064A \u0639\u0628\u0631 \u0627\u0644\u0640 UI consumer.
    final rawBarcode = barcode;
    try {

    // Sanitize comprehensive scanner input anomalies (Invisible chars, spaces, LRM)
    barcode = barcode.trim()
                     .replaceAll(RegExp(r'\s+'), '')
                     .replaceAll('\u200E', '')
                     .replaceAll('\u200F', '');

    // Read prevent-stacking setting once for all addItem calls in this search.
    // It is NOT passed straight through as `forceNewEntry` any more — the
    // setting only governs weighed items (see `resolveStackingFlags`), so each
    // add site resolves it against the product it is actually adding.
    final preventStacking =
        ref.read(preventItemStackingProvider).value ?? false;
    // Scale-label paths always add a weighed product, so their flags are fixed.
    final scaleStacking = resolveStackingFlags(
      isSoldByWeight: true,
      preventStacking: preventStacking,
    );

    if (barcode.isEmpty) {
      state = state.copyWith(
        searchResults: [],
        isSearchActive: false,
        clearError: true,
      );
      return;
    }

    final productRepo = ref.read(productRepositoryProvider);
    final offersRepo = ref.read(offersRepositoryProvider);

    debugPrint('[BarcodeSearch] Looking up: "$barcode"');

    // ═══ Step 1: Scale barcode detection ═══
    if (barcode.length == 13 && barcode.startsWith('2')) {
      _logBarcodeStep('scale-parse', barcode);
      final scaleResult = await ScaleBarcodeHandler.tryParse(
        RepositoryBarcodeAdapter(ref),
        barcode,
      );
      if (scaleResult != null) {
        // NOTE: Deliberately NO duplicate-weight check here.
        //
        // Scale-label barcodes come pre-weighed from a label scale (Fire
        // Bird / Aclas etc.). Each label represents a distinct weighing
        // done elsewhere — two identical labels for "500g meat" are two
        // legitimate, separate purchases. The duplicate-weight guard only
        // makes sense for the LIVE counter-scale flow (see
        // `checkAndWarnDuplicateWeight` called from `_addProductToCart`).
        final cartCtl = ref.read(cartControllerProvider.notifier);
        cartCtl.addItem(
          scaleResult.product,
          quantity: scaleResult.quantity,
          mergeWeight: scaleStacking.mergeWeight,
          forceNewEntry: scaleStacking.forceNewEntry,
        );
        state = state.copyWith(searchResults: [], clearError: true);
        _playSuccessBeep();
        debugPrint('[BarcodeSearch] ✓ Scale barcode → ${scaleResult.product.name}');
        return;
      }
      // Scale handler failed — try direct code/PLU lookup as last resort
      final pluPart = barcode.substring(2, 7);
      final pluInt = int.tryParse(pluPart);
      final trimmedPlu = pluPart.replaceFirst(RegExp(r'^0+'), '');
      debugPrint('[BarcodeSearch] Scale handler failed. Trying direct PLU fallback: "$pluPart" (int=$pluInt)');

      // Direct fallback: try code, trimmed code, barcode, PLU
      ProductEntity? fallbackProduct;
      fallbackProduct ??= await productRepo.getProductByCode(pluPart);
      if (fallbackProduct == null && trimmedPlu.isNotEmpty && trimmedPlu != pluPart) {
        fallbackProduct = await productRepo.getProductByCode(trimmedPlu);
      }
      fallbackProduct ??= await productRepo.getProductByBarcode(pluPart);
      if (fallbackProduct == null && pluInt != null) {
        fallbackProduct = await productRepo.getProductByScalePlu(pluInt);
      }

      if (fallbackProduct != null) {
        // Parse weight/price from barcode value section
        final valueStr = barcode.substring(7, 12);
        final rawValue = double.tryParse(valueStr) ?? 0;
        final quantity = rawValue / 1000.0; // default weight divider
        ref.read(cartControllerProvider.notifier).addItem(
          fallbackProduct,
          quantity: quantity > 0 ? quantity : 1,
          mergeWeight: scaleStacking.mergeWeight,
          forceNewEntry: scaleStacking.forceNewEntry,
        );
        state = state.copyWith(searchResults: [], clearError: true);
        _playSuccessBeep();
        debugPrint('[BarcodeSearch] ✓ Scale fallback found: ${fallbackProduct.name} (qty=$quantity)');
        return;
      }

      _playErrorBeep();
      state = state.copyWith(
        error: tr('باركود ميزان: رقم PLU المستخرج "{pluPart}" (={pluInt}) غير مطابق لأي صنف.\nتأكد من تسجيل رقم PLU في إعدادات الصنف أو مطابقة كود الصنف.', {'pluPart': pluPart, 'pluInt': pluInt}),
        errorKind: PicposBarcodeSearchErrorKind.invalidScale,
        searchResults: [],
        isSearchActive: false,
      );
      return;
    }

    // ═══ Step 2: Parallel barcode + unit lookup (PERF FIX) ═══
    // ISS-06: Route unit barcode lookup through unitByBarcodeProvider
    _logBarcodeStep('db-lookup', 'unit+product byBarcode="$barcode"');
    final unitRecord = await ref.read(unitByBarcodeProvider(barcode).future);
    var product = await productRepo.getProductByBarcode(barcode);

    // If product wasn't found by raw barcode, but it matched a specific unit's barcode
    if (product == null && unitRecord != null) {
      product = await productRepo.getProductById(unitRecord.productId);
    }

    // ═══ Step 3: Exact internal code match ═══
    product ??= await productRepo.getProductByCode(barcode);

    // ═══ Step 3.5: Fallback — Strip leading zeroes ═══
    if (product == null && unitRecord == null) {
      final trimmedBarcode = barcode.replaceFirst(RegExp(r'^0+'), '');
      if (trimmedBarcode.isNotEmpty && trimmedBarcode != barcode) {
        debugPrint('[BarcodeSearch] Falling back to trimmed zeros: "$trimmedBarcode"');

        // Run trimmed lookups in parallel too
        // ISS-06: Raw DB access needed for barcode trimming + server cache writes below
        final db = ref.read(databaseProvider);
        final checkUnit = await db.getUnitByBarcode(trimmedBarcode);
        product = await productRepo.getProductByBarcode(trimmedBarcode);

        if (checkUnit != null && product == null) {
          product = await productRepo.getProductById(checkUnit.productId);
        }

        if (checkUnit != null && product != null) {
          final unitPrice = checkUnit.salePrice > 0
              ? checkUnit.salePrice
              : product.salePrice;
          final unitStacking = resolveStackingFlags(
            isSoldByWeight: product.isSoldByWeight,
            preventStacking: preventStacking,
          );
          final askedQty = await _resolveScanQuantity(product);
          if (askedQty == null) {
            state = state.copyWith(searchResults: [], clearError: true);
            return;
          }
          _addItemWithUnit(
            product: product,
            unitId: checkUnit.id,
            unitName: checkUnit.unitName,
            quantityInBase: checkUnit.quantityInBase,
            unitPrice: unitPrice,
            forceNewEntry: unitStacking.forceNewEntry,
            mergeWeight: unitStacking.mergeWeight,
            quantity: askedQty,
          );
          state = state.copyWith(searchResults: [], clearError: true);
          _playSuccessBeep();
          debugPrint('[BarcodeSearch] ✓ Found Unit (trimmed zeros): ${product.name}');
          return;
        }

        product ??= await productRepo.getProductByCode(trimmedBarcode);
      }
    }

    if (product != null) {
      final productStacking = resolveStackingFlags(
        isSoldByWeight: product.isSoldByWeight,
        preventStacking: preventStacking,
      );
      final askedQty = await _resolveScanQuantity(product);
      if (askedQty == null) {
        state = state.copyWith(searchResults: [], clearError: true);
        return;
      }
      if (unitRecord != null) {
        final unitPrice = unitRecord.salePrice > 0 ? unitRecord.salePrice : product.salePrice;
        _addItemWithUnit(
          product: product,
          unitId: unitRecord.id,
          unitName: unitRecord.unitName,
          quantityInBase: unitRecord.quantityInBase,
          unitPrice: unitPrice,
          forceNewEntry: productStacking.forceNewEntry,
          mergeWeight: productStacking.mergeWeight,
          quantity: askedQty,
        );
      } else {
        ref.read(cartControllerProvider.notifier).addItem(
              product,
              quantity: askedQty,
              forceNewEntry: productStacking.forceNewEntry,
              mergeWeight: productStacking.mergeWeight,
            );
      }
      
      state = state.copyWith(searchResults: [], clearError: true);
      _playSuccessBeep();
      debugPrint('[BarcodeSearch] ✓ Found: ${product.name}');
      return;
    }

    // ═══ Step 4: Offer barcode match ═══
    _logBarcodeStep('offers-lookup', barcode);
    try {
      final allOffers = await offersRepo.getOffers();
      final offer = allOffers.where((o) => o.barcode == barcode).firstOrNull;
      if (offer != null) {
        final outcome =
            await ref.read(cartControllerProvider.notifier).applyOffer(offer);
        // الباركود اتطابق فعلاً، فالمسار بينتهي هنا في كل الحالات — بس بيب
        // النجاح لازم يبقى مقصور على الإضافة الحقيقية. من غير الفرق ده كان
        // العرض المرفوض بيدّي نفس صوت العرض اللي اتضاف.
        if (outcome == ApplyOfferOutcome.added) {
          state = state.copyWith(searchResults: [], clearError: true);
          _playSuccessBeep();
          debugPrint('[BarcodeSearch] ✓ Offer matched');
        } else {
          _playErrorBeep();
          state = state.copyWith(
            error: switch (outcome) {
              ApplyOfferOutcome.alreadyInCart =>
                tr('العرض "{p0}" مضاف بالفعل إلى السلة.', {'p0': offer.name}),
              ApplyOfferOutcome.notADiscount =>
                tr('العرض "{p0}" سعره أعلى من مجموع أسعار بيع أصنافه — اترفض عشان ما يرفعش الأسعار. راجع سعر العرض.', {'p0': offer.name}),
              _ => tr('تعذّر تطبيق العرض "{p0}" — تأكد من أصناف العرض.', {'p0': offer.name}),
            },
            errorKind: PicposBarcodeSearchErrorKind.general,
            searchResults: [],
          );
          debugPrint('[BarcodeSearch] ✗ Offer rejected: $outcome');
        }
        return;
      }
    } catch (e) {
      debugPrint('[BarcodeSearch] Offer lookup error: $e');
    }

    // ═══ Step 5 (CLIENT MODE): Server barcode fallback ═══
    // If the product isn't in the local cache (e.g. assigned to a different
    // warehouse not included in the branch sync), ask the server directly.
    if (ref.read(isClientModeProvider)) {
      _logBarcodeStep('server-fallback', barcode);
      try {
        debugPrint('[BarcodeSearch] Local miss — trying server barcode lookup...');
        final prefs = await SharedPreferences.getInstance();
        final clientBranchId = prefs.getInt('client_branch_id');
        final serverResult = await ServerProxy.instance.fetchProductByBarcode(barcode, branchId: clientBranchId);
        if (serverResult != null && serverResult['found'] == true) {
          final pd = serverResult['product'] as Map<String, dynamic>;
          final barcodes = serverResult['barcodes'] as List? ?? [];

          // Cache product locally so future scans are instant
          // ISS-06: Raw DB access needed for server→local product cache writes
          final db = ref.read(databaseProvider);
          await db.into(db.products).insertOnConflictUpdate(
            ProductsCompanion(
              id: Value(pd['id'] as int),
              code: Value(pd['code'] as String? ?? ''),
              barcode: Value(pd['barcode'] as String?),
              name: Value(pd['name'] as String),
              searchName: Value(pd['searchName'] as String?),
              categoryId: Value(pd['categoryId'] as int?),
              unitId: Value(pd['unitId'] as int? ?? 1),
              salePrice: Value((pd['salePrice'] as num).toDouble()),
              wholesalePrice: Value((pd['wholesalePrice'] as num? ?? 0).toDouble()),
              costPrice: Value((pd['costPrice'] as num? ?? 0).toDouble()),
              currentStock: Value((pd['currentStock'] as num? ?? 0).toDouble()),
              isActive: Value(pd['isActive'] as bool? ?? true),
              taxRate: Value((pd['taxRate'] as num? ?? 0).toDouble()),
              trackInventory: Value(pd['trackInventory'] as bool? ?? true),
              isSoldByWeight: Value(pd['isSoldByWeight'] as bool? ?? false),
              allowNegativeSale: Value(pd['allowNegativeSale'] as bool? ?? false),
            ),
          );
          for (final b in barcodes) {
            final bm = b as Map<String, dynamic>;
            await db.into(db.productBarcodes).insertOnConflictUpdate(
              ProductBarcodesCompanion(
                id: Value(bm['id'] as int),
                productId: Value(bm['productId'] as int),
                barcode: Value(bm['barcode'] as String),
                isPrimary: Value(bm['isPrimary'] as bool? ?? false),
              ),
            );
          }

          // Re-lookup from local DB to get full ProductEntity
          product = await productRepo.getProductByBarcode(barcode);
          if (product != null) {
            final serverStacking = resolveStackingFlags(
              isSoldByWeight: product.isSoldByWeight,
              preventStacking: preventStacking,
            );
            // مسارُ السحب من الخادم يضيف صنفاً عاديّاً كسائر المسارات،
            // فيستشير الكميةَ مثلَها. وإغفالُه كان يجعل «سؤال عن الكمية»
            // يعمل محلّيّاً ويصمت على أوّل صنفٍ يأتي من المركز — أي على
            // الأصناف الجديدة تحديداً، وهي أولى ما يُسأل عن كميّته.
            final serverQty = await _resolveScanQuantity(product);
            if (serverQty == null) {
              state = state.copyWith(searchResults: [], clearError: true);
              return;
            }
            ref.read(cartControllerProvider.notifier).addItem(
                  product,
                  quantity: serverQty,
                  forceNewEntry: serverStacking.forceNewEntry,
                  mergeWeight: serverStacking.mergeWeight,
                );
            state = state.copyWith(searchResults: [], clearError: true);
            _playSuccessBeep();
            debugPrint('[BarcodeSearch] ✓ Found via server fallback: ${product.name}');
            return;
          }
        }
      } catch (e) {
        debugPrint('[BarcodeSearch] Server fallback error: $e');
      }
    }

    // ═══ Not found (with Diagnostic check) ═══
    debugPrint('[BarcodeSearch] ✗ Not found in active products: $barcode');

    // Check if it exists but is inactive
    final inactiveProduct = await productRepo.getProductAnyStatusByBarcode(barcode);
    if (inactiveProduct != null) {
      debugPrint('[BarcodeSearch] ! Diagnostic: Product exists but is INACTIVE: ${inactiveProduct.name}');
      _playErrorBeep();
      state = state.copyWith(
        error: tr('عفواً، الصنف ({p0}) موجود ولكنه "غير نشط".\nيرجى تفعيله من شاشة الأصناف ليظهر في البيع السريع.', {'p0': inactiveProduct.name}),
        errorKind: PicposBarcodeSearchErrorKind.inactive,
        searchResults: [],
        isSearchActive: false,
      );
      return;
    }

    _playErrorBeep();
    state = state.copyWith(
      error: tr('لم يتم العثور على منتج بهذا الباركود: "{barcode}"', {'barcode': barcode}),
      errorKind: PicposBarcodeSearchErrorKind.notFound,
      searchResults: [],
      isSearchActive: false,
    );
    debugPrint('[BarcodeSearch] ✗ Completely unknown: "$barcode"');
    } catch (e, st) {
      // Spec 116 (L1) — defensive catch. لا تُسقط الـ POS.
      unawaited(
        DiagnosticLogger.log(
          'BARCODE-CRASH',
          'controller barcode="$rawBarcode" error=$e\n$st',
        ).catchError((_) {}),
      );
      debugPrint('[BarcodeSearch] CRITICAL: $e');
      try {
        _playErrorBeep();
      } catch (_) {}
      state = state.copyWith(
        error: tr('خطأ في معالجة الباركود — حاول مرة أخرى.'),
        errorKind: PicposBarcodeSearchErrorKind.general,
        searchResults: [],
        isSearchActive: false,
      );
    }
  }

  void clearSearchResults() {
    state = state.copyWith(
      searchResults: [],
      isSearchActive: false,
      clearError: true,
    );
  }
}

final picposSearchControllerProvider =
    NotifierProvider<PicposSearchController, PicposSearchState>(
  PicposSearchController.new,
);
