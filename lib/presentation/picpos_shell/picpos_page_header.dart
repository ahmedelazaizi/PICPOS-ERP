import 'picpos_surface.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

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

  const PicPosPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.search,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
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
          if (Navigator.canPop(context)) ...[
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_forward),
              color: AppColors.primary,
              tooltip: 'رجوع',
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
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineSmall,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
              ],
            ),
          ),
          const Spacer(),
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
    );
  }
}
