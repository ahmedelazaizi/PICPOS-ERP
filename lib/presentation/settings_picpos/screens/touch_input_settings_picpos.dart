// نسخة حرفية من lib/presentation/screens/settings/touch_input_settings.dart
// (مصيدة النسخ §٥.٨) — أي إصلاح منطقي يتصلّح في المصدر أولاً ثم يُنقل بـ patch
// لهذا الملف. لا يُنسخ أبداً من D:\URAL-ERP. `part of` فقط تغيّر — لا تعديل
// منطقي ولا تسمية (الكلاس خاص، لا تعارض عبر المكتبات).
part of 'settings_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TOUCH INPUT SETTINGS — Feature 031
// ═══════════════════════════════════════════════════════════════════════════
//
// Runtime toggle for the on-screen touch keyboard. Per-device only — the
// `touchMode` setting is excluded from sync (FR-019), so flipping this
// here does NOT propagate to other devices in the same cluster.
//
// Flipping the toggle takes effect on the next text-field focus event,
// no app restart required (FR-020).
// ═══════════════════════════════════════════════════════════════════════════

class _TouchInputSettings extends ConsumerWidget {
  const _TouchInputSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOn = ref.watch(touchModeProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text(
              'جهاز لمسي / POS',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'تظهر لوحة مفاتيح عربية / إنجليزية / رقمية على الشاشة عند '
              'لمس أي حقل إدخال في كل شاشات النظام.',
              style: TextStyle(fontSize: 12),
            ),
            value: isOn,
            onChanged: (v) =>
                ref.read(touchModeProvider.notifier).set(v),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  PhosphorIconsBold.info,
                  color: AppColors.info,
                  size: 16,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'هذا الإعداد محلي على هذا الجهاز فقط ولا ينتقل للأجهزة '
                    'الأخرى في المزامنة. التغيير يُفعَّل فوراً بدون إعادة تشغيل.',
                    style: TextStyle(fontSize: 11, color: AppColors.info),
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
