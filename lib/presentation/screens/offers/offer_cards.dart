part of '../offers_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OFFER CARDS — Card UI, status toggle, delete, print barcode
// ═══════════════════════════════════════════════════════════════════════════

/// هل [permissions] تسمح بتعديل عرض؟
///
/// مستخرجة كدالة top-level (مش method جوه الـState) — فعل التعديل/الحذف بينده
/// عليهم `PopupMenuButton.onSelected` لكل كارت عرض، فمفيش ودجت واحد يتلف
/// بـ`PermissionGuard` (نفس وضع `canCancelEInvoice` في Task 6a): الـ
/// `PopupMenuItem` نفسه بيمسك الضغطة ويقفل الميني قبل ما أي حارس جواه يشتغل.
bool canEditOffer(List<String> permissions) {
  final isAdmin =
      permissions.contains('system_admin') || permissions.contains('*');
  return isAdmin || permissions.contains(PermissionCodes.offersEdit);
}

/// هل [permissions] تسمح بحذف عرض؟ نفس منطق [canEditOffer].
bool canDeleteOffer(List<String> permissions) {
  final isAdmin =
      permissions.contains('system_admin') || permissions.contains('*');
  return isAdmin || permissions.contains(PermissionCodes.offersDelete);
}

mixin _OfferCardsMixin on ConsumerState<OffersScreen> {
  // Abstract — provided by the shell
  String offerTypeLabel(String type);
  Color offerTypeColor(String type);
  void showEditOfferDialog(BuildContext context, IOffersRepository repo, Offer offer);

  Widget buildOfferCard(Offer offer, IOffersRepository repo, IProductRepository productRepo) {
    final now = DateTime.now();
    final isExpired = offer.endDate != null && offer.endDate!.isBefore(now);
    final isNotStarted =
        offer.startDate != null && offer.startDate!.isAfter(now);

    String statusText;
    Color statusColor;
    if (!offer.isActive) {
      statusText = 'غير فعال';
      statusColor = AppColors.textMuted;
    } else if (isExpired) {
      statusText = 'منتهي';
      statusColor = AppColors.error;
    } else if (isNotStarted) {
      statusText = 'لم يبدأ';
      statusColor = AppColors.info;
    } else {
      statusText = 'فعال';
      statusColor = AppColors.success;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    PhosphorIconsBold.tag,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              offer.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: offerTypeColor(
                                offer.offerType,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              offerTypeLabel(offer.offerType),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: offerTypeColor(offer.offerType),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    try {
                      final perms = ref
                              .read(currentUserPermissionsProvider)
                              .asData
                              ?.value ??
                          const <String>[];
                      if (value == 'edit') {
                        if (!mounted) return;
                        if (!canEditOffer(perms)) {
                          AppToast.show(context, 'ليس لديك صلاحية تعديل العروض',
                              type: ToastType.error);
                          return;
                        }
                        showEditOfferDialog(context, repo, offer);
                      } else if (value == 'delete') {
                        if (!mounted) return;
                        if (!canDeleteOffer(perms)) {
                          AppToast.show(context, 'ليس لديك صلاحية حذف العروض',
                              type: ToastType.error);
                          return;
                        }
                        _confirmDeleteOffer(repo, offer);
                      } else if (value == 'toggle') {
                        // تفعيل/إيقاف العرض بينده على `repo.updateOffer` — نفس
                        // فعل الكتابة اللي وراء ديالوج التعديل بالظبط (مجرد
                        // تغيير حقل `isActive` بدل فتح الفورم كله)، فبيتحمي
                        // بنفس كود `offers_edit` مش كود جديد.
                        if (!mounted) return;
                        if (!canEditOffer(perms)) {
                          AppToast.show(context, 'ليس لديك صلاحية تعديل العروض',
                              type: ToastType.error);
                          return;
                        }
                        _toggleOfferStatus(repo, offer);
                      } else if (value == 'print_barcode') {
                        _printOfferBarcode(offer);
                      }
                    } catch (e) {
                      debugPrint('[OfferCards] Action error: $e');
                      if (mounted) {
                        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
                      }
                    }
                  },
                  position: PopupMenuPosition.under,
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(
                            PhosphorIconsBold.pencil,
                            size: 18,
                            color: AppColors.info,
                          ),
                          SizedBox(width: 8),
                          Text('تعديل'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Row(
                        children: [
                          Icon(
                            offer.isActive
                                ? PhosphorIconsBold.pause
                                : PhosphorIconsBold.play,
                            size: 18,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 8),
                          Text(offer.isActive ? 'إيقاف' : 'تفعيل'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'print_barcode',
                      child: Row(
                        children: [
                          Icon(
                            PhosphorIconsBold.barcode,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 8),
                          Text('طباعة باركود'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            PhosphorIconsBold.trash,
                            size: 18,
                            color: AppColors.error,
                          ),
                          SizedBox(width: 8),
                          Text('حذف'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Price
            Row(
              children: [
                const Text(
                  'سعر العرض: ',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                Text(
                  '${offer.offerPrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Date range
            if (offer.startDate != null || offer.endDate != null) ...[
              Row(
                children: [
                  const Icon(
                    PhosphorIconsBold.calendar,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formatDateRange(offer.startDate, offer.endDate),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            const Divider(),

            // Items count
            Expanded(
              child: FutureBuilder<List<OfferItem>>(
                future: repo.getOfferItems(offer.id),
                builder: (ctx, snap) {
                  final items = snap.data ?? [];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            PhosphorIconsBold.package,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${items.length} أصناف في العرض',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (items.isNotEmpty)
                        Expanded(
                          child: ListView.builder(
                            itemCount: items.take(3).length,
                            itemBuilder: (ctx, idx) {
                              final item = items[idx];
                              return FutureBuilder<ProductEntity?>(
                                future: productRepo.getProductById(item.productId),
                                builder: (ctx, prodSnap) {
                                  final product = prodSnap.data;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: AppColors.warning,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            product?.name ??
                                                'صنف #${item.productId}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          '×${item.quantity.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      if (items.length > 3)
                        Text(
                          '+${items.length - 3} أصناف أخرى',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String formatDateRange(DateTime? start, DateTime? end) {
    if (start == null && end == null) return 'غير محدد';
    if (start != null && end == null) {
      return 'يبدأ ${start.day}/${start.month}/${start.year}';
    }
    if (start == null && end != null) {
      return 'ينتهي ${end.day}/${end.month}/${end.year}';
    }
    return '${start!.day}/${start.month} - ${end!.day}/${end.month}/${end.year}';
  }

  Future<void> _toggleOfferStatus(IOffersRepository repo, Offer offer) async {
    final newStatus = !offer.isActive;
    await repo.updateOffer(offer.copyWith(isActive: newStatus));
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logOfferToggle(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        offer.name,
        newStatus,
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
  }

  Future<void> _confirmDeleteOffer(IOffersRepository repo, Offer offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.warning, color: AppColors.error),
              SizedBox(width: 8),
              Text('حذف العرض'),
            ],
          ),
          content: Text('هل أنت متأكد من حذف العرض "${offer.name}"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
 
    if (confirmed == true) {
      await repo.deleteOfferItems(offer.id);
      await repo.deleteOffer(offer.id);
      try {
        final auth = ref.read(authProvider);
        final logger = ref.read(activityLoggerProvider);
        await logger.logOfferDelete(
          auth.user?.id ?? 0,
          auth.user?.displayName ?? '',
          offer.name,
        );
      } catch (e) {
        debugPrint('[ActivityLog] Error: $e');
      }
      if (mounted) {
        AppToast.show(context, 'تم حذف العرض', type: ToastType.success);
      }
    }
  }

  Future<void> _printOfferBarcode(Offer offer) async {
    if (offer.barcode == null || offer.barcode!.isEmpty) {
      if (mounted) {
        AppToast.show(
          context,
          'لا يوجد باركود مسجل لهذا العرض',
          type: ToastType.warning,
        );
      }
      return;
    }

    final copiesController = TextEditingController(text: '1');
    final copies = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.printer, color: AppColors.primary),
              SizedBox(width: 8),
              Text('طباعة باركود العرض'),
            ],
          ),
          content: TextField(
            controller: copiesController,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'عدد النسخ',
              prefixIcon: Icon(PhosphorIconsBold.copy),
            ),
            onSubmitted: (_) =>
                Navigator.pop(ctx, int.tryParse(copiesController.text) ?? 1),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(copiesController.text) ?? 1),
              child: const Text('طباعة'),
            ),
          ],
        ),
      ),
    );

    if (copies == null || copies <= 0) return;

    try {
      await InvoiceGenerator.printBarcodeLabel(
        barcodeValue: offer.barcode!,
        productName: offer.name,
        price: offer.offerPrice,
        copies: copies,
      );

      try {
        final user = ref.read(authProvider).user;
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id,
          userName: user?.displayName ?? 'مستخدم',
          action: 'offer_print',
          entityType: 'offer',
          entityId: offer.id,
          description: 'طباعة باركود عرض: ${offer.name} — $copies نسخة',
        );
      } catch (_) {}

      if (mounted) {
        AppToast.show(
          context,
          'تم إرسال $copies نسخة للطباعة',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
      }
    }
  }
}
