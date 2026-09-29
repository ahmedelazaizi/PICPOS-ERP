import 'package:ural_erp/core/i18n/tr.dart';
// حوارُ تحويل الحجز إلى فاتورة.
//
// ═══ ⚠️ لا يُنشئ فاتورةً — يُسلِّم الحجزَ لنقطة البيع ═══
//
// قرارُ المالك: **مسارُ المال كلُّه في نقطة البيع** (توجيهُ الخزنة · طرقُ
// الدفع · الضريبةُ · ربطُ الورديّة · القيودُ · الطباعة). وفاتورةٌ تُصنع من
// شاشة الحجوزات كانت **تكرّر مسارَ المال** — وهو أخطرُ تكرار: نسخةٌ ثانيةٌ
// تتباعد عن الأولى بصمتٍ عند أوّل إصلاحٍ يقع في واحدةٍ دون الأخرى.
//
// فهذا الحوارُ يفعل ثلاثةً لا أكثر:
//   ‏١) يتحقّق أنّ الحجزَ **قابلٌ للتفويتر** قبل أن يُفتَح الكاشير — وإلّا
//      تُرك المستخدمُ أمام سلّةٍ معلّقةٍ تفشل عند الحفظ.
//   ‏٢) يرفع علامةَ «هذه بيعةُ تفويترِ حجزٍ لا بيعةٌ عاديّة».
//   ‏٣) يُحمِّل صنفَ الخدمة في السلّة ويُسنِد العميل.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/picpos_booking_view.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../screens/bookings_picpos_screen.dart';

/// يفتح حوارَ التفويتر. يعيد `true` حين تُسلَّم البيعةُ لنقطة البيع.
Future<bool?> showBookingInvoiceDialog(
  BuildContext context, {
  required BookingBoardRow row,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => BookingInvoiceDialog(row: row),
  );
}

class BookingInvoiceDialog extends ConsumerStatefulWidget {
  const BookingInvoiceDialog({super.key, required this.row});

  final BookingBoardRow row;

  @override
  ConsumerState<BookingInvoiceDialog> createState() =>
      _BookingInvoiceDialogState();
}

class _BookingInvoiceDialogState extends ConsumerState<BookingInvoiceDialog> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final due = row.servicePrice - row.depositAmount;

    return PicPosDialog(
      icon: PhosphorIconsBold.receipt,
      title: tr('تحويل الحجز إلى فاتورة'),
      subtitle: '${row.customerName} · ${bookingTimeLabel(row.startsAt)}',
      width: 620,
      primaryAction: PicPosDialogAction(
        label: tr('متابعة في نقطة البيع'),
        icon: PhosphorIconsBold.arrowLeft,
        busy: _busy,
        onPressed: _busy ? null : _handOff,
      ),
      body: [
        _line(tr('الخدمة'), row.serviceName),
        _line(tr('الموظف / المورد'), row.resourceName ?? tr('بلا إسناد')),
        _line(tr('سعر الخدمة'), _money(row.servicePrice)),
        _line(
          tr('العربون المدفوع'),
          row.depositAmount > 0 ? '− ${_money(row.depositAmount)}' : '—',
          color: row.depositAmount > 0 ? AppColors.success : null,
        ),
        const Divider(height: 20),
        _line(tr('المتبقّي على العميل'), _money(due < 0 ? 0 : due), bold: true),
        const SizedBox(height: 12),
        _note(
          PhosphorIconsBold.info,
          'الفاتورةُ تُصدَر من نقطة البيع — هناك تُحسَب الضريبةُ وتُوجَّه '
          'الخزنةُ وتُربَط الورديّةُ وتُرحَّل القيود. والعربونُ يُخصَم '
          'تلقائيّاً عند إتمام البيع.',
          AppColors.info,
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          _note(PhosphorIconsBold.xCircle, _error!, AppColors.error),
        ],
      ],
    );
  }

  Future<void> _handOff() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = ref.read(databaseProvider);

      // ‏١) الحارسُ **قبل** فتح الكاشير: خدمةٌ بلا صنفٍ مربوطٍ لا تُفوتَر.
      await db.assertBookingInvoiceable(widget.row.id);

      // ‏٢) العلامةُ الصريحةُ — بها وحدَها يعرف مسارُ الدفع أنّ هذه بيعةُ
      //    تفويترٍ فيُطفئ التزامَ العربون ويكتب `Bookings.invoiceId`.
      ref.read(bookingInvoicingProvider.notifier).begin(widget.row.id);

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // ⚠️ والعلامةُ **لا تُرفَع عند الفشل**: حجزٌ معلَّقٌ بلا سلّةٍ يلتصق
      // بأوّل بيعةٍ تالية فيخصم عربوناً من زبونٍ آخر.
      ref.read(bookingInvoicingProvider.notifier).clear();
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _money(double v) =>
      '${v.toStringAsFixed(AppConstants.decimalPlaces)} '
      '${AppConstants.currencySymbol}';

  Widget _line(String label, String value, {Color? color, bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: bold ? null : AppColors.textMuted,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: bold ? 15 : 13,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: bookingTabularFigures,
              ),
            ),
          ],
        ),
      );

  Widget _note(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          border: Border.all(color: color.withValues(alpha: .30)),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
              ),
            ),
          ],
        ),
      );
}
