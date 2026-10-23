import 'package:ural_erp/core/i18n/tr.dart';
import 'picpos_surface.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'picpos_header_actions.dart';

/// هيدر شاشات PicPos: خلفية فاتحة، عنوان داكن، وخط لوني سفلي 2.5px بلون العلامة
/// (فلسفة PicPosTheme: «شريط علوي فاتح بشريحة لونية سفلية»). التايبوغرافي من الثيم.
class PicPosPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;

  /// حقل بحث اختياري يوضع على يسار صف العنوان (بعرض محدود).
  final Widget? search;

  /// أزرار الإجراءات على أول الصف (يمين في RTL).
  final List<Widget> actions;

  /// بديلٌ اختياريّ عن [actions]: إجراءاتٌ بأولويّات تُقاس على العرض الفعليّ
  /// وتنتقل الأقلُّ أولويّةً منها إلى قائمة «⋯» بدل أن تنزلق خارجَ الشاشة.
  /// حين يُمرَّر يُهمَل [actions]؛ وحين لا يُمرَّر يبقى السلوكُ القديمُ كما هو
  /// (إجراءاتٌ في `SingleChildScrollView`) لكلّ الشاشات الأخرى.
  final List<PicPosHeaderAction>? actionsBar;

  /// رجوعٌ صريح: يرسم سهمَ الرجوع حتى حين لا يستطيع `Navigator.canPop`
  /// (شاشاتُ الشريط الجانبيّ ليست راوتاً مدفوعاً).
  final VoidCallback? onBack;

  const PicPosPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.search,
    this.actions = const [],
    this.actionsBar,
    this.onBack,
  });

  /// خانةُ العنوان. القديمُ: حصّةٌ مرنةٌ 28%. ومع [actionsBar]: عرضٌ طبيعيٌّ
  /// بسقف 240 — فيأخذ الشريطُ **كلَّ** ما تبقّى ويقيسه بدقّة، بدل أن يُحصَر في
  /// 72% فينزلق أوّلُ إجراءٍ خارجَ النافذة بصمت.
  Widget _titleSlot(Widget child) => actionsBar == null
      ? Flexible(flex: 28, child: child)
      : ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: child,
        );

  /// ذيلُ الصفّ مع [actionsBar]: البحثُ (إن وُجد) ثم الشريط.
  Widget _barTail() {
    final bar = PicPosHeaderActionsBar(actions: actionsBar!);
    if (search == null) return bar;
    return Row(
      children: [
        Flexible(
          flex: 2,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: search!,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(flex: 3, child: bar),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: const Border(
          bottom: BorderSide(color: AppColors.primary, width: 2.5),
        ),
      ),
      child: Row(
        children: [
          // زر رجوع يظهر تلقائياً لما الشاشة مدفوعة على راوت (مستوى أعمق /
          // شاشة فرعية بـ Navigator.push). شاشات الشريط الجانبي أعلى المكدّس
          // (canPop=false) فما بيظهرش عندها — التنقّل بينها بالشريط. في RTL
          // «رجوع» سهم لليمين (→) مطابقةً لباقي الشاشات.
          //
          // ⚠️ `arrow_back` لا `arrow_forward`: الاثنان يحملان
          // `matchTextDirection` فينعكسان وحدَهما في RTL. فـ`arrow_back`
          // يُرسَم → في RTL و← في LTR (نحو بداية السطر)، بينما
          // `arrow_forward` القديمُ كان يُرسَم ← في RTL و→ في LTR.
          if (onBack != null || Navigator.canPop(context)) ...[
            IconButton(
              key: const Key('picpos_header_back'),
              onPressed: onBack ?? () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back),
              color: AppColors.primary,
              tooltip: tr('رجوع'),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary.withValues(alpha: 0.08),
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
          ],
          // ⚠️ **`Flexible` لازمةٌ لا زينة.** كان العمودُ عارياً في الصفّ،
          // فيأخذ عرضَه الطبيعيَّ كاملاً ولا ينضغط. وسطرٌ خافتٌ طويلٌ
          // («الفروع ونقاط البيع والمخازن وتقويم العطلات وصلاحيات الوصول»)
          // يدفع البحثَ والأزرارَ خارجَ الشاشة: فيضٌ ٤٧٥ بكسل على عرض ٨٢٠،
          // أمسكه اختبارُ تركيب شاشة الفروع لا التحليل.
          //
          // والقصُّ بسطرٍ واحدٍ ونقاطٍ يُبقي الترويسةَ صفّاً واحداً كما في
          // التصميم بدل أن تنمو رأسيّاً على الشاشات الضيّقة.
          // حصّةٌ مرنةٌ لا عرضٌ طبيعيّ — راجع شرحَ مجموعة الذيل أدناه.
          _titleSlot(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr(title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineSmall,
                ),
                if (subtitle != null)
                  Text(
                    tr(subtitle!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // ⚠️ **مجموعةُ الذيل حصّةٌ مرنةٌ تتمرّر عند الضيق.** البحثُ
          // والأزرارُ كانا ودجتاتٍ عاريةً في الصفّ، فيأخذان عرضَهما الطبيعيَّ
          // كاملاً مهما ضاقت الشاشة. وشاشةٌ تجمع بحثاً (٣٢٠) ومنتقيَ طرفٍ
          // وزرَّي تصديرٍ وطباعةٍ تفيض ٢٧٤ بكسل على عرض ٨٢٠ — أمسكه اختبارُ
          // تركيب كشف الحساب لا التحليل.
          //
          // ═══ 🔴 وسقفُها كان ميّتاً منذ كُتب (‏بلاغٌ ميدانيّ 2026-09-21) ═══
          //
          // كان: `LayoutBuilder(maxWidth: c.maxWidth.isFinite ? c.maxWidth *
          // 0.72 : 720)` بعد `Spacer()`. و`LayoutBuilder` هناك طفلٌ **غيرُ
          // مرنٍ** في `Row`، و`Row` يعطي أطفالَه غيرَ المرنين قيداً أفقيّاً
          // **لا نهائيّاً** — فـ`isFinite` كاذبةٌ دائماً والسقفُ يقع على
          // الاحتياط `720` **مهما اتّسعت الشاشة**.
          //
          // وأثرُه عطبان متقابلان مقيسان:
          //   • على الواسع: المجموعةُ محصورةٌ في ٧٢٠ فتتمرّر، و`reverse`
          //     يثبّتها من آخرها ⇒ **أوّلُ زرٍّ يُقصّ** («إضافة طاولة» ظهر
          //     «ة طاولة» على نافذةٍ عرضُها ١٧٠٩)؛
          //   • وعلى الضيّق: تطلب ٧٢٠ وليست هناك ⇒ **صفُّ الترويسة يفيض**
          //     ‏١١٢ بكسلاً عند ٧٠٠.
          //
          // ⚠️ **والقصُّ لا يرمي ولا يُحذّر**: المجموعةُ تتمرّر ولا تفيض،
          //    فالزرُّ يختفي بصمتٍ تامّ — ولذلك يُقاس **العرضُ** لا الاستثناء.
          //
          // والعلاجُ حصّةٌ مرنةٌ صريحةٌ (٧٢ مقابلَ ٢٨ للعنوان) — وهي النيّةُ
          // المكتوبةُ أصلاً، تُنفَّذ الآن بدل أن تُروى. والتمريرُ يبقى: آليّةٌ
          // مقصودةٌ للضيق الحقيقيّ لا عَرَضٌ يُزال.
          if (actionsBar != null)
            Expanded(child: _barTail())
          else
          Expanded(
            flex: 72,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // الأزرارُ آخرَ المجموعة، وهي المقصودةُ بالضغط — فتبقى ظاهرةً
                // ويتوارى البحثُ أوّلاً عند الضيق.
                reverse: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (search != null) ...[
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: search!,
                      ),
                      const SizedBox(width: 12),
                    ],
                    ...actions,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
