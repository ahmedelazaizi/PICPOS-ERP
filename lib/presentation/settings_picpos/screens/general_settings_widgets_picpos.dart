// نسخة حرفية من lib/presentation/screens/settings/general_settings_widgets.dart
// (مصيدة النسخ §٥.٨) — أي إصلاح منطقي يتصلّح في المصدر أولاً ثم يُنقل بـ patch
// لهذا الملف. لا يُنسخ أبداً من D:\URAL-ERP.
//
// كل الكلاسات هنا خاصة (بادئة `_`) — خصوصية Dart مكتبة-بمكتبة، فمفيش تعارض
// أسماء مع settings_screen.dart الأصلي حتى لو الاثنين مستوردين من غير بادئة في
// app_main_screen.dart. مفيش أي تعديل منطقي أو تسمية هنا — part of فقط تغيّر.
part of 'settings_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// GENERAL SETTINGS WIDGETS — IndustryModeToggle, CurrencySelector,
//                             DeliveryToggle, CostingMethodToggle
// ═══════════════════════════════════════════════════════════════════════════

class _IndustryModeToggle extends ConsumerWidget {
  const _IndustryModeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(industryModeProvider);

    // صفُّ بلوكٍ لا `ListTile`: المحتوى في تصميم الإعدادات بطاقاتٌ مقسَّمةٌ
    // بشرائحِ قيم. والمنتقي أدناه كما هو.
    return SettingsValueRow(
      icon: PhosphorIconsBold.storefront,
      title: 'نوع النشاط',
      sub: 'يحدد الشاشات والحسابات المتاحة',
      value: _getShortModeLabel(mode),
      onTap: () => _showModeSelector(context, ref, mode),
    );
  }

  /// تسميةٌ قصيرةٌ تسع شريحةَ القيمة — الطويلةُ في [_getModeLabel] تُعرض
  /// داخلَ المنتقي حيث لا يضيق بها المكان.
  String _getShortModeLabel(IndustryMode mode) {
    switch (mode) {
      case IndustryMode.supermarket:
        return 'تجزئة';
      case IndustryMode.restaurant:
        return 'مطعم';
      case IndustryMode.cafe:
        return 'كافيه';
      default:
        return _getModeLabel(mode);
    }
  }

  String _getModeLabel(IndustryMode mode) {
    switch (mode) {
      case IndustryMode.supermarket:
        return 'سوبر ماركت / بقالة (بيع سريع)';
      case IndustryMode.restaurant:
        return 'مطعم (طاولات وصالات)';
      case IndustryMode.cafe:
        return 'كافيه (طلبات سريعة)';
      case IndustryMode.retail:
        return 'بيع بالتجزئة';
    }
  }

  void _showModeSelector(
    BuildContext context,
    WidgetRef ref,
    IndustryMode current,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('اختر نوع النشاط'),
          children: [
            _buildOption(
              ctx,
              ref,
              IndustryMode.supermarket,
              'سوبر ماركت / بيع بالتجزئة',
              PhosphorIconsBold.barcode,
              current,
            ),
            _buildOption(
              ctx,
              ref,
              IndustryMode.restaurant,
              'مطعم / صالات طعام',
              PhosphorIconsBold.cookingPot,
              current,
            ),
            _buildOption(
              ctx,
              ref,
              IndustryMode.cafe,
              'كافيه / طلبات سريعة',
              PhosphorIconsBold.coffee,
              current,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context,
    WidgetRef ref,
    IndustryMode mode,
    String label,
    IconData icon,
    IndustryMode current,
  ) {
    final isSelected = mode == current;
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppColors.primary : null),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? const Icon(PhosphorIconsBold.check, color: AppColors.success)
          : null,
      onTap: () {
        ref.read(industryModeProvider.notifier).setMode(mode);
        // #Forensic Log: Industry mode change
        try {
          final auth = ref.read(authProvider);
          final logger = ref.read(activityLoggerProvider);
          logger.logSettingsChange(
            auth.user?.id ?? 0,
            auth.user?.displayName ?? '',
            'نوع النشاط التجاري',
            newValue: label,
          );
        } catch (e) {
          debugPrint('[ActivityLog] Error: $e');
        }
        Navigator.pop(context);
      },
    );
  }
}

/// Currency selector widget — switches between EGP and JOD instantly
class _CurrencySelector extends ConsumerWidget {
  const _CurrencySelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentCode = ref.watch(systemCurrencyProvider);
    final info = CurrencyInfo.fromCode(currentCode);
    // ‏`false` أثناء التحميل: القفلُ يُشدّ حين يُعرَف أنه قفل، والمنعُ
    // الحقيقيُّ عند الكتابة على أيّ حال.
    final locked = ref.watch(currencyChangeLockedProvider).value ?? false;

    // ⚠️ `buildCurrencyTileGuarded` **مشتركٌ مع UralCash** فلا يُبدَّل رسمُه
    //    هناك. والحارسُ يُعاد بناؤه هنا حرفاً بحرف: القفلُ يمنع التبديل بعد
    //    تسجيل حركاتٍ ماليّة، والصلاحيةُ `settingsCurrency` مع تجاوز المدير.
    if (locked) {
      return SettingsValueRow(
        icon: PhosphorIconsBold.lockSimple,
        title: 'عملة النظام',
        sub: 'مقفولة بعد تسجيل حركات مالية — الدقة العشرية جزءٌ من كل '
            'مبلغ محفوظ',
        value: info.code,
        tint: AppColors.textMuted,
      );
    }

    return PermissionGuard(
      permission: PermissionCodes.settingsCurrency,
      allowManagerOverride: true,
      actionName: 'تغيير عملة النظام',
      onGranted: () => _showCurrencySelector(context, ref, currentCode),
      child: SettingsValueRow(
        icon: PhosphorIconsBold.currencyCircleDollar,
        title: 'عملة النظام',
        sub: 'كل المبالغ والتقارير',
        value: info.code,
        onTap: () => _showCurrencySelector(context, ref, currentCode),
      ),
    );
  }

  void _showCurrencySelector(
    BuildContext context,
    WidgetRef ref,
    String currentCode,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('اختر عملة النظام'),
          children: CurrencyInfo.all.map((c) {
            final isSelected = c.code == currentCode;
            return ListTile(
              leading: Text(
                c.symbolAr,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.primary : null,
                ),
              ),
              title: Text(
                c.nameAr,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: Text(c.code),
              trailing: isSelected
                  ? const Icon(
                      PhosphorIconsBold.check,
                      color: AppColors.success,
                    )
                  : null,
              onTap: () async {
                await ref
                    .read(systemCurrencyProvider.notifier)
                    .setCurrency(c.code);
                // Log activity
                try {
                  final auth = ref.read(authProvider);
                  final logger = ref.read(activityLoggerProvider);
                  logger.logSettingsChange(
                    auth.user?.id ?? 0,
                    auth.user?.displayName ?? '',
                    'عملة النظام',
                    newValue: '${c.nameAr} (${c.code})',
                  );
                } catch (e) {
                  debugPrint('[ActivityLog] Error: $e');
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _DeliveryToggle extends ConsumerStatefulWidget {
  const _DeliveryToggle();

  @override
  ConsumerState<_DeliveryToggle> createState() => _DeliveryToggleState();
}

class _DeliveryToggleState extends ConsumerState<_DeliveryToggle> {
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final val = await ref
        .read(settingsRepositoryProvider)
        .getSetting('enable_delivery');
    if (mounted) {
      setState(() {
        _enabled = val == 'true';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink(); // Or loading indicator
    return SwitchListTile(
      secondary: Icon(
        PhosphorIconsBold.moped,
        color: _enabled ? AppColors.success : Colors.grey,
      ),
      title: const Text('تفعيل خدمة التوصيل'),
      subtitle: Text(
        _enabled
            ? 'يمكنك إنشاء طلبات توصيل وإدارة المناديب'
            : 'خدمة التوصيل غير مفعلة',
      ),
      value: _enabled,
      onChanged: (v) async {
        setState(() => _enabled = v);
        await ref
            .read(settingsRepositoryProvider)
            .saveSetting('enable_delivery', v.toString());
        // #Forensic Log: Delivery toggle
        try {
          final auth = ref.read(authProvider);
          final logger = ref.read(activityLoggerProvider);
          await logger.logSettingsChange(
            auth.user?.id ?? 0,
            auth.user?.displayName ?? '',
            'خدمة التوصيل',
            newValue: v ? 'مفعل' : 'معطل',
          );
        } catch (e) {
          debugPrint('[ActivityLog] Error: $e');
        }
      },
    );
  }
}

// Feature 022 (follow-up): _NegativeSalesToggle was previously rendered
// here under Financial Settings. Moved to the POS Settings dialog
// (pos_settings_widget.dart `_buildMainPOSSection`) where operators
// expect to find it. The setting key (`enable_negative_sales`) is
// unchanged — the orchestrator reads the same value, the boot-time
// backfill still runs, and existing installs keep their previously
// written value.

/// عرض صيغة تحميل تكلفة المخزون — **للاطلاع لا للتغيير**.
///
/// كانت قائمة اختيار بين «آخر سعر شراء» و«متوسط مرجح». اتشالت لسببين:
///
/// ١. «آخر سعر شراء» مش صيغة تحميل تكلفة مسموحة — `IAS 2.25` بيحصر الصيغ في
///    المتوسط المرجّح وFIFO والتمييز المحدد. وكانت الافتراضية كمان.
/// ٢. حتى بين الصيغ المسموحة، تبديل الصيغة بعد التشغيل هو **تغيير في السياسة
///    المحاسبية** (`IAS 8`) بيستوجب تعديل بأثر رجعي — فتوجل حر في الإعدادات
///    هو نفسه مَخرج للمخالفة.
///
/// وعملياً الاختيار ما كانش بيعمل حاجة أصلاً: مسار الشراء الحيّ
/// (`purchase_dao.createPurchaseInvoice`) بيستعمل المتوسط المرجّح مثبَّتاً
/// ويتجاهل الإعداد.
class _CostingMethodToggle extends ConsumerStatefulWidget {
  const _CostingMethodToggle();

  @override
  ConsumerState<_CostingMethodToggle> createState() => _CostingMethodToggleState();
}

class _CostingMethodToggleState extends ConsumerState<_CostingMethodToggle> {
  CostingMethod _method = CostingMethod.weightedAverage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await CostingMethodService.load(ref.read(settingsRepositoryProvider));
    if (mounted) setState(() { _method = m; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    // بلا `onTap`: الصيغة قرار سياسة محاسبية بتتحدد مرة، مش تفضيل استخدام.
    return ListTile(
      leading: const Icon(
        PhosphorIconsBold.calculator,
        color: AppColors.info,
      ),
      title: const Text('طريقة حساب التكلفة'),
      subtitle: Text(
        '${CostingMethodService.label(_method)} — وفق IAS 2',
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Feature 009 / T027 — Stock-shortage policy: global default
// ═══════════════════════════════════════════════════════════════════════════

class _StockShortagePolicyToggle extends ConsumerStatefulWidget {
  const _StockShortagePolicyToggle();

  @override
  ConsumerState<_StockShortagePolicyToggle> createState() =>
      _StockShortagePolicyToggleState();
}

class _StockShortagePolicyToggleState
    extends ConsumerState<_StockShortagePolicyToggle> {
  StockShortagePolicy _policy = StockShortagePolicyService.defaultPolicy;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(settingsRepositoryProvider);
    final raw = await repo.getSetting('stock_shortage_policy');
    final p = StockShortagePolicyService.fromName(raw) ??
        StockShortagePolicyService.defaultPolicy;
    if (mounted) setState(() { _policy = p; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(
        PhosphorIconsBold.warning,
        color: AppColors.warning,
      ),
      title: const Text('سياسة النظام عند نقص الخامات'),
      subtitle: Text(_policy.arabicLabel),
      trailing: const Icon(PhosphorIconsBold.caretLeft),
      onTap: _showSelector,
    );
  }

  void _showSelector() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('اختر السياسة الافتراضية'),
          children: [
            for (final policy in StockShortagePolicy.values)
              _buildOption(ctx, policy),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(BuildContext context, StockShortagePolicy policy) {
    final isSelected = policy == _policy;
    final (subtitle, icon) = _describe(policy);
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppColors.primary : null),
      title: Text(
        policy.arabicLabel,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: isSelected
          ? const Icon(PhosphorIconsBold.check, color: AppColors.success)
          : null,
      onTap: () async {
        await StockShortagePolicyService.saveGlobal(
          ref.read(settingsRepositoryProvider),
          policy,
        );
        setState(() => _policy = policy);
        if (context.mounted) Navigator.pop(context);
      },
    );
  }

  static (String, IconData) _describe(StockShortagePolicy policy) {
    switch (policy) {
      case StockShortagePolicy.block:
        return (
          'يمنع البيع تماماً عند عدم كفاية الخامات وتظهر رسالة خطأ',
          PhosphorIconsBold.prohibit,
        );
      case StockShortagePolicy.allowNegative:
        return (
          'يسمح بإتمام البيع وتسجيل المخزون كرقم سالب — مناسب للمحلات السريعة',
          PhosphorIconsBold.minusCircle,
        );
      case StockShortagePolicy.clampToZero:
        return (
          'يخصم ما هو متاح فقط ويوقف عند صفر — لا يدخل المخزون فى السالب',
          PhosphorIconsBold.gauge,
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Feature 009 / T028 — Stock-shortage policy: per-branch matrix
// ═══════════════════════════════════════════════════════════════════════════

class _StockShortagePolicyPerBranchTile extends ConsumerWidget {
  const _StockShortagePolicyPerBranchTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(
        PhosphorIconsBold.buildings,
        color: AppColors.info,
      ),
      title: const Text('سياسة نقص الخامات لكل فرع'),
      subtitle: const Text('تخصيص السياسة لفرع بعينه (تتجاوز الافتراضى)'),
      trailing: const Icon(PhosphorIconsBold.caretLeft),
      onTap: () => _showMatrix(context, ref),
    );
  }

  void _showMatrix(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => const Directionality(
        textDirection: ui.TextDirection.rtl,
        child: _ShortagePolicyPerBranchDialog(),
      ),
    );
  }
}

class _ShortagePolicyPerBranchDialog extends ConsumerStatefulWidget {
  const _ShortagePolicyPerBranchDialog();

  @override
  ConsumerState<_ShortagePolicyPerBranchDialog> createState() =>
      _ShortagePolicyPerBranchDialogState();
}

class _ShortagePolicyPerBranchDialogState
    extends ConsumerState<_ShortagePolicyPerBranchDialog> {
  Map<int, StockShortagePolicy> _selections = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(settingsRepositoryProvider);
    final raw = await repo.getSetting('stock_shortage_policy_per_branch');
    final parsed = <int, StockShortagePolicy>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            final id = int.tryParse(k.toString());
            final p = StockShortagePolicyService.fromName(v?.toString());
            if (id != null && p != null) parsed[id] = p;
          });
        }
      } catch (_) {/* corrupted JSON — start empty */}
    }
    if (mounted) setState(() { _selections = parsed; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(allBranchesProvider);
    return PicPosDialog(
      icon: PhosphorIconsBold.warningDiamond,
      title: 'سياسة نقص الخامات لكل فرع',
      subtitle: 'اترك «افتراضى» للفروع التى تستخدم السياسة العامّة',
      width: 560,
      // ⚠️ حارسٌ داخليٌّ لا `null`: `onCancel: null` **يُخفي** زرَّ الإلغاء
      //    ولا يعطّله، فكان الزرُّ يختفي أثناء الحفظ بدل أن يخمُد.
      onCancel: () {
        if (!_saving) Navigator.pop(context);
      },
      body: [
        SizedBox(
        width: 500,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : branchesAsync.when(
                data: (branches) {
                  if (branches.isEmpty) {
                    return const Text('لا توجد فروع لعرضها');
                  }
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'اترك "افتراضى" للفروع التى تستخدم السياسة العامة. الإعداد لكل فرع يتجاوز الافتراضى ويسبق التخصيص لكل ماكينة.',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                        const Divider(),
                        for (final b in branches)
                          ListTile(
                            dense: true,
                            title: Text(b.name),
                            trailing: DropdownButton<StockShortagePolicy?>(
                              value: _selections[b.id],
                              hint: const Text('افتراضى'),
                              items: [
                                const DropdownMenuItem<StockShortagePolicy?>(
                                  value: null,
                                  child: Text('افتراضى'),
                                ),
                                for (final p in StockShortagePolicy.values)
                                  DropdownMenuItem<StockShortagePolicy?>(
                                    value: p,
                                    child: Text(p.arabicLabel),
                                  ),
                              ],
                              onChanged: (v) => setState(() {
                                if (v == null) {
                                  _selections.remove(b.id);
                                } else {
                                  _selections[b.id] = v;
                                }
                              }),
                            ),
                          ),
                      ],
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('خطأ فى تحميل الفروع: $e'),
              ),
      ),
      ],
      primaryAction: PicPosDialogAction(
        label: 'حفظ',
        icon: PhosphorIconsBold.floppyDisk,
        busy: _saving,
        onPressed: _saving
            ? null
            : () async {
                setState(() => _saving = true);
                try {
                  await StockShortagePolicyService.savePerBranch(
                    ref.read(settingsRepositoryProvider),
                    _selections,
                  );
                  if (context.mounted) Navigator.pop(context);
                } finally {
                  if (mounted) setState(() => _saving = false);
                }
              },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// C-03: Session Timeout Setting
// ═══════════════════════════════════════════════════════════════════════════

class _SessionTimeoutSetting extends ConsumerStatefulWidget {
  const _SessionTimeoutSetting();

  @override
  ConsumerState<_SessionTimeoutSetting> createState() => _SessionTimeoutSettingState();
}

class _SessionTimeoutSettingState extends ConsumerState<_SessionTimeoutSetting> {
  int _timeoutMinutes = 30;
  bool _loading = true;

  static const _options = [
    (value: 0, label: 'معطل'),
    (value: 5, label: '5 دقائق'),
    (value: 10, label: '10 دقائق'),
    (value: 15, label: '15 دقيقة'),
    (value: 30, label: '30 دقيقة'),
    (value: 60, label: 'ساعة'),
  ];

  @override
  void initState() {
    super.initState();
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final val = await ref
        .read(settingsRepositoryProvider)
        .getSetting('session_timeout_minutes');
    if (mounted) {
      setState(() {
        _timeoutMinutes = int.tryParse(val ?? '') ?? 30;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final label = _options.firstWhere(
      (o) => o.value == _timeoutMinutes,
      orElse: () => (value: _timeoutMinutes, label: '$_timeoutMinutes دقيقة'),
    ).label;

    return ListTile(
      leading: Icon(
        PhosphorIconsBold.timer,
        color: _timeoutMinutes > 0 ? AppColors.warning : Colors.grey,
      ),
      title: const Text('مهلة انتهاء الجلسة'),
      subtitle: Text(
        _timeoutMinutes > 0
            ? 'تسجيل خروج تلقائي بعد $label من عدم النشاط'
            : 'تسجيل الخروج التلقائي معطل',
      ),
      trailing: const Icon(PhosphorIconsBold.caretLeft),
      onTap: () => _showSelector(context),
    );
  }

  void _showSelector(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('مهلة انتهاء الجلسة'),
          children: _options.map((opt) {
            final isSelected = opt.value == _timeoutMinutes;
            return ListTile(
              leading: Icon(
                opt.value == 0 ? PhosphorIconsBold.prohibit : PhosphorIconsBold.timer,
                color: isSelected ? AppColors.primary : null,
              ),
              title: Text(
                opt.label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: isSelected
                  ? const Icon(PhosphorIconsBold.check, color: AppColors.success)
                  : null,
              onTap: () async {
                setState(() => _timeoutMinutes = opt.value);
                await ref
                    .read(settingsRepositoryProvider)
                    .saveSetting('session_timeout_minutes', opt.value.toString());
                // Push the new value to the live detector. Without this the
                // FutureProvider (no autoDispose, nothing else invalidates it
                // from here) kept serving the OLD duration until the app was
                // restarted — so choosing "معطل" here did not actually stop
                // the auto sign-out. The POS settings screen already did this;
                // this screen did not.
                ref.invalidate(sessionTimeoutProvider);
                // #Forensic Log
                try {
                  final auth = ref.read(authProvider);
                  final logger = ref.read(activityLoggerProvider);
                  await logger.logSettingsChange(
                    auth.user?.id ?? 0,
                    auth.user?.displayName ?? '',
                    'مهلة انتهاء الجلسة',
                    newValue: opt.label,
                  );
                } catch (e) {
                  debugPrint('[ActivityLog] Error: $e');
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
