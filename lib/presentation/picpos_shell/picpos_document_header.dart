import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'picpos_surface.dart';

/// ترويسةُ مستند: عنوانٌ ورقمٌ ووسمُ حالة.
///
/// ═══ لماذا واحدةٌ لكلّ المستندات ═══
///
/// تصاميمُ المالك تفتح كلَّ مستندٍ بنفس السطر: «فاتورة مشتريات `PINV-0201`»
/// ومعه وسمُ «مسودة»، و«سند صرف `PV-0041`» ومعه وسمُه، و«مردود مشتريات
/// `PR-0011`». تسعةُ مستنداتٍ بنفس البنية.
///
/// ⚠️ **والوسمُ يقول الحالةَ الحقيقيّةَ لا المرغوبة.** درسٌ من هذه الجلسة:
/// تصميمُ سند القبض عرض شيكاً بحالة «برسم التحصيل» لحظةَ إنشائه، وهي حالةٌ
/// **لاحقةٌ** لا تقع إلّا بالإيداع — وعرضُها مبكّراً يُوهم المستخدمَ أنّ
/// الشيكَ في البنك وهو في يده.
class PicPosDocumentHeader extends StatelessWidget {
  const PicPosDocumentHeader({
    super.key,
    required this.title,
    this.number,
    this.status,
    this.icon,
    this.trailing = const [],
    this.note,
  });

  final String title;

  /// رقمُ المستند — `null` قبل توليده («يُولَّد تلقائياً»).
  final String? number;

  final PicPosDocStatus? status;
  final IconData? icon;

  /// أفعالٌ يمينَ الترويسة (قائمةُ القيود · المزيد).
  final List<Widget> trailing;

  /// سطرٌ صغيرٌ تحت العنوان («نموذج بديل لنفس السند» مثلاً).
  final String? note;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 20, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
              ],
              // ⚠️ **`Flexible` لازمةٌ هنا — وغيابُها فيضٌ مقيس.**
              //
              // هذا `Row` داخلَ `Wrap`، و`Wrap` يمنح ابنَه عرضَه الأقصى؛ لكنّ
              // `Row` يمنح أبناءَه غيرَ المرِنين عرضاً **غيرَ محدود**. فعنوانٌ
              // ورقمٌ ووسمُ حالةٍ معاً يتجاوزون ٤٢٠px ويفيضون.
              //
              // وأمسكه اختبارُ التركيب على العرض الضيّق وحدَه — على الواسع كان
              // أخضرَ تماماً.
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // و`Wrap` لا `Row`: العنوانُ والرقمُ والوسمُ ينزلون سطراً
                    // ثانياً بدل أن يخرجوا من الحدّ.
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: onSurface,
                          ),
                        ),
                        if (number != null)
                          Text(
                            number!,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: context.picposMuted,
                            ),
                          ),
                        if (status case final s?) _StatusPill(status: s),
                      ],
                    ),
                    if (note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          note!,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.picposMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (trailing.isNotEmpty)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: trailing,
            ),
        ],
      ),
    );
  }
}

/// حالةُ المستند كما تُعرَض.
class PicPosDocStatus {
  const PicPosDocStatus(this.label, this.tone);

  /// مسودةٌ — لم تُرحَّل بعد.
  PicPosDocStatus.draft() : label = tr('مسودة'), tone = AppColors.warning;

  /// مرحَّلٌ ومعتمَد.
  PicPosDocStatus.posted() : label = tr('معتمد'), tone = AppColors.success;

  /// ملغًى أو مرتجَع.
  PicPosDocStatus.cancelled() : label = tr('ملغى'), tone = AppColors.error;

  final String label;
  final Color tone;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final PicPosDocStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.tone.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: status.tone,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: status.tone,
            ),
          ),
        ],
      ),
    );
  }
}
