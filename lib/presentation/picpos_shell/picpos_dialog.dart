// نمطُ ديالوجات PicPos — الغلافُ المشترك لكلّ حوارات النظام.
//
// المصدر: تصميمُ Claude Design «تصميم شاشات فواتير PicPos» — الديالوجاتُ
// الثلاثة (سند قبض · سند صرف · مراجعة الأرصدة). وقد **قِيس أن الثلاثةَ
// تتشارك الغلافَ نفسَه حرفاً بحرف** ولا تختلف إلّا في شيئين: العرض
// (‏٧٦٠ للسندَين · ٦٦٠ للمراجعة) واللونِ المميّز. فبُني غلافاً واحداً
// بمُعامِلَين لا ثلاثةَ نسخٍ تنحرف بأوّل تعديل.
//
// ولهذا الملفُّ سببُ وجودٍ أبعدُ من الثلاثة: في `lib/` **١٠٤ ملفَّ حوار**،
// وكلٌّ منها يرسم رأسَه وتذييلَه بيده. فأيُّ تعديلٍ في الهويّة كان يعني
// ١٠٤ تعديلاً — أو انحرافاً صامتاً بين حوارٍ وآخر. الغلافُ هنا يجعلها
// تعديلاً واحداً.
//
// ═══ الاستعمال ═══
//
// ```dart
// PicPosDialog(
//   icon: PhosphorIconsBold.arrowCircleDown,
//   accent: AppColors.success,
//   title: 'سند قبض',
//   subtitle: 'RV-2026-0842 · 21 أغسطس 2026',
//   body: [ ...حقول... ],
//   secondaryActions: [PicPosDialogAction(label: 'طباعة A4', ...)],
//   primaryAction: PicPosDialogAction(label: 'حفظ السند', ...),
// )
// ```
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/i18n/tr.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/picpos_theme.dart';
import 'picpos_panel_groups.dart';
import 'picpos_surface.dart';

/// لونُ النصِّ الخافت — `--muted` في الوضعين.
Color picposDialogMuted(BuildContext context) => context.picposMuted;

/// لونُ الحقل — `--field` في الوضعين.
Color picposDialogField(BuildContext context) =>
    Theme.of(context).inputDecorationTheme.fillColor ??
    (Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF18243A)
        : PicPosTheme.lightFieldFill);

/// رقاقةُ حالةٍ في ترويسة الحوار — `bench.chips` في ملفّ التصميم.
///
/// تُستعمل في «منضدة العمل» (‏الحوارُ العريضُ ذو العمودَين): رقاقةٌ تُلخّص
/// حالةً مقيسةً بجانب العنوان — «٣ تعديلات غير محفوظة» مثلاً. و[tint] لونُ
/// النصّ والإطار؛ فإن كان `null` رُسمت رقاقةً محايدةً بلون الحقل.
class PicPosDialogChip {
  const PicPosDialogChip({required this.icon, required this.label, this.tint});

  final IconData icon;
  final String label;
  final Color? tint;
}

/// زرٌّ في تذييل الحوار.
class PicPosDialogAction {
  const PicPosDialogAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.busy = false,
  });

  final String label;

  /// `null` ⇒ معطَّل. يبقى الزرُّ مرئيّاً كي يعرف المستخدمُ أن الإجراءَ
  /// موجودٌ لكنّ شرطَه لم يكتمل — لا أن يختفي فيبدو غيرَ مدعوم.
  final VoidCallback? onPressed;

  final IconData? icon;

  /// لونُ الزرّ الرئيسيّ — يُهمَل في الأزرار الثانويّة.
  final Color? color;

  /// الإجراءُ قيد التنفيذ — تحلّ دوّارةٌ محلَّ الأيقونة.
  ///
  /// ولا يكفي [onPressed] الفارغُ وحدَه: زرٌّ معطَّلٌ بلا إشارةِ انشغالٍ
  /// يُقرأ «مكسور» لا «يعمل الآن»، فيُنقَر ثانيةً — وفي إجراءٍ يمسّ أرصدةً
  /// تكون النقرةُ الثانيةُ تشغيلاً ثانياً لو رُفع التعطيل يوماً.
  final bool busy;
}

/// غلافُ حوارٍ على هويّة PicPos: رأسٌ بأيقونةٍ ملوّنة، جسمٌ، وتذييلُ أزرار.
class PicPosDialog extends StatelessWidget {
  const PicPosDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.accent = AppColors.primary,
    this.subtitle,
    this.width = 760,
    this.primaryAction,
    this.secondaryActions = const [],
    this.cancelLabel,
    this.onCancel,
    this.scrollable = true,
    this.indexLabels = const [],
    this.headerChips = const [],
    this.footerHint,
    this.bodyFill = false,
  });

  final IconData icon;
  final String title;

  /// السطرُ الخافتُ تحت العنوان — رقمُ المستند وتاريخُه، أو وصفُ الغرض.
  final String? subtitle;

  final Color accent;

  /// ‏٧٦٠ في السندَين و٦٦٠ في مراجعة الأرصدة — وهما القياسان في التصميم.
  final double width;

  final List<Widget> body;
  final PicPosDialogAction? primaryAction;
  final List<PicPosDialogAction> secondaryActions;

  /// `null` ⇒ «إلغاء» مترجَمةً عبر `tr()` وقتَ الرسم — لا قيمةٌ افتراضيّةٌ
  /// عربيّةٌ ثابتةٌ تظهر كما هي في الواجهة الإنجليزيّة.
  final String? cancelLabel;

  /// `null` ⇒ لا زرَّ إلغاء. والافتراضُ إغلاقُ الحوار.
  final VoidCallback? onCancel;

  final bool scrollable;

  /// عناوينُ مجموعات الجسم — تُرسم عموداً مرقّماً على جانب اللوحة كما في
  /// التصميم (`panel.index`). أقلُّ من عنوانَين ⇒ لا عمود، وهو حالُ الحوارات
  /// التي ليست لوحاتِ مجموعات وحالُ اللوحة ذاتِ المجموعة الواحدة.
  ///
  /// ⚠️ **اشتقّها من المجموعات نفسِها** بـ`picposPanelLabels` — لا تكتبها
  /// بيدٍ ثانيةً بجانب الجسم فتنحرف عنه.
  final List<String> indexLabels;

  /// رقائقُ الحالة في الترويسة — تُرسَم بين العنوان وزرِّ الإغلاق.
  final List<PicPosDialogChip> headerChips;

  /// سطرُ التلميح في التذييل — `bench.hint` في التصميم.
  ///
  /// حين يُمرَّر، يتحوّل التذييلُ من `Wrap` إلى صفٍّ بثلاثة مواضع كما في
  /// التصميم: الإلغاءُ يميناً، والتلميحُ يتمدّد في الوسط، والإجراءُ الأساسيُّ
  /// يساراً. وبدونه يبقى `Wrap` كما هو لكلّ الحوارات القائمة.
  final String? footerHint;

  /// الجسمُ يملأ الارتفاعَ المتاحَ بدل أن يُقاس بمحتواه — لمنضدة العمل.
  ///
  /// ⚠️ **علَمٌ لا زخرفة.** الجسمُ في الوضع العاديّ داخلَ `Column` بـ
  /// `mainAxisSize: min`، و`Column` يمنح أبناءه ارتفاعاً **غيرَ محدود** —
  /// فأيُّ `LayoutBuilder` داخله يقرأ `maxHeight == infinity` ولا يستطيع أن
  /// يقيس المتاح. وُقع في ذلك فعلاً: الجسمُ سقط على قيمةٍ احتياطيّةٍ فطفح
  /// ١٠٧ بكسل، وأمسكه اختبارُ التركيب لا التحليل.
  ///
  /// فحين يكون `true` يُلغى العمودُ من المسار ويُسلَّم الطفلُ الأوّلُ وحدَه
  /// إلى `Flexible` — فيصل إليه القيدُ الحقيقيُّ ويقيسه بنفسه. ويقتضي جسماً
  /// بطفلٍ واحدٍ و`scrollable: false`.
  final bool bodyFill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = picposDialogMuted(context);

    return Directionality(
      textDirection: Directionality.of(context),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          // العرضُ سقفٌ لا إلزام: شاشةٌ أضيقُ من ٧٦٠ (لوحُ كاشيرٍ صغير)
          // كانت ستُخرج الحوارَ خارجَ حدّها لو ثُبِّت العرضُ تثبيتاً.
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: MediaQuery.of(context).size.height - 48,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(context, muted),
                Flexible(child: _bodyArea()),
                if (primaryAction != null ||
                    secondaryActions.isNotEmpty ||
                    onCancel != null ||
                    footerHint != null)
                  _footer(context, muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// منطقةُ الجسم: الجسمُ وحدَه، أو الجسمُ وبجانبه عمودُ أرقام المجموعات.
  ///
  /// ⚠️ **العمودُ خارجَ ناحيةِ التمرير** — في التصميم هو عمودٌ ثابتٌ بجانب
  /// المحتوى المتمرِّر، لا جزءٌ منه يزحف معه.
  ///
  /// و`IntrinsicHeight` هي ما يجعل الأمرَين يجتمعان: `CrossAxisAlignment
  /// .stretch` وحدَها تُجبر الصفَّ على **كامل** الارتفاع المتاح فيصير كلُّ
  /// حوارٍ بطولِ الشاشة ولو كان جسمُه سطرَين؛ ومع `IntrinsicHeight` يصير
  /// الارتفاعُ ارتفاعَ المحتوى مقصوصاً عند المتاح — فيقصر مع القصير ويتمرّر
  /// مع الطويل، والعمودُ ممتدٌّ بكامل الطول في الحالتين.
  Widget _bodyArea() {
    final content = scrollable
        ? SingleChildScrollView(child: _body())
        : _body();
    // عمودٌ برقمٍ واحدٍ فهرسٌ لا يفهرس شيئاً — وشريطٌ بعرض ٦٤ يقتطع من عرض
    // الجسم بلا مقابل. ولوحاتُ التصميم كلُّها مجموعتان فأكثر.
    if (indexLabels.length < 2) return content;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PicPosPanelIndexRail(labels: indexLabels),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _body() {
    if (bodyFill && body.length == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: body.first,
      );
    }
    return _bodyColumn();
  }

  Widget _bodyColumn() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < body.length; i++) ...[
          if (i > 0) const SizedBox(height: 13),
          body[i],
        ],
      ],
    ),
  );

  Widget _header(BuildContext context, Color muted) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          for (final c in headerChips) ...[
            _chip(context, c, muted),
            const SizedBox(width: 8),
          ],
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: onCancel ?? () => Navigator.of(context).maybePop(),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(PhosphorIconsBold.x, size: 14, color: muted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// رقاقةُ الترويسة — إطارٌ وأرضيّةٌ مشتقّان من [PicPosDialogChip.tint].
  Widget _chip(BuildContext context, PicPosDialogChip c, Color muted) {
    final tint = c.tint;
    final fg = tint ?? muted;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: tint == null
            ? picposDialogField(context)
            : tint.withValues(alpha: .10),
        border: Border.all(
          color: tint == null
              ? Theme.of(context).dividerColor
              : tint.withValues(alpha: .28),
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(c.icon, size: 13, color: fg),
          const SizedBox(width: 6),
          Text(
            c.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, Color muted) {
    final theme = Theme.of(context);
    final hint = footerHint;
    if (hint != null) {
      // تذييلُ «منضدة العمل»: إلغاءٌ ثمّ تلميحٌ متمدِّدٌ ثمّ الإجراءُ الأساسيّ.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: picposDialogField(context),
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            if (onCancel != null)
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  cancelLabel ?? tr('إلغاء'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
              ),
            for (final a in secondaryActions) ...[
              const SizedBox(width: 9),
              _secondary(context, a),
            ],
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Icon(PhosphorIconsBold.info, size: 14, color: muted),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (primaryAction != null) _primary(context, primaryAction!),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: picposDialogField(context),
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      // يلتفّ عند الضيق بدل أن يفيض: تذييلٌ بأربعة أزرارٍ على حوارِ ٦٦٠
      // كان يتجاوز عرضَه، والفيضُ شريطٌ أصفرُ وأسودُ لا قصٌّ صامت.
      child: Wrap(
        spacing: 9,
        runSpacing: 9,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final a in secondaryActions) _secondary(context, a),
          if (onCancel != null)
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                cancelLabel ?? tr('إلغاء'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
            ),
          if (primaryAction != null) _primary(context, primaryAction!),
        ],
      ),
    );
  }

  /// أيقونةُ الزرّ — أو دوّارةٌ بمقاسها حين يكون الإجراءُ قيد التنفيذ.
  ///
  /// المقاسُ ثابتٌ في الحالتين كي لا يقفز عرضُ الزرّ حين يبدأ العمل.
  static Widget _leading(PicPosDialogAction a, double size, Color spinner) {
    if (a.busy) {
      return SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: 2, color: spinner),
      );
    }
    return a.icon == null ? const SizedBox.shrink() : Icon(a.icon, size: size);
  }

  Widget _secondary(BuildContext context, PicPosDialogAction a) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: a.onPressed,
        icon: _leading(
          a,
          15,
          theme.textTheme.bodyMedium?.color ?? AppColors.primary,
        ),
        label: Text(
          a.label,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: theme.cardColor,
          side: BorderSide(color: theme.dividerColor, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _primary(BuildContext context, PicPosDialogAction a) {
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: a.onPressed,
        icon: _leading(a, 16, Colors.white),
        label: Text(
          a.label,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: a.color ?? accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

/// حوارُ تأكيدٍ على نمط PicPos — الشكلُ الغالبُ في النظام.
///
/// ‏٣٩٠ موضعَ `AlertDialog` في `lib/presentation` أكثرُها عنوانٌ ورسالةٌ
/// وزرّا إلغاءٍ وتأكيد. فبدل نقلِ كلٍّ منها يدويّاً إلى [PicPosDialog]
/// بثلاثين سطراً، يصير النقلُ سطرَين — وكلّما رخُص النقلُ زاد ما يُنقَل.
///
/// ⚠️ **ويُرجِع `false` لا `null` عند الإغلاق بلا اختيار.**
/// هذا ليس تجميلاً في نوعٍ: `showDialog<bool>` يُرجع `null` حين يُغلَق
/// الحوارُ بالمفتاح أو بالنقر خارجَه، و`if (result == true)` تنجو منها
/// بينما `if (result != false)` — أو `result!` — لا تنجو. وأخطرُها حوارُ
/// حذفٍ: إغلاقٌ عرَضيٌّ يُقرأ موافقةً. فالنوعُ هنا `bool` غيرُ لاغٍ،
/// والافتراضُ **الرفض**، فلا يُترَك القرارُ لطريقةِ فحصِ كلِّ مستدعٍ.
Future<bool> showPicPosConfirm(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  String? subtitle,
  Color accent = AppColors.primary,

  /// إجراءٌ مدمِّر — يصبغ الزرَّ الرئيسيَّ بلون الخطأ.
  bool danger = false,
  double width = 520,

  /// عناصرُ تُلحَق بالرسالة — أشهرُها [PicPosDialogSummary].
  ///
  /// ⚠️ حوارُ تأكيدٍ بلا **رقمٍ** يجعل القرارَ ظنّاً: «اعتماد القيد» يجعله
  /// مؤثّراً على الأرصدة ولا يمكن تعديله، فقيمتُه يجب أن تُقرأ في الحوار
  /// نفسِه لا أن تُفترَض من الشاشة خلفَه. وهذا ما يفعله التصميمُ في
  /// حوارَيه (‏`post` و`reverse` يعرضان أربعةَ أسطرِ ملخّص).
  List<Widget> details = const [],
}) async {
  final color = danger ? AppColors.error : accent;
  final result = await showDialog<bool>(
    context: context,
    // الإغلاقُ بالنقر خارجَه مسموحٌ، ويعني **رفضاً** — وهو ما يضمنه
    // `?? false` تحت.
    builder: (ctx) => PicPosDialog(
      icon: icon,
      accent: color,
      title: title,
      subtitle: subtitle,
      width: width,
      onCancel: () => Navigator.pop(ctx, false),
      cancelLabel: cancelLabel,
      primaryAction: PicPosDialogAction(
        label: confirmLabel ?? tr('تأكيد'),
        icon: danger ? PhosphorIconsBold.trash : PhosphorIconsBold.check,
        color: color,
        onPressed: () => Navigator.pop(ctx, true),
      ),
      body: [
        Text(
          message,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.6,
          ),
        ),
        ...details,
      ],
    ),
  );
  return result ?? false;
}

/// حقلٌ معنوَنٌ على نمط الحوار — عنوانٌ خافتٌ ثمّ صندوقُ الحقل.
class PicPosDialogField extends StatelessWidget {
  const PicPosDialogField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.boxed = true,
    this.height = 42,
  });

  final String label;
  final Widget child;

  /// نجمةٌ حمراءُ بجانب العنوان — كما في التصميم.
  final bool required;

  /// `false` حين يرسم الابنُ إطارَه بنفسه (‏`DropdownButtonFormField` مثلاً).
  final bool boxed;

  final double height;

  @override
  Widget build(BuildContext context) {
    final muted = picposDialogMuted(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
            ),
            if (required)
              const Text(
                ' *',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        if (boxed)
          Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: picposDialogField(context),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: AlignmentDirectional.centerStart,
            child: child,
          )
        else
          child,
      ],
    );
  }
}

/// بلاطةُ اختيارٍ — طريقةُ الدفع في التصميم، وأيُّ اختيارٍ متبادلٍ غيرِها.
class PicPosDialogChoice extends StatelessWidget {
  const PicPosDialogChoice({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = AppColors.primary,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = picposDialogMuted(context);
    return Material(
      color: selected ? accent.withValues(alpha: .10) : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? accent : theme.dividerColor,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: selected ? accent : muted),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    color: selected
                        ? accent
                        : theme.textTheme.bodyMedium?.color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريطُ تنبيهٍ ملوّنٌ بمعناه — أعلى جسمِ الحوار.
class PicPosDialogBanner extends StatelessWidget {
  const PicPosDialogBanner({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        border: Border.all(color: color.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// صندوقُ ملخّصٍ — أسطرُ «مفتاح ← قيمة» بإطارٍ واحد.
class PicPosDialogSummary extends StatelessWidget {
  const PicPosDialogSummary({super.key, required this.rows});

  /// القيمةُ تحمل لونَها: أحمرُ لمتبقٍّ، أخضرُ لمسدَّد، وهكذا.
  final List<({String label, String value, Color? color})> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = picposDialogMuted(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(11),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      rows[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    rows[i].value,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: rows[i].color ?? theme.textTheme.bodyLarge?.color,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
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

/// صفٌّ من حقولٍ متساويةِ الحصص — `grid-template-columns` في التصميم.
///
/// ينكسر رأسيّاً تحت [breakpoint] بدل أن يسحق الحقولَ إلى عرضٍ لا يُقرأ.
class PicPosDialogRow extends StatelessWidget {
  const PicPosDialogRow({
    super.key,
    required this.children,
    this.flex = const [],
    this.gap = 12,
    this.breakpoint = 520,
  });

  final List<Widget> children;

  /// حصصٌ اختياريّة — `[1, 2]` يعني الثاني ضعفَ الأوّل. وفارغةٌ ⇒ التساوي.
  final List<int> flex;

  final double gap;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(flex: i < flex.length ? flex[i] : 1, child: children[i]),
            ],
          ],
        );
      },
    );
  }
}
