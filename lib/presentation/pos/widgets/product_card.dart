import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/design_system/typography.dart';
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

  /// PicPos indicator scheme: the corner dot means SALE TYPE — red for a
  /// weighed item, blue for a counted one — and the scale badge is hidden
  /// because the dot now carries that information.
  ///
  /// Defaults to `false`, which keeps the UralCash scheme byte-identical: dot
  /// means stock, and weighed items keep their scale badge. That badge is
  /// load-bearing over there — the same grid backs the table-service screen,
  /// where the badge is how staff know to weigh an item before it goes to the
  /// kitchen — so removing it for both tills was never on the table.
  final bool saleTypeDot;

  /// PicPos out-of-stock treatment: fade the whole card instead of laying a
  /// scrim over it. Defaults to `false` (UralCash keeps the scrim).
  final bool dimWhenOutOfStock;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.showImages = true,
    this.nameFontSize = 12.0,
    this.priceFontSize = 14.0,
    this.saleTypeDot = false,
    this.dimWhenOutOfStock = false,
  });

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
                    // PicPos: the whole card fades when out of stock. The
                    // 'غير متوفر' badge and the corner dot are siblings BELOW
                    // in this Stack, i.e. outside the Opacity, so the two
                    // signals stay crisp while the content recedes.
                    Opacity(
                      opacity: widget.dimWhenOutOfStock && isOutOfStock
                          ? 0.42
                          : 1.0,
                      child: Column(
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
                    ),

                    // Out of stock badge. In `dimWhenOutOfStock` mode the
                    // scrim is dropped (the Opacity above replaces it) but the
                    // badge stays — dimming alone is a weak signal to catch at
                    // a glance across a grid of forty cards.
                    if (isOutOfStock)
                      Positioned.fill(
                        child: Container(
                          color: widget.dimWhenOutOfStock
                              ? Colors.transparent
                              : Theme.of(
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
                              child:  Text(
                                tr('غير متوفر'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // PicPos hides the badge — the corner dot below carries the
                    // sale type instead.
                    if (widget.product.isSoldByWeight && !widget.saleTypeDot)
                      _buildWeightBadge(scaleFactor),

                    PositionedDirectional(
                      top: 10,
                      end: 10,
                      child: widget.saleTypeDot
                          ? _buildSaleTypeDot()
                          : _buildStockDot(isOutOfStock),
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

  /// UralCash corner dot — a STOCK indicator (red = out of stock).
  ///
  /// The old code comment called this a "Category Accent"; it never was one.
  /// Left exactly as it was so that till's grid is unchanged.
  Widget _buildStockDot(bool isOutOfStock) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: isOutOfStock ? AppColors.error : AppColors.primary,
          shape: BoxShape.circle,
        ),
      );

  /// PicPos corner dot — a SALE-TYPE indicator. Red = weighed, blue = counted.
  ///
  /// ── ليه الوزن فيه رمز والعدد لأ ───────────────────────────────────────────
  /// لو الفرق بين الصنفين **اللون وحده**، الكاشير اللي عنده عمى ألوان أحمر-أخضر
  /// (حوالي ٨٪ من الرجال) ما بيشوفش أي فرق — والشارة اللي اتخفت (طلب ٦) كانت
  /// مُرمَّزة بالشكل مش باللون، فشيلها بيخصم معلومة عنه.
  ///
  /// فنقطة الوزن جواها ميزان أبيض صغير: الفرق بقى **شكل + لون**، ومين ما يشوف
  /// اللون يشوف الرمز. نقطة العدد بتفضل نقطة صافية — «مفيش رمز» هو نفسه إشارة،
  /// وإضافة رمز ليها كان هيرجّعنا لزحمة بصرية على كل كارت في الشبكة.
  ///
  /// ── وليه مش رجعنا الشارة القديمة ──────────────────────────────────────────
  /// الشارة كانت ٢٢ بكسل بظل ولون خلفية كامل في رُكن الكارت. دي ١٤ بكسل في مكان
  /// النقطة نفسه — أصغر بكتير وبتقرأ كنقطة مميّزة، مش كشارة تاني.
  Widget _buildSaleTypeDot() {
    final isWeighed = widget.product.isSoldByWeight;
    final color = isWeighed ? AppColors.error : AppColors.primary;
    // نقطة العدد ٨ بكسل؛ نقطة الوزن ١٤ عشان الرمز يبان. الفرق في الحجم إشارة
    // زيادة، مجاناً.
    final size = isWeighed ? 14.0 : 8.0;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 2,
          ),
        ],
      ),
      child: isWeighed
          ? const Icon(PhosphorIconsBold.scales, size: 8, color: Colors.white)
          : null,
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
                              fontFamily: AppTypography.mono,
                            ),
                          ),
                          TextSpan(
                            text: tr(' د.أ'),
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
    return PositionedDirectional(
      top: 8 * scaleFactor,
      start: 8 * scaleFactor,
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
