import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/entities/product_entity.dart';

class ProductCard extends ConsumerStatefulWidget {
  final ProductEntity product;
  final VoidCallback onTap;
  final bool showImages;
  final double nameFontSize;
  final double priceFontSize;

  const ProductCard({super.key, required this.product, required this.onTap, this.showImages = true, this.nameFontSize = 12.0, this.priceFontSize = 14.0});

  @override
  ConsumerState<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<ProductCard>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _pingController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pingScaleAnimation;
  late Animation<double> _pingOpacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _pingController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _pingScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.5,
    ).animate(CurvedAnimation(parent: _pingController, curve: Curves.easeOut));
    _pingOpacityAnimation = Tween<double>(
      begin: 0.5,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pingController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    _pingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cluster 024 / Issue 2 — global negative-sales toggle overrides the
    // per-product flag for the out-of-stock UI gate.
    final globalNegativeSales =
        ref.watch(enableNegativeSalesProvider).value ?? false;
    final isOutOfStock = widget.product.trackInventory &&
        widget.product.currentStock <= 0 &&
        !widget.product.allowNegativeSale &&
        !globalNegativeSales;
    final isLowStock = widget.product.trackInventory &&
        widget.product.currentStock > 0 &&
        widget.product.currentStock <= widget.product.minStock;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaleFactor = (constraints.maxWidth / 100).clamp(0.6, 1.2);

        return ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Card(
              clipBehavior: Clip.antiAlias,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isOutOfStock
                      ? AppColors.error.withValues(alpha: 0.5)
                      : isLowStock
                      ? AppColors.warning.withValues(alpha: 0.5)
                      : AppColors.border.withValues(alpha: 0.6),
                  width: (isOutOfStock || isLowStock) ? 1.5 : 0.8,
                ),
              ),
              child: InkWell(
                onTapDown: (_) => _controller.forward(),
                onTapUp: (_) => _controller.reverse(),
                onTapCancel: () => _controller.reverse(),
                splashFactory: InkSparkle.splashFactory,
                onTap: isOutOfStock
                    ? null
                    : () {
                        _pingController.forward(from: 0.0);
                        widget.onTap();
                      },
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.showImages) ...[
                          // Image section (only when showImages is true)
                          Expanded(
                            flex: 12,
                            child: Stack(
                              children: [
                                Positioned.fill(child: _buildImage(scaleFactor)),
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.02),
                                          Colors.transparent,
                                          Colors.black.withValues(alpha: 0.08),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Info section (compact)
                          Expanded(
                            flex: 9,
                            child: _buildInfo(
                              isOutOfStock,
                              isLowStock,
                              scaleFactor,
                              textOnly: false,
                            ),
                          ),
                        ] else ...[
                          // #3: Text-only card — name + price prominent, no image
                          Expanded(
                            child: _buildInfo(
                              isOutOfStock,
                              isLowStock,
                              scaleFactor,
                              textOnly: true,
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Out of stock overlay (More professional)
                    if (isOutOfStock)
                      Positioned.fill(
                        child: Container(
                          color: Theme.of(
                            context,
                          ).cardColor.withValues(alpha: 0.7),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.error.withValues(
                                      alpha: 0.4,
                                    ),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: const Text(
                                'غير متوفر',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    if (widget.product.isSoldByWeight)
                      _buildWeightBadge(scaleFactor),

                    // Category Accent (More subtle)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isOutOfStock
                              ? AppColors.error
                              : AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),

                    // Success Ping Overlay
                    AnimatedBuilder(
                      animation: _pingController,
                      builder: (context, child) {
                        if (!_pingController.isAnimating) {
                          return const SizedBox.shrink();
                        }
                        return Positioned.fill(
                          child: Center(
                            child: Opacity(
                              opacity: _pingOpacityAnimation.value,
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primary,
                                ),
                                width:
                                    constraints.maxWidth *
                                    _pingScaleAnimation.value,
                                height:
                                    constraints.maxWidth *
                                    _pingScaleAnimation.value,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImage(double scaleFactor) {
    final imageData = widget.product.imageData;
    if (imageData != null && imageData.isNotEmpty) {
      return Image.memory(
        imageData,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildPlaceholderImage(scaleFactor),
      );
    }
    return _buildPlaceholderImage(scaleFactor);
  }

  Widget _buildPlaceholderImage(double scaleFactor) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Icon(
          PhosphorIconsBold.package,
          size: 32 * scaleFactor,
          color: AppColors.primary.withValues(alpha: 0.15),
        ),
      ),
    );
  }

  Widget _buildInfo(bool isOutOfStock, bool isLowStock, double scaleFactor, {bool textOnly = false}) {
    // BUG (خط الصنف/السعر): سابقاً الأرضيات كانت 13/14 (نص فقط) و10/12 (مع
    // الصور)، فتخفيض إعداد `pos_product_name/price_font_size` (المدى 10..24) كان
    // بيوصل للأرضية ويقف — خصوصاً على الكروت الضيّقة حيث scaleFactor يهبط لـ0.6
    // فأي إعداد لحد ~16 كان بيتقصّ لـ13. النتيجة: «التصغير مش بيصغّر». الآن
    // الأرضية 8.0 (حدّ مقروء) عشان الإعداد يسري حتى أصغره، مع الحفاظ على السقف.
    const double kMinFont = 8.0;
    final nameFontSize = textOnly
        ? (widget.nameFontSize * 1.33 * scaleFactor).clamp(kMinFont, 26.0)
        : (widget.nameFontSize * scaleFactor).clamp(kMinFont, 20.0);
    final priceFontSize = textOnly
        ? (widget.priceFontSize * 1.33 * scaleFactor).clamp(kMinFont, 28.0)
        : (widget.priceFontSize * scaleFactor).clamp(kMinFont, 22.0);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: textOnly ? 12 : 8,
        vertical: textOnly ? 8 : 4,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: AppColors.border.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Name with more vertical space and flexible layout
          Flexible(
            flex: textOnly ? 3 : 2,
            child: Align(
              alignment: textOnly
                  ? Alignment.center
                  : AlignmentDirectional.centerStart,
              child: Text(
                widget.product.name,
                style: TextStyle(
                  fontSize: nameFontSize,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                  height: 1.1,
                  letterSpacing: -0.2,
                ),
                maxLines: textOnly ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                textAlign: textOnly ? TextAlign.center : TextAlign.start,
              ),
            ),
          ),

          // Price and Stock row
          Flexible(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Price with modern alignment
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: widget.product.salePrice.toStringAsFixed(AppConstants.decimalPlaces),
                            style: TextStyle(
                              fontSize: priceFontSize,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                              fontFamily: 'monospace',
                            ),
                          ),
                          TextSpan(
                            text: ' د.أ',
                            style: TextStyle(
                              fontSize: 9 * scaleFactor,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Stock Indicator
                if (widget.product.trackInventory)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isOutOfStock
                          ? AppColors.error.withValues(alpha: 0.1)
                          : isLowStock
                          ? AppColors.warning.withValues(alpha: 0.1)
                          : AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color:
                            (isOutOfStock
                                    ? AppColors.error
                                    : isLowStock
                                    ? AppColors.warning
                                    : AppColors.success)
                                .withValues(alpha: 0.2),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      widget.product.currentStock.toStringAsFixed(0),
                      style: TextStyle(
                        fontSize: (10 * scaleFactor).clamp(8, 12),
                        fontWeight: FontWeight.w900,
                        color: isOutOfStock
                            ? AppColors.error
                            : isLowStock
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeightBadge(double scaleFactor) {
    return Positioned(
      top: 8 * scaleFactor,
      right: 8 * scaleFactor,
      child: Container(
        padding: EdgeInsets.all(6 * scaleFactor),
        decoration: BoxDecoration(
          color: AppColors.info,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: AppColors.info.withValues(alpha: 0.3),
              blurRadius: 4,
            ),
          ],
        ),
        child: Icon(
          PhosphorIconsBold.scales,
          size: 14 * scaleFactor,
          color: Colors.white,
        ),
      ),
    );
  }
}
