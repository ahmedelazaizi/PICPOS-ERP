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

// ── فيكس المراجعة (Task 6b) ──────────────────────────────────────────────
// المراجعة رصدت إن `canEditOffer`/`canDeleteOffer` كانوا متفحوصين لوحدهم
// بس — لو حد شال شرط `if (!canEditOffer(perms))` من جوه `onSelected` وسايب
// الدالة زي ما هي، كل الاختبارات كانت هتفضل خضرا (نفس شكل باج f8d3fa9:
// الفحص موجود، لكن السلك اللي بينده عليه مش مضمون). عشان الفحص ده يتثبت
// فعلاً، اتنقلت `PopupMenuButton` كلها (مع منطق `onSelected`) لودجت
// top-level مستقل (`OfferCardActionsMenu`) — بيتبنى هنا لوحده في اختبار
// widget (فتح الميني، اختيار عنصر، والتأكد إن الـcallback اتنفذ أو لأ)
// من غير ما نحتاج شاشة `OffersScreen`/قاعدة بيانات حقيقية، لإن الـcallbacks
// (`onEdit`/`onDelete`/`onToggle`/`onPrintBarcode`) بقوا بارامترات بسيطة.
@visibleForTesting
class OfferCardActionsMenu extends ConsumerWidget {
  final bool offerIsActive;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;
  final VoidCallback onPrintBarcode;

  const OfferCardActionsMenu({
    super.key,
    required this.offerIsActive,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onPrintBarcode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `ref.watch` (مش `ref.read`) هنا مقصودة: بيخلّي الـFutureProvider يبدأ
    // يتحلّ من أول ما الودجت يتبني، فمفيش سباق زمني لو المستخدم ضغط على
    // القائمة قبل ما أول قراءة تحصل (اللي كانت بترجع `AsyncLoading` وتتفسّر
    // غلط كـ"مفيش صلاحيات"). اتكشف الباج ده عملياً في اختبار الودجت لما
    // الحالة "مع الصلاحية" كانت بتفشل رغم إن الـoverride مظبوط.
    final perms = ref.watch(currentUserPermissionsProvider).asData?.value ??
        const <String>[];
    return PopupMenuButton<String>(
      onSelected: (value) {
        try {
          if (value == 'edit') {
            if (!canEditOffer(perms)) {
              AppToast.show(context, tr('ليس لديك صلاحية تعديل العروض'),
                  type: ToastType.error);
              return;
            }
            onEdit();
          } else if (value == 'delete') {
            if (!canDeleteOffer(perms)) {
              AppToast.show(context, tr('ليس لديك صلاحية حذف العروض'),
                  type: ToastType.error);
              return;
            }
            onDelete();
          } else if (value == 'toggle') {
            // تفعيل/إيقاف العرض بينده على `repo.updateOffer` — نفس فعل
            // الكتابة اللي وراء ديالوج التعديل بالظبط (مجرد تغيير حقل
            // `isActive` بدل فتح الفورم كله)، فبيتحمي بنفس كود
            // `offers_edit` مش كود جديد.
            if (!canEditOffer(perms)) {
              AppToast.show(context, tr('ليس لديك صلاحية تعديل العروض'),
                  type: ToastType.error);
              return;
            }
            onToggle();
          } else if (value == 'print_barcode') {
            onPrintBarcode();
          }
        } catch (e) {
          debugPrint('[OfferCards] Action error: $e');
          AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
        }
      },
      position: PopupMenuPosition.under,
      itemBuilder: (ctx) => [
         PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.pencil, size: 18, color: AppColors.info),
              const SizedBox(width: 8),
              Text(tr('تعديل')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: Row(
            children: [
              Icon(
                offerIsActive ? PhosphorIconsBold.pause : PhosphorIconsBold.play,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: 8),
              Text(offerIsActive ? tr('إيقاف') : tr('تفعيل')),
            ],
          ),
        ),
         PopupMenuItem(
          value: 'print_barcode',
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.barcode, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(tr('طباعة باركود')),
            ],
          ),
        ),
         PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(PhosphorIconsBold.trash, size: 18, color: AppColors.error),
              const SizedBox(width: 8),
              Text(tr('حذف')),
            ],
          ),
        ),
      ],
    );
  }
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
      statusText = tr('غير فعال');
      statusColor = AppColors.textMuted;
    } else if (isExpired) {
      statusText = tr('منتهي');
      statusColor = AppColors.error;
    } else if (isNotStarted) {
      statusText = tr('لم يبدأ');
      statusColor = AppColors.info;
    } else {
      statusText = tr('فعال');
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
                OfferCardActionsMenu(
                  offerIsActive: offer.isActive,
                  onEdit: () {
                    if (!mounted) return;
                    showEditOfferDialog(context, repo, offer);
                  },
                  onDelete: () {
                    if (!mounted) return;
                    _confirmDeleteOffer(repo, offer);
                  },
                  onToggle: () {
                    if (!mounted) return;
                    _toggleOfferStatus(repo, offer);
                  },
                  onPrintBarcode: () => _printOfferBarcode(offer),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Price
            Row(
              children: [
                 Text(
                  tr('سعر العرض: '),
                  style: const TextStyle(color: AppColors.textMuted),
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
                            tr('{p0} أصناف في العرض', {'p0': items.length}),
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
                                                tr('صنف #{p0}', {'p0': item.productId}),
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
                          tr('+{p0} أصناف أخرى', {'p0': items.length - 3}),
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
    if (start == null && end == null) return tr('غير محدد');
    if (start != null && end == null) {
      return tr('يبدأ {p0}/{p1}/{p2}', {'p0': start.day, 'p1': start.month, 'p2': start.year});
    }
    if (start == null && end != null) {
      return tr('ينتهي {p0}/{p1}/{p2}', {'p0': end.day, 'p1': end.month, 'p2': end.year});
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
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.warning, color: AppColors.error),
              const SizedBox(width: 8),
              Text(tr('حذف العرض')),
            ],
          ),
          content: Text(tr('هل أنت متأكد من حذف العرض "{p0}"؟', {'p0': offer.name})),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child:  Text(tr('حذف')),
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
        AppToast.show(context, tr('تم حذف العرض'), type: ToastType.success);
      }
    }
  }

  Future<void> _printOfferBarcode(Offer offer) async {
    if (offer.barcode == null || offer.barcode!.isEmpty) {
      if (mounted) {
        AppToast.show(
          context,
          tr('لا يوجد باركود مسجل لهذا العرض'),
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
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.printer, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(tr('طباعة باركود العرض')),
            ],
          ),
          content: TextField(
            controller: copiesController,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration:  InputDecoration(
              labelText: tr('عدد النسخ'),
              prefixIcon: const Icon(PhosphorIconsBold.copy),
            ),
            onSubmitted: (_) =>
                Navigator.pop(ctx, int.tryParse(copiesController.text) ?? 1),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(copiesController.text) ?? 1),
              child:  Text(tr('طباعة')),
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
          userName: user?.displayName ?? tr('مستخدم'),
          action: 'offer_print',
          entityType: 'offer',
          entityId: offer.id,
          description: tr('طباعة باركود عرض: {p0} — {copies} نسخة', {'p0': offer.name, 'copies': copies}),
        );
      } catch (_) {}

      if (mounted) {
        AppToast.show(
          context,
          tr('تم إرسال {copies} نسخة للطباعة', {'copies': copies}),
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ في الطباعة: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }
}
