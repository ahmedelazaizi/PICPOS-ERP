import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Shimmer loading effect for skeleton screens.
/// Use instead of plain CircularProgressIndicator for a more polished look.
class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoading({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();

  /// Build a full card skeleton (title + 3 lines)
  static Widget card({double? width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerLoading(width: 120, height: 14),
          SizedBox(height: 12),
          ShimmerLoading(height: 12),
          SizedBox(height: 8),
          ShimmerLoading(width: 200, height: 12),
          SizedBox(height: 8),
          ShimmerLoading(width: 160, height: 12),
        ],
      ),
    );
  }

  /// Build a list skeleton (N rows)
  static Widget list({int itemCount = 5}) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, _) => const _ShimmerListItem(),
    );
  }

  /// Build a grid skeleton
  static Widget grid({int itemCount = 6, int crossAxisCount = 3}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (_, _) => ShimmerLoading.card(),
    );
  }
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(
      begin: -1.5,
      end: 2.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value, 0),
              colors: [
                AppColors.surface,
                AppColors.surface.withValues(alpha: 0.5),
                AppColors.surface,
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShimmerListItem extends StatelessWidget {
  const _ShimmerListItem();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.surface),
      ),
      child: const Row(
        children: [
          ShimmerLoading(width: 40, height: 40, borderRadius: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerLoading(width: 140, height: 14),
                SizedBox(height: 6),
                ShimmerLoading(width: 200, height: 11),
              ],
            ),
          ),
          ShimmerLoading(width: 60, height: 14),
        ],
      ),
    );
  }
}
