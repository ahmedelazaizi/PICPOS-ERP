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
    this.tooltip,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// سطرٌ يظهر عند المرور — عنوانُ الفرع، أو موقعُ المخزن وكونُه الافتراضيّ.
  ///
  /// ⚠️ **سببُ وجوده**: شريحةُ التصميم عنوانٌ وحدَه، بينما تعرض قوائمُ
  /// `CheckboxListTile` التي تحلّ الشريحةُ محلَّها سطراً ثانياً فيه بيانٌ
  /// حقيقيّ. فلولا هذا لكان النقلُ إلى التصميم **حذفاً لمعلومة** لا تنسيقاً.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final on = selected;
    // مطابقةُ التصميم: المحدّدةُ بحدِّ العلامة وأرضيّةِ الغسل ونصِّ العلامة،
    // وغيرُها بحدِّ الشعرة وأرضيّةِ الحقل ونصٍّ ثانويّ.
    final fg = on ? AppColors.primary : context.picposText;
    final chip = _chip(context, on, fg);
    final t = tooltip;
    return t == null || t.isEmpty ? chip : Tooltip(message: t, child: chip);
  }

  Widget _chip(BuildContext context, bool on, Color fg) {
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

/// عمودُ أرقام المجموعات على جانب اللوحة — `panel.index` في ملفّ التصميم.
///
/// رقمٌ لكلّ مجموعةٍ في اللوحة: الأوّلُ بأرضيّةِ العلامة وحدِّها ونصٍّ أبيض،
/// والباقي بأرضيّةِ البطاقة وحدِّ الشعرة ونصٍّ خافت. وبين كلِّ رقمٍ وتاليه
/// وصلةٌ شعريّةٌ رأسيّة.
///
/// ⚠️ **يأخذ العناوينَ لا العدد.** الرقمُ الذي يكذب أسوأُ من لا رقم، فمصدرُ
/// العمود هو قائمةُ المجموعات نفسُها عبر [picposPanelLabels] — لا عددٌ يُكتب
/// بيدٍ فينحرف أوّلَ ما تُضاف مجموعة.
///
/// ⚠️ **القياساتُ من التصميم لا مخترَعة**: عرضُ العمود ٦٤ وحشوُه الرأسيُّ ٢٠،
/// والرقمُ ٣٤×٣٤ باستدارة ١١ وحدٍّ ١.٥ وخطٍّ ١٢.٥ وزنُه ٨٠٠، والوصلةُ ١.٥×١٢.
///
/// ولا يُنقَل بالنقر: التصميمُ نموذجٌ ساكنٌ ولا يعرّف وجهةَ النقرة، وزرٌّ
/// يبدو قابلاً للنقر ولا يفعل شيئاً أسوأُ من رقمٍ ساكنٍ صريح. والعنوانُ يظهر
/// تلميحاً عند المرور.
class PicPosPanelIndexRail extends StatelessWidget {
  const PicPosPanelIndexRail({super.key, required this.labels});

  /// عناوينُ المجموعات بترتيبها — طولُها هو عددُ الأرقام.
  final List<String> labels;

  /// عرضُ العمود في التصميم.
  static const double width = 64;

  @override
  Widget build(BuildContext context) {
    final hairline = context.picposHairline;
    final side = BorderSide(color: hairline);
    // `border-inline-end` في التصميم: الحدُّ على الحافّة المواجهة للمحتوى،
    // وهي اليسرى في RTL واليمنى في LTR.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: context.picposField,
        border: rtl ? Border(left: side) : Border(right: side),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _badge(context, i),
            // الوصلةُ بعد كلِّ رقمٍ — كما يبثّها `sc-for` في التصميم.
            Container(width: 1.5, height: 12, color: hairline),
          ],
        ],
      ),
    );
  }

  Widget _badge(BuildContext context, int i) {
    final first = i == 0;
    return Tooltip(
      message: labels[i],
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: first ? AppColors.primary : context.picposCard,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: first ? AppColors.primary : context.picposHairline,
            width: 1.5,
          ),
        ),
        child: Text(
          '${i + 1}',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            // ⚠️ أبيضُ **مقدّمةٍ** على أرضيّةِ العلامة لا أرضيّةُ سطح: يبقى
            //    أبيضَ في الوضعين، وخريطةُ الحبر الداكن في التصميم لا تمسّ
            //    `#FFFFFF`.
            color: first ? Colors.white : context.picposMuted,
          ),
        ),
      ),
    );
  }
}

/// عناوينُ المجموعات بترتيبها — مصدرُ أرقام [PicPosPanelIndexRail].
///
/// تُقرأ من المجموعات المبنيّة نفسِها، فلا يمكن أن يختلف عددُ الأرقام عن عدد
/// المجموعات ولا نصُّ التلميح عن عنوانها.
List<String> picposPanelLabels(List<PicPosPanelGroup> groups) =>
    [for (final g in groups) g.label];

/// المجموعاتُ متباعدةً بمسافة التصميم بين المجموعات (‏`gap:20px`).
List<Widget> picposPanelBody(List<PicPosPanelGroup> groups) => [
      for (var i = 0; i < groups.length; i++) ...[
        if (i > 0) const SizedBox(height: 20),
        groups[i],
      ],
    ];

/// جسمُ مجموعةِ «قوّة كلمة المرور» (`kind:'strength'` في التصميم).
///
/// صندوقٌ بأرضيّةِ الحقل يضمّ: حقلَ الكلمة، ثمّ خمسةَ أشرطةٍ ومعها وصفُ
/// القوّة، ثمّ شبكةَ القواعد في عمودَين بعلامةِ تحقّقٍ لكلٍّ.
///
/// ⚠️ **لا يحسب قوّةً ولا قاعدة.** يأخذهما جاهزَين كي تبقى سياسةُ كلمة
/// المرور في `SecurityService` وحدَه — وواجهةٌ تعيد تطبيقَ نفس التعابير
/// النمطيّة تنحرف عن السياسة صامتةً أوّلَ ما تُعدَّل إحداهما.
///
/// ⚠️ **والقياساتُ من التصميم**: الصندوقُ استدارتُه ١٤ وحشوُه ١٦، والشريطُ
/// ارتفاعُه ٧ باستدارة ٤ وبينها ٥، والشبكةُ عمودان بفاصل ٨.
class PicPosPanelStrength extends StatelessWidget {
  const PicPosPanelStrength({
    super.key,
    required this.field,
    required this.strength,
    required this.strengthLabel,
    required this.rules,
  });

  /// حقلُ الكلمة نفسُه — يُمرَّر كما هو ليبقى واحداً في الفرعَين.
  final Widget field;

  /// ‏٠..١٠٠ كما يعطيها `SecurityService`.
  final int strength;

  final String strengthLabel;

  final List<({String label, bool ok})> rules;

  /// ⚠️ التصميمُ يرسم الحالةَ القويّةَ وحدَها (‏`#22C55E`)، فألوانُ الحالات
  /// الأضعف ليست فيه — وأُخذت من لوحة العلامة لا من `Colors.red` وأخواتها
  /// التي لا تتبع الثيم.
  Color get _tone => strength < 30
      ? AppColors.error
      : (strength < 70 ? AppColors.warning : AppColors.success);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final filled = (strength / 20).ceil().clamp(0, 5);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.picposHairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < 5; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(
                  child: Container(
                    height: 7,
                    decoration: BoxDecoration(
                      color: i < filled ? _tone : context.picposHairline,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 11),
              Text(
                strengthLabel,
                style: text.labelMedium
                    ?.copyWith(color: _tone, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          if (rules.isNotEmpty) ...[
            const SizedBox(height: 14),
            // ⚠️ `Wrap` بعرضٍ محسوبٍ لا `GridView`: الشبكةُ داخلَ عمودٍ
            //    متمرِّرٍ تحتاج ارتفاعاً مقيَّداً، و`shrinkWrap` عليها يعيد
            //    حسابَ كلِّ خانةٍ في كلّ إطار.
            LayoutBuilder(
              builder: (context, c) {
                final w = (c.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in rules)
                      SizedBox(width: w, child: _rule(context, r)),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _rule(BuildContext context, ({String label, bool ok}) r) {
    final fg = r.ok ? AppColors.success : context.picposMuted;
    return Row(
      children: [
        Icon(
          r.ok ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.circleDashed,
          size: 14,
          color: fg,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            r.label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
