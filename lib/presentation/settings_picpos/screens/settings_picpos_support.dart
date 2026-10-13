part of 'settings_picpos_screen.dart';


/// E-Invoicing visibility toggles — hide/show ETA/JOFOTARA sections
class _EInvoiceVisibilityToggles extends ConsumerStatefulWidget {
  const _EInvoiceVisibilityToggles();

  @override
  ConsumerState<_EInvoiceVisibilityToggles> createState() => _EInvoiceVisibilityTogglesState();
}

class _EInvoiceVisibilityTogglesState extends ConsumerState<_EInvoiceVisibilityToggles> {
  bool _showEta = true;
  bool _showJofotara = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(settingsRepositoryProvider);
    final etaVal = await repo.getSetting('show_eta_einvoice');
    final joVal = await repo.getSetting('show_jofotara_einvoice');
    if (mounted) {
      setState(() {
        _showEta = etaVal != 'false';
        _showJofotara = joVal != 'false';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          secondary: const Text('🇪🇬', style: TextStyle(fontSize: 22)),
          title:  Text(tr('إظهار الفوترة المصرية (ETA)')),
          subtitle:  Text(tr('منظومة ETA — مصلحة الضرائب المصرية')),
          value: _showEta,
          onChanged: (v) async {
            setState(() => _showEta = v);
            await ref.read(settingsRepositoryProvider).saveSetting('show_eta_einvoice', v.toString());
          },
        ),
        SwitchListTile(
          secondary: const Text('🇯🇴', style: TextStyle(fontSize: 22)),
          title:  Text(tr('إظهار الفوترة الأردنية (JOFOTARA)')),
          subtitle:  Text(tr('منظومة JOFOTARA — دائرة ضريبة الدخل')),
          value: _showJofotara,
          onChanged: (v) async {
            setState(() => _showJofotara = v);
            await ref.read(settingsRepositoryProvider).saveSetting('show_jofotara_einvoice', v.toString());
          },
        ),
      ],
    );
  }
}

// Spec 078 — بلاطةُ جاهزيّة صلاحيّات السيرفر (‏توأمُ نظيرتها في
// `settings_screen.dart`).
//
// ⚠️ كانت مفتاحَ تشغيلٍ يقرأ `server_per_user_perms_enabled` ويعرض
// «غير مُفعّل» على كلِّ تنصيبةٍ لأنّ المفتاحَ لا يُزرع أبداً. والفحصُ صار
// يُنفَّذ بلا شرط، فالبلاطةُ الآن **تصف الحقيقة** وتفتح تقريرَ الاستطلاع.
class _ServerPermsToggleTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ServerPermsToggleTile> createState() =>
      _ServerPermsToggleTileState();
}

class _ServerPermsToggleTileState
    extends ConsumerState<_ServerPermsToggleTile> {
  Future<void> _openDialog() async {
    final db = ref.read(databaseProvider);
    await ServerPermsToggleDialog.show(context: context, db: db);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(
        PhosphorIconsBold.shieldCheck,
        color: AppColors.success,
      ),
      title:  Text(tr('فحص الصلاحيات على السيرفر')),
      subtitle:  Text(
        tr('مُفعّل دائماً — اضغط لفحص الأدوار التي ينقصها منح'),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(PhosphorIconsBold.caretLeft, size: 18),
      onTap: _openDialog,
    );
  }
}

/// قسم واحد في شاشة الإعدادات.
///
/// [children] دالة مش قائمة جاهزة عن قصد: محتوى الأقسام بيقرا feature flags
/// و`NetworkService.isClient` و`PermissionGuard`، فلازم يتبني وقت العرض مش
/// وقت تعريف القائمة.
class _SettingsSection {
  final String id;
  final String title;
  final IconData icon;

  /// مجموعةُ القسم في عمود التصميم — أربعُ مجموعاتٍ تجمع الأقسام التسعة.
  ///
  /// ⚠️ **ولا عدّادَ إعداداتٍ هنا.** التصميمُ يعرض رقماً لكلّ قسم (‏١٤ · ١٢ ·
  /// ١١ …) ومجموعَه ٩٤ في نصّ البحث، وهو رقمٌ **لا يمكن قياسُه من الشجرة**:
  /// معظمُ الإعدادات داخلَ حواراتٍ وبطاقاتٍ متداخلةٍ بلا هويّةٍ مُعنوَنة.
  /// ورقمٌ مكتوبٌ بيدٍ يبطُل عند أوّل إضافة — فالعدُّ مُسقَطٌ عمداً بدل عرضِ
  /// عددٍ يكذب.
  final String group;

  /// سطرُ الوصف تحت العنوان في العمود — يشرح ما يضمّه القسم.
  final String desc;

  /// كلمات البحث. بتظهر كمان كسطر وصف تحت اسم القسم في نتايج البحث، فهي
  /// مش مخفية — المستخدم بيشوف ليه القسم ده طلع.
  final String keywords;

  final List<Widget> Function() children;

  const _SettingsSection({
    required this.id,
    required this.title,
    required this.icon,
    required this.group,
    required this.desc,
    required this.keywords,
    required this.children,
  });
}

/// ترتيبُ مجموعات العمود كما في التصميم.
  // ignore: unused_element
List<String> get _kSettingsGroupOrder => <String>[
  tr('التشغيل'),
  tr('الأمان'),
  tr('المال والبيانات'),
  tr('الامتدادات'),
];

/// ترويسةُ القسم — أيقونةٌ ٥٦px وعنوانٌ كبيرٌ وسطرُ وصف، كما في التصميم.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});

  final _SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(section.icon, size: 27, color: AppColors.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: text.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                section.desc,
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// صفوفُ بلوكات قسم «النظام والمظهر»
// ═══════════════════════════════════════════════════════════════════════════

class _TouchModeSwitchRow extends ConsumerWidget {
  const _TouchModeSwitchRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(touchModeProvider);
    return SettingsSwitchRow(
      first: true,
      icon: PhosphorIconsBold.handTap,
      title: tr('نمط الإدخال اللمسي'),
      sub: tr('لوحة مفاتيح على الشاشة في حقول الأرقام'),
      value: on,
      onChanged: (v) => ref.read(touchModeProvider.notifier).set(v),
    );
  }
}

/// مربّعاتُ «الشاشات المتقدمة» — بحالةٍ مقيسةٍ لا مفترَضة.
/// صفوفُ «الأقسام المحميّة» — تُبنى من [kPicPosGuardedSections] لا من قائمةٍ
/// مكتوبةٍ هنا.
///
/// ⚠️ **ولماذا سجلٌّ في ملفٍّ آخر:** لأنّ المفتاحَ المعروضَ وعدٌ، والوفاءُ به
/// عند `SecurityScreenGate` في `app_main_screen.dart`. والسجلُّ هو الرابطُ
/// الذي يقيسه `guarded_sections_have_real_gates_test` — فلا يُعرَض قفلٌ لقسمٍ
/// بلا بوّابة.
///
/// و**الحالةُ تُقرأ لا تُفترَض**: مفتاحٌ مضبوطٌ ⇒ «مفعَّل»، وفارغٌ ⇒ «مفتوح».
class _GuardedSectionRows extends ConsumerWidget {
  const _GuardedSectionRows({required this.features});

  final FeaturePolicy features;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_guardedSectionStateProvider);

    // `hr_access_password` وحدَه يتبع `features.hrEnabled`: الوحدةُ نفسُها
    // غيرُ موجودةٍ في `lite`، فقفلُها بلا معنى. وبقيّةُ الأقسام في كلّ
    // بروفايل.
    final sections = kPicPosGuardedSections.where((s) {
      if (s.settingKey == 'hr_access_password') return features.hrEnabled;
      return true;
    }).toList();

    return SettingsRowsBody(
      children: [
        for (var i = 0; i < sections.length; i++)
          SettingsValueRow(
            first: i == 0,
            icon: sections[i].icon,
            title: sections[i].title,
            sub: sections[i].sub,
            // ⚠️ القيمةُ من الحالة الحيّة لا من افتراض. وقبل وصولِها
            //    تُترك فارغةً بدل أن تُعرض «مفتوح» تفاؤلاً — فقفلٌ يُقرأ
            //    مفتوحاً وهو مقفولٌ يُقلق، والعكسُ يُطمئن كذباً.
            value: state.when(
              data: (m) => (m[sections[i].settingKey] ?? false)
                  ? tr('مفعَّل')
                  : tr('مفتوح'),
              loading: () => null,
              error: (_, _) => null,
            ),
            tint: state.value?[sections[i].settingKey] == true
                ? AppColors.error
                : AppColors.textMuted,
            onTap: () => _showSectionPasswordDialogFor(
              context,
              ref,
              sections[i].settingKey,
              sections[i].title,
            ),
          ),
      ],
    );
  }
}

/// حالةُ الأقفال — `true` يعني أنّ للقسم كلمةً مضبوطة.
final _guardedSectionStateProvider =
    FutureProvider.autoDispose<Map<String, bool>>((ref) async {
  final repo = ref.watch(settingsRepositoryProvider);
  final out = <String, bool>{};
  for (final s in kPicPosGuardedSections) {
    final pw = await repo.getSetting(s.settingKey);
    out[s.settingKey] = pw != null && pw.isNotEmpty;
  }
  return out;
});

/// نسخةٌ حرّةٌ من حوار كلمة القسم تصلح خارجَ حالةِ الشاشة.
///
/// ⚠️ وتُبطِل [_guardedSectionStateProvider] بعد الحفظ: بلا ذلك يبقى الصفُّ
/// يقول «مفتوح» بعد ضبطِ كلمةٍ للتوّ — والحالةُ الكاذبةُ هنا تُطمئن بغير حقّ.
Future<void> _showSectionPasswordDialogFor(
  BuildContext context,
  WidgetRef ref,
  String key,
  String title,
) async {
  final repo = ref.read(settingsRepositoryProvider);
  final current = await repo.getSetting(key);
  if (!context.mounted) return;

  final controller = TextEditingController(text: current ?? '');
  final result = await showDialog<String?>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: Directionality.of(context),
      child: PicPosDialog(
        icon: PhosphorIconsBold.lockKey,
        title: tr('كلمة مرور {title}', {'title': title}),
        subtitle: tr('اتركها فارغةً لفتح القسم بلا كلمة'),
        width: 460,
        onCancel: () => Navigator.pop(ctx),
        body: [
          PicPosDialogField(
            label: tr('كلمة المرور'),
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
        ],
        primaryAction: PicPosDialogAction(
          label: tr('حفظ'),
          icon: PhosphorIconsBold.floppyDisk,
          onPressed: () => Navigator.pop(ctx, controller.text),
        ),
      ),
    ),
  );
  controller.dispose();

  if (result == null) return;
  await repo.saveSetting(key, result);
  ref.invalidate(_guardedSectionStateProvider);
  if (context.mounted) {
    AppToast.show(
      context,
      result.isEmpty ? tr('فُتح القسم — بلا كلمة') : tr('حُفظت كلمة {title}', {'title': title}),
      type: ToastType.success,
    );
  }
}

