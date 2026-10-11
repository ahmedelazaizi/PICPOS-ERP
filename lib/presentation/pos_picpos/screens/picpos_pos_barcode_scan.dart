part of 'picpos_pos_screen.dart';

/// Barcode scan flow: search, unknown-barcode quick add, silently refused scans.
extension _PicPosBarcodeScanOps on _PicPosOperations {
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
        tr('أنت في وضع المرتجع — أنهِ الحفظَ أو الإلغاءَ قبل إضافة صنفٍ للبيع'),
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
            tr('باركود غير مسجَّل — ابحث بالاسم في الشبكة'),
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
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.warningCircle,
                  color: AppColors.warning, size: 28),
              const SizedBox(width: 8),
              Expanded(child: Text(tr('صنف غير معرف'))),
            ],
          ),
          content: Text(
            tr('الباركود "{barcode}" غير مسجل في النظام.\nهل تريد إضافته كصنف جديد؟', {'barcode': barcode}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text(tr('لا')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success),
              child:  Text(tr('نعم — إضافة سريعة')),
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
        actionName: tr('إضافة صنف جديد'))) {
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
}
