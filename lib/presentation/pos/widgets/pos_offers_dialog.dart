import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/offers_repository.dart';
import '../providers/cart_controller.dart';
import '../providers/pos_notification_provider.dart';
import '../../../../../../core/constants/app_constants.dart';

/// Dialog for viewing and adding active offers to the cart
class PosOffersDialog extends ConsumerWidget {
  const PosOffersDialog({super.key});

  /// Static helper to show the dialog
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const PosOffersDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offersRepo = ref.read(offersRepositoryProvider);
    final now = DateTime.now();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                PhosphorIconsBold.tag,
                color: AppColors.warning,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text('عروض خاصة'),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: StreamBuilder<List<Offer>>(
            stream: offersRepo.watchActiveOffers(),
            builder: (ctx, snapshot) {
              var offers = snapshot.data ?? [];

              // Filter active and valid date range offers
              offers = offers.where((o) {
                if (o.startDate != null && o.startDate!.isAfter(now)) {
                  return false;
                }
                if (o.endDate != null && o.endDate!.isBefore(now)) return false;
                return true;
              }).toList();

              if (offers.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        PhosphorIconsBold.tag,
                        size: 64,
                        color: AppColors.textMuted.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'لا توجد عروض نشطة حالياً',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                );
              }

              return GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                ),
                itemCount: offers.length,
                itemBuilder: (ctx, index) {
                  final offer = offers[index];
                  return _buildOfferCard(ctx, ref, offersRepo, offer);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferCard(
    BuildContext ctx,
    WidgetRef ref,
    IOffersRepository offersRepo,
    Offer offer,
  ) {
    return InkWell(
      onTap: () => _addOfferToCart(ctx, ref, offersRepo, offer),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  PhosphorIconsBold.tag,
                  color: AppColors.warning,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    offer.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FutureBuilder<List<OfferItem>>(
              future: offersRepo.getOfferItems(offer.id),
              builder: (ctx, snap) {
                final count = snap.data?.length ?? 0;
                return Text(
                  '$count أصناف',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${offer.offerPrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(
                  PhosphorIconsBold.plus,
                  color: AppColors.success,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addOfferToCart(
    BuildContext context,
    WidgetRef ref,
    IOffersRepository offersRepo,
    Offer offer,
  ) async {
    final items = await offersRepo.getOfferItems(offer.id);

    if (items.isEmpty) {
      if (!context.mounted) return;
      showPosToast(
        context,
        ref,
        'العرض لا يحتوي على أصناف',
        type: PosNotificationType.warning,
      );
      return;
    }

    // Use the controller's applyOffer for atomic batch-add
    final controller = ref.read(cartControllerProvider.notifier);
    final outcome = await controller.applyOffer(offer);

    if (!context.mounted) return;
    // كل رفض له رسالته. الفرق بين «مضاف بالفعل» و«سعر العرض غلط» هو الفرق بين
    // «كمّل شغلك» و«روح صلّح العرض» — دمجهم في رسالة واحدة كان بيخلّي عرض
    // مقلوب يبان كأنه مكرَّر.
    if (outcome != ApplyOfferOutcome.added) {
      final message = switch (outcome) {
        ApplyOfferOutcome.alreadyInCart =>
          'العرض "${offer.name}" مضاف بالفعل إلى السلة',
        ApplyOfferOutcome.notADiscount =>
          'العرض "${offer.name}" سعره أعلى من مجموع أسعار بيع أصنافه — '
              'اترفض عشان ما يرفعش الأسعار. راجع سعر العرض.',
        _ => 'تعذّر تطبيق العرض "${offer.name}" — تأكد من أصناف العرض',
      };
      showPosToast(
        context,
        ref,
        message,
        type: PosNotificationType.warning,
      );
      return;
    }
    showPosToast(
      context,
      ref,
      'تمت إضافة عرض "${offer.name}" (${items.length} أصناف) بسعر ${offer.offerPrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
      type: PosNotificationType.success,
    );
  }
}
