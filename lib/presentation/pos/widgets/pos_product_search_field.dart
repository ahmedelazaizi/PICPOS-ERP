import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/pos_controller.dart';
import '../../widgets/permission_guard.dart';
import '../../picpos_shell/picpos_surface.dart';

/// حقلُ البحث عن المنتج حين يُرفع من داخل شبكة الأصناف إلى صفّ الباركود
/// (‏`PosLayoutPolicy.searchBesideBarcode`).
///
/// ── لماذا ودجتٌ مستقلٌّ بدل تمرير متحكّم الشبكة ────────────────────────────
/// حقلُ `ProductGrid` الداخليُّ يملك `TextEditingController` خاصّاً به، أُضيف
/// بعد بلاغٍ ميدانيّ: «لا يمكن حذف البحث حتى بعد اختيار المنتج». وتمريرُ ذاك
/// المتحكّم إلى أعلى الشجرة كان سيربط عمرَه بودجتَين ويعيد فتحَ ذاك العطب.
///
/// وهذا الحقلُ **يزامن نفسَه من الحالة**: أيُّ `setSearchQuery` من أيّ موضعٍ
/// — ومنه تفريغُ `ProductGrid` بعد اختيار منتج — يصل النصَّ المعروضَ فوراً.
/// فالمصدرُ الوحيدُ للحقيقة هو `PosController`، لا نسختان تتسابقان.
class PosProductSearchField extends ConsumerStatefulWidget {
  const PosProductSearchField({super.key, this.height = 48});

  /// ارتفاعُ الحقل.
  ///
  /// الافتراضيُّ ٤٨ — نفسُ ارتفاع حقل البحث داخلَ رأس الشبكة. ويُرفع إلى ٥٦
  /// حين يقف بجانب الباركود، فحقلُ الباركود `contentPadding` رأسيُّه ١٦ بخطٍّ
  /// قياسُه ١٦ — أي ~٥٦. و«متناسقة» في طلب المالك تعني هذا بالضبط: لا حقلٌ
  /// أقصرُ من جاره في نفس الصفّ.
  final double height;

  @override
  ConsumerState<PosProductSearchField> createState() =>
      _PosProductSearchFieldState();
}

class _PosProductSearchFieldState extends ConsumerState<PosProductSearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ الشرطُ `!=` ليس تجميلاً: بدونه تُعاد الكتابةُ في كلّ إطارٍ فتقفز
    // نقطةُ الإدراج إلى الصفر مع كلّ حرف.
    ref.listen<String>(
      posControllerProvider.select((s) => s.searchQuery),
      (previous, next) {
        if (_controller.text != next) _controller.text = next;
      },
    );

    final query =
        ref.watch(posControllerProvider.select((s) => s.searchQuery));

    return PermissionGuard(
      permission: PermissionCodes.posSearch,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: context.picposField,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.picposHairline.withValues(alpha: 0.8),
            width: 1.5,
          ),
        ),
        child: TextField(
          controller: _controller,
          onChanged: ref.read(posControllerProvider.notifier).setSearchQuery,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'بحث عن منتج...',
            hintStyle: TextStyle(
              color: AppColors.textMuted.withValues(alpha: 0.7),
              fontSize: 13,
            ),
            prefixIcon: const Icon(
              PhosphorIconsBold.magnifyingGlass,
              size: 22,
              color: AppColors.primary,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
            isDense: true,
            suffixIcon: query.isNotEmpty
                ? IconButton(
                    icon: const Icon(PhosphorIconsBold.xCircle, size: 20),
                    // تفريغُ الحالةِ وحدَها — والحقلُ يتبعها عبر `ref.listen`
                    // أعلاه. تفريغُ الاثنين يدوياً هو ما تسابق من قبل.
                    onPressed: () => ref
                        .read(posControllerProvider.notifier)
                        .setSearchQuery(''),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
