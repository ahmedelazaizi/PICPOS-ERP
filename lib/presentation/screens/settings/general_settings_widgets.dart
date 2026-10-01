part of '../settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// GENERAL SETTINGS WIDGETS — IndustryModeToggle, CurrencySelector,
//                             DeliveryToggle, CostingMethodToggle
// ═══════════════════════════════════════════════════════════════════════════

class _IndustryModeToggle extends ConsumerWidget {
  const _IndustryModeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(industryModeProvider);

    return ListTile(
      leading: const Icon(
        PhosphorIconsBold.storefront,
        color: AppColors.primary,
      ),
      title:  Text(tr('نوع النشاط التجاري')),
      subtitle: Text(_getModeLabel(mode)),
      trailing: const Icon(PhosphorIconsBold.caretLeft),
      onTap: () => _showModeSelector(context, ref, mode),
    );
  }

  String _getModeLabel(IndustryMode mode) {
    switch (mode) {
      case IndustryMode.supermarket:
        return tr('سوبر ماركت / بقالة (بيع سريع)');
      case IndustryMode.restaurant:
        return tr('مطعم (طاولات وصالات)');
      case IndustryMode.cafe:
        return tr('كافيه (طلبات سريعة)');
      case IndustryMode.retail:
        return tr('بيع بالتجزئة');
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
          title:  Text(tr('اختر نوع النشاط')),
          children: [
            _buildOption(
              ctx,
              ref,
              IndustryMode.supermarket,
              tr('سوبر ماركت / بيع بالتجزئة'),
              PhosphorIconsBold.barcode,
              current,
            ),
            _buildOption(
              ctx,
              ref,
              IndustryMode.restaurant,
              tr('مطعم / صالات طعام'),
              PhosphorIconsBold.cookingPot,
              current,
            ),
            _buildOption(
              ctx,
              ref,
              IndustryMode.cafe,
              tr('كافيه / طلبات سريعة'),
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
            tr('نوع النشاط التجاري'),
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

    return buildCurrencyTileGuarded(
      subtitle: '${info.nameAr} (${info.code})',
      locked: ref.watch(currencyChangeLockedProvider).value ?? false,
      onOpen: () => _showCurrencySelector(context, ref, currentCode),
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
          title:  Text(tr('اختر عملة النظام')),
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
                    tr('عملة النظام'),
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
      title:  Text(tr('تفعيل خدمة التوصيل')),
      subtitle: Text(
        _enabled
            ? tr('يمكنك إنشاء طلبات توصيل وإدارة المناديب')
            : tr('خدمة التوصيل غير مفعلة'),
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
            tr('خدمة التوصيل'),
            newValue: v ? tr('مفعل') : tr('معطل'),
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

/// Costing method toggle — last purchase price vs weighted average
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
      title:  Text(tr('طريقة حساب التكلفة')),
      subtitle: Text(
        tr('{p0} — وفق IAS 2', {'p0': CostingMethodService.label(_method)}),
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
    // Show what a sale actually runs under — on a fresh install that is the
    // legacy `enable_negative_sales` fallback, not [defaultPolicy].
    final p = await StockShortagePolicyService.effectiveGlobalWith(
      repo.getSetting,
    );
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
      title:  Text(tr('سياسة النظام عند نقص الخامات')),
      subtitle: Text(_policy.displayLabel),
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
          title:  Text(tr('اختر السياسة الافتراضية')),
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
        policy.displayLabel,
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
          tr('يمنع البيع تماماً عند عدم كفاية الخامات وتظهر رسالة خطأ'),
          PhosphorIconsBold.prohibit,
        );
      case StockShortagePolicy.allowNegative:
        return (
          tr('يسمح بإتمام البيع وتسجيل المخزون كرقم سالب — مناسب للمحلات السريعة'),
          PhosphorIconsBold.minusCircle,
        );
      case StockShortagePolicy.clampToZero:
        return (
          tr('يخصم ما هو متاح فقط ويوقف عند صفر — لا يدخل المخزون فى السالب'),
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
      title:  Text(tr('سياسة نقص الخامات لكل فرع')),
      subtitle:  Text(tr('تخصيص السياسة لفرع بعينه (تتجاوز الافتراضى)')),
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
    return AlertDialog(
      title:  Text(tr('سياسة نقص الخامات لكل فرع')),
      content: SizedBox(
        width: 500,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : branchesAsync.when(
                data: (branches) {
                  if (branches.isEmpty) {
                    return  Text(tr('لا توجد فروع لعرضها'));
                  }
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                         Text(
                          tr('اترك "افتراضى" للفروع التى تستخدم السياسة العامة. الإعداد لكل فرع يتجاوز الافتراضى ويسبق التخصيص لكل ماكينة.'),
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                        const Divider(),
                        for (final b in branches)
                          ListTile(
                            dense: true,
                            title: Text(b.name),
                            trailing: DropdownButton<StockShortagePolicy?>(
                              value: _selections[b.id],
                              hint:  Text(tr('افتراضى')),
                              items: [
                                 DropdownMenuItem<StockShortagePolicy?>(
                                  value: null,
                                  child: Text(tr('افتراضى')),
                                ),
                                for (final p in StockShortagePolicy.values)
                                  DropdownMenuItem<StockShortagePolicy?>(
                                    value: p,
                                    child: Text(p.displayLabel),
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
                error: (e, _) => Text(tr('خطأ فى تحميل الفروع: {e}', {'e': e})),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child:  Text(tr('إلغاء')),
        ),
        ElevatedButton(
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
          child:  Text(tr('حفظ')),
        ),
      ],
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

  static List<({int value, String label})> get _options => [
    (value: 0, label: tr('معطل')),
    (value: 5, label: tr('5 دقائق')),
    (value: 10, label: tr('10 دقائق')),
    (value: 15, label: tr('15 دقيقة')),
    (value: 30, label: tr('30 دقيقة')),
    (value: 60, label: tr('ساعة')),
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
      orElse: () => (value: _timeoutMinutes, label: tr('{_timeoutMinutes} دقيقة', {'_timeoutMinutes': _timeoutMinutes})),
    ).label;

    return ListTile(
      leading: Icon(
        PhosphorIconsBold.timer,
        color: _timeoutMinutes > 0 ? AppColors.warning : Colors.grey,
      ),
      title:  Text(tr('مهلة انتهاء الجلسة')),
      subtitle: Text(
        _timeoutMinutes > 0
            ? tr('تسجيل خروج تلقائي بعد {label} من عدم النشاط', {'label': label})
            : tr('تسجيل الخروج التلقائي معطل'),
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
          title:  Text(tr('مهلة انتهاء الجلسة')),
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
                    tr('مهلة انتهاء الجلسة'),
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

