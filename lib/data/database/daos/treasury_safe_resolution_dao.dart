part of '../database.dart';

/// Safe resolution for drawer movements, operations and refunds.
extension TreasurySafeResolutionDao on AppDatabase {
  /// الورديّةُ التي تحكم **درجَ** [userId] الآن، أو `null` إن لم توجد.
  ///
  /// المصدرُ الوحيد لسؤال «هل يجوز أن يخرج نقدٌ الآن؟» (‏ح‑١، مواصفة
  /// 2026-08-18) — يستعمله حارسُ `processSalesReturn` وحارسُ المرتجع السريع
  /// في `sales_transaction_orchestrator`.
  ///
  /// ⚠️ السؤالُ عن **الدرج** لا عن المستخدم، ولذلك يقبل ورديّةَ غيرِه على
  /// فرعه: `_settleShift` يحسب `expectedCash` من `drawerTxs` **بلا فلترِ
  /// مستخدم** عن قصدٍ منصوصٍ عليه («الدرجُ واحدٌ يشترك فيه كلُّ من مسّه»)،
  /// فحركةُ مديرٍ على درج الكاشير تدخل توقّعَ ورديّة الكاشير ولا تُنتج عجزاً.
  /// ومديرُ النظام لا يفتح ورديّةً لنفسه أصلاً بل يلتحق بورديّة الكاشير
  /// (Spec 135 NOTE 2)، فحصرُ السؤال في ورديّته كان رفضاً باطلاً.
  Future<Shift?> resolveOpenShiftForDrawer(int userId) async {
    final own = await getCurrentOpenShift(userId);
    if (own != null) return own;
    final branchId = await getUserBranchId(userId);
    final onBranch = await getOpenShiftsForBranch(branchId: branchId);
    return onBranch.isEmpty ? null : onBranch.first;
  }

  /// هل [safeId] **درجٌ** يستلزم ورديّةً مفتوحة؟ (‏ح‑١، مواصفة 2026-08-18)
  ///
  /// الصندوقُ الرئيسيُّ مُعفًى: المحاسبُ في المقرّ يسجّل عليه سنداتِه ولا
  /// ورديّةَ له ولا يحتاجها — وهو ليس درجاً أمام كاشير. وما عداه من الخزائن
  /// النقديّة درجٌ يعدّه أحدٌ عند الإقفال، فحركتُه خارجَ أيّ نافذةٍ تُنتج
  /// فرقاً وهميّاً يُقيَّد في ذمّته.
  ///
  /// والخزائنُ غيرُ النقديّة (بنك/كليك) ليست أدراجاً ولا تدخل `expectedCash`
  /// أصلاً، فلا ورديّةَ تُشترط لها.
  /// ⚠️ السؤالُ عن **فرعِ الخزنة** لا عن المستخدم — والدرجُ هو الخزنة.
  /// وعقدُ `ITreasuryRepository` للسندات لا يحمل `userId` أصلاً، فربطُ الحكمِ
  /// بالمستخدم كان سيقرأ صفراً دائماً ويُفتي بلا معلومة.
  Future<bool> drawerMovementAllowed(int? safeId) async {
    if (safeId == null) return true;
    final safe = await getSafeById(safeId);
    if (safe == null || safe.safeType != 'cash') return true;
    final central = await getCentralSafe();
    if (central != null && safe.id == central.id) return true;
    final shifts = await getOpenShiftsForBranch(branchId: safe.branchId);
    return shifts.isNotEmpty;
  }

  /// سُلَّمُ اختيارِ الخزنةِ لأيّ حركةِ مالٍ — المصدرُ الوحيد.
  ///
  /// استُخرج من `_recordSalesReceipt` (مسارُ البيع) ليستعمله مسارُ المرتجع
  /// أيضاً: كان المرتجعُ ينادي `getDefaultSafeByType` مباشرةً، فيخصم من
  /// **الخزنةِ الافتراضيّةِ العامّة** أيّاً كان فرعُ من يُجري المرتجع — نقدٌ
  /// يخرج من درجِ فرعٍ ورقٌ يُسلَّم في فرعٍ آخر.
  ///
  /// الأولويّات:
  ///   * P1 — [specificSafeId] صريحٌ ونشط.
  ///   * P2‑أ — [preferredBranchId]: فرعٌ يعرفه النداءُ يقيناً (فرعُ الورديّة
  ///     المفتوحة في مسار المرتجع = الفرعُ القائمُ بالعمليّة فعلاً).
  ///   * P2‑ب — الفرعُ المشتقُّ من [warehouseId] (سلوكُ مسار البيع القائم).
  ///   * P3 — الافتراضيّةُ العامّة.
  ///
  /// ولا تُرجِع `null` أبداً: تعذُّرُ الخزنةِ **يرمي**. وهذا مقصودٌ بنيويّاً —
  /// نداءٌ يُرجَع له `null` يُغري بـ`if (safe != null)` بلا `else`، فتمضي
  /// العمليّةُ ويُرحَّل قيدٌ يقول «تحرّك نقد» والدرجُ ساكن. وهو ما كان يفعله
  /// مسارُ المرتجع بالضبط. (‏ح‑٣ في مواصفة 2026-08-18.)
  ///
  /// [operationLabel] و[noSafeMessage] للتشخيص ولرسالةِ المستخدم — تختلف
  /// بين بيعةٍ («الفاتورة لم تُحفظ») ومرتجعٍ («المرتجع لم يُحفظ»).
  Future<Safe> resolveSafeForOperation({
    required String safeType,
    required String operationLabel,
    required String noSafeMessage,
    int? specificSafeId,
    int? preferredBranchId,
    int? warehouseId,
  }) async {
    Safe? targetSafe;
    var reason = 'unknown';

    // ── P1: تجاوزٌ صريح ──
    if (specificSafeId != null) {
      targetSafe = await (select(safes)
            ..where((s) => s.id.equals(specificSafeId) & s.isActive.equals(true)))
          .getSingleOrNull();
      if (targetSafe != null) {
        reason = 'P1-explicit(id=$specificSafeId)';
      } else {
        debugPrint('[SafeRoute] ⚠ P1: explicit safeId=$specificSafeId '
            'not found/inactive, falling through');
      }
    }

    // ── P2‑أ: فرعٌ يعرفه النداءُ يقيناً ──
    if (targetSafe == null && preferredBranchId != null) {
      targetSafe = await _safeForBranch(preferredBranchId, safeType);
      if (targetSafe != null) {
        reason = 'P2a-preferredBranch(branchId=$preferredBranchId,type=$safeType)';
      } else {
        debugPrint('[SafeRoute] ⚠ P2a: no $safeType safe for '
            'preferredBranchId=$preferredBranchId — trying warehouse branch');
      }
    }

    // ── P2‑ب: الفرعُ المشتقُّ من المخزن ──
    if (targetSafe == null && warehouseId != null) {
      final warehouse = await (select(warehouses)
            ..where((w) => w.id.equals(warehouseId)))
          .getSingleOrNull();
      final whBranchId = warehouse?.branchId;
      if (whBranchId != null) {
        targetSafe = await _safeForBranch(whBranchId, safeType);
        if (targetSafe != null) {
          reason = 'P2-branch(branchId=$whBranchId,type=$safeType)';
        } else {
          debugPrint('[SafeRoute] ⚠ P2: no $safeType safe for '
              'branchId=$whBranchId (warehouseId=$warehouseId) — '
              'falling to system default');
        }
      } else {
        debugPrint('[SafeRoute] ⚠ P2: warehouseId=$warehouseId has no branchId '
            '— skipping branch-aware lookup');
      }
    }

    // ── P3: الافتراضيّةُ العامّة — آخرُ ملاذ ──
    if (targetSafe == null) {
      targetSafe = await getDefaultSafeByType(safeType);
      if (targetSafe != null) {
        reason = 'P3-systemDefault(type=$safeType,id=${targetSafe.id})';
        debugPrint('[SafeRoute] ⚠ P3 used for $operationLabel → '
            'safe "${targetSafe.name}" (${targetSafe.id})');
      }
    }

    if (targetSafe == null) {
      // H1 · كان `return` صامتاً في مسار البيع: الفاتورةُ تُحفظ وقيدُها
      // يُقيَّد (مدين نقدية) **والدرجُ لا يتحرّك إطلاقاً** ⇒ عجزٌ عند الإقفال
      // بحجم البيعة، وحسابُ النقدية في الأستاذ ينفصل عن الخزائن. ولا رسالةَ
      // للكاشير ولا صفَّ فشلٍ يُراجَع — البيعةُ تبدو ناجحة.
      //
      // والرميُ يرجّع المعاملةَ كلَّها (النداءاتُ كلُّها من داخل معاملة)، فلا
      // يبقى نصفُ عملية: إما عمليّةٌ كاملةٌ بنقديةٍ مقيَّدة، أو لا شيء.
      debugPrint('[SafeRoute] ✗ No safe found for $operationLabel '
          'safeType=$safeType warehouseId=$warehouseId '
          'preferredBranchId=$preferredBranchId');
      throw Exception(noSafeMessage);
    }

    debugPrint('[SafeRoute] ✓ $operationLabel → safe "${targetSafe.name}" '
        '(id=${targetSafe.id}, type=${targetSafe.safeType}, '
        'branch=${targetSafe.branchId}) [$reason]');
    return targetSafe;
  }

  /// أنشطُ خزائنِ [branchId] من [safeType]، والمعلَّمةُ افتراضيّةً أوّلاً.
  Future<Safe?> _safeForBranch(int branchId, String safeType) {
    return (select(safes)
          ..where((s) =>
              s.branchId.equals(branchId) &
              s.safeType.equals(safeType) &
              s.isActive.equals(true))
          ..orderBy([
            (s) => OrderingTerm(expression: s.isDefault, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// خزنةُ صرف المرتجع: درجُ فرع وردية المستخدم المفتوحة.
  ///
  /// كان المرتجعُ يضرب `getDefaultSafeByType('cash')` — خزنةً **عامّةً**
  /// تتجاهل الفرع — بينما البيعَ والإقفالَ ينسبان للفرع. فمرتجعٌ في فرعٍ
  /// كان يُنقص خزنةَ فرعٍ آخر (مقيسٌ 2026-08-16).
  ///
  /// مرشِّحو الدرج هنا مطابقون لـ`_settleShift` (أعلاه) في مصدر الخزائن
  /// (كلُّ الخزائن النقدية في النظام، بلا فلتر فرعٍ عند الجلب — الفرعُ
  /// يُطبَّق فقط عند بناء مجموعة السقوط، تماماً كما هناك) وبلا `orderBy`
  /// (فيرجع رتيبُ الصفّ الطبيعيّ لا ترتيبَ الاسم) — لا `getCashSafesForBranch`
  /// (كانت تُفلتر وترتّب بالاسم، فتختار درجاً مختلفاً عمّا يسوّيه الإقفالُ
  /// لنفس الوردية). وما لمسَته حركاتُ المستخدم فعلاً يُفضَّل أوّلاً، وإلا
  /// فخزائنُ الفرع المُقفَل عليه كاملةً — بنفس شرط `_settleShift` بعد أن
  /// صار `branchId` هنا مضموناً غيرَ null (اقرأ سقوطَ الفرع أدناه).
  ///
  /// ثلاثةُ فروقٍ بنيويّةٍ باقيةٌ **مقصودة**، بعد جولة مراجعة ٣ (2026-08-16):
  ///
  /// ١. **النافذةُ مفتوحة**: `_settleShift` نافذتُه مغلقةٌ
  ///    `[startTime, endTime]` لأن الورديةَ أُقفلت فعلاً؛ وهذه الدالّةُ
  ///    نافذتُها مفتوحةٌ `[startTime, الآن]` — الورديةُ لسه شغّالة والمرتجعُ
  ///    يحصل أثناءها بلا `endTime` معروف.
  ///
  /// ٢. **فلترُ الخزنة النشِطة**: `_settleShift` لا يفلتر `isActive` (يكتب
  ///    تسويةً محاسبيةً فقط، لا يصرف نقداً). وهذه الدالّةُ **تصرف نقداً
  ///    فعلياً** — فلا يجوز الاختيارُ خزنةً أخرجها المشغّلُ من الخدمة.
  ///    قياسٌ فعليٌّ (جولة مراجعة ٢): فرعٌ بدرجَين، أحدُهما معطَّلٌ برقمٍ
  ///    أصغرَ والآخرُ نشِطٌ، ووردية بلا حركةٍ بعد ⇒ كان الاختيارُ يقع على
  ///    المعطَّلة (رتيبُ الصفّ الطبيعيّ لا يعرف `isActive`)، والمبلغُ
  ///    المصروفُ يختفي من `getTotalCashBalance`/`getSafesBalancesByType`
  ///    (يفلتران `is_active = 1`) بينما الأستاذُ يسجّله — فجوةٌ صامتة.
  ///    فبعد بناء المرشَّحين (لمسٌ أو فرعٌ) تُفلتر الخزائنُ النشِطةُ منهم:
  ///    لو وُجدت واحدةٌ نشِطةٌ على الأقل تُستبعد المعطَّلة؛ وإلا (كلُّ خزائن
  ///    المجموعة معطَّلة — حالةٌ شاذّة) سقوطٌ كاملٌ إلى الخزنة الافتراضية
  ///    العامّة (جولةُ مراجعة ٣ — راجع أسفله) بدل إبقائها كلِّها مرشَّحةً:
  ///    الإبقاءُ كان يسمح بصرفٍ فعليٍّ من خزنةٍ معطَّلة، وهذا الانحدارُ
  ///    نفسُه الذي صحَّحه هذا التعليق قبل الإصلاح مباشرةً — `getDefaultSafeByType`
  ///    (السلوكُ القديمُ قبل جولة المراجعة الأولى) كان يفلتر `isActive`
  ///    **دوماً** فما كان يصرف من معطَّلةٍ أبداً.
  ///
  /// ٣. **مصدرُ سقوط الفرع عند `shift.branchId == null`**: `_settleShift`
  ///    (سطرا ٥٧٦-٥٨١ أعلاه) يتوسّع عندها لخزائن **كلّ فروع النظام**
  ///    (الشرطُ `shift.branchId == null || ...` يصير `true` دوماً — تسويةٌ
  ///    محاسبيةٌ فقط، فاتساعُ النطاق لا يصرف نقداً من فرعٍ غيرِ المستخدم).
  ///    وهذه الدالّةُ **لا** تتوسّع أبداً: تسقط أوّلاً إلى
  ///    `getUserBranchId(userId)` (أعلاه) قبل بناء أيّ مجموعةِ مرشَّحين،
  ///    فيبقى `branchId` مضموناً غيرَ null دوماً بعد تلك النقطة — خزنةٌ
  ///    يُصرف منها نقداً فعلياً يجب أن تنتسب لفرع المستخدم تحديداً، لا أن
  ///    تُختار من مجموع خزائن كلّ الفروع.
  ///
  /// وحلقةُ `moved` هنا **لا تستثني** `shift_variance` — مطابقةٌ لحلقة
  /// `moved` نفسِها في `_settleShift` (أعلاه، بعد حساب `expectedCash`)
  /// التي لا تستثنيه هي الأخرى. الاستثناءُ في `_settleShift` موجودٌ في
  /// حلقةٍ **مختلفة** (‏`totalReceipts`/`totalPayments` لحساب
  /// `expectedCash`)، لا في حلقة بناء الدرج؛ جولةُ مراجعة ١ خلطت بين
  /// الحلقتَين فأنتجت تعريفَين مختلفَين للدرج — أُصلح ذلك.
  ///
  /// كلُّ سقوطٍ إلى الخزنة الافتراضية العامّة **مُسجَّلٌ فعلياً** عبر
  /// `DiagnosticLogger` (تاگ `REFUND-SAFE-FALLBACK`) كي يظهر لمراجع — لا في
  /// وصف حركة الخزنة: صفُّ `safe_transactions` لا يحمل أيَّ إشارة سقوطٍ،
  /// فالسجلُّ التشخيصيُّ هو الأثرُ القابلُ للتدقيق.
  Future<Safe?> resolveRefundSafe({required int userId}) async {
    final shift = await getCurrentOpenShift(userId);
    if (shift == null) {
      unawaited(DiagnosticLogger.log('REFUND-SAFE-FALLBACK',
          'userId=$userId reason=no-open-shift → default cash safe'));
      return getDefaultSafeByType('cash');
    }

    // جولةُ مراجعةٍ ١ (2026-08-16) — Critical: `shift.branchId` قد يكون
    // null. `BranchScope.fullAccess()` (مدير النظام) يعطي `primaryBranchId
    // == null`، و`app_main_screen.dart:1390-1401` يفتح الورديةَ بهذا الـ
    // null **بلا سقوطٍ احتياطيّ**. وتمريرُ null إلى `getCashSafesForBranch`
    // القديمة كان **يتوسّع** إلى خزائن **كلّ** الفروع بدل أن ينهار — وبلا
    // حركةٍ في النافذة يختار `resolveShiftDrawer` أوّلَ عنصرٍ بترتيب
    // الاسم، فيقع على «الصندوق الرئيسي» (يسبق «صندوق الكاشير» أبجدياً)
    // بدل خزنة الفرع الحقيقية — قياسٌ فعليّ على بذرةٍ قياسيةٍ بفرعَين.
    // الإصلاح: نفسُ سقوطِ `pos_main_dialogs.dart:107-111` عند فتح
    // الوردية — `getUserBranchId`، وتعليقُ `Shifts.branchId`
    // (‏`audit_tables.dart:31-33`) يوصي بنفس الشيء. **لا يُمرَّر null إلى
    // أيّ استعلامٍ بالفرع بعد هذه النقطة إطلاقاً.**
    var branchId = shift.branchId;
    branchId ??= await getUserBranchId(userId);
    if (branchId == null) {
      unawaited(DiagnosticLogger.log('REFUND-SAFE-FALLBACK',
          'userId=$userId shiftId=${shift.id} '
          'reason=no-branch(shift-and-user) → default cash safe'));
      return getDefaultSafeByType('cash');
    }

    // مطابقةٌ لاستعلام `cashSafes` في `_settleShift`: كلُّ الخزائن النقدية
    // في النظام، بلا فلتر فرعٍ هنا (الفرعُ يُطبَّق أدناه عند بناء مجموعة
    // السقوط فقط، تماماً كما هناك) وبلا فلتر `isActive`.
    final cashSafes =
        await (select(safes)..where((s) => s.safeType.equals('cash'))).get();
    final cashSafeIds = {for (final s in cashSafes) s.id};
    if (cashSafeIds.isEmpty) {
      unawaited(DiagnosticLogger.log('REFUND-SAFE-FALLBACK',
          'userId=$userId shiftId=${shift.id} '
          'reason=no-cash-safes-at-all → default cash safe'));
      return getDefaultSafeByType('cash');
    }

    // مطابقةٌ لـ`txs` في `_settleShift`: ما لمسَه هذا المستخدمُ فعلاً منذ
    // بداية الوردية (بلا سقفٍ زمنيّ أعلى — الورديةُ مفتوحةٌ، خلافاً
    // لـ`_settleShift` صاحبةِ `endTime` المعروف).
    final userTxs = await (select(safeTransactions)
          ..where((t) =>
              t.userId.equals(userId) &
              t.createdAt.isBiggerOrEqualValue(shift.startTime)))
        .get();
    // ⚠️ المرشَّحون محصورون بفرع الورديّة **قبل** ترجيح الأكثرِ حركة. كان
    // الحصرُ غائباً فيقع المرتجعُ على خزنةٍ لمسَها المستخدمُ في فرعٍ آخر:
    // بيعةٌ متحصَّلُها على الخزنة الافتراضيّة العامّة ثمّ مرتجعٌ في ورديّةِ
    // فرعٍ ب كان يخصم من العامّة لا من درج ب — فرعٌ ينتفخ وفرعٌ يعجز، وهي
    // العلّةُ عينُها التي وُجدت هذه الدالّةُ لأجلها.
    //
    // والترجيحُ بالأكثرِ حركةً يبقى كما هو **داخل** الفرع: فرعٌ فيه خزنتان
    // يُنتقى بينهما بالحركة الفعلية لا بالاسم ولا برقم الإنشاء.
    final branchCashSafeIds = {
      for (final s in cashSafes)
        if (s.branchId == branchId) s.id,
    };
    var drawerSafeIds = userTxs
        .map((t) => t.safeId)
        .where(branchCashSafeIds.contains)
        .toSet();
    if (drawerSafeIds.isEmpty) {
      // مطابقةٌ لفرع `_settleShift` الاحتياطيّ — خزائنُ الفرع كاملةً. الشرطُ
      // هناك `shift.branchId == null || s.branchId == shift.branchId`؛
      // هنا `branchId` مضمونٌ غيرُ null فوق فيبسَّط إلى المساواة فقط.
      drawerSafeIds = {
        for (final s in cashSafes)
          if (s.branchId == branchId) s.id,
      };
    }
    if (drawerSafeIds.isEmpty) {
      unawaited(DiagnosticLogger.log('REFUND-SAFE-FALLBACK',
          'userId=$userId shiftId=${shift.id} branchId=$branchId '
          'reason=no-cash-safes-for-branch → default cash safe'));
      return getDefaultSafeByType('cash');
    }

    // جولةُ مراجعةٍ ٣ (2026-08-16) — فلترُ الخزنة النشِطة (اقرأ التعليقَ فوق
    // الدالّة، الفرقُ البنيويّ ٢): المرتجعُ يصرف نقداً فعلياً، فلا يجوز
    // الاختيارُ خزنةً معطَّلة، لا تفضيلاً ولا اضطراراً. جولةُ مراجعة ٢ كانت
    // تُبقي كلَّ المرشَّحين حين تعطُّلهم جميعاً — انحدارٌ سلوكيٌّ فعليّ عن
    // `getDefaultSafeByType` القديمة (تفلتر `isActive` **دوماً**) يسمح
    // بصرفٍ صامتٍ من خزنةٍ عُطِّلت في منتصف وردية بعد أن لمسَها الكاشير:
    // `getTotalCashBalance`/`getSafesBalancesByType` يفلتران `is_active=1`
    // فيختفي المبلغُ من لوحات الخزينة بينما الأستاذُ يسجّله. فبدل الإبقاء،
    // خزائنُ المجموعة كلُّها معطَّلةٌ ⇒ سقوطٌ كاملٌ إلى الخزنة الافتراضية
    // العامّة (السلوكُ القديمُ بالضبط)، مسجَّلاً بسطر REFUND-SAFE-FALLBACK
    // بسببٍ مميَّز — كبقيّة السقوطات الخمس.
    final activeIds = {
      for (final s in cashSafes)
        if (drawerSafeIds.contains(s.id) && s.isActive) s.id,
    };
    if (activeIds.isEmpty) {
      unawaited(DiagnosticLogger.log('REFUND-SAFE-FALLBACK',
          'userId=$userId shiftId=${shift.id} branchId=$branchId '
          'reason=all-candidate-safes-inactive → default cash safe'));
      return getDefaultSafeByType('cash');
    }
    drawerSafeIds = activeIds;

    // مطابقةٌ لـ`drawerTxs` في `_settleShift`: حركاتُ **أيّ** مستخدمٍ على
    // الدرج المرشَّح — لا حركاتُ هذا المستخدم وحده — كي يعكس ما بالدرج
    // فعلياً.
    final drawerTxs = await (select(safeTransactions)
          ..where((t) =>
              t.safeId.isIn(drawerSafeIds) &
              t.createdAt.isBiggerOrEqualValue(shift.startTime)))
        .get();
    // جولةُ مراجعةٍ ٢: بلا استثناء `shift_variance` — مطابقةٌ لحلقة
    // `moved` نفسِها في `_settleShift` (لا لحلقة `totalReceipts`/
    // `totalPayments` المختلفة). اقرأ تعليقَ الدالّة فوق.
    final moved = <int, double>{};
    for (final t in drawerTxs) {
      moved[t.safeId] = (moved[t.safeId] ?? 0) + t.amount.abs();
    }

    final drawerId = resolveShiftDrawer(
        cashSafeIdsInBranch: drawerSafeIds, movedBySafeId: moved);
    if (drawerId == null) {
      unawaited(DiagnosticLogger.log('REFUND-SAFE-FALLBACK',
          'userId=$userId shiftId=${shift.id} branchId=$branchId '
          'reason=resolver-returned-null → default cash safe'));
      return getDefaultSafeByType('cash');
    }
    return cashSafes.firstWhere((s) => s.id == drawerId);
  }
}
