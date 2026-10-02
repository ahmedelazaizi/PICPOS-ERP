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
  // بندُ المالك ٦: قسمٌ في خطوة الترحيب (‏إعدادُ جهازٍ بجوار اللغة ونمط
  // التشغيل) لا خطوةٌ مستقلّة. البطاقتان نفسُهما بنصوصهما، على `_choiceCard`
  // التابعة للثيم بدل `AppColors.border`/`textMuted` المثبَّتَين للفاتح.
  //
  // «اختر نوع الجهاز… الإعداد محلي على هذا الجهاز فقط ولا ينتشر إلى أجهزة
  // أخرى في المزامنة» — يقولها الآن وصفُ القسم في الترحيب.
  Widget _buildTouchModeSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _choiceCard(
            key: const Key('setup_touch_off'),
            icon: PhosphorIconsBold.keyboard,
            title: tr('جهاز عادي (لوحة مفاتيح)'),
            subtitle: tr('كمبيوتر مكتبي أو لاب توب مع لوحة مفاتيح فعلية. لن تظهر أي لوحة مفاتيح على الشاشة.'),
            selected: !_touchMode,
            onTap: () => _onTouchModePicked(false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _choiceCard(
            key: const Key('setup_touch_on'),
            icon: PhosphorIconsBold.handTap,
            title: tr('جهاز لمسي / POS'),
            subtitle: tr('جهاز نقاط بيع أو شاشة لمس أو كاشير all-in-one. تظهر لوحة مفاتيح عربية / إنجليزية / رقمية على الشاشة عند لمس أي حقل إدخال.'),
            selected: _touchMode,
            onTap: () => _onTouchModePicked(true),
          ),
        ),
      ],
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
