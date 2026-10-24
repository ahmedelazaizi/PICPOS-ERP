// الخطوة ١ — طريقة التشغيل: اللغة + ثلاثُ بطاقات + «خيارات متقدمة» (المرآة).
//
// التفعيلُ ليس من الإعداد الأول: سطرُ معلومةٍ للقراءة فقط يوجّه إلى
// الإعدادات › حول (قرار المالك 2026-10-23).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/locale_provider.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../data/providers/providers.dart';
import '../../../../domain/models/first_run/first_run_path.dart';
import '../first_run_controller.dart';
import '../first_run_texts.dart';
import '../widgets/first_run_callout.dart';
import '../widgets/first_run_choice_card.dart';

/// اللغةُ تُطبَّق فوراً وتُحفَظ افتراضيّاً للجهاز (`device_locale`).
Future<void> setFirstRunLanguage(WidgetRef ref, String code) async {
  final locale = localeForCode(code);
  I18nCatalog.setLocale(locale);
  try {
    await ref.read(userLocaleProvider.notifier).setLocale(locale);
    await UserLocalePreference.saveDevice(
      ref.read(settingsRepositoryProvider),
      locale,
    );
  } catch (_) {
    // فشلُ حفظ اللغة لا يوقف الإعداد.
  }
}

class StepMode extends ConsumerWidget {
  const StepMode({super.key, required this.onOpenMirror});

  /// المرآةُ تُفتح في المعالج القديم حتى P6.
  final VoidCallback onOpenMirror;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(firstRunControllerProvider.select((s) => s.draft.path));
    final ctl = ref.read(firstRunControllerProvider.notifier);
    final isEnglish = I18nCatalog.activeLocale.languageCode == 'en';
    const icons = {
      FirstRunPath.standalone: Icons.computer_outlined,
      FirstRunPath.hq: Icons.dns_outlined,
      FirstRunPath.branch: Icons.store_outlined,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              key: const Key('first_run_lang_ar'),
              label: const Text('العربية'),
              selected: !isEnglish,
              onSelected: (_) => setFirstRunLanguage(ref, 'ar'),
            ),
            ChoiceChip(
              key: const Key('first_run_lang_en'),
              label: const Text('English'),
              selected: isEnglish,
              onSelected: (_) => setFirstRunLanguage(ref, 'en'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final p in FirstRunPath.values) ...[
          FirstRunChoiceCard(
            key: Key('first_run_path_${p.name}'),
            icon: icons[p]!,
            title: firstRunPathTitle(p),
            subtitle: firstRunPathSubtitle(p),
            selected: path == p,
            onTap: () => ctl.selectPathTo(p),
          ),
          const SizedBox(height: 10),
        ],
        if (path == FirstRunPath.branch)
          FirstRunCallout(
            title: tr('اختيار «فرع تابع» لا يمنح صلاحية مدير.'),
            body: tr('حساب الموظف وصلاحياته يُحددان من الإدارة الرئيسية.'),
            tone: FirstRunTone.warning,
            icon: Icons.warning_amber_rounded,
          ),
        if (path != FirstRunPath.standalone)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: FirstRunCallout(
              key: const Key('first_run_legacy_note'),
              title: tr('سيُكمل هذا المسار بالمعالج الحالي مؤقتًا.'),
              body: tr('خطوات الخادم والفرع الجديدة قيد التنفيذ؛ سيفتح «التالي» معالج الخادم/الربط الحالي.'),
            ),
          ),
        const SizedBox(height: 10),
        FirstRunCallout(
          key: const Key('first_run_license_note'),
          title: tr('يمكن التفعيل لاحقًا من الإعدادات › حول'),
          body: tr('تعمل النسخة بوضع التجربة قبل التفعيل، ولا يلزم التفعيل لإكمال هذا الإعداد.'),
          icon: Icons.verified_outlined,
        ),
        const SizedBox(height: 6),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('first_run_advanced'),
            tilePadding: EdgeInsets.zero,
            title: Text(tr('خيارات متقدمة')),
            children: [
              FirstRunChoiceCard(
                key: const Key('first_run_path_mirror'),
                icon: Icons.copy_all_outlined,
                title: tr('نسخة مرآة للسيرفر الرئيسي'),
                subtitle: tr('تعرض بيانات المقر وتعمل كجهاز مدير؛ تفتح معالج المرآة الحالي.'),
                selected: false,
                onTap: onOpenMirror,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
