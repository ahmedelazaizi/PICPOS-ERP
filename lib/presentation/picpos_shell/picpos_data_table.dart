// جدولُ بيانات PicPos — كتلةُ `kind:'table'` في ملفّات تصميم الشاشات.
//
// ═══ لماذا لبنةٌ واحدةٌ لا جدولٌ في كلّ شاشة ═══
//
// الكتلةُ نفسُها تتكرّر في **كلّ** تبويبةٍ من تبويبات التصميم الجديدة —
// الفروعُ ونقاطُ البيع والمخازنُ والعطلاتُ والمسارات والزياراتُ والموظفون
// والحضورُ والرواتبُ والشيكاتُ والأصولُ والولاء. وترميزُها متطابقٌ حرفيّاً:
// رأسٌ بشريطٍ ملوَّنٍ وعنوانٍ وشرائحِ ترشيح، ثمّ صفُّ عناوينِ أعمدةٍ على
// أرضيّةِ الحقل، ثمّ صفوفٌ بخلايا مصنَّفةٍ، ثمّ صفُّ مجاميعَ اختياريّ.
//
// فكتابتُها في كلّ شاشةٍ تعني عشرين نسخةً تنحرف بأوّل تعديلٍ في الهويّة.
//
// ═══ الخليّةُ مصنَّفةٌ لا حرّة ═══
//
// التصميمُ يعرّف ستَّ صيغٍ للخليّة ولا سابعةَ لها: نصٌّ (بأيقونةٍ وسطرٍ
// خافتٍ اختياريَّين) · حبّةٌ ملوَّنة · شريطُ نسبة · اتّجاهٌ بسهم · زرُّ إجراء.
// وحصرُها في نوعٍ مغلقٍ يمنع أن تخترع كلُّ شاشةٍ صيغتَها.
//
// ⚠️ **والعرضُ نِسَبٌ لا بكسلات.** التصميمُ يكتب `grid` مثل
// `1.9fr 1.3fr 1.4fr …` — فتُمرَّر [PicPosTableColumn.flex] بنفس الأرقام،
// ويتمرّر الجدولُ أفقيّاً حين لا يتّسع بدل أن يهرس الأعمدة.
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'picpos_surface.dart';

/// محاذاةُ العمود — البداية أو النهاية (‏`align:'end'` في التصميم).
enum PicPosCellAlign { start, end }

/// عمودٌ في الجدول: عنوانٌ ووزنٌ نسبيٌّ ومحاذاة.
class PicPosTableColumn {
  const PicPosTableColumn(
    this.label, {
    this.flex = 1,
    this.align = PicPosCellAlign.start,
  });

  final String label;
  final double flex;
  final PicPosCellAlign align;
}

/// شريحةُ ترشيحٍ في رأس الجدول — «كل المخازن ٦» · «بها نقص ٤».
class PicPosTableChip {
  const PicPosTableChip({
    required this.label,
    required this.count,
    this.onTap,
  });

  final String label;
  final String count;
  final VoidCallback? onTap;
}

/// خليّةٌ واحدة — مغلقةٌ على صيغ التصميم الستّ.
sealed class PicPosCell {
  const PicPosCell();
}

/// نصٌّ، وقد يسبقه مربّعُ أيقونةٍ ويتبعه سطرٌ خافت.
class PicPosTextCell extends PicPosCell {
  const PicPosTextCell(this.text, {this.sub, this.icon, this.tint, this.bold});

  final String text;
  final String? sub;
  final IconData? icon;
  final Color? tint;

  /// `null` ⇒ يتبع محاذاةَ العمود كما في التصميم: المحاذاةُ للنهاية أعرضُ
  /// خطّاً (٨٠٠) لأنّها أرقام، والبدايةُ ٧٠٠.
  final bool? bold;
}

/// حبّةٌ ملوَّنة — الحالةُ والنوع.
class PicPosPillCell extends PicPosCell {
  const PicPosPillCell(this.text, this.tint);

  final String text;
  final Color tint;
}

/// شريطُ نسبةٍ ونصُّها.
class PicPosBarCell extends PicPosCell {
  const PicPosBarCell(this.text, this.fraction, this.tint);

  final String text;

  /// من ٠ إلى ١ — تُقصَّ عند الحدَّين فلا يخرج الشريطُ عن مساره.
  final double fraction;
  final Color tint;
}

/// اتّجاهٌ بسهمٍ أخضرَ أو أحمر.
class PicPosTrendCell extends PicPosCell {
  const PicPosTrendCell(this.text, {required this.up});

  final String text;
  final bool up;
}

/// زرُّ إجراءٍ داخلَ الصفّ.
class PicPosButtonCell extends PicPosCell {
  const PicPosButtonCell(
    this.text, {
    required this.icon,
    required this.tint,
    this.onPressed,
  });

  final String text;
  final IconData icon;
  final Color tint;
  final VoidCallback? onPressed;
}

/// زرُّ اختيارٍ **مفرد** — دائرةُ راديو لا مربّعُ تعليم.
///
/// ⚠️ **والشكلُ عقدٌ لا زينة**: المربّعُ يَعِد بتعدّدٍ، والدائرةُ تقول
/// «واحدٌ فقط». وشريطُ الإجراءات تحت الجدول يخصّ صفّاً واحداً (سندُه ·
/// إيداعُه · عرضُ سنده)، فمربّعٌ كان سيَعِد بما لا يقع.
class PicPosRadioCell extends PicPosCell {
  const PicPosRadioCell({required this.selected, this.onSelect});

  final bool selected;
  final VoidCallback? onSelect;
}

/// صفٌّ: خلاياه وإجراءُ فتحه إن كان قابلاً للنقر.
class PicPosTableRow {
  const PicPosTableRow({required this.cells, this.onTap, this.selected = false});

  final List<PicPosCell> cells;
  final VoidCallback? onTap;

  /// يُظلَّل الصفُّ المختار — التصميمُ يميّزه بأرضيّةٍ زرقاءَ خفيفة.
  final bool selected;
}

class PicPosDataTable extends StatelessWidget {
  const PicPosDataTable({
    super.key,
    required this.title,
    required this.columns,
    required this.rows,
    this.subtitle,
    this.chips = const [],
    this.selectedChip,
    this.totals,
    this.emptyLabel = 'لا صفوفَ لعرضها',
    this.minWidth = 760,
    this.headerAction,
  });

  final String title;
  final String? subtitle;
  final List<PicPosTableColumn> columns;
  final List<PicPosTableRow> rows;
  final List<PicPosTableChip> chips;
  final int? selectedChip;

  /// صفُّ المجاميع — طولُه طولُ [columns] وإلّا انزاحت الخانات. الفراغُ
  /// يُرسَم خافتاً كما في التصميم.
  final List<String>? totals;

  final String emptyLabel;

  /// ودجتٌ في آخر رأس الجدول، بعد الشرائح — «تخصيص الأعمدة» في تصميم كشف
  /// الحساب.
  ///
  /// ⚠️ **داخلَ نفس `Wrap` الشرائح** لا في صفٍّ ثالث: الرأسُ يحمل عنواناً
  /// وسطراً خافتاً وخمسَ شرائحَ، وزرٌّ خارجَ الالتفاف كان يفيض عند الضيق.
  final Widget? headerAction;

  /// أدنى عرضٍ قبل أن يبدأ التمريرُ الأفقيّ.
  final double minWidth;

  static const double _hPad = 18;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    assert(
      totals == null || totals!.length == columns.length,
      'صفُّ المجاميع طولُه ${totals?.length} وأعمدةُ الجدول ${columns.length} '
      '— الفرقُ يزيح كلَّ خانةٍ عن عمودها.',
    );
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(17),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _head(context),
          LayoutBuilder(
            builder: (context, c) {
              final avail = c.maxWidth.isFinite ? c.maxWidth : minWidth;
              final w = avail < minWidth ? minWidth : avail;
              final body = SizedBox(
                width: w,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _columnsRow(context, w),
                    if (rows.isEmpty)
                      _empty(context)
                    else
                      for (final r in rows) _row(context, r, w),
                    if (totals != null) _totalsRow(context, w),
                  ],
                ),
              );
              if (w <= avail) return body;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: body,
              );
            },
          ),
        ],
      ),
    );
  }

  // ── الرأس ──────────────────────────────────────────────────────────────

  Widget _head(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _hPad, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 15,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(3),
            ),
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
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: context.picposText,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: context.picposMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (chips.isNotEmpty || headerAction != null) ...[
            const SizedBox(width: 11),
            // تلتفّ عند الضيق: أربعُ شرائحَ ورأسٌ طويلٌ كانا يفيضان.
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (var i = 0; i < chips.length; i++)
                    _chip(context, chips[i], i == selectedChip),
                  ?headerAction,
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, PicPosTableChip c, bool on) {
    final fg = on ? context.picposBrandInk : context.picposText;
    return Material(
      color: on
          ? AppColors.primary.withValues(alpha: .08)
          : context.picposField,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: c.onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: on ? AppColors.primary : context.picposHairline,
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              if (c.count.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  c.count,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: fg.withValues(alpha: .75),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── الشبكة ─────────────────────────────────────────────────────────────

  /// عرضُ كلِّ عمودٍ من وزنه النسبيّ — نفسُ `grid-template-columns` بالـ`fr`.
  List<double> _widths(double w) {
    final total = columns.fold<double>(0, (s, c) => s + c.flex);
    final free = w - _hPad * 2 - _gap * (columns.length - 1);
    return [for (final c in columns) free * (c.flex / total)];
  }

  Widget _gridRow(
    BuildContext context,
    double w,
    List<Widget> cells,
  ) {
    final ws = _widths(w);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          SizedBox(width: ws[i], child: cells[i]),
        ],
      ],
    );
  }

  Widget _columnsRow(BuildContext context, double w) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _hPad, vertical: 11),
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: _gridRow(context, w, [
        for (final c in columns)
          Align(
            alignment: c.align == PicPosCellAlign.end
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: Text(
              c.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: context.picposMuted,
              ),
            ),
          ),
      ]),
    );
  }

  Widget _row(BuildContext context, PicPosTableRow r, double w) {
    // ⚠️ **خليّةٌ ناقصةٌ تُملأ فراغاً لا تُزيح الصفَّ.** صفٌّ أقصرُ من
    //    الأعمدة كان سيرمي `RangeError` أو يزيح كلَّ خانةٍ عن عمودها.
    final cells = <Widget>[
      for (var i = 0; i < columns.length; i++)
        i < r.cells.length
            ? _cell(context, r.cells[i], columns[i].align)
            : const SizedBox.shrink(),
    ];
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: _hPad, vertical: 11),
      decoration: BoxDecoration(
        color: r.selected ? AppColors.primary.withValues(alpha: 0.06) : null,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: _gridRow(context, w, cells),
    );
    if (r.onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: r.onTap, child: content),
    );
  }

  Widget _totalsRow(BuildContext context, double w) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _hPad, vertical: 14),
      color: context.picposField,
      child: _gridRow(context, w, [
        for (var i = 0; i < columns.length; i++)
          Align(
            alignment: columns[i].align == PicPosCellAlign.end
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: Text(
              totals![i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: context.picposText,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ]),
    );
  }

  Widget _empty(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 34),
        child: Center(
          child: Text(
            emptyLabel,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: context.picposMuted,
            ),
          ),
        ),
      );

  // ── الخلايا ────────────────────────────────────────────────────────────

  Widget _cell(BuildContext context, PicPosCell c, PicPosCellAlign align) {
    final end = align == PicPosCellAlign.end;
    final main = end ? MainAxisAlignment.end : MainAxisAlignment.start;
    switch (c) {
      case PicPosRadioCell():
        return Row(
          mainAxisAlignment: main,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⚠️ `Radio` بلا مجموعةٍ: الاختيارُ حالةُ الشاشة، والجدولُ يعرضه.
            //    وربطُه بـ`groupValue` هنا كان سيجعل الجدولَ يملك الاختيارَ
            //    فلا يعرف شريطُ الإجراءات تحته ما اختير.
            // ⚠️ **لا `IconButton`**: حدُّه الأدنى ٢٨ بكسلاً لا ينكمش، وعمودُ
            //    الاختيار أضيقُ من ذلك عند العروض الصغيرة — فيفيض الصفُّ
            //    ويُبتَر ما بعده. (قِيس: فيضٌ ١٩ بكسلاً عند ٨٢٠.) والصفُّ
            //    كلُّه قابلٌ للنقر على أيّ حال، فهذه أيقونةُ حالةٍ تُنقَر.
            InkWell(
              onTap: c.onSelect,
              customBorder: const CircleBorder(),
              child: Icon(
                c.selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: c.selected ? AppColors.primary : context.picposMuted,
              ),
            ),
          ],
        );
      case PicPosTextCell():
        return Row(
          mainAxisAlignment: main,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.icon != null) ...[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: (c.tint ?? context.picposMuted)
                      .withValues(alpha: c.tint == null ? .10 : .09),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  c.icon,
                  size: 15,
                  color: c.tint ?? context.picposMuted,
                ),
              ),
              const SizedBox(width: 9),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: end
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: end ? TextAlign.end : TextAlign.start,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: (c.bold ?? end)
                          ? FontWeight.w800
                          : FontWeight.w700,
                      color: context.picposText,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (c.sub != null && c.sub!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        c.sub!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: end ? TextAlign.end : TextAlign.start,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: context.picposMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );

      case PicPosPillCell():
        return Row(
          mainAxisAlignment: main,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: c.tint.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  c.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: c.tint,
                  ),
                ),
              ),
            ),
          ],
        );

      case PicPosBarCell():
        return Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: c.fraction.clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: context.picposField,
                  valueColor: AlwaysStoppedAnimation(c.tint),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              c.text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: c.tint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );

      case PicPosTrendCell():
        final fg = c.up ? AppColors.success : AppColors.error;
        return Row(
          mainAxisAlignment: main,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              c.up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 14,
              color: fg,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                c.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );

      case PicPosButtonCell():
        return Row(
          mainAxisAlignment: main,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  onTap: c.onPressed,
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(
                      border: Border.all(color: c.tint, width: 1.5),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(c.icon, size: 13, color: c.tint),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            c.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: c.tint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }
}

/// شريطُ ملاحظةِ التبويبة — السطرُ الخافتُ تحت شريط التبويبات في التصميم.
///
/// ⚠️ **جملةٌ تشرح قاعدةَ عملٍ لا زخرفة**: «مخزن التالف لا يُباع منه»،
/// «الاستحقاق يُحسب من dueDate لا من تاريخ الإصدار». فحذفُها يُسقط الشرحَ
/// الوحيدَ لسلوكٍ قد يبدو خطأً للمشغّل.
class PicPosTabNote extends StatelessWidget {
  const PicPosTabNote({super.key, required this.note, this.icon});

  final String note;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (note.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 9),
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          Icon(
            icon ?? Icons.info_outline_rounded,
            size: 14,
            color: context.picposMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: context.picposMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
