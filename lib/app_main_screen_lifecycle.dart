// ignore_for_file: avoid_dynamic_calls

part of 'app_main_screen.dart';

extension _MainScreenLifecycle on _MainScreenState {
  void initializeMainScreen() {
    // Add window listener for close confirmation
    if (platform.isDesktop()) {
      windowManager.addListener(this);
      // Auto-connect to scale on desktop startup
      _autoConnectScale();
    }
    // Check for expiring products on app launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Materialize the permission sync bridge so any role/permission/user/
      // role_permission delta-pull or full-sync immediately invalidates the
      // Riverpod permission caches. Without this, PermissionGuard reads stale
      // data after a server-side permission change and the manager-override
      // dialog fires unnecessarily.
      ref.read(permissionSyncBridgeProvider);
      _checkFiscalYear();
      _checkExpiringProducts();
      _initDefaultScreen();
      _enforceShiftForCashier();
      // Auto-link cost centers to branches/warehouses/regions by name match
      ref.read(databaseProvider).autoLinkCostCenters();
      // Refresh license activation cache for demo builds
      if (AppConfig.isDemo) {
        ref.read(licenseServiceProvider).refreshActivationStatus();
      }
      // Start auto-sync if in offline fallback mode
      if (PostgresConfig.isOfflineFallback) {
        final db = ref.read(databaseProvider);
        OfflineFallbackSyncService.instance.startAutoSync(db);
      }
      // I-3 — desktop ↔ cloud link scheduler (no-op until configured; never
      // on a LAN client).
      unawaited(ref.read(cloudLinkControllerProvider).startScheduler());
    });
  }

  Future<void> initializeDefaultScreen() async {
    final db = ref.read(databaseProvider);
    final authState = ref.read(authProvider);
    final allowedIndices = await ref.read(userAllowedScreensProvider.future);

    debugPrint(
      '[NAV] _initDefaultScreen: userDefault='
      '${authState.user?.defaultScreen}, allowed=$allowedIndices, '
      'userId=${authState.user?.id}',
    );
    await DiagnosticLogger.log(
      'NAV',
      'init: userId=${authState.user?.id} '
          'username=${authState.user?.username} '
          'defaultScreen=${authState.user?.defaultScreen} '
          'allowedIndices=$allowedIndices '
          'userHasNavigatedManually=$_userHasNavigatedManually',
    );

    // 1. Per-user default screen (set in user management)
    int targetScreenIndex = 1; // fallback: POS
    final userDefault = authState.user?.defaultScreen;
    if (userDefault != null && userDefault.isNotEmpty) {
      switch (userDefault) {
        case 'pos':
          targetScreenIndex = 1;
        case 'dashboard':
          targetScreenIndex = 0;
        case 'tables':
          targetScreenIndex = 3;
        case 'products':
          targetScreenIndex = 4;
        case 'inventory':
          targetScreenIndex = 8;
        default:
          targetScreenIndex = int.tryParse(userDefault) ?? 1;
      }
    } else {
      // 2. Global setting fallback
      final savedSetting = await db.getSettingValue('default_home_screen');
      if (savedSetting != null) {
        targetScreenIndex = int.tryParse(savedSetting) ?? 1;
      }
    }

    // 3. Validate against allowed indices for current user
    if (!allowedIndices.contains(targetScreenIndex)) {
      debugPrint(
        '[NAV] Target screen $targetScreenIndex not in allowed '
        '$allowedIndices — falling back',
      );
      targetScreenIndex = allowedIndices.contains(1)
          ? 1
          : (allowedIndices.isNotEmpty ? allowedIndices.first : 0);
    }

    // ⚠️ **بالفهرس المطلق لا بموضعٍ في قائمة.** الحسابُ السابقُ كان
    // `allowedIndices.indexOf(target)` والقراءةُ `screens[_currentIndex]`،
    // و`screens` مُرتَّبةٌ بترتيب `_getAllScreens()` لا بترتيب
    // `allowedIndices` — فموضعٌ صحيحٌ في إحداهما يفتح شاشةً أخرى.
    final isAllowed = allowedIndices.contains(targetScreenIndex);
    debugPrint(
      '[NAV] _initDefaultScreen: target=$targetScreenIndex → '
      'allowed=$isAllowed',
    );
    await DiagnosticLogger.log(
      'NAV',
      'resolved: targetScreenIndex=$targetScreenIndex allowed=$isAllowed '
          '(will ${isAllowed && !_userHasNavigatedManually ? "apply" : "skip"})',
    );

    // Cache for re-entry detection
    _lastDefaultScreenApplied = userDefault;
    _lastAllowedIndicesApplied = List.of(allowedIndices);

    if (isAllowed && mounted && !_userHasNavigatedManually) {
      setState(() => _tabs = _tabs.open(targetScreenIndex));
      await DiagnosticLogger.log(
        'NAV',
        '✓ active tab set to screen index=$targetScreenIndex',
      );
    }
  }

  Future<void> autoConnectScale() async {
    try {
      // ScaleService is only available on desktop platform
      // This is safe because _autoConnectScale is only called when platform.isDesktop() is true
      await platform.autoConnectScale();
    } catch (e) {
      // Silently fail - scale connection is not critical
      debugPrint('Scale auto-connect failed: $e');
    }
  }

  Future<void> checkFiscalYear() async {
    if (!mounted) return;
    final result = await FiscalYearGateDialog.check(context, ref);
    // If dialog returned true, navigate to fiscal year screen
    if (result == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FiscalYearScreen()),
      );
    }
  }

  Future<void> checkExpiringProducts() async {
    if (!mounted) return;

    final db = ref.read(databaseProvider);
    try {
      // Get products expiring within 30 days
      final expiringBatches = await db.getExpiringBatches(30);

      if (expiringBatches.isNotEmpty && mounted) {
        _showExpiryAlertDialog(expiringBatches);
      }
    } catch (e, stackTrace) {
      // Log error on startup using the new AppLogger
      AppLogger.e('Error checking expiring products', e, stackTrace);
    }
  }

  void showExpiryAlertDialog(List<dynamic> expiringBatches) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: Directionality.of(context),
        child: AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade700,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(tr('تنبيه: منتجات قاربت على انتهاء الصلاحية')),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('يوجد {p0} منتج(ات) ستنتهي صلاحيتها خلال 30 يوم:', {
                    'p0': expiringBatches.length,
                  }),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: expiringBatches.length > 10
                        ? 10
                        : expiringBatches.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final batch = expiringBatches[index];
                      final daysUntilExpiry = batch.expiryDate != null
                          ? batch.expiryDate!.difference(DateTime.now()).inDays
                          : 0;

                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: daysUntilExpiry <= 7
                              ? Colors.red.shade100
                              : Colors.orange.shade100,
                          child: Icon(
                            Icons.inventory_2,
                            color: daysUntilExpiry <= 7
                                ? Colors.red.shade700
                                : Colors.orange.shade700,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          batch.productName ?? tr('منتج غير معروف'),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          tr('الكمية: {p0} | تاريخ الشراء: {p1}', {
                            'p0': batch.quantity,
                            'p1': batch.purchaseDate != null
                                ? '${batch.purchaseDate!.day}/${batch.purchaseDate!.month}/${batch.purchaseDate!.year}'
                                : tr('غير محدد'),
                          }),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: daysUntilExpiry <= 7
                                ? Colors.red.shade100
                                : Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            daysUntilExpiry <= 0
                                ? tr('منتهي')
                                : tr('{daysUntilExpiry} يوم', {
                                    'daysUntilExpiry': daysUntilExpiry,
                                  }),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: daysUntilExpiry <= 7
                                  ? Colors.red.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (expiringBatches.length > 10)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      tr('و {p0} منتج(ات) أخرى...', {
                        'p0': expiringBatches.length - 10,
                      }),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.check),
              label: Text(tr('حسناً، فهمت')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> handleWindowClose() async {
    // First, close any open dialogs/overlays before showing our close confirmation
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      // Small delay to ensure dialogs are closed
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!mounted) return;

    // ── SERVER MODE: hide window instead of destroying process ──
    // This keeps the HTTP API server alive for client machines without
    // requiring anyone to be physically logged in at the server terminal.
    final ns = platform.getNetworkService();
    if (ns.isServer) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => Directionality(
            textDirection: Directionality.of(context),
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  const Icon(
                    Icons.cloud_done_rounded,
                    color: Color(0xFF16C79A),
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(tr('السيرفر يعمل في الخلفية')),
                ],
              ),
              content: Text(
                tr(
                  'تم تصغير النافذة وإخفاؤها.\nالسيرفر لا يزال يعمل في الخلفية ويستقبل اتصالات العملاء.\n\nلإغلاق السيرفر نهائياً، افتح النافذة وأغلقها من الإعدادات.',
                ),
                style: const TextStyle(height: 1.6),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16C79A),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(tr('حسناً')),
                ),
              ],
            ),
          ),
        );
      }
      // Hide window: server keeps running, clients stay connected
      await windowManager.hide();
      return;
    }

    // #B2: منعُ إغلاق البرنامج وسلّةُ البيع عامرة — طلبُ مالكٍ 2026-08-17.
    // القرارُ عمداً **بعد** فرع وضع السيرفر لا قبله: في وضع السيرفر أعلاه
    // النافذةُ تُخفى فقط (`windowManager.hide()`) والعمليةُ تبقى حيّةً —
    // فسلّةُ البيع لا تُفقد، ولا داعي لمنعها هناك. من هنا وأسفلَ، كلا
    // الفرعين (مدير/كاشير) ينتهيان بـ`windowManager.destroy()` الذي يُنهي
    // العمليةَ فعلياً — فهنا وحده يجب المنعُ قبل عرض أيّ حوار تأكيدٍ آخر.
    if (mounted) {
      final saleCartItemCount = ref.read(cartControllerProvider).items.length;
      if (shouldBlockAppCloseForCart(saleCartItemCount)) {
        await showCartNotEmptyCloseBlockedDialog(context);
        return;
      }
    }

    final authState = ref.read(authProvider);
    // ده قرار صلاحية حقيقي: بيقرر هل غلق البرنامج محتاج كلمة سر مدير ولا لأ.
    // قبل كده كانت `isAdmin || isManager` بتتحدد بمطابقة اسم الدور، فأي دور
    // اسمه فيه «مدير» كان بيتخطى كلمة السر.
    final canSkipPassword = canCloseAppWithoutPassword(authState);

    if (canSkipPassword) {
      // Admin/Manager: simple yes/no confirmation
      final shouldClose = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.95),
        builder: (ctx) => Directionality(
          textDirection: Directionality.of(context),
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(tr('تأكيد إغلاق البرنامج')),
              ],
            ),
            content: Text(tr('هل أنت متأكد من أنك تريد إغلاق البرنامج؟')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('لا، البقاء')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: Text(tr('نعم، إغلاق')),
              ),
            ],
          ),
        ),
      );

      if (shouldClose == true) {
        windowManager.destroy();
      }
    } else {
      // Cashier/Non-admin: require admin password to close
      final shouldClose = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.95),
        builder: (ctx) => Directionality(
          textDirection: Directionality.of(context),
          child: const _AdminCloseDialog(),
        ),
      );

      if (shouldClose == true) {
        windowManager.destroy();
      }
    }
  }
}
