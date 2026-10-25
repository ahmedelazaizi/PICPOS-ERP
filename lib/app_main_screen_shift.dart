part of 'app_main_screen.dart';

/// Screen configuration with permission-based access.
/// PIR: Uses lazy [WidgetBuilder] — screens are only constructed when first accessed.
/// بتضمن إن المستخدم الحالي عنده وردية مفتوحة، وبتسأله يفتح واحدة لو لأ.
///
/// ── ليه دالة عليا مش دالة خاصة في `State` ────────────────────────────────
/// كانت بتتنادى من `initState` **وبس**، وده كان كفاية وقت ما كل دخول مستخدم
/// جديد كان بيمرّ بإعادة بناء الشجرة. بعد إلغاء الإغلاق الإجباري بقى فيه
/// مسار تاني: `switchUser()` بتغيّر المستخدم **من غير** ما تهدّ الشجرة —
/// مقصود، عشان ديالوج التبديل ما يموتش مع مفتاح `MaterialApp` في
/// `main.dart:1217`. فـ`initState` ما بتشتغلش، والكاشير الجاي كان هيبيع بلا
/// وردية مفتوحة وفواتيره ما تتنسبش لأي وردية.
///
/// [callSite] بيتكتب في سجل التشخيص عشان نعرف أي مسار سأل — الدخول ولا
/// التبديل.
Future<void> enforceShiftForUser(
  BuildContext context,
  WidgetRef ref, {
  required String callSite,
}) async {
  if (!context.mounted) return;
  final authState = ref.read(authProvider);
  // Spec 135 NOTE 2 — سياسة وردية مقصودة، مش قرار صلاحية: مدير النظام
  // عمداً ما بيفتحش وردية لنفسه، وبيتصل بوردية الكاشير المفتوحة عشان
  // يسويها. `isAdmin || isManager` هنا تفادياً لتضييق السلوك على «مدير
  // فرع» لغاية ما فحص «مين المدير» ده يتراجع فيه قرار منفصل.
  if (authState.isAdmin || authState.isManager) return; // admins/managers skip
  final userId = authState.user?.id;
  if (userId == null) return;

  // Pull latest shift state from server before checking locally.
  if (NetworkService.instance.isClient) {
    try {
      await DeltaPullService.instance.pullTable('shifts');
    } catch (e) {
      debugPrint('[ShiftGuard] Shift pull failed (non-fatal): $e');
    }
  }

  final treasuryRepo = ref.read(treasuryRepositoryProvider);
  final openShift = await treasuryRepo.getCurrentOpenShift(userId);
  unawaited(
    DiagnosticLogger.log(
      'SHIFT-GUARD',
      'enforceShiftForUser check userId=$userId '
          'openShiftId=${openShift?.id} '
          'alreadyPrompted=${shiftDialogPromptedUserIds.contains(userId)} '
          'callSite=$callSite',
    ),
  );
  if (openShift != null) return; // shift already open — nothing to do

  // Feature 012 / Issue C-SHIFT-LOOP: same-session guard. If we
  // already prompted this user once in this app session, do not
  // re-prompt — even if the local shift row was transiently
  // overwritten or removed by an upstream sync. The user can still
  // open a shift manually from the treasury screen if needed.
  //
  // `switchUser()` بتفضّي المجموعة دي (`clearShiftDialogPromptedUsers`)،
  // فالكاشير الجاي بيتسأل عادي — الحارس بيمنع تكرار السؤال لنفس المستخدم
  // في نفس الجلسة بس.
  if (shiftDialogPromptedUserIds.contains(userId)) {
    unawaited(
      DiagnosticLogger.log(
        'SHIFT-GUARD',
        '⚠ suppressed re-prompt for userId=$userId '
            '(already prompted in this session) — see ShiftSyncStrategy',
      ),
    );
    return;
  }
  shiftDialogPromptedUserIds.add(userId);

  if (!context.mounted) return;
  final userName =
      authState.user?.displayName ?? authState.user?.username ?? tr('كاشير');

  // Prompt for opening balance — barrierDismissible: false makes it mandatory.
  final opening = await showDialog<double>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PosOpeningBalanceDialog(userName: userName),
  );

  // Spec 008 / FR-004: resolve the operating branch from BranchScope so
  // multi-branch users open the shift on their CURRENT branch (not always
  // their first user_branch_access row). Full-access users (system admin,
  // mirror admin) get null — close-time logic falls back gracefully.
  int? scopedBranchId;
  try {
    final scope = await ref.read(branchScopeProvider.future);
    scopedBranchId = scope.primaryBranchId;
  } catch (e) {
    debugPrint('[ShiftGuard] BranchScope lookup failed (non-fatal): $e');
  }

  // Local-first on a branch device, HQ-first on the console (M3 / MIR-009).
  await openShiftAndSync(treasuryRepo, userId, opening ?? 0.0,
      branchId: scopedBranchId);
  // Re-fetch the freshly inserted shift so the diag entry carries id +
  // globalId — these are the values the server-side close-shift now keys
  // off, so logging them lets us correlate the open ↔ close end-to-end.
  int? loggedShiftId;
  String? loggedShiftGid;
  try {
    final fresh = await treasuryRepo.getCurrentOpenShift(userId);
    loggedShiftId = fresh?.id;
    loggedShiftGid = fresh?.globalId;
  } catch (_) {}
  unawaited(
    DiagnosticLogger.log(
      'SHIFT',
      'New shift opened userId=$userId '
          'localShiftId=$loggedShiftId globalId=$loggedShiftGid '
          'opening=${opening ?? 0.0} branchId=$scopedBranchId callSite=$callSite',
    ),
  );
}
