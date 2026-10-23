import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shimmer_loading.dart';

import '../../data/providers/providers.dart';
import '../../domain/repositories/offers_repository.dart';
import '../../domain/repositories/i_products_repository.dart';
import '../../domain/entities/product_entity.dart';
import '../../services/invoice_generator.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/constants/app_constants.dart';
import '../../core/permissions/permission_codes.dart';
import '../widgets/permission_guard.dart';

// ── Part files (mixin-based extraction) ─────────────────────────────────
part 'offers/offer_cards.dart';
part 'offers/offer_dialogs.dart';

// ── دالة بناء مستخرجة (Task 6b) ─────────────────────────────────────────
// زرار «إضافة عرض» كان محمي بكود عرض خشن بس (`offers_view`)، مفيش فحص على
// الإنشاء نفسه (`offers_create`). مستخرج كدالة top-level عشان يتبنى في
// اختبار widget خفيف من غير شاشة/قاعدة بيانات.
@visibleForTesting
Widget buildOffersCreateButton({required VoidCallback onPressed}) {
  return PermissionGuard(
    permission: PermissionCodes.offersCreate,
    allowManagerOverride: true,
    actionName: tr('إضافة عرض'),
    onGranted: onPressed,
    child: ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(PhosphorIconsBold.plus),
      label:  Text(tr('إضافة عرض')),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.warning,
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 16,
        ),
      ),
    ),
  );
}

/// Offers Screen - Manage product bundles/offers with time-limited validity
class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key});

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen>
    with _OfferCardsMixin, _OfferDialogsMixin {
  final _searchController = TextEditingController();
  bool _showActiveOnly = true;
  late Stream<List<Offer>> _offersStream;

  @override
  void initState() {
    super.initState();
    _offersStream = ref.read(offersRepositoryProvider).watchOffers();
  }

  /// Re-subscribe to the stream after a mutation (add/edit/delete)
  @override
  void refreshOffers() {
    setState(() {
      _offersStream = ref.read(offersRepositoryProvider).watchOffers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Shared helpers (used by both mixins) ──────────────────────────────
  @override
  String offerTypeLabel(String type) {
    switch (type) {
      case 'buy_x_get_y':
        return tr('اشترِ X واحصل Y');
      case 'percentage':
        return tr('خصم نسبة');
      case 'fixed_discount':
        return tr('خصم مبلغ');
      case 'bundle':
      default:
        return 'باقة';
    }
  }

  @override
  Color offerTypeColor(String type) {
    switch (type) {
      case 'buy_x_get_y':
        return Colors.purple;
      case 'percentage':
        return Colors.teal;
      case 'fixed_discount':
        return Colors.orange;
      case 'bundle':
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(offersRepositoryProvider);
    final productRepo = ref.read(productRepositoryProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      PhosphorIconsBold.tag,
                      color: AppColors.warning,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                   Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('العروض'),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          tr('إدارة عروض الباقات والأسعار الخاصة'),
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  buildOffersCreateButton(
                    onPressed: () => showAddOfferDialog(context, repo),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Filters
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: tr('بحث في العروض...'),
                        prefixIcon: const Icon(
                          PhosphorIconsBold.magnifyingGlass,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(PhosphorIconsBold.x),
                                onPressed: () =>
                                    setState(() => _searchController.clear()),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Theme.of(context).cardColor,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilterChip(
                    label:  Text(tr('العروض الفعالة فقط')),
                    selected: _showActiveOnly,
                    onSelected: (v) => setState(() => _showActiveOnly = v),
                    avatar: Icon(
                      _showActiveOnly
                          ? PhosphorIconsBold.checkCircle
                          : PhosphorIconsBold.circle,
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Offers Grid
              Expanded(
                child: StreamBuilder<List<Offer>>(
                  stream: _offersStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: ShimmerLoading.list(itemCount: 6),
                      );
                    }

                    var offers = snapshot.data ?? [];

                    // Apply filters
                    final now = DateTime.now();
                    if (_showActiveOnly) {
                      offers = offers.where((dynamic o) {
                        final off = o as Offer;
                        if (!off.isActive) return false;
                        if (off.endDate != null && off.endDate!.isBefore(now)) {
                          return false;
                        }
                        return true;
                      }).toList();
                    }

                    final searchText = _searchController.text
                        .trim()
                        .toLowerCase();
                    if (searchText.isNotEmpty) {
                      offers = offers
                          .where(
                            (dynamic o) => (o as Offer).name.toLowerCase().contains(searchText),
                          )
                          .toList();
                    }

                    if (offers.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              PhosphorIconsBold.tag,
                              size: 80,
                              color: AppColors.textMuted.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 24),
                             Text(
                              tr('لا توجد عروض'),
                              style: const TextStyle(
                                fontSize: 18,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () =>
                                  showAddOfferDialog(context, repo),
                              icon: const Icon(PhosphorIconsBold.plus),
                              label:  Text(tr('إضافة عرض جديد')),
                            ),
                          ],
                        ),
                      );
                    }

                    return GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 400,
                            mainAxisExtent: 280,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                      itemCount: offers.length,
                      itemBuilder: (ctx, index) =>
                          buildOfferCard(offers[index], repo, productRepo),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
