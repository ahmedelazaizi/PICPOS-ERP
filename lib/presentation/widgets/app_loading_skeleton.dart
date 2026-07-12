import 'package:flutter/material.dart';

/// Reusable loading skeleton widget for shimmer/placeholder effect.
///
/// Usage:
/// ```dart
/// AppLoadingSkeleton.list(itemCount: 5) // List of skeleton items
/// AppLoadingSkeleton.card()             // Single card skeleton
/// AppLoadingSkeleton.table(rows: 8)     // Table skeleton
/// ```
class AppLoadingSkeleton extends StatefulWidget {
  final Widget child;

  const AppLoadingSkeleton({super.key, required this.child});

  @override
  State<AppLoadingSkeleton> createState() => _AppLoadingSkeletonState();

  // ═══════════════════════════════════════════════════════════════════════════
  // FACTORY CONSTRUCTORS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Creates a skeleton list with N items (default 5)
  static Widget list({int itemCount = 5, double itemHeight = 72}) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemBuilder: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppLoadingSkeleton(
          child: _SkeletonListItem(height: itemHeight),
        ),
      ),
    );
  }

  /// Creates a skeleton card
  static Widget card({double height = 180, double width = double.infinity}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: AppLoadingSkeleton(
        child: _SkeletonBox(height: height, width: width, borderRadius: 12),
      ),
    );
  }

  /// Creates a skeleton table with N rows
  static Widget table({int rows = 8, int columns = 4}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header
          const AppLoadingSkeleton(
            child: _SkeletonBox(height: 48, borderRadius: 8),
          ),
          const SizedBox(height: 8),
          // Rows
          ...List.generate(
            rows,
            (i) => const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: AppLoadingSkeleton(
                child: _SkeletonBox(height: 40, borderRadius: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Creates a skeleton grid (e.g., for product cards)
  static Widget grid({
    int itemCount = 8,
    int crossAxisCount = 4,
    double childAspectRatio = 1.0,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: itemCount,
      itemBuilder: (_, _) => const AppLoadingSkeleton(
        child: _SkeletonBox(borderRadius: 12),
      ),
    );
  }

  /// Simple inline skeleton (for single values loading)
  static Widget inline({double width = 100, double height = 16}) {
    return AppLoadingSkeleton(
      child: _SkeletonBox(height: height, width: width, borderRadius: 4),
    );
  }
}

class _AppLoadingSkeletonState extends State<AppLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: widget.child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SKELETON BUILDING BLOCKS
// ═══════════════════════════════════════════════════════════════════════════

class _SkeletonBox extends StatelessWidget {
  final double? height;
  final double? width;
  final double borderRadius;

  const _SkeletonBox({
    this.height,
    this.width,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: height,
      width: width ?? double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.white12 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class _SkeletonListItem extends StatelessWidget {
  final double height;

  const _SkeletonListItem({this.height = 72});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white12 : Colors.grey.shade200;

    return Container(
      height: height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade100,
        ),
      ),
      child: Row(
        children: [
          // Avatar placeholder
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          // Text placeholders
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 14,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  width: 120,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Action placeholder
          Container(
            width: 60,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
