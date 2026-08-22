// لوحُ مقاييس الخزينة بهويّة PicPos — **فوركٌ بقرار المالك 2026-08-22**
// («انسخه إلى PicPos ولا تشارك تعديلاتِ PicPos على UralCash»).
//
// المصدر: `treasury/widgets/treasury_metrics_panel.dart`، ويبقى بلا مساسٍ
// لشاشة UralCash.
//
// **الجديدُ من التصميم:** شريطُ تقسيمِ الرصيد (`trSplit`) — نقديٌّ وبنكيٌّ
// بنسبتَيهما. والأصلُ يعرض المجموعَ وحدَه.
//
// ⚠️ **وحرّاسُ السندَين نُقلا كما هما** (`treasury_receipts_create` و
// `treasury_payments_create` بـ`allowManagerOverride`). حذفُ حارسٍ أثناء
// النسخ هو بالضبط فئةُ العطب التي وُجد `picpos_permission_parity_test`
// لأجلها — ومُقاسةٌ هنا في `picpos_treasury_metrics_test`.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../domain/models/picpos_treasury_view.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../treasury/widgets/receipt_voucher_dialog.dart';
import '../../treasury/widgets/payment_voucher_dialog.dart';
import '../../widgets/permission_guard.dart';

import 'package:ural_erp/l10n/app_localizations.dart';
import '../../../data/providers/providers.dart';
import '../../../core/constants/app_constants.dart';

class TreasuryMetricsPanelPicpos extends ConsumerWidget {
  const TreasuryMetricsPanelPicpos({super.key, this.split});

  /// تقسيمُ الرصيد — يُرسم **داخل** البطاقة الداكنة كما في التصميم.
  ///
  /// `null` يعني «لم يصل بعد» (الصناديقُ تُحمَّل بثّاً)، فتُرسم البطاقةُ بلا
  /// شرائحَ بدل أن تُرسم شرائحُ أصفارٍ تُقرأ خبراً.
  final PicPosTreasurySplit? split;

  void _showReceiptVoucherDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const ReceiptVoucherDialog(),
    );
  }

  void _showPaymentVoucherDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const PaymentVoucherDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalBalance = ref.watch(totalCashBalanceProvider);
    final localizations = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              PhosphorIconsBold.wallet,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.totalTreasuryBalance,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 4),
              totalBalance.when(
                data: (balance) => Text(
                  '${NumberFormat('#,##0.00', 'ar').format(balance)} ${AppConstants.currencySymbolEn}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                loading: () => const Text(
                  '...',
                  style: TextStyle(color: Colors.white, fontSize: 32),
                ),
                error: (e, s) => Text(
                  '0.00 ${AppConstants.currencySymbolEn}',
                  style: const TextStyle(color: Colors.white, fontSize: 32),
                ),
              ),
              // الشرائحُ **داخل** البطاقة الداكنة — لا تحتها على الفاتح.
              // راجع تعليقَ [PicPosTreasurySplitChips]: وضعُها خارجاً هو ما
              // أنتج «أبيضَ على فاتح» في لقطة المالك.
              if (split != null) ...[
                const SizedBox(height: 14),
                PicPosTreasurySplitChips(split: split!),
              ],
            ],
          ),
          const SizedBox(width: 20),
          const Spacer(),
          Column(
            children: [
              // Receipt Voucher - Requires permission
              PermissionGuard(
                permission: PermissionCodes.treasuryReceiptsCreate,
                allowManagerOverride: true,
                actionName: 'إنشاء سند قبض',
                child: ElevatedButton.icon(
                  onPressed: () => _showReceiptVoucherDialog(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                  icon: const Icon(PhosphorIconsBold.plus),
                  label: Text(localizations.receiptVoucher),
                ),
              ),
              const SizedBox(height: 8),
              // Payment Voucher - Requires permission
              PermissionGuard(
                permission: PermissionCodes.treasuryPaymentsCreate,
                allowManagerOverride: true,
                actionName: 'إنشاء سند صرف',
                child: OutlinedButton.icon(
                  onPressed: () => _showPaymentVoucherDialog(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                  ),
                  icon: const Icon(PhosphorIconsBold.minus),
                  label: Text(localizations.paymentVoucher),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// شرائحُ تقسيم الرصيد — `trSplit` في التصميم.
///
/// ═══ ⚠️ عطبٌ شُحن ثمّ صُحّح — والدرسُ أهمُّ من الإصلاح ═══
///
/// كُتبت أوّلاً شريطاً أفقيّاً بنصوصٍ **بيضاء** (`Colors.white70`) لأنها
/// صُمِّمت لتقع داخل البطاقة الداكنة، ثمّ وُضعت **خارجَها** على خلفيّة
/// الصفحة الفاتحة. النتيجةُ في لقطة المالك: نصٌّ غيرُ مقروءٍ ومقصوص.
///
/// وهو **حرفيّاً** عطبُ `headingRowColor` الذي حُرس في هذه الجلسة نفسِها:
/// لونُ النصِّ ولونُ الأرضيّة عقدٌ **مقترن**، وفصلُ أحدهما عن الآخر يُخفي
/// المحتوى بلا خطأٍ ولا تحذير.
///
/// فالعلاجُ ليس تفتيحَ النصِّ يدويّاً: الشرائحُ صارت **جزءاً من البطاقة
/// الداكنة** كما يرسمها التصميمُ أصلاً، فالعقدُ مستأنَفٌ في مكانٍ واحد.
/// و[onDark] يُمرَّر صراحةً فلا يُستنتَج — من يضعها على سطحٍ فاتحٍ يقول ذلك.
@visibleForTesting
class PicPosTreasurySplitChips extends StatelessWidget {
  const PicPosTreasurySplitChips({
    super.key,
    required this.split,
    this.onDark = true,
  });

  final PicPosTreasurySplit split;

  /// هل تقع الشرائحُ على سطحٍ داكن؟ **يُمرَّر ولا يُستنتَج** — راجع تعليقَ
  /// الصنف: استنتاجُه ضمناً هو ما أنتج «أبيضَ على فاتح».
  final bool onDark;

  /// ألوانُ الأنواع الثلاثة — نفسُ دلالة ألوان بطاقات الصناديق.
  static const _colors = <String, Color>{
    'cash': Color(0xFF22C55E),
    'bank': Color(0xFF4A80E8),
    'click': Color(0xFFA78BFA),
  };

  @override
  Widget build(BuildContext context) {
    final labelColor = onDark ? Colors.white70 : AppColors.textMuted;
    final valueColor =
        onDark ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color;
    final chipBg = onDark
        ? Colors.white.withValues(alpha: .10)
        : Theme.of(context).scaffoldBackgroundColor;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final s in split.slices)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // النسبةُ تُعرض فقط حين يكون لها معنى — مجموعٌ غيرُ موجبٍ
                    // يجعل «0%» تُقرأ كأن الرصيدَ صفر. راجع [hasBar].
                    if (split.hasBar) ...[
                      Text(
                        s.percentLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: labelColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _colors[s.kind] ?? AppColors.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      s.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: labelColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  s.valueLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
