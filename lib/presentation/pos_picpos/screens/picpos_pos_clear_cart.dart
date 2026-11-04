part of 'picpos_pos_screen.dart';

/// «مسح الكل» أعلى السلة — بيتعطّل لما السلة فاضية بدل ما يفتح تأكيد
/// على مفيش حاجة.
class _ClearCartButton extends ConsumerWidget {
  final VoidCallback onClear;

  const _ClearCartButton({required this.onClear});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // في وضع المرتجع/الاستبدال تكون سلّة البيع فارغة عادةً، لكن الزر يبقى
    // مفعّلاً لأنه مخرجٌ من الوضع (`_cancelInvoice` يعالجه بتأكيد).
    final inMode = ref.watch(posReturnModeProvider) != null ||
        ref.watch(posExchangeModeProvider) != null;
    final isEmpty = !inMode &&
        ref.watch(cartControllerProvider.select((s) => s.items.isEmpty));
    return Opacity(
      opacity: isEmpty ? 0.35 : 1,
      child: InkWell(
        onTap: isEmpty ? null : onClear,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                  PhosphorIconsBold.trash, size: 13, color: AppColors.error),
              const SizedBox(width: 4),
              Text(
                tr('مسح الكل'),
                style: PicPosText.v(context, 10, color: AppColors.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
