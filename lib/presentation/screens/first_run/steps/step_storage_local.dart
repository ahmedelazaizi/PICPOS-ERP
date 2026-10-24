// الخطوة ٣ (مستقل) — حفظ البيانات: مسارُ القاعدة **للقراءة فقط** (B14) مع فحصٍ
// لقابلية الكتابة وكشفِ بياناتٍ سابقة. نقلُ قاعدةٍ مشفَّرةٍ مفتوحةٍ خطرٌ على
// البيانات فلا يُعرض اختيارُ مجلد.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/tr.dart';
import '../../../picpos_shell/picpos_surface.dart';
import '../first_run_controller.dart';
import '../widgets/first_run_callout.dart';
import '../widgets/first_run_field.dart';

class StepStorageLocal extends ConsumerWidget {
  const StepStorageLocal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(firstRunControllerProvider.select((s) => s.storage));
    final ok = storage?.writable ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FirstRunField(
          key: const Key('first_run_db_path'),
          label: tr('ملف قاعدة البيانات'),
          value: storage?.path ?? '',
          readOnly: true,
          ltr: true,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FirstRunStatusBadge(
              key: const Key('first_run_storage_badge'),
              label: storage == null
                  ? tr('جارٍ الفحص…')
                  : ok
                      ? tr('جاهز للكتابة')
                      : tr('غير قابل للكتابة'),
              tone: storage == null
                  ? FirstRunTone.info
                  : ok
                      ? FirstRunTone.success
                      : FirstRunTone.danger,
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              key: const Key('first_run_storage_recheck'),
              onPressed: () =>
                  ref.read(firstRunControllerProvider.notifier).recheckStorage(),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(tr('إعادة الفحص')),
            ),
          ],
        ),
        if (storage != null && !ok) ...[
          const SizedBox(height: 12),
          FirstRunCallout(
            title: tr('تعذّرت الكتابة في مجلد البيانات.'),
            body: storage.error,
            tone: FirstRunTone.danger,
            icon: Icons.error_outline,
          ),
        ],
        if (storage?.hasPriorData ?? false) ...[
          const SizedBox(height: 12),
          FirstRunCallout(
            key: const Key('first_run_prior_data'),
            title: tr('توجد بيانات سابقة في هذه القاعدة.'),
            body: tr('سيُحدَّث الإعداد فوقها دون حذف شيء. للاستعادة من نسخة احتياطية استعملها من الإعدادات بعد البدء.'),
            tone: FirstRunTone.warning,
            icon: Icons.warning_amber_rounded,
          ),
        ],
        const SizedBox(height: 12),
        FirstRunCallout(
          title: tr('البيانات مشفّرة ومحفوظة على هذا الجهاز فقط.'),
          body: tr('تُحفظ النسخ الاحتياطية المحلية بجوارها، ويمكن ضبط النسخ عن بُعد لاحقًا.'),
        ),
        const SizedBox(height: 10),
        Text(
          tr('يمكن تعديل هذا لاحقًا من الإعدادات › النسخ الاحتياطي.'),
          style: TextStyle(fontSize: 12, color: context.picposMuted),
        ),
      ],
    );
  }
}
