part of 'picpos_pos_screen.dart';

/// Cart line edits: permission gate, remove, line edit dialog, invoice discount.
extension _PicPosCartEditOps on _PicPosOperations {
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
      tr('حذف صنف من السلة'),
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
        actionName: tr('حذف سطر من الفاتورة'),
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
      showPosToast(context, ref, tr('اختر صنفاً أولاً'),
          type: PosNotificationType.info);
      return;
    }
    _removeAt(idx);
  }

  Future<void> _editSelected() async {
    final idx = selectedIndex;
    final items = ref.read(cartControllerProvider).items;
    if (idx == null || idx >= items.length) {
      showPosToast(context, ref, tr('اختر صنفاً أولاً'),
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
                decoration:  InputDecoration(
                    labelText: tr('الكمية'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:  InputDecoration(
                    labelText: tr('السعر'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: discCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:  InputDecoration(
                    labelText: tr('الخصم %'), border: const OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:  Text(tr('حفظ')),
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
            tr('الكميةُ تتجاوز الحدَّ المسموح ({p0})', {'p0': maxQty.toStringAsFixed(0)}),
            type: PosNotificationType.error,
          );
          return;
        }

        if (await _ensureCartPermission(
          canEditCartQuantity,
          PermissionCodes.posQuantityEdit,
          tr('تعديل الكمية'),
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
          tr('تعديل سعر الصنف'),
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
        if (!mounted) return;
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
          title:  Text(tr('خصم الفاتورة')),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:  InputDecoration(
              labelText: tr('نسبة الخصم %'),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) =>
                Navigator.pop(ctx, double.tryParse(v.trim()) ?? current),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                  ctx, double.tryParse(controller.text.trim()) ?? current),
              child:  Text(tr('تطبيق')),
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
             if (!mounted) return;
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
}
