part of 'picpos_pos_screen.dart';

/// Checkout: payment flow, quick-sale rules and saving the invoice.
extension _PicPosCheckoutOps on _PicPosOperations {
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
      showPosToast(context, ref, tr('الفاتورة فارغة'),
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
        tr('اختر عميلاً قبل الدفع — الإعداد يُلزم بذلك'),
        type: PosNotificationType.error,
      );
      return;
    }

    // Selling into a closed fiscal year would post a journal entry into a
    // locked period. Fail before taking the customer's money, not after.
    try {
      await ref.read(fiscalPeriodValidationProvider(
        (date: DateTime.now(), operation: tr('بيع')),
      ).future);
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title:  Row(children: [
              const Icon(Icons.lock_clock, color: AppColors.error, size: 26),
              const SizedBox(width: 8),
              Text(tr('السنة المالية مغلقة')),
            ]),
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child:  Text(tr('موافق')),
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
        actionName: tr('حفظ فاتورة البيع السريع'),
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
            tr('فاتورة {p0} — فوق حدّ {p1}', {'p0': total.toStringAsFixed(2), 'p1': confirmAbove.toStringAsFixed(0)}),
        // ⚠️ **لا `posDiscount` هنا.** استعمالُه كان يفتح عطبَين معاً:
        // كاشيرٌ يملك الخصمَ يصير مؤهَّلاً للمصادقة على فاتورةٍ كبيرة،
        // **والإذنُ الممنوحُ يدخل `ManagerApprovalCache` تحت `pos_discount`**
        // فيستهلكه فحصُ خصمٍ لاحقٌ في نفس الدقيقة بلا سؤال. والافتراضُ
        // `approve_high_value_return` مخصَّصٌ لهذا المعنى بالضبط.
      );
      if (!okBig) {
        if (mounted) {
          showPosToast(context, ref, tr('أُلغيت البيعة — لم يُصادَق على المبلغ'),
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
    // §٤ `round` — **التقريبُ قرارٌ يقع هنا، قبل عدِّ النقد.**
    //
    // ⚠️ ولا يُترَك للأوركستريتر: لو قُرِّب هناك لكان الكاشيرُ قد عدّ النقدَ
    // وأعاد الباقيَ على الإجماليِّ **غيرِ** المقرَّب (‏حوارُ التحصيل يستقبل
    // ما نمرّره له)، فيبقى في الدرج ١١٤٫٠٨ ويقول الدفترُ ١١٤٫٠٠ ⇒ فرقُ
    // ورديّةٍ يخلقه الإعدادُ الذي وُجد ليمنعه. الأوركستريترُ الآن **يشتقّ**
    // الفرقَ ممّا قُبض فعلاً ولا يُعيد كتابةَ المقبوض.
    // (‏بلاغُ التدقيق المحاسبيّ 2026-08-30 · BLOCKER-1)
    //
    // ونقداً خالصاً فقط، ووصفُ الإعداد نفسُه «لأقرب وحدة عملة متاحة فعلاً في
    // الدرج» — فالبطاقةُ والتحويلُ يسدّدان القرشَ بالضبط.
    double collectTotal = paidTotal;
    double? collectCash = cashAmount;
    if (method == 'cash') {
      // §٤ `quickamt` — يُمرَّر من هنا لا يُقرَأ داخلَ الحوار: الحوارُ
      // مشترَكٌ مع UralCash، فالسياسةُ تُحقَن عند نداء PicPos وحدَه.
      //
      // وقراءةٌ مستقلّةٌ عن قراءة `skipdlg` فوق عمداً: تلك تعيش في فرع
      // «ليست منصّةً آجلة» وحدَه، وهذا المسارُ يصله النقديُّ من الفرعين.
      final cashPolicy = await ref.read(quickSalePolicyProvider.future);
      if (!mounted) return;

      final roundStep = quickSaleRoundingStep(cashPolicy);
      if (roundStep > 0) {
        final rounded = FinancialUtils.round(
            quickSaleRoundedTotal(total: paidTotal, step: roundStep));
        if (rounded != paidTotal) {
          collectTotal = rounded;
          if (collectCash != null) collectCash = rounded;
        }
      }

      final confirmed = await PosCashTenderingDialog.show(
        context,
        // المقرَّبُ هو ما يراه الكاشيرُ والعميلُ وما تُحسَب عليه الفكّة.
        totalAmount: collectTotal,
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
          tr('البيعة تُدخل {p0} نقداً إلى الدرج.', {'p0': amount.toStringAsFixed(2)}),
      attempt: () async => success = await ref
          .read(checkoutControllerProvider.notifier)
          .processPayment(
            method: method,
            // المقرَّبُ — هو ما دخل الدرجَ فعلاً، فيتطابق الدفترُ مع العدّ.
            total: collectTotal,
            cashAmount: collectCash,
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
            ? tr('أُلغيت البيعة — لم تُفتَح وردية')
            : tr('تعذّر فتح الوردية، فلم تُحفَظ الفاتورة'),
        type: PosNotificationType.error,
      );
      return;
    }
    if (!success) {
      final err =
          ref.read(checkoutControllerProvider).error ?? tr('فشل حفظ الفاتورة');
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
        tr('تمت تسوية فروقات تقريب {p0}', {'p0': adj.abs().toStringAsFixed(3)}),
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
          printed ? tr('تم حفظ وطباعة الفاتورة') : tr('تم حفظ الفاتورة'),
          type: PosNotificationType.success,
        );
      }
    } else {
      showPosToast(context, ref, tr('تم حفظ الفاتورة'),
          type: PosNotificationType.success);
    }

    await _applyAfterInvoiceAction(printPolicy);
  }
}
