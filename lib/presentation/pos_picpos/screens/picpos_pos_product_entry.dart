part of 'picpos_pos_screen.dart';

/// Product tap, unit/quantity prompts, add-to-cart and oversell/weight dialogs.
extension _PicPosProductEntryOps on _PicPosOperations {
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
        tr('أنت في وضع المرتجع — أنهِ الحفظَ أو الإلغاءَ قبل إضافة صنفٍ للبيع'),
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
      if (!mounted) return;
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
      // ── الفهرسُ من `_addToCart`، لا `length - 1` ──────────────────────
      //
      // 🔴 كان السطرُ `cartItems.length - 1` — أي «آخرُ سطرٍ في السلّة»،
      // وهو ليس بالضرورة السطرَ الذي أُضيف. و`_addToCart` تعرف الفهرسَ
      // الصحيحَ أصلاً وتحسبه لتحديد التحديد، ففُصل عنها بلا سبب:
      //
      //   • **الاندماج**: مع التكديس يندمج الصنفُ في سطرٍ قائمٍ ليس الأخير،
      //     فمعاملُ الوحدة (`quantityInBase`) يهبط على **صنفٍ آخر**. صنفٌ
      //     يخرج من المخزون ×٦ وآخرُ يُبخَس — وكلاهما بكلفةٍ خاطئة.
      //   • **الرفض**: حين يوقف حارسُ المخزون الإضافةَ (أو يرفضها الـuse
      //     case) لا يُضاف سطرٌ إطلاقاً — وكان الوسمُ يقع مع ذلك على آخرِ
      //     سطرٍ موجود، فيُفسد بيعةً سليمةً لم يمسّها المستخدم.
      final addedIndex =
          await _addToCart(product, quantity: quantity, customPrice: unitPrice);
      if (!mounted) return;
      if (addedIndex == null) {
        // لم يُضَف شيء — لا سطرَ يُوسَم.
        _refocusScanner();
        return;
      }

      ref.read(cartControllerProvider.notifier).updateItemUnit(
            addedIndex,
            unitId: selectedUnit.id,
            unitName: selectedUnit.unitName,
            quantityInBase: selectedUnit.quantityInBase,
            unitSalePrice: unitPrice,
          );
      return;
    }

    await _addToCart(product, quantity: quantity);
  }

  /// The actual cart write, plus the selection/rejection bookkeeping the
  /// PicPos cart relies on.
  ///
  /// يُرجع **فهرسَ السطر الذي تأثّر فعلاً** — سواءٌ أُلحق سطرٌ جديدٌ أم اندمجت
  /// الكمّيّةُ في سطرٍ قائم — و`null` حين لم يُضَف شيء (‏رفضُ المخزون أو رفضُ
  /// الـuse case). كان يُرجع `void` والمنادي يخمّن `length - 1`.
  Future<int?> _addToCart(
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
      return null;
    }
    if (!mounted) return null;

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
    // الفهرسُ المتأثّرُ فعلاً — يُرجَع للمنادي كي لا يخمّنه. `null` = لم يُضَف
    // شيءٌ ولا اندمج، فلا سطرَ يخصُّ هذه المحاولة.
    int? affectedIndex;
    if (items.length > before) {
      affectedIndex = items.length - 1;
      setState(() => selectedIndex = affectedIndex!);
    } else if (items.length == before) {
      // Either merged into an existing line, or refused. Select the line the
      // product is on so the cashier sees what changed either way.
      final idx = items.lastIndexWhere((i) => i.productId == product.id);
      if (idx != -1) {
        affectedIndex = idx;
        setState(() => selectedIndex = idx);
      } else {
        // مش رفض مخزون — ده اتعامل معاه فوق قبل الإضافة. أي رفض تاني (سعر
        // صفر مرفوض من الـ use case مثلاً) بيوصل هنا.
        showPosToast(context, ref, tr('تعذّرت إضافة الصنف'),
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

    return affectedIndex;
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
          title:  Row(children: [
            const Icon(PhosphorIconsBold.warningDiamond,
                color: AppColors.warning, size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('الصنف غير متوفر'))),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name, style: PicPosText.v(context, 15)),
              const SizedBox(height: 6),
              Text(
                tr('الرصيد الحالي: {p0}', {'p0': NumberUtils.formatQuantity(product.currentStock)}),
                style: PicPosText.v(context, 13, color: AppColors.error),
              ),
              const Divider(height: 18),
              Text(
                tr('تسمح بالبيع بالسالب في هذه الفاتورة؟ الرصيد هيبقى سالب ولازم جرد يصحّحه.'),
                style: PicPosText.l(context, 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('لا'), style: PicPosText.l(context, 14)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              child:  Text(tr('نعم، اسمح بالسالب')),
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
          title:  Text(
            tr('تنبيه: نفس الوزن'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              child:  Text(tr('متابعة')),
            ),
          ],
        ),
      ),
    );
    _refocusScanner();
  }
}
