import 'package:picpos_erp/core/i18n/tr.dart';
// جدولُ لوحة الحجوزات — سبعةُ أعمدةٍ كما في التصميم.
//
// ═══ ⚠️ `ListView.builder` لا `Column` ═══
//
// نفسُ الدرسِ الموثَّقِ في قائمة الفواتير: `Column` داخلَ `SingleChildScrollView`
// يبني **كلَّ** صفٍّ في كلّ إطار. ويومٌ مزدحمٌ في صالونٍ يبلغ عشراتِ الصفوف،
// وكلُّ صفٍّ يحمل دائرةَ حروفٍ وحبّةَ حالةٍ وثلاثةَ أزرار.
//
// ═══ ولا `stretch` داخلَ `Column` ═══
//
// شاشةُ الخزينة شُحنت **بيضاء** لأنّ `stretch` جوّه `Column` يطلب ارتفاعاً
// لا نهائيّاً — وفي بناء الإصدار لا تظهر شاشةٌ حمراءُ بل بياض. فالارتفاعاتُ
// هنا محدودةٌ صراحةً والتمدّدُ بـ`Expanded` وحدَه.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/models/picpos_booking_view.dart';
import '../screens/bookings_picpos_screen.dart';

/// عرضُ الأعمدة الثابتة — من التصميم، ومجموعُها يترك «العميل» مرناً.
// ⚠️ ‏١١٢ كما في التصميم لا ١٠٤: قِيس أنّ «10:00 ص» بوزنٍ ثقيلٍ وأرقامٍ
// جدوليّةٍ مع الأيقونةِ والفجوةِ يتجاوز ١٠٤ بـ‎4.8 بكسل بالضبط — وهو فيضٌ
// **مستقلٌّ عن عرض الشاشة**، فلا يظهر بتوسيع النافذة ولا يختفي.
const _kTimeW = 112.0;
const _kServiceW = 168.0;
const _kResourceW = 186.0;
const _kStatusW = 156.0;
const _kDepositW = 124.0;
const _kActionsW = 190.0;
const _kRowH = 58.0;

class BookingsBoardTable extends StatelessWidget {
  const BookingsBoardTable({super.key, required this.rows, this.onAction});

  final List<BookingBoardRow> rows;

  /// يُنادى بالحجز والحالةِ المطلوبة — و`next` فارغةٌ تعني «تفويتر».
  final void Function(BookingBoardRow row, String next)? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(13),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _HeaderRow(),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemExtent: _kRowH,
              itemBuilder: (_, i) => _BoardRow(row: rows[i], onAction: onAction),
            ),
          ),
          _FooterRow(count: rows.length),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: Colors.white,
    );
    return Container(
      height: 36,
      color: AppColors.primaryDark,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child:  Row(
        children: [
          SizedBox(width: _kTimeW, child: Text(tr('الوقت'), style: style)),
          Expanded(child: Text(tr('العميل'), style: style)),
          SizedBox(width: _kServiceW, child: Text(tr('الخدمة'), style: style)),
          SizedBox(
              width: _kResourceW, child: Text(tr('الموظف / المورد'), style: style)),
          SizedBox(width: _kStatusW, child: Text(tr('الحالة'), style: style)),
          SizedBox(
            width: _kDepositW,
            child: Text(tr('العربون'), style: style, textAlign: TextAlign.end),
          ),
          SizedBox(
            width: _kActionsW,
            child: Text(tr('الإجراءات'), style: style, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({required this.row, this.onAction});

  final BookingBoardRow row;
  final void Function(BookingBoardRow row, String next)? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final view = bookingStatusView(row.status);
    final toneColor = bookingToneColor(view.tone);
    // الملغى والمتخلّفُ يُخفَّتان: قائمةٌ تعرضهما بنفس ثقل الحيّ تُربك القراءة.
    final dimmed = !row.occupiesTime;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _kTimeW,
              child: Row(
                children: [
                  const Icon(PhosphorIconsBold.clock,
                      size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  // ‏`Flexible` حزامٌ ثانٍ: خطٌّ أعرضُ أو لغةٌ أطولُ تفيض
                  // بعرضٍ ثابتٍ مهما ضُبط، والقصُّ أهونُ من شريطٍ أصفر.
                  Flexible(
                    child: Text(
                      bookingTimeLabel(row.startsAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        fontFeatures: bookingTabularFigures,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _twoLines(
                row.customerName,
                row.customerPhone ?? '—',
                // الهاتفُ يُقرأ يساراً إلى يمين ولو كانت الشاشةُ عربيّة —
                // وإلّا قُلبت مجموعاتُ أرقامه.
                subDirection: TextDirection.ltr,
              ),
            ),
            SizedBox(
              width: _kServiceW,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 30,
                    decoration: BoxDecoration(
                      color: bookingColorOf(row.serviceColorHex),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _twoLines(
                      row.serviceName,
                      tr('{p0} دقيقة', {'p0': row.durationMinutes}),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: _kResourceW,
              child: row.resourceName == null
                  // حجزٌ بلا موظَّفٍ مسموحٌ — ويُقال صراحةً لا يُترك فراغاً.
                  ?  Text(
                      tr('بلا إسناد'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    )
                  : Row(
                      children: [
                        _avatar(row),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _twoLines(
                            row.resourceName!,
                            row.resourceRole ??
                                (row.resourceKind == 'device' ? tr('جهاز') : '—'),
                          ),
                        ),
                      ],
                    ),
            ),
            SizedBox(
              width: _kStatusW,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _pill(view.label, toneColor),
              ),
            ),
            SizedBox(
              width: _kDepositW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    row.depositAmount > 0
                        ? row.depositAmount
                            .toStringAsFixed(AppConstants.decimalPlaces)
                        : '—',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFeatures: bookingTabularFigures,
                      color: row.depositAmount > 0
                          ? AppColors.success
                          : AppColors.textMuted,
                    ),
                  ),
                  if (row.depositAmount > 0)
                    Text(
                      _depositLabel(row.depositStatus),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: _kActionsW, child: _actions(context)),
          ],
        ),
      ),
    );
  }

  static String _depositLabel(String depositStatus) => switch (depositStatus) {
        'refunded' => tr('مُعاد'),
        'forfeited' => tr('مُصادَر'),
        _ => tr('محتجَز'),
      };

  Widget _avatar(BookingBoardRow row) {
    final color = bookingColorOf(row.resourceColorHex);
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        border: Border.all(color: color, width: 1.5),
        shape: BoxShape.circle,
      ),
      child: Text(
        initialsFor(row.resourceName!),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _twoLines(String top, String bottom, {TextDirection? subDirection}) {
    final sub = Text(
      bottom,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textDirection: subDirection,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
        fontFeatures: bookingTabularFigures,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          top,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
        ),
        subDirection == null
            ? sub
            : Align(alignment: AlignmentDirectional.centerStart, child: sub),
      ],
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        border: Border.all(color: color.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final action = bookingNextAction(
      status: row.status,
      isInvoiced: row.isInvoiced,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (action != null)
          FilledButton(
            onPressed:
                onAction == null ? null : () => onAction!(row, action.next),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle:
                  const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
            child: Text(action.label),
          )
        else if (row.isInvoiced)
           _Tag(label: tr('مُفوتَر'), color: AppColors.success)
        else
          const SizedBox.shrink(),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(PhosphorIconsBold.checkCircle, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _FooterRow extends StatelessWidget {
  const _FooterRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        // ‏لا مُرقِّمَ صفحاتٍ: يومٌ واحدٌ يبلغ عشراتِ الصفوف لا آلافَها،
        // والقائمةُ مُفهرَسةٌ فتنزلق. ومُرقِّمٌ لصفحةٍ واحدةٍ ضجيج.
        tr('إجمالي {count} حجزاً في هذا اليوم', {'count': count}),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          fontFeatures: bookingTabularFigures,
        ),
      ),
    );
  }
}
