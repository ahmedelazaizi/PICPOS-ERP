// خطوةُ الترحيب — بندُ المالك ٦، الخطوة ١.
//
// كلُّ ما يخصّ **هذا الجهاز** في مكانٍ واحدٍ قبل أيّ بيانٍ تجاريّ: اللغة،
// وحالةُ الترخيص، وطريقةُ التشغيل (‏التي تقرّر بقيّةَ المسار)، ونمطُ الإدخال.
//
// ⚠️ **نمطُ التشغيل هنا لا في خطوة الفرع**: هو الذي يحدّد أيَّ خطواتٍ تلي —
// العميلُ لا يسأل عن الصناديق، والخادمُ يحتاج PostgreSQL — فاختيارُه بعد ثلاث
// خطواتٍ كان يبدّل المسارَ تحت مستخدمٍ قطع نصفَه.
part of '../setup_wizard_screen.dart';

extension _SetupWizardWelcomeExt on _SetupWizardScreenState {
  Widget _buildWelcomeStep() {
    final isEnglish = I18nCatalog.activeLocale.languageCode == 'en';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLicenseBanner(),
        const SizedBox(height: 18),

        // ── اللغة ──
        _stepFieldLabel(tr('لغة الواجهة')),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _choiceCard(
                key: const Key('setup_lang_ar'),
                icon: PhosphorIconsBold.translate,
                title: 'العربية',
                subtitle: tr('الواجهة من اليمين إلى اليسار'),
                selected: !isEnglish,
                onTap: () => _setLanguage('ar'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _choiceCard(
                key: const Key('setup_lang_en'),
                icon: PhosphorIconsBold.globe,
                title: 'English',
                subtitle: tr('الواجهة من اليسار إلى اليمين'),
                selected: isEnglish,
                onTap: () => _setLanguage('en'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── طريقة التشغيل ──
        _stepFieldLabel(tr('طريقة تشغيل هذا الجهاز')),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth < 760 ? 2 : 4;
            const gap = 10.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (mode, title, sub, icon) in _modeCards)
                  SizedBox(
                    width: w,
                    child: _choiceCard(
                      key: Key('setup_mode_${mode.name}'),
                      icon: icon,
                      title: title,
                      subtitle: sub,
                      selected: _networkMode == mode,
                      onTap: () => setState(() => _networkMode = mode),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),

        // ── نمط الإدخال ──
        _stepFieldLabel(tr('نمط الإدخال')),
        const SizedBox(height: 4),
        Text(
          tr('إعدادٌ خاصٌّ بهذا الجهاز وحدَه — لا يُزامَن مع باقي الأجهزة.'),
          style: TextStyle(fontSize: 12, color: _mutedInk(context)),
        ),
        const SizedBox(height: 8),
        _buildTouchModeSection(),
      ],
    );
  }

  List<(NetworkMode, String, String, IconData)> get _modeCards => [
        (
          NetworkMode.standalone,
          tr('مستقل'),
          tr('جهازٌ واحدٌ بقاعدةٍ محلّيّة — الأنسبُ لمحلٍّ واحد'),
          PhosphorIconsBold.desktop,
        ),
        (
          NetworkMode.server,
          tr('سيرفر'),
          tr('قاعدةُ PostgreSQL مركزيّةٌ تتّصل بها الأجهزةُ الأخرى'),
          PhosphorIconsBold.hardDrives,
        ),
        (
          NetworkMode.client,
          tr('عميل'),
          tr('كاشيرٌ يتّصل بسيرفرٍ قائمٍ ويزامن بياناته منه'),
          PhosphorIconsBold.monitor,
        ),
        (
          NetworkMode.mirror,
          tr('مرآة'),
          tr('لابتوبُ المدير بصلاحياتٍ كاملةٍ على كلّ الفروع'),
          PhosphorIconsBold.crown,
        ),
      ];

  /// حالةُ الترخيص — من الذاكرة المؤقّتة لا من القرص.
  ///
  /// ⚠️ `TrialState.isActivatedCached` تملؤه شاشةُ البدء؛ وقراءةُ الملفّات
  /// هنا تُبطئ أوّلَ رسمٍ ولا تضيف شيئاً — والتفعيلُ نفسُه من «الترخيص».
  Widget _buildLicenseBanner() {
    final activated = LicenseService.isActivatedCached;
    final trial = LicenseService.isTrial;
    final tone = activated
        ? AppColors.success
        : (trial ? AppColors.warning : AppColors.info);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsBold.clock, size: 20, color: _brandInk(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('{p0} خطواتٍ قصيرة — نحو خمس دقائق', {'p0': _totalSteps}),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  tr('كلُّ ما تختاره هنا يظهر في المراجعة قبل الحفظ، ويمكن تعديلُه لاحقاً من الإعدادات.'),
                  style: TextStyle(fontSize: 12, color: _mutedInk(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            key: const Key('setup_license_status'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.10),
              border: Border.all(color: tone.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  activated
                      ? PhosphorIconsBold.sealCheck
                      : PhosphorIconsBold.key,
                  size: 14,
                  color: tone,
                ),
                const SizedBox(width: 6),
                Text(
                  activated
                      ? tr('النسخة مفعّلة')
                      : (trial ? tr('نسخة تجريبية') : tr('غير مفعّلة')),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: tone,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
