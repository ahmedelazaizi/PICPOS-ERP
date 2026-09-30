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
      title: tr('نوع النشاط'),
      sub: tr('يحدد الشاشات والحسابات المتاحة'),
      value: _getShortModeLabel(mode),
      onTap: () => _showModeSelector(context, ref, mode),
    );
  }

  /// تسميةٌ قصيرةٌ تسع شريحةَ القيمة — الطويلةُ في [_getModeLabel] تُعرض
  /// داخلَ المنتقي حيث لا يضيق بها المكان.
  String _getShortModeLabel(IndustryMode mode) {
    switch (mode) {
      case IndustryMode.supermarket:
        return tr('تجزئة');
      case IndustryMode.restaurant:
        return tr('مطعم');
      case IndustryMode.cafe:
        return tr('كافيه');
      default:
        return _getModeLabel(mode);
    }
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

  /// ⚠️ كان `SimpleDialog` بشكل Material الافتراضيّ — وهو عينُ ما بلّغ عنه
  /// المالكُ بالصورة 2026-08-25 («التصميم القديم لا زال موجوداً»). صار
  /// `showPicPosOptionPicker` فيأخذ رأسَ `PicPosDialog` وتذييلَه.
  ///
  /// ⚠️ **وتبدّل السلوكُ عن قصد**: كانت النقرةُ تُطبِّق وتُغلق فوراً، فنقرةٌ
  /// خاطئةٌ هنا تبدّل شاشاتِ النظام كلَّها بلا تأكيد. صارت النقرةُ تُعلِّم
  /// وزرُّ «تطبيق» يُنفِّذ.
  Future<void> _showModeSelector(
    BuildContext context,
    WidgetRef ref,
    IndustryMode current,
  ) async {
    final picked = await showPicPosOptionPicker<IndustryMode>(
      context: context,
      icon: PhosphorIconsBold.storefront,
      title: tr('نوع النشاط'),
      subtitle: tr('يحدّد الشاشاتِ والحساباتِ المتاحة'),
      selected: current,
      options:  [
        PicPosOption(
          value: IndustryMode.supermarket,
          label: tr('سوبر ماركت / بيع بالتجزئة'),
          sub: tr('بيعٌ سريعٌ وباركود وميزان PLU'),
          icon: PhosphorIconsBold.barcode,
        ),
        PicPosOption(
          value: IndustryMode.restaurant,
          label: tr('مطعم / صالات طعام'),
          sub: tr('طاولاتٌ وحجوزاتٌ وتذاكرُ مطبخ'),
          icon: PhosphorIconsBold.cookingPot,
        ),
        PicPosOption(
          value: IndustryMode.cafe,
          label: tr('كافيه / طلبات سريعة'),
          sub: tr('طلباتٌ سريعةٌ بلا طاولات'),
          icon: PhosphorIconsBold.coffee,
        ),
      ],
    );

    if (picked == null || picked == current) return;
    ref.read(industryModeProvider.notifier).setMode(picked);

    // #Forensic Log: Industry mode change
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      logger.logSettingsChange(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        tr('نوع النشاط التجاري'),
        newValue: _getModeLabel(picked),
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
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
        title: tr('عملة النظام'),
        sub: tr('مقفولة بعد تسجيل حركات مالية — الدقة العشرية جزءٌ من كل مبلغ محفوظ'),
        value: info.code,
        tint: AppColors.textMuted,
      );
    }

    return PermissionGuard(
      permission: PermissionCodes.settingsCurrency,
      allowManagerOverride: true,
      actionName: tr('تغيير عملة النظام'),
      onGranted: () => _showCurrencySelector(context, ref, currentCode),
      child: SettingsValueRow(
        icon: PhosphorIconsBold.currencyCircleDollar,
        title: tr('عملة النظام'),
        sub: tr('كل المبالغ والتقارير'),
        value: info.code,
        onTap: () => _showCurrencySelector(context, ref, currentCode),
      ),
    );
  }

  /// ⚠️ **والعملةُ قرارٌ شبهُ نهائيّ** — التصميمُ يقول «لا تتغيّر بعد أوّل
  /// فاتورة». فتحويلُها من `SimpleDialog` (‏تُطبِّق باللمس) إلى منتقٍ بزرِّ
  /// «تطبيق» ليس تجميلاً: نقرةٌ خاطئةٌ كانت تبدّل عملةَ النظام كلِّه صامتةً.
  Future<void> _showCurrencySelector(
    BuildContext context,
    WidgetRef ref,
    String currentCode,
  ) async {
    final picked = await showPicPosOptionPicker<String>(
      context: context,
      icon: PhosphorIconsBold.currencyCircleDollar,
      title: tr('عملة النظام'),
      subtitle: tr('كلُّ المبالغ والتقارير — راجعها قبل أوّل فاتورة'),
      selected: currentCode,
      options: [
        for (final c in CurrencyInfo.all)
          PicPosOption(
            value: c.code,
            label: c.nameAr,
            sub: '${c.code} · ${c.symbolAr}',
          ),
      ],
    );

    if (picked == null || picked == currentCode) return;
    await ref.read(systemCurrencyProvider.notifier).setCurrency(picked);

    try {
      final info = CurrencyInfo.all.firstWhere((c) => c.code == picked);
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      logger.logSettingsChange(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        tr('عملة النظام'),
        newValue: '${info.nameAr} (${info.code})',
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
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

/// عرض صيغة تحميل تكلفة المخزون — **للاطلاع لا للتغيير**.
///
/// كانت قائمة اختيار بين «آخر سعر شراء» و«متوسط مرجح». اتشالت لسببين:
///
/// ١. «آخر سعر شراء» مش صيغة تحميل تكلفة مسموحة — `IAS 2.25` بيحصر الصيغ في
///    المتوسط المرجّح هو طريقة التقييم الوحيدة؛ FIFO/FEFO ترتيب انتقاء كمي فقط.
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
      title:  Text(tr('سياسة النظام عند نقص الخامات')),
      subtitle: Text(_policy.displayLabel),
      trailing: const Icon(PhosphorIconsBold.caretLeft),
      onTap: _showSelector,
    );
  }

  Future<void> _showSelector() async {
    final picked = await showPicPosOptionPicker<StockShortagePolicy>(
      context: context,
      icon: PhosphorIconsBold.warning,
      title: tr('سياسة نقص الخامات'),
      subtitle: tr('ماذا يحدث حين لا تكفي الكميّةُ عند البيع'),
      selected: _policy,
      options: [
        for (final p in StockShortagePolicy.values)
          PicPosOption(
            value: p,
            label: p.displayLabel,
            sub: _describe(p).$1,
            icon: _describe(p).$2,
          ),
      ],
    );

    if (picked == null || picked == _policy) return;
    await StockShortagePolicyService.saveGlobal(
      ref.read(settingsRepositoryProvider),
      picked,
    );
    // The POS stock guard reads the resolved sale policy.
    ref.invalidate(enableNegativeSalesProvider);
    if (mounted) setState(() => _policy = picked);
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
    return PicPosDialog(
      icon: PhosphorIconsBold.warningDiamond,
      title: tr('سياسة نقص الخامات لكل فرع'),
      subtitle: tr('اترك «افتراضى» للفروع التى تستخدم السياسة العامّة'),
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
      ],
      primaryAction: PicPosDialogAction(
        label: tr('حفظ'),
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
                  // The POS stock guard reads the resolved sale policy.
                  ref.invalidate(enableNegativeSalesProvider);
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

  Future<void> _showSelector(BuildContext context) async {
    final picked = await showPicPosOptionPicker<int>(
      context: context,
      icon: PhosphorIconsBold.timer,
      title: tr('مهلة انتهاء الجلسة'),
      subtitle: tr('تسجيلُ خروجٍ تلقائيٍّ بعد سكونٍ بهذه المدّة'),
      selected: _timeoutMinutes,
      options: [
        for (final opt in _options)
          PicPosOption(
            value: opt.value,
            label: opt.label,
            icon: opt.value == 0
                ? PhosphorIconsBold.prohibit
                : PhosphorIconsBold.timer,
            sub: opt.value == 0
                ? tr('الجلسةُ لا تنتهي — لا تستعمله على جهازٍ مشترك')
                : null,
          ),
      ],
    );

    if (picked == null || picked == _timeoutMinutes) return;
    setState(() => _timeoutMinutes = picked);
    await ref
        .read(settingsRepositoryProvider)
        .saveSetting('session_timeout_minutes', picked.toString());
    // Push the new value to the live detector. Without this the
    // FutureProvider (no autoDispose, nothing else invalidates it
    // from here) kept serving the OLD duration until the app was
    // restarted — so choosing "معطل" here did not actually stop
    // the auto sign-out. The POS settings screen already did this;
    // this screen did not.
    ref.invalidate(sessionTimeoutProvider);
    // #Forensic Log
    try {
      final label = _options.firstWhere((o) => o.value == picked).label;
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logSettingsChange(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        tr('مهلة انتهاء الجلسة'),
        newValue: label,
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
  }
}
