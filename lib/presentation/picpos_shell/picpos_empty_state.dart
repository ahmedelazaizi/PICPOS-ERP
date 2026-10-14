import 'picpos_surface.dart';
import 'package:flutter/material.dart';

import '../../core/design_system/spacing.dart';

/// حالة «مفيش بيانات» موحّدة.
///
/// الفرق اللي بيهم بيتلغبط المستخدم — «مفيش نتايج للفلتر ده» غير «مفيش بيانات
/// في النظام أصلاً» — فالنص المساعد ([hint]) مش زينة: هو اللي بيقول للمستخدم
/// يوسّع المدى ولا يسجّل أول حركة.
class PicPosEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;

  /// إجراء مقترح — «امسح الفلاتر» أو «أضف أول صنف».
  final Widget? action;

  const PicPosEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    // ألوانٌ تتبع الوضع: `textSecondary`/`textMuted` الثابتان رماديّان داكنان
    // يختفيان على بطاقة الوضع الداكن.
    final muted = context.picposMuted;
    final secondary = context.picposSecondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: Spacing.xxl,
          horizontal: Spacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(Spacing.lg),
              decoration: BoxDecoration(
                color: context.picposField,
                shape: BoxShape.circle,
                border: Border.all(color: context.picposHairline),
              ),
              child: Icon(icon, size: 30, color: muted),
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: Spacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
