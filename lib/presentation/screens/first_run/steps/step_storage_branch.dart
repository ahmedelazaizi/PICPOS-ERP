// الخطوة ٣ (فرع) — حفظ البيانات: دورُ الجهاز في الفرع (أوّل جهاز أو إضافيّ) مع
// فحوص القاعدة المحلية نفسها. «الإضافيّ» عميلٌ آخرُ للرئيسي بنفس الفرع (E5/B13):
// لا خادمَ فرعٍ طبقيّاً ولا قاعدةً منفصلة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../domain/models/first_run/first_run_invalidation.dart' as inv;
import '../../../../domain/models/first_run/first_run_path.dart';
import '../first_run_controller.dart';
import '../widgets/first_run_callout.dart';
import '../widgets/first_run_choice_card.dart';
import 'step_storage_local.dart';

class StepStorageBranch extends ConsumerWidget {
  const StepStorageBranch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(firstRunControllerProvider.select((s) => s.draft.branchRole));
    final ctl = ref.read(firstRunControllerProvider.notifier);
    Future<void> choose(BranchDeviceRole r) async {
      ctl.update((d) =>
          inv.invalidate(d.copyWith(branchRole: r), inv.FirstRunField.branchRole));
      // الإبطال يصفّر فحص المجلد — يُعاد فحصه فوراً كي لا يعلق «التالي».
      await ctl.recheckStorage();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FirstRunChoiceCard(
          key: const Key('first_run_branch_role_first'),
          icon: Icons.dns_outlined,
          title: tr('أول جهاز في الفرع'),
          subtitle: tr('يحفظ نسخة كاملة من بيانات الفرع محليًا ويزامنها مع الرئيسي.'),
          selected: role == BranchDeviceRole.first,
          onTap: () => choose(BranchDeviceRole.first),
        ),
        const SizedBox(height: 10),
        FirstRunChoiceCard(
          key: const Key('first_run_branch_role_additional'),
          icon: Icons.devices_other_outlined,
          title: tr('جهاز إضافي داخل الفرع'),
          subtitle: tr('عميل آخر للسيرفر الرئيسي بنفس الفرع، له قاعدته المحلية وجهاز مستقل.'),
          selected: role == BranchDeviceRole.additional,
          onTap: () => choose(BranchDeviceRole.additional),
        ),
        if (role == BranchDeviceRole.additional) ...[
          const SizedBox(height: 10),
          FirstRunCallout(
            key: const Key('first_run_branch_additional_note'),
            title: tr('لا يُنشأ خادم فرع ولا قاعدة مشتركة.'),
            body: tr('يتصل هذا الجهاز بالسيرفر الرئيسي مباشرة ويُسجَّل برمز طرفية مستقل.'),
          ),
        ],
        const SizedBox(height: 16),
        const StepStorageLocal(),
      ],
    );
  }
}
