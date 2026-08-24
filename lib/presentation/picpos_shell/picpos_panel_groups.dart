// مجموعاتُ لوحات PicPos — لبناتُ `PANELS` في ملفّ التصميم.
//
// كلُّ لوحةٍ في التصميم سلسلةُ **مجموعات**، لكلٍّ منها عنوانٌ (‏وشريطٌ لونيٌّ
// صغيرٌ قبله) وتلميحٌ اختياريٌّ، ثمّ جسمٌ بأحد الأنواع:
//
//     fields · chips · toggles · rows · note · key · keypad · strength
//
// الجاهزُ منها قبل هذا الملفّ: `fields` → `PicPosDialogField`، و`rows` →
// `PicPosDialogRow`، و`note` → `PicPosDialogBanner`، و`toggles` →
// `SettingsSwitchRow`. والناقصُ ما هنا: رأسُ المجموعة، والشرائح، وحاويةُ
// الصندوق التي تلفّ `toggles`/`rows` (‏حدٌّ + استدارة + أرضيّةُ الحقل).
//
// ⚠️ **القياساتُ منقولةٌ من التصميم لا مخترَعة**: ارتفاعُ الشريحة ٤٠ واستدارتُها
// ١١ وحدُّها ١.٥؛ وشريطُ العنوان ٣.٥×١٥ باستدارة ٣؛ والصندوقُ استدارتُه ١٤
// وحشوُه الأفقيُّ ١٥. تبديلُها يفكّ الاتّساقَ مع بقيّة الشاشات.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import 'picpos_surface.dart';

/// رأسُ مجموعةٍ داخل لوحة: شريطٌ لونيٌّ + عنوانٌ + تلميحٌ خافت.
class PicPosPanelGroup extends StatelessWidget {
  const PicPosPanelGroup({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;

  /// السطرُ الخافتُ بجانب العنوان — «دور واحد لكل مستخدم» وأمثالُه.
  final String? hint;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 3.5,
              height: 15,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                label,
                style: text.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (hint != null && hint!.isNotEmpty) ...[
              const SizedBox(width: 9),
              // ⚠️ `Flexible` لا `Text` عارياً: تلميحاتُ التصميم تبلغ «يظهر فقط
              //    مخازن الفروع المحددة» — صفٌّ بلا مرونةٍ يفيض بها عند ٦٦٠px.
              Flexible(
                child: Text(
                  hint!,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(
                    color: context.picposMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

/// صندوقُ مجموعةٍ — يلفّ `toggles` و`rows` بحدٍّ وأرضيّةِ حقل.
class PicPosPanelBox extends StatelessWidget {
  const PicPosPanelBox({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.picposHairline),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// شريحةُ اختيارٍ واحدة (`kind:'chips'`).
class PicPosPanelChip extends StatelessWidget {
  const PicPosPanelChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = selected;
    // مطابقةُ التصميم: المحدّدةُ بحدِّ العلامة وأرضيّةِ الغسل ونصِّ العلامة،
    // وغيرُها بحدِّ الشعرة وأرضيّةِ الحقل ونصٍّ ثانويّ.
    final fg = on ? AppColors.primary : context.picposText;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: on
                ? AppColors.primary.withValues(alpha: 0.08)
                : context.picposField,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: on ? AppColors.primary : context.picposHairline,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.circle,
                size: 16,
                color: fg,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// صفُّ شرائحَ يلتفّ على الشاشات الضيّقة (`kind:'chips'`).
///
/// ⚠️ `Wrap` لا `Row`: مجموعةُ «الفروع المسموحة» في التصميم أربعُ شرائحَ
/// وقد تصير عشراً في تركيبٍ حقيقيّ — وصفٌّ بلا التفافٍ يفيض بلا إنذار.
class PicPosPanelChips extends StatelessWidget {
  const PicPosPanelChips({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 9, runSpacing: 9, children: children);
  }
}
