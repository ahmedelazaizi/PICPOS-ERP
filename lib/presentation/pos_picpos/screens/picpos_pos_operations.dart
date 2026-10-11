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
        final userName = authState.user?.displayName ?? tr('كاشير');
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
          tr('تعذّر فتح الوردية تلقائياً: {shortMsg}', {'shortMsg': shortMsg}),
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
            title:  Text(tr('السلة غير فارغة')),
            content:  Text(
              tr('فيه أصناف في السلة لسه ما اتحفظتش. تحويل المستخدم هيمسحها. تحب تكمّل؟'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:  Text(tr('رجوع')),
              ),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child:  Text(tr('مسح وتحويل')),
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
        tr('تم التحويل إلى {p0}', {'p0': ref.read(authProvider).effectiveUser?.displayName ?? tr('المستخدم الجديد')}),
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
}
