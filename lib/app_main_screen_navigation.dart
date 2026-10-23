part of 'app_main_screen.dart';

extension _MainScreenNavigation on _MainScreenState {
  /// Get screens based on allowed indices (from permissions).
  ///
  /// In CLIENT mode we additionally hide the HR (employees) screen — user,
  /// employee, and permission management are server-authoritative and must
  /// only be accessed from the server to avoid ID collisions and out-of-sync
  /// accounts. These settings carry over to the client via user pull sync.
  List<ScreenConfig> getScreensForAllowed(List<int> allowedIndices) {
    final allScreens = _getAllScreens();
    final isClientMode = NetworkService.instance.isClient;
    const clientHiddenScreens = <AppScreen>{
      AppScreen.hr, // Employees / HR — managed centrally on the server
      AppScreen.hrEmployees, // J4 — same rule for the PicPos employee file
      AppScreen.hrOrganization,
      AppScreen.hrAttendance, // J4 part 2
      AppScreen.hrLeave,
      AppScreen.hrShifts,
      AppScreen.hrPayroll, // J4 part 3
      AppScreen.hrAdvances,
      AppScreen.hrCommissions,
    };
    return allScreens.where((s) {
      if (!allowedIndices.contains(s.index)) return false;
      if (isClientMode && clientHiddenScreens.contains(s.appScreen))
        return false;
      return true;
    }).toList();
  }

  void _navigateToScreenImpl(int screenIndex) {
    final allowedAsync = ref.read(userAllowedScreensProvider);
    allowedAsync.whenData((allowedIndices) {
      if (!allowedIndices.contains(screenIndex)) return;
      // Record that the user manually navigated — stops the auto-default
      // re-pick on subsequent builds from overriding the user's choice.
      _userHasNavigatedManually = true;
      _activateScreen(screenIndex);
    });
  }

  /// يفتح تابَ [screenIndex] أو ينشّطه، ويسجّل السابقَ في تاريخ الرجوع.
  ///
  /// ⚠️ **وهي المعبرُ الوحيد.** كانت سبعةَ مواضعَ تكتب `_currentIndex`
  /// مباشرةً، وكلُّ موضعٍ ينسى شيئاً: هذا ينسى التاريخَ وذاك يحسب الموضعَ
  /// من قائمةٍ أخرى. والتاباتُ تضيف عملاً ثالثاً (‏الفتحَ والإخلاء) — فنسخُه
  /// سبعاً كان يُنتج شريطاً يتناقض مع المحتوى.
  void _activateScreenImpl(int screenIndex) {
    // ⚠️ **والمسارُ الفرعيُّ يُزال أوّلاً.** الشاشاتُ تدفع مساراتٍ على
    // مُوجِّه الشلّ (‏تقريرٌ مفتوحٌ، شاشةُ وحداتِ قياس…) وهي تعلو الكومةَ
    // كلَّها؛ فتبديلُ التاب تحتها لا يُرى — نقرةٌ عاملةٌ تبدو ميّتة، وهو
    // عينُ ما بلّغ عنه المالك في الشريط السابق. و`_navigateToPosShortcut`
    // كانت وحدَها تفعل هذا.
    appShellNestedNavigatorKey.currentState?.popUntil((route) => route.isFirst);

    if (_tabs.active == screenIndex) return;
    _navigationHistory.add(_tabs.active);

    // ⚠️ **والإخلاءُ يُعلَن.** السقفُ يُغلق تاباً لم يطلب أحدٌ إغلاقَه؛
    // واختفاءٌ صامتٌ يُنتج بلاغاً («التابُ الذي فتحتُه اختفى») أشدَّ من
    // السقف نفسِه. ويُقرأ قبل `open` لأنّ الضحيّةَ تُحسَب من الحالة السابقة.
    final evicted = _tabs.isFull && !_tabs.contains(screenIndex)
        ? _tabs.evictionCandidate
        : null;

    setState(() => _tabs = _tabs.open(screenIndex));

    if (evicted != null && mounted) {
      final label = _screenLabelFor(evicted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(
            tr('أُغلق تاب «{label}» — السقف {kMaxScreenTabs} تابات', {
              'label': label,
              'kMaxScreenTabs': kMaxScreenTabs,
            }),
            textDirection: Directionality.of(context),
          ),
        ),
      );
    }

    // ⚠️ **وبؤرةُ لوحة المفاتيح تنتقل مع التاب.** حقلُ الباركود في شاشة
    // البيع يطلب البؤرةَ في `initState`، والتابُ يُبقي الشاشةَ مبنيّةً —
    // فتبقى البؤرةُ عندها وأنت على شاشةٍ أخرى، ويذهب مسحُ الماسح إلى سلّةٍ
    // لا تراها. و`FocusScopeNode` يتذكّر آخرَ ما كان مبئوراً فيه، فالعودةُ
    // إلى التاب تُعيد البؤرةَ إلى حقلها بلا نقرة.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pruneTabScopes();
      _tabFocusScopes[screenIndex]?.requestFocus();
    });
  }

  /// تسميةُ شاشةٍ بفهرسها — للرسائل وحدَها.
  String _screenLabelForImpl(int screenIndex) {
    for (final s in _getAllScreens()) {
      if (s.index == screenIndex) return s.label;
    }
    return tr('شاشة {screenIndex}', {'screenIndex': screenIndex});
  }

  /// يُتلف نطاقاتِ التابات التي لم تعد مفتوحة.
  ///
  /// ⚠️ **والإغلاقُ ليس المخرجَ الوحيد**: الإخلاءُ عند السقف و`retain` عند
  /// سحب الصلاحية يُسقطان تاباتٍ بلا مرورٍ بـ`_closeTab`. وبعد الإطار وحدَه:
  /// إتلافُ عقدةٍ ما زالت موصولةً بشجرةٍ حيّةٍ يرمي في وضع التصحيح.
  void _pruneTabScopesImpl() {
    final stale = _tabFocusScopes.keys
        .where((k) => !_tabs.contains(k))
        .toList();
    for (final k in stale) {
      _tabFocusScopes.remove(k)?.dispose();
    }
  }

  /// الشاشاتُ المفتوحةُ كلُّها مبنيّةٌ، والمعروضةُ واحدة.
  ///
  /// ⚠️ **والمفتاحُ إلزاميّ.** `IndexedStack` يطابق أطفالَه **بالموضع**؛
  /// فإغلاقُ تابٍ في الوسط يُزحزح ما بعده موضعاً واحداً، فتُسلَّم حالةُ
  /// شاشةٍ إلى شاشةٍ أخرى — سلّةُ الكاشير تظهر في شاشة المخزون. والمفتاحُ
  /// بالفهرس يجعل المطابقةَ بالهويّة لا بالموضع.
  ///
  /// ⚠️ **وكلفةُ هذا حقيقيّةٌ لا مجّانيّة**: كلُّ تابٍ مفتوحٍ شجرةٌ حيّةٌ
  /// بمؤقّتاتها ومراقباتها على القاعدة، لا اسمٌ في شريط. ولذلك سقفُ
  /// `kMaxScreenTabs` ثمانية، ولذلك تُخلى الأقدمُ استعمالاً.
  Widget _openScreensStackImpl(Map<int, ScreenConfig> byScreenIndex) {
    final open = [
      for (final i in _tabs.order)
        if (byScreenIndex[i] case final s?) (index: i, config: s),
    ];
    if (open.isEmpty) return const SizedBox.shrink();

    var active = open.indexWhere((e) => e.index == _tabs.active);
    if (active < 0) active = 0;

    return IndexedStack(
      index: active,
      sizing: StackFit.expand,
      children: [
        for (final e in open)
          KeyedSubtree(
            key: ValueKey<int>(e.index),
            // ⚠️ **ومؤقّتاتُ التاب المستور تتوقّف.** `IndexedStack` يُبقي
            // كلَّ طفلٍ مبنيّاً حيّاً، فثمانيةُ تاباتٍ بثمانيةِ مجموعاتٍ من
            // الرسوم المتحرّكة تُبقي الإطارَ يُعاد رسمُه بلا سببٍ مرئيّ —
            // وهو ثمنٌ يدفعه الجهازُ الضعيفُ الذي يُشحَن إليه هذا المنتج.
            child: TickerMode(
              enabled: e.index == _tabs.active,
              child: FocusScope(
                node: _tabFocusScopes.putIfAbsent(
                  e.index,
                  () => FocusScopeNode(debugLabel: 'tab_${e.index}'),
                ),
                child: e.config.screen,
              ),
            ),
          ),
      ],
    );
  }

  /// يرجع خطوةً في تاريخ التنقّل. ويعود `false` إن لم يبقَ ما يُرجَع إليه.
  ///
  /// ⚠️ **ويتخطّى ما لم يبقَ مفتوحاً.** التاريخُ كان يحمل مواضعَ في قائمةٍ
  /// مُرشَّحةٍ تتغيّر طولاً مع الصلاحيات، فرجوعٌ بعد تغيُّرها كان يفتح شاشةً
  /// غيرَ التي تُرِكت. والفهرسُ المطلقُ يُنهي ذلك، ويبقى أن تابَ الوجهة قد
  /// أُغلِق — فالرجوعُ إليه فتحٌ جديدٌ لا رجوع.
  bool _goBackImpl() {
    while (_navigationHistory.isNotEmpty) {
      final target = _navigationHistory.removeLast();
      if (target == _tabs.active) continue;
      if (!_tabs.contains(target)) continue;
      setState(() => _tabs = _tabs.open(target));
      return true;
    }
    return false;
  }

  /// يُغلق تابَ [screenIndex] بعد حارسِ السلّة إن كان شاشةَ البيع.
  ///
  /// ⚠️ **وحارسُ السلّة انتقل من التنقّل إلى الإغلاق.** فالتابُ يُبقي شاشةَ
  /// البيع مبنيّةً حيّةً، فالتنقّلُ عنها لم يبقَ يمسح السلّة — والإغلاقُ
  /// وحدَه يهدم الشجرةَ ويمسحها. وإبقاءُ الحارس على التنقّل كان يسأل
  /// الكاشيرَ في كلّ نقرةِ تابٍ عن خطرٍ لم يبقَ قائماً.
  Future<void> _closeTabImpl(int screenIndex) async {
    if (!_tabs.contains(screenIndex)) return;
    if (_tabs.order.length <= 1) return;

    // شاشةٌ متّسخةٌ (مثل مصمّم القاعة) تسأل قبل أن يهدمها الإغلاقُ (E-1).
    final registry = ref.read(dirtyScreensRegistryProvider);
    if (!await registry.confirmCloseScreen(screenIndex) || !mounted) return;

    if (screenIndex == AppScreen.pos.value) {
      final cartState = ref.read(cartControllerProvider);
      if (cartState.items.isNotEmpty) {
        final shouldClose =
            await showDialog<bool>(
              context: context,
              builder: (ctx) => Directionality(
                textDirection: Directionality.of(context),
                child: AlertDialog(
                  title: Text(tr('تنبيه')),
                  content: Text(
                    tr('إغلاق تاب نقطة البيع يمسح السلة. هل تريد المتابعة؟'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(tr('لا')),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: Text(tr('نعم، إغلاق')),
                    ),
                  ],
                ),
              ),
            ) ??
            false;
        if (!shouldClose || !mounted) return;
      }
    }

    setState(() {
      _tabs = _tabs.close(screenIndex);
      _navigationHistory.removeWhere((i) => i == screenIndex);
      // النطاقُ يموت مع تابه — وإلّا تراكمت عُقَدٌ لشاشاتٍ لم تعد مبنيّة.
      _tabFocusScopes.remove(screenIndex)?.dispose();
    });
  }

  /// Fast equality for small int lists (allowed-screens comparisons).
  bool _listsEqualImpl(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Widget buildMainScreen(BuildContext context) {
    // ═══ قناةُ «افتح شاشةَ كذا» ═══════════════════════════════════════════
    //
    // ‏`_activateScreen` حالةٌ خاصّةٌ في هذه الودجت، فالشاشاتُ المتداخلةُ لا
    // تصلها — وكان `onNavigate` يُمرَّر يدويّاً إلى ودجتَين اثنتَين. وزرُّ
    // «المستند المصدر» في اليومية العامة (قرارُ المالك 2026-09-18) يحتاجها
    // من عمقٍ أبعد، و«عرض المستند» في كشف الحساب يقرؤها بعده.
    //
    // ⚠️ **والطلبُ يُستهلَك بعد تنفيذه**: مزوِّدٌ يحتفظ بآخر طلبٍ يُعيد
    // تنفيذَه مع أوّل إعادةِ بناءٍ عارضة، فتقفز الشاشةُ بلا أن ينقر أحد.
    ref.listen(screenNavigationProvider, (_, next) {
      if (next == null) return;
      _navigateToScreen(next.screenIndex);
      ref.read(screenNavigationProvider.notifier).consume();
    });

    final allowedScreensAsync = ref.watch(userAllowedScreensProvider);
    final authState = ref.watch(authProvider);

    // Re-apply the per-user default screen when either the auth'd user's
    // `defaultScreen` or the allowed-indices list changes AFTER the first
    // paint. This covers the case where a client login triggers a background
    // user refresh that arrives *after* the initial `_initDefaultScreen()`
    // has already run with stale data.
    if (allowedScreensAsync.hasValue) {
      final current = allowedScreensAsync.value!;
      final userDefault = authState.user?.defaultScreen;
      final defaultChanged = _lastDefaultScreenApplied != userDefault;
      final allowedChanged =
          _lastAllowedIndicesApplied == null ||
          !_listsEqual(_lastAllowedIndicesApplied!, current);
      if (!_userHasNavigatedManually &&
          authState.isAuthenticated &&
          (defaultChanged || allowedChanged)) {
        // Defer to avoid calling setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _initDefaultScreen();
        });
      }
    }

    // Use cached value to keep AppShell alive during provider reloads
    // (e.g. admin elevation). This prevents _isHidden state from being reset.
    final allowedIndices = allowedScreensAsync.hasValue
        ? allowedScreensAsync.value
        : null;

    if (allowedIndices == null) {
      if (allowedScreensAsync.hasError) {
        return Scaffold(
          body: Center(child: Text(tr('خطأ في تحميل الصلاحيات'))),
        );
      }
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F3460),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  size: 44,
                  color: Color(0xFF16C79A),
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF16C79A),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tr('جاري تحميل الصلاحيات...'),
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }
    // B-7: لا شاشةَ يفتحها المستخدم ⇒ حالةٌ صريحةٌ بمخرج، لا هيكلٌ فارغ.
    if (allowedIndices.isEmpty) return const NoScreensAvailableView();
    {
      final screens = _getScreensForAllowed(allowedIndices);
      final byScreenIndex = {for (final s in screens) s.index: s};

      // ⚠️ **تاباتُ الشاشات التي لم تبقَ مسموحةً تُسقَط هنا.** والشاشةُ
      // المفتوحةُ في تابٍ **مبنيّةٌ حيّةٌ** تقرأ وتكتب، لا مجرّدَ اسمٍ في
      // شريط؛ فبقاءُ تابٍ بعد سحب الصلاحية إبقاءُ الشاشة عاملةً لمن مُنِع.
      //
      // و`screens` تخلو مؤقّتاً أثناء إعادة تحميل المزوّد، و`retain` تُعيد
      // الحالةَ كما هي عند المجموعة الفارغة — فلا تُهدَم التاباتُ كلُّها
      // على وميضٍ عابر.
      if (screens.isNotEmpty) {
        _tabs = _tabs.retain(byScreenIndex.keys.toSet());
      }

      final currentScreenIndex = _tabs.active;

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;

          // 1. Try popping the nested navigator (sub-screens like UOM, reports)
          final nestedNav = appShellNestedNavigatorKey.currentState;
          if (nestedNav != null && nestedNav.canPop()) {
            nestedNav.pop();
            return;
          }

          // 2. Try popping sidebar navigation history
          if (_goBack()) return;

          // 3. No history — show exit dialog
          //
          // #B2: منعُ الخروجَ هنا أيضاً وسلّةُ البيع عامرة. هذا المسارُ
          // ينادي `platform.exitApp()` (= `dart:io exit(0)` بعد نسخة
          // احتياطية) مباشرةً — بلا مرورٍ بـ`onWindowClose`/`windowManager`
          // إطلاقاً — فحارسُ `onWindowClose` وحده لا يغطّيه.
          final cartItemCountForBackExit = ref
              .read(cartControllerProvider)
              .items
              .length;
          if (shouldBlockAppCloseForCart(cartItemCountForBackExit)) {
            await showCartNotEmptyCloseBlockedDialog(context);
            return;
          }
          // مسوّداتٌ لم تُحفَظ (مصمّم القاعة…) تُسأل قبل الخروج (E-1).
          if (!await ref.read(dirtyScreensRegistryProvider).confirmCloseAll() ||
              !context.mounted) {
            return;
          }

          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => Directionality(
              textDirection: Directionality.of(context),
              child: AlertDialog(
                title: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(tr('تأكيد الخروج')),
                  ],
                ),
                content: Text(
                  tr('هل أنت متأكد من أنك تريد الخروج من البرنامج؟'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(tr('إلغاء')),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: Text(tr('خروج')),
                  ),
                ],
              ),
            ),
          );
          if (shouldExit == true) {
            platform.exitApp();
          }
        },
        child: AppShell(
          // Pass actual screen index for proper highlighting
          currentIndex: currentScreenIndex,
          // Back navigation via history stack — always pass callback
          onBackTap: _goBack,
          // ⚠️ **وحارسُ «يوجد أصناف في السلة» نُزع من هنا.** كان يمنع
          // التنقّلَ عن شاشة البيع لأنّ التنقّلَ كان يهدم شجرتَها فتُمسَح
          // السلّة. والتابُ يُبقيها مبنيّةً حيّةً، فالسلّةُ تنتظر كما هي —
          // والسؤالُ في كلّ نقرةٍ صار إنذاراً عن خطرٍ غيرِ قائم. والخطرُ
          // انتقل إلى `_closeTab` وهناك يُسأل.
          onNavigate: (screenIndex) {
            if (!screens.any((s) => s.index == screenIndex)) return;
            _activateScreen(screenIndex);
          },
          tabs: [
            for (final i in _tabs.order)
              if (byScreenIndex[i] case final s?)
                ScreenTabView(
                  index: i,
                  label: s.label,
                  icon: s.icon,
                  closable: _tabs.order.length > 1,
                ),
          ],
          onSelectTab: _activateScreen,
          onCloseTab: _closeTab,
          onHomeTab: byScreenIndex.containsKey(AppScreen.dashboard.value)
              ? () => _activateScreen(AppScreen.dashboard.value)
              : null,
          child: Column(
            children: [
              // ── Offline fallback banner ──────────────────────
              // Only show for PostgreSQL offline fallback, NOT for client mode
              // (client mode uses SQLite + HTTP sync, not PostgreSQL).
              //
              // Defensive: hex Color literals instead of Colors.orange.shadeNNN.
              // The previous implementation crashed during build with
              //   RangeError (length): Invalid value: Valid value range is empty: 0
              //   #0  MaterialColor.shade800
              //   #1  _MainScreenState.build (app_main_screen.dart:1084)
              // for some users on the server (offline-fallback path) — likely a
              // Flutter framework swatch lookup quirk in this build chain.
              // Literal const Color values eliminate the indirection entirely.
              if (PostgresConfig.isOfflineFallback &&
                  !NetworkService.instance.isClient)
                MaterialBanner(
                  backgroundColor: const Color(0xFFFFF3E0), // orange shade50
                  leading: const Icon(
                    PhosphorIconsBold.wifiSlash,
                    color: Color(0xFFEF6C00),
                  ), // orange shade800
                  content: Text(
                    tr('وضع أوفلاين — العمل على قاعدة البيانات المحلية. {p0}', {
                      'p0': PostgresConfig.offlineFallbackStart != null
                          ? tr('منذ {p0}', {
                              'p0': _formatOfflineTime(
                                PostgresConfig.offlineFallbackStart!,
                              ),
                            })
                          : "",
                    }),
                    style: const TextStyle(
                      color: Color(0xFFE65100), // orange shade900
                      fontSize: 13,
                    ),
                  ),
                  actions: [
                    // ── Sync Now button ──
                    TextButton.icon(
                      icon: const Icon(
                        PhosphorIconsBold.arrowsClockwise,
                        size: 16,
                        color: Color(0xFF388E3C),
                      ), // green shade700
                      label: Text(
                        tr('مزامنة الآن'),
                        style: const TextStyle(
                          color: Color(0xFF388E3C),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () => _showSyncDialog(context),
                    ),
                    // ── Test Connection button ──
                    TextButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final pgConfig = await PostgresConfig.load();
                        final error = await testPostgresConnection(pgConfig);
                        if (error == null) {
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  tr(
                                    '✅ السيرفر متاح — اضغط "مزامنة الآن" لنقل البيانات',
                                  ),
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } else {
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  tr('❌ السيرفر غير متاح: {error}', {
                                    'error': error,
                                  }),
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      child: Text(
                        tr('اختبار الاتصال'),
                        style: const TextStyle(color: Color(0xFFE65100)),
                      ), // orange shade900
                    ),
                  ],
                ),
              // ── Main content ──────────────────────────────────
              Expanded(
                child: GlobalSearchOmnibox(
                  onNavigateToScreen: (index) {
                    if (!byScreenIndex.containsKey(index)) return;
                    _activateScreen(index);
                  },
                  // Guard: screens can be transiently empty during a provider
                  // reload (e.g. after updateActivity() triggers a rebuild while
                  // userAllowedScreensProvider is still computing).
                  child: screens.isEmpty
                      ? const SizedBox.shrink()
                      : _openScreensStack(byScreenIndex),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // ── Offline sync helpers ────────────────────────────────────────
}
