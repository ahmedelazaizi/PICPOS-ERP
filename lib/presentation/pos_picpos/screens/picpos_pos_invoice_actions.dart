part of 'picpos_pos_screen.dart';

/// Invoice-level actions: cancel, customer, held orders, expenses, previous/last invoices, edit posted.
extension _PicPosInvoiceActionsOps on _PicPosOperations {
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
        title: tr('إلغاء الاستبدال'),
        message: tr('سيُلغى وضعُ الاستبدال بلا حفظ، **وتُفرَّغ سلّةُ البديل**. متأكد؟'),
        confirmLabel: tr('إلغاء الاستبدال'),
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
        title: tr('إلغاء المرتجع'),
        message: tr('سيُلغى وضعُ المرتجع الحاليّ بلا حفظ. متأكد؟'),
        confirmLabel: tr('إلغاء المرتجع'),
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
      title: tr('إلغاء الفاتورة'),
      message: tr('سيتم مسح كل الأصناف. متأكد؟'),
      confirmLabel: tr('إلغاء الفاتورة'),
      isDangerous: true,
    );
    if (!ok || !mounted) return;
    if (!await _ensureCartPermission(
      canClearCart,
      PermissionCodes.posClearCart,
      tr('تفريغ السلة'),
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
        tr('أنت في وضع المرتجع — أنهِ الحفظَ أو الإلغاءَ قبل فتح الفواتير المعلّقة'),
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
      showPosToast(context, ref, tr('الفاتورة فارغة'),
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
        tr('بلغتَ الحدَّ الأقصى للفواتير المعلّقة ({cap}) — أنهِ فاتورةً معلّقةً أوّلاً', {'cap': cap}),
        type: PosNotificationType.error,
      );
      return;
    }

    final err = await ref.read(cartControllerProvider.notifier).holdOrder();
    if (!mounted) return;
    if (err == null) {
      setState(() => selectedIndex = null);
      showPosToast(context, ref, tr('تم تعليق الفاتورة'),
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
              actionName: tr('إعادة طباعة فاتورة'))) {
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
        actionName: tr('تعديل طريقة دفع فاتورة مرحّلة'),
        permission: PermissionCodes.posEditInvoice,
      );
      if (!approved) return;
    }
    if (!mounted) return;
    await PosEditInvoiceDialog.show(context, invoice: invoice);
    _refocusScanner();
  }
}
