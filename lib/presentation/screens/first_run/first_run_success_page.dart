// صفحةُ النجاح — تظهر بعد كتابة `setup_completed` فعلاً (آخر كتابة)، لا قبلها.
// «الخطوة التالية» نصٌّ ثابتٌ للمسار المستقلّ؛ التفعيلُ يُذكر كوجهةٍ في الإعدادات
// فقط ولا يُنفَّذ هنا.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/models/first_run/first_run_steps.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'first_run_controller.dart';
import 'first_run_texts.dart';
import 'widgets/first_run_callout.dart';

class FirstRunSuccessPage extends ConsumerWidget {
  const FirstRunSuccessPage({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(firstRunControllerProvider);
    final next = <(IconData, String)>[
      (Icons.login, tr('ادخل بحساب المسؤول (admin) وكلمة المرور التي اخترتها.')),
      (Icons.inventory_2_outlined, tr('أضف أصنافك وأسعارها من شاشة الأصناف.')),
      (Icons.group_add_outlined, tr('أنشئ مستخدميك وصلاحياتهم من الإعدادات.')),
      (Icons.print_outlined, tr('جهّز الطابعة من الإعدادات › الطابعات.')),
      (Icons.verified_outlined, tr('فعّل النسخة من الإعدادات › حول.')),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success.withValues(alpha: 0.14),
                ),
                child: const Icon(Icons.check_rounded, size: 44, color: AppColors.success),
              ),
              const SizedBox(height: 16),
              Text(
                firstRunStepTitle(FirstRunStep.success),
                key: const Key('first_run_success_title'),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: context.picposText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.draft.companyName.trim(),
                style: TextStyle(fontSize: 15, color: context.picposMuted),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.picposCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.picposHairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('الخطوة التالية'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: context.picposText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final (icon, text) in next)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(icon, size: 18, color: context.picposBrandInk),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                text,
                                style: TextStyle(color: context.picposText),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (s.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                FirstRunCallout(
                  key: const Key('first_run_success_warnings'),
                  title: tr('اكتمل الإعداد، لكن مع تحذيرات: {p0}. يُفضَّل إعادة تشغيل التطبيق.',
                      {'p0': s.warnings.join(tr('، '))}),
                  tone: FirstRunTone.warning,
                  icon: Icons.warning_amber_rounded,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('first_run_start'),
                onPressed: onStart,
                icon: const Icon(Icons.arrow_forward),
                label: Text(tr('ابدأ الاستخدام')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
