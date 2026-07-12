// ═══════════════════════════════════════════════════════════════════════════
// SETUP WIZARD — STEP 9: Touch Mode (Feature 031)
// ═══════════════════════════════════════════════════════════════════════════
//
// Per-device on-screen-keyboard preference. Two cards: ordinary desktop
// (default) vs touch / POS / all-in-one. Picking a card persists the
// `touchMode` setting through the cached repository AND updates the
// runtime provider, so the keyboard immediately reacts (it can be
// useful within the wizard's later steps if the operator is on a
// touch-only device).
// ═══════════════════════════════════════════════════════════════════════════

part of '../setup_wizard_screen.dart';

extension _TouchModeStep on _SetupWizardScreenState {
  Widget _buildTouchModeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'نمط الإدخال',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'اختر نوع الجهاز الذي يعمل عليه النظام. يمكن تغيير هذا الخيار '
          'لاحقًا من شاشة الإعدادات. الإعداد محلي على هذا الجهاز فقط ولا '
          'ينتشر إلى أجهزة أخرى في المزامنة.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        _touchModeCard(
          selected: !_touchMode,
          icon: PhosphorIconsBold.keyboard,
          title: 'جهاز عادي (لوحة مفاتيح)',
          description: 'كمبيوتر مكتبي أو لاب توب مع لوحة مفاتيح فعلية. لن '
              'تظهر أي لوحة مفاتيح على الشاشة.',
          onTap: () => _onTouchModePicked(false),
        ),
        const SizedBox(height: 12),
        _touchModeCard(
          selected: _touchMode,
          icon: PhosphorIconsBold.handTap,
          title: 'جهاز لمسي / POS',
          description: 'جهاز نقاط بيع أو شاشة لمس أو كاشير all-in-one. '
              'تظهر لوحة مفاتيح عربية / إنجليزية / رقمية على الشاشة عند '
              'لمس أي حقل إدخال.',
          onTap: () => _onTouchModePicked(true),
        ),
      ],
    );
  }

  Widget _touchModeCard({
    required bool selected,
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? PhosphorIconsBold.checkCircle
                  : PhosphorIconsBold.circle,
              color: selected ? AppColors.primary : AppColors.textMuted,
              size: 22,
            ),
            const SizedBox(width: 12),
            Icon(
              icon,
              size: 32,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onTouchModePicked(bool value) async {
    setState(() => _touchMode = value);
    // Persist + update the runtime provider so subsequent wizard fields
    // (and the rest of the app) immediately reflect the choice without a
    // restart (FR-020).
    await ref.read(touchModeProvider.notifier).set(value);
  }
}
