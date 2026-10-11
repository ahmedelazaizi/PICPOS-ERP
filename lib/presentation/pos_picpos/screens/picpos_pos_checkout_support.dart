part of 'picpos_pos_screen.dart';

/// Checkout support: after-invoice action, printing, shift-conflict, payment methods, validation.
extension _PicPosCheckoutSupportOps on _PicPosOperations {
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
  /// ⚠️ **الإخفاقُ يصل هنا بالقيمة لا بالرمي.** `printReceipt` تلفّ جسمَها
  /// في `try/catch` لا يُعيد الرمي، فهي لا ترمي أبداً — وكان هذا يجعل
  /// `return true` بعد النداء صحيحاً **دائماً**: رسالةُ «تم حفظ وطباعة
  /// الفاتورة» تظهر ولا ورقةَ خرجت، والتحذيرُ أدناه كودٌ ميّت، وحلقةُ النسخ
  /// تُعيد المحاولةَ على طابعةٍ عاطلةٍ لأنّ `if (!printed) break` لا تقطع.
  /// فالفحصُ على القيمة، والرميُ يبقى مُمسَكاً احتياطاً لمنادٍ يتغيّر.
  Future<bool> _tryPrintReceipt(int invoiceId) async {
    void warn(String why) {
      debugPrint('[PicPos-Print] فشلت طباعة الفاتورة #$invoiceId: $why');
      if (mounted) {
        showPosToast(context, ref,
            tr('⚠️ الحفظ تم، لكن فشلت الطباعة (تأكد من الورق)'),
            type: PosNotificationType.warning);
      }
    }

    try {
      final printed =
          await ref.read(posControllerProvider.notifier).printInvoice(invoiceId);
      if (!printed) warn('الخدمةُ أبلغت بعدم الطباعة');
      return printed;
    } catch (e) {
      warn('$e');
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
          tr('المستخدم الحالي'),
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
          actionName: tr('فتح وردية ثانية لنفس المستخدم'),
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
          title:  Text(tr('اختر الحساب البنكي')),
          children: [
            for (final safe in safes)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, safe.id),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsBold.bank,
                        size: 16, color: AppColors.info),
                    const SizedBox(width: 8),
                    Expanded(child: Text(trData(safe.name))),
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
          title:  Row(children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 26),
            const SizedBox(width: 8),
            Text(tr('أصناف بدون قيمة')),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (zeroPrice.isNotEmpty) ...[
                 Text(tr('أصناف بسعر صفر:'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.error)),
                ...zeroPrice.map((n) => Text('• $n',
                    style: const TextStyle(fontSize: 13))),
                const SizedBox(height: 8),
              ],
              if (zeroQty.isNotEmpty) ...[
                 Text(tr('أصناف بكمية صفر:'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.error)),
                ...zeroQty.map((n) => Text('• $n',
                    style: const TextStyle(fontSize: 13))),
              ],
              const Divider(),
               Text(tr('هل تريد المتابعة؟'),
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text(tr('لا، تعديل الفاتورة')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white),
              child:  Text(tr('نعم، متابعة')),
            ),
          ],
        ),
      ),
    );
    return proceed == true;
  }

  // ── Cancel the whole invoice (ESC) ─────────────────────────────────────
}
