import 'package:flutter/material.dart';

import '../../core/i18n/tr.dart';
import '../../core/theme/app_colors.dart';
import 'picpos_surface.dart';

/// شريطُ أفعالٍ سفليٌّ لشاشات المستندات.
///
/// ═══ لماذا واحدٌ لا واحدٌ لكلّ شاشة ═══
///
/// تصاميمُ المالك الستَّ عشرةَ تنتهي كلُّها بنفس الشريط: **رجوعٌ** يميناً،
/// و**حفظُ مسودةٍ** ثمّ **مراجعةٌ واعتماد** يساراً، وبينهما تلميحٌ أحياناً
/// («يتطلب الترحيل تساوي المدين والدائن»). وبناؤه في كلّ شاشةٍ على حدة يعني
/// ستَّ عشرةَ نسخةً تتباعد في التباعد والترتيب وحجم الزرّ.
///
/// و**زرّان منفصلان** قرارُ مالكٍ متكرّرٌ (سندُ الصرف · سندُ القبض · سندُ
/// القيد · طلبُ الاستبعاد): الحفظُ لا يُرحّل، والاعتمادُ خطوةٌ ثانيةٌ صريحة.
///
/// ⚠️ **و[primary] وحدَه هو المرحِّل.** خلطُ «حفظ» بـ«اعتماد» في زرٍّ واحدٍ
/// هو ما يجعل المستخدمَ يُرحّل مستنداً ظنَّ أنّه يحفظه مسوّدة.
class PicPosFormActionBar extends StatelessWidget {
  const PicPosFormActionBar({
    super.key,
    this.onBack,
    this.backLabel,
    this.draft,
    this.primary,
    this.hint,
    this.extras = const [],
    this.busy = false,
  });

  final VoidCallback? onBack;
  /// `null` ⇒ «رجوع» مترجَمةً عبر `tr()` وقتَ الرسم.
  final String? backLabel;

  /// «حفظ مسودة» — يُخفى بتمرير `null` لشاشةٍ بلا دورةِ مسوّدة.
  final PicPosFormAction? draft;

  /// «مراجعة واعتماد» — الفعلُ المرحِّل.
  final PicPosFormAction? primary;

  /// تلميحٌ يسارَ الأزرار (شرطُ الترحيل مثلاً).
  final String? hint;

  /// أفعالٌ إضافيّةٌ (معاينة · طباعة · حفظٌ كعرض سعر).
  final List<Widget> extras;

  /// أثناء الحفظ: كلُّ الأزرار تُعطَّل — لا الزرُّ المضغوطُ وحدَه.
  ///
  /// ⚠️ تعطيلُ المضغوطِ وحدَه يترك «مراجعة واعتماد» حيّاً أثناء حفظِ مسوّدةٍ،
  /// فضغطةٌ ثانيةٌ تُرحّل مستنداً نصفَ محفوظ.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final muted = context.picposMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: muted.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          if (onBack != null)
            OutlinedButton.icon(
              onPressed: busy ? null : onBack,
              // ⚠️ `chevron_left` لا `chevron_right`: أيقوناتُ Material هذه
              // تحمل `matchTextDirection` فتنعكس وحدَها في RTL. فـ«يسارٌ»
              // يُرسَم «‹» في LTR و«›» في RTL — أي نحو بداية السطر دائماً.
              // و`chevron_right` القديمةُ كانت تشير إلى النهاية في الاتجاهين.
              icon: const Icon(Icons.chevron_left, size: 18),
              label: Text(backLabel ?? tr('رجوع')),
            )
          else
            const SizedBox.shrink(),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hint != null)
                Text(
                  hint!,
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ...extras,
              if (draft case final d?)
                OutlinedButton.icon(
                  onPressed: busy ? null : d.onPressed,
                  icon: Icon(d.icon ?? Icons.save_outlined, size: 18),
                  label: Text(d.label),
                ),
              if (primary case final p?)
                FilledButton.icon(
                  onPressed: busy ? null : p.onPressed,
                  icon: Icon(p.icon ?? Icons.check, size: 18),
                  label: Text(p.label),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// فعلٌ في شريط الأفعال. `onPressed` الفارغُ يُعطّل الزرَّ ولا يُخفيه —
/// الاختفاءُ يُخفي عن المستخدم أنّ الفعلَ موجودٌ أصلاً.
class PicPosFormAction {
  const PicPosFormAction({
    required this.label,
    this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
}
