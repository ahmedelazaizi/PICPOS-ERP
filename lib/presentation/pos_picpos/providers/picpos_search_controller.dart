import 'package:picpos_erp/core/i18n/tr.dart';
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
part 'picpos_search_controller_barcode.dart';
void _logBarcodeStep(String step, String details) {
  unawaited(
    DiagnosticLogger.log('BARCODE-STEP', '$step: $details').catchError((_) {}),
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
        duplicateWeightWarning: tr(
          'نفس الوزن ({p0} كجم) تم إضافته لصنف "{productName}" من قبل — غيّر الوزن على الميزان لتجنب التكرار.',
          {'p0': weightKg.toStringAsFixed(3), 'productName': productName},
        ),
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
