// ignore_for_file: avoid_dynamic_calls
part of '../offers_screen.dart';


// ═══════════════════════════════════════════════════════════════════════════
// OFFER DIALOGS — Add/Edit Offer, Product Search
// ═══════════════════════════════════════════════════════════════════════════

mixin _OfferDialogsMixin on ConsumerState<OffersScreen> {
  // Abstract — provided by the shell
  String offerTypeLabel(String type);
  Color offerTypeColor(String type);
  void refreshOffers();

  void showAddOfferDialog(BuildContext context, IOffersRepository repo) {
    showOfferDialog(context, repo, null);
  }

  void showEditOfferDialog(
    BuildContext context,
    IOffersRepository repo,
    Offer offer,
  ) {
    showOfferDialog(context, repo, offer);
  }

  void showOfferDialog(
    BuildContext context,
    IOffersRepository repo,
    Offer? existingOffer,
  ) {
    final nameController = TextEditingController(
      text: existingOffer?.name ?? '',
    );
    final barcodeController = TextEditingController(
      text: existingOffer?.barcode ?? '',
    );
    final copiesController = TextEditingController(text: '1');
    final priceController = TextEditingController(
      text: existingOffer?.offerPrice.toString() ?? '',
    );
    final discountController = TextEditingController(
      text: existingOffer?.discountValue?.toString() ?? '',
    );
    final buyQtyController = TextEditingController(
      text: existingOffer?.buyQuantity?.toString() ?? '',
    );
    final getQtyController = TextEditingController(
      text: existingOffer?.getQuantity?.toString() ?? '',
    );
    final minQtyController = TextEditingController(
      text: existingOffer?.minQuantity?.toString() ?? '',
    );
    final maxUsesController = TextEditingController(
      text: existingOffer?.maxUses?.toString() ?? '',
    );
    final timeStartController = TextEditingController(
      text: existingOffer?.timeStart ?? '',
    );
    final timeEndController = TextEditingController(
      text: existingOffer?.timeEnd ?? '',
    );
    String selectedOfferType = existingOffer?.offerType ?? 'bundle';
    DateTime? startDate = existingOffer?.startDate;
    DateTime? endDate = existingOffer?.endDate;
    List<Map<String, dynamic>> selectedItems = [];
    // Branch targeting — empty list = global (applies everywhere).
    // For an existing offer we hydrate from its branchIds CSV; isGlobal
    // alone is not enough because we need the actual ids to pre-select.
    final List<int> selectedBranchIds = (existingOffer?.isGlobal ?? true)
        ? <int>[]
        : (existingOffer?.branchIds ?? '')
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toList();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // One-time load for existing items
          if (existingOffer != null && selectedItems.isEmpty && !isLoading) {
            isLoading = true;
            repo.getOfferItems(existingOffer.id).then((items) async {
              final productRepo = ref.read(productRepositoryProvider);
              for (final item in items) {
                final product = await productRepo.getProductById(item.productId);
                if (product != null) {
                  setDialogState(() {
                    selectedItems.add({
                      'productId': item.productId,
                      'productName': product.name,
                      'quantity': item.quantity,
                      'currentStock': product.currentStock,
                    });
                  });
                }
              }
              isLoading = false;
            });
          }

          return Directionality(
            textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(PhosphorIconsBold.tag, color: AppColors.warning),
                const SizedBox(width: 8),
                Text(existingOffer == null ? 'إضافة عرض جديد' : 'تعديل العرض'),
              ],
            ),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم العرض *',
                        prefixIcon: Icon(PhosphorIconsBold.textT),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Offer Type Selector
                    Wrap(
                      spacing: 8,
                      children:
                          [
                            'bundle',
                            'buy_x_get_y',
                            'percentage',
                            'fixed_discount',
                          ].map((type) {
                            final isSelected = selectedOfferType == type;
                            return ChoiceChip(
                              label: Text(offerTypeLabel(type)),
                              selected: isSelected,
                              selectedColor: offerTypeColor(
                                type,
                              ).withValues(alpha: 0.2),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? offerTypeColor(type)
                                    : null,
                                fontWeight: isSelected ? FontWeight.bold : null,
                              ),
                              onSelected: (_) => setDialogState(
                                () => selectedOfferType = type,
                              ),
                            );
                          }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Barcode + Print
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: barcodeController,
                            decoration: const InputDecoration(
                              labelText: 'الباركود (اختياري)',
                              prefixIcon: Icon(PhosphorIconsBold.barcode),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 70,
                          child: TextField(
                            controller: copiesController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'نسخ',
                              isDense: true,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 42,
                          child: ElevatedButton.icon(
                            onPressed: barcodeController.text.isEmpty
                                ? null
                                : () async {
                                    final copies =
                                        int.tryParse(copiesController.text) ??
                                        1;
                                    if (copies <= 0) return;
                                    try {
                                      await InvoiceGenerator.printBarcodeLabel(
                                        barcodeValue: barcodeController.text,
                                        productName:
                                            nameController.text.isNotEmpty
                                            ? nameController.text
                                            : 'عرض',
                                        price:
                                            double.tryParse(
                                              priceController.text,
                                            ) ??
                                            0,
                                        copies: copies,
                                      );
                                      if (ctx.mounted) {
                                        AppToast.show(
                                          ctx,
                                          'تم إرسال $copies نسخة للطباعة',
                                          type: ToastType.success,
                                        );
                                      }
                                    } catch (e) {
                                      if (ctx.mounted) {
                                        AppToast.show(
                                          ctx,
                                          'خطأ في الطباعة: $e',
                                          type: ToastType.error,
                                        );
                                      }
                                    }
                                  },
                            icon: const Icon(
                              PhosphorIconsBold.printer,
                              size: 16,
                            ),
                            label: const Text(
                              'طباعة',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.warning,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // — Dynamic fields based on offer type —
                    if (selectedOfferType == 'percentage' ||
                        selectedOfferType == 'fixed_discount') ...[
                      TextField(
                        controller: discountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: selectedOfferType == 'percentage'
                              ? 'نسبة الخصم (%) *'
                              : 'مبلغ الخصم *',
                          prefixIcon: const Icon(PhosphorIconsBold.percent),
                          suffixText: selectedOfferType == 'percentage'
                              ? '%'
                              : AppConstants.currencySymbolEn,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (selectedOfferType == 'buy_x_get_y') ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: buyQtyController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'اشترِ (كمية) *',
                                prefixIcon: Icon(
                                  PhosphorIconsBold.shoppingCart,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: getQtyController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'واحصل على (كمية) *',
                                prefixIcon: Icon(PhosphorIconsBold.gift),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Min quantity + Max uses (all types)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minQtyController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'الحد الأدنى للكمية',
                              prefixIcon: Icon(PhosphorIconsBold.listNumbers),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxUsesController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'الحد الأقصى للاستخدام',
                              prefixIcon: Icon(PhosphorIconsBold.usersThree),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Daily time window
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: timeStartController,
                            decoration: const InputDecoration(
                              labelText: 'من ساعة (HH:mm)',
                              prefixIcon: Icon(PhosphorIconsBold.clock),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: timeEndController,
                            decoration: const InputDecoration(
                              labelText: 'إلى ساعة (HH:mm)',
                              prefixIcon: Icon(
                                PhosphorIconsBold.clockAfternoon,
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Price
                    TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'سعر العرض *',
                        prefixIcon: const Icon(
                          PhosphorIconsBold.currencyCircleDollar,
                        ),
                        suffixText: AppConstants.currencySymbolEn,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Date range
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: ctx,
                                initialDate: startDate ?? DateTime.now(),
                                firstDate: DateTime.now().subtract(
                                  const Duration(days: 365),
                                ),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365),
                                ),
                              );
                              if (date != null) {
                                setDialogState(() => startDate = date);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.textMuted.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    PhosphorIconsBold.calendarBlank,
                                    size: 18,
                                    color: AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    startDate != null
                                        ? '${startDate!.day}/${startDate!.month}/${startDate!.year}'
                                        : 'تاريخ البداية',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: ctx,
                                initialDate:
                                    endDate ??
                                    (startDate ?? DateTime.now()).add(
                                      const Duration(days: 7),
                                    ),
                                firstDate: startDate ?? DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365),
                                ),
                              );
                              if (date != null) {
                                setDialogState(() => endDate = date);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.textMuted.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    PhosphorIconsBold.calendarCheck,
                                    size: 18,
                                    color: AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    endDate != null
                                        ? '${endDate!.day}/${endDate!.month}/${endDate!.year}'
                                        : 'تاريخ النهاية',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Products section
                    Row(
                      children: [
                        const Icon(
                          PhosphorIconsBold.package,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'مكونات العرض',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _showProductSearchDialog(
                            ctx,
                            ref.read(productRepositoryProvider),
                            selectedItems,
                            setDialogState,
                          ),
                          icon: const Icon(PhosphorIconsBold.plus, size: 16),
                          label: const Text('إضافة صنف'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Selected products list
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.textMuted.withValues(alpha: 0.2),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: selectedItems.isEmpty
                          ? const Center(
                              child: Text(
                                'لم يتم إضافة أصناف بعد',
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(8),
                              itemCount: selectedItems.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (ctx, idx) {
                                final item = selectedItems[idx];
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    PhosphorIconsBold.package,
                                    size: 18,
                                  ),
                                  title: Text(item['productName'] ?? ''),
                                  subtitle: Text(
                                    'الرصيد: ${(item['currentStock'] as double).toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          PhosphorIconsBold.minus,
                                          size: 16,
                                        ),
                                        onPressed: item['quantity'] > 1
                                            ? () => setDialogState(
                                                () => item['quantity'] =
                                                    item['quantity'] - 1,
                                              )
                                            : null,
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.warning.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          (item['quantity'] as double)
                                              .toStringAsFixed(0),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          PhosphorIconsBold.plus,
                                          size: 16,
                                        ),
                                        onPressed: () => setDialogState(
                                          () => item['quantity'] =
                                              item['quantity'] + 1,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          PhosphorIconsBold.x,
                                          size: 16,
                                          color: AppColors.error,
                                        ),
                                        onPressed: () => setDialogState(
                                          () => selectedItems.removeAt(idx),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 16),
                    // Branch targeting — leave empty to apply to all branches.
                    // Hidden when only one branch exists (no choice to make);
                    // shown unconditionally otherwise so the admin can scope
                    // the offer per outlet.
                    Consumer(builder: (ctx, ref, _) {
                      final branchesAsync = ref.watch(allBranchesProvider);
                      return branchesAsync.maybeWhen(
                        data: (branches) {
                          if (branches.length <= 1) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'الفروع التي يطبق فيها العرض',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'اتركها فارغة لتطبيق العرض على كل الفروع',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: branches.map((b) {
                                  final sel = selectedBranchIds.contains(b.id);
                                  return FilterChip(
                                    label: Text(
                                      b.name,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    selected: sel,
                                    onSelected: (v) => setDialogState(() {
                                      if (v) {
                                        selectedBranchIds.add(b.id);
                                      } else {
                                        selectedBranchIds.remove(b.id);
                                      }
                                    }),
                                  );
                                }).toList(),
                              ),
                            ],
                          );
                        },
                        orElse: () => const SizedBox.shrink(),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        // Validation
                        if (nameController.text.trim().isEmpty) {
                          AppToast.show(
                            ctx,
                            'يرجى إدخال اسم العرض',
                            type: ToastType.warning,
                          );
                          return;
                        }
                        final price = double.tryParse(priceController.text);
                        if (price == null || price <= 0) {
                          AppToast.show(
                            ctx,
                            'يرجى إدخال سعر صحيح',
                            type: ToastType.warning,
                          );
                          return;
                        }
                        if (selectedItems.isEmpty) {
                          AppToast.show(
                            ctx,
                            'يرجى إضافة أصناف للعرض',
                            type: ToastType.warning,
                          );
                          return;
                        }

                        setDialogState(() => isLoading = true);

                        try {
                          if (existingOffer == null) {
                            // Create new offer
                            final offerId = await repo.insertOffer(
                              OffersCompanion.insert(
                                name: nameController.text.trim(),
                                barcode: Value(
                                  barcodeController.text.trim().isEmpty
                                      ? null
                                      : barcodeController.text.trim(),
                                ),
                                offerPrice: price,
                                startDate: Value(startDate),
                                endDate: Value(endDate),
                                offerType: Value(selectedOfferType),
                                discountValue: Value(
                                  double.tryParse(discountController.text),
                                ),
                                buyQuantity: Value(
                                  int.tryParse(buyQtyController.text),
                                ),
                                getQuantity: Value(
                                  int.tryParse(getQtyController.text),
                                ),
                                minQuantity: Value(
                                  int.tryParse(minQtyController.text),
                                ),
                                maxUses: Value(
                                  int.tryParse(maxUsesController.text),
                                ),
                                timeStart: Value(
                                  timeStartController.text.isEmpty
                                      ? null
                                      : timeStartController.text,
                                ),
                                timeEnd: Value(
                                  timeEndController.text.isEmpty
                                      ? null
                                      : timeEndController.text,
                                ),
                                isGlobal: Value(selectedBranchIds.isEmpty),
                                branchIds: Value(
                                  selectedBranchIds.isEmpty
                                      ? null
                                      : selectedBranchIds.join(','),
                                ),
                              ),
                            );

                            // Add items
                            for (final item in selectedItems) {
                              await repo.insertOfferItem(
                                OfferItemsCompanion.insert(
                                  offerId: offerId,
                                  productId: item['productId'] as int,
                                  quantity: item['quantity'] as double,
                                ),
                              );
                            }
                            try {
                              final auth = ref.read(authProvider);
                              final logger = ref.read(activityLoggerProvider);
                              await logger.logOfferAdd(
                                auth.user?.id ?? 0,
                                auth.user?.displayName ?? '',
                                nameController.text.trim(),
                                price,
                              );
                            } catch (e) {
                              debugPrint('[ActivityLog] Error: $e');
                            }
                          } else {
                            // Update existing offer
                            await repo.updateOffer(
                              existingOffer.copyWith(
                                name: nameController.text.trim(),
                                barcode: barcodeController.text.trim().isEmpty
                                    ? const Value(null)
                                    : Value(barcodeController.text.trim()),
                                offerPrice: price,
                                startDate: Value(startDate),
                                endDate: Value(endDate),
                                offerType: selectedOfferType,
                                discountValue: Value(
                                  double.tryParse(discountController.text),
                                ),
                                buyQuantity: Value(
                                  int.tryParse(buyQtyController.text),
                                ),
                                getQuantity: Value(
                                  int.tryParse(getQtyController.text),
                                ),
                                minQuantity: Value(
                                  int.tryParse(minQtyController.text),
                                ),
                                maxUses: Value(
                                  int.tryParse(maxUsesController.text),
                                ),
                                timeStart: Value(
                                  timeStartController.text.isEmpty
                                      ? null
                                      : timeStartController.text,
                                ),
                                timeEnd: Value(
                                  timeEndController.text.isEmpty
                                      ? null
                                      : timeEndController.text,
                                ),
                                isGlobal: selectedBranchIds.isEmpty,
                                branchIds: Value(
                                  selectedBranchIds.isEmpty
                                      ? null
                                      : selectedBranchIds.join(','),
                                ),
                              ),
                            );

                            // Delete old items and add new ones
                            await repo.deleteOfferItems(existingOffer.id);
                            for (final item in selectedItems) {
                              await repo.insertOfferItem(
                                OfferItemsCompanion.insert(
                                  offerId: existingOffer.id,
                                  productId: item['productId'] as int,
                                  quantity: item['quantity'] as double,
                                ),
                              );
                            }
                            try {
                              final auth = ref.read(authProvider);
                              final logger = ref.read(activityLoggerProvider);
                              await logger.logOfferEdit(
                                auth.user?.id ?? 0,
                                auth.user?.displayName ?? '',
                                nameController.text.trim(),
                              );
                            } catch (e) {
                              debugPrint('[ActivityLog] Error: $e');
                            }
                          }

                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            refreshOffers();
                            AppToast.show(
                              context,
                              existingOffer == null
                                  ? 'تم إضافة العرض بنجاح'
                                  : 'تم تحديث العرض بنجاح',
                              type: ToastType.success,
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isLoading = false);
                          if (ctx.mounted) {
                            AppToast.show(
                              ctx,
                              'خطأ: $e',
                              type: ToastType.error,
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(existingOffer == null ? 'إضافة' : 'حفظ'),
              ),
            ],
            ),
          );
        },
      ),
    );
  }

  void _showProductSearchDialog(
    BuildContext parentCtx,
    IProductRepository productRepo,
    List<Map<String, dynamic>> selectedItems,
    StateSetter setParentState,
  ) {
    final searchController = TextEditingController();
    final barcodeController = TextEditingController();

    showDialog(
      context: parentCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(
                  PhosphorIconsBold.magnifyingGlass,
                  color: AppColors.primary,
                ),
                SizedBox(width: 8),
                Text('اختر صنف'),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 450,
              child: Column(
                children: [
                  // Barcode input for quick add
                  TextField(
                    controller: barcodeController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'امسح أو اكتب الباركود...',
                      prefixIcon: const Icon(PhosphorIconsBold.barcode),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: AppColors.warning.withValues(alpha: 0.05),
                    ),
                    onSubmitted: (barcode) async {
                      if (barcode.isEmpty) return;

                      var product = await productRepo.getProductByBarcode(barcode);
                      product ??= await productRepo.getProductByCode(barcode);

                      if (product != null) {
                        final p = product;
                        final alreadySelected = selectedItems.any(
                          (i) => i['productId'] == p.id,
                        );
                        if (alreadySelected) {
                          if (ctx.mounted) {
                            AppToast.show(
                              ctx,
                              'الصنف مضاف مسبقاً',
                              type: ToastType.warning,
                            );
                          }
                        } else {
                          selectedItems.add({
                            'productId': product.id,
                            'productName': product.name,
                            'quantity': 1.0,
                            'currentStock': product.currentStock,
                          });
                          setParentState(() {});
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            AppToast.show(
                              parentCtx,
                              'تمت إضافة: ${product.name}',
                              type: ToastType.success,
                            );
                          }
                        }
                      } else {
                        if (ctx.mounted) {
                          AppToast.show(
                            ctx,
                            'لم يتم العثور على صنف بالباركود: $barcode',
                            type: ToastType.error,
                          );
                        }
                      }
                      barcodeController.clear();
                    },
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  // Name search field
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'أو ابحث بالاسم...',
                      prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StreamBuilder<List<ProductEntity>>(
                      stream: productRepo.watchAllProducts(),
                      builder: (ctx, snap) {
                        var products = snap.data ?? [];
                        final search = searchController.text.toLowerCase();
                          if (search.isNotEmpty) {
                            products = products
                                .where(
                                  (p) =>
                                      p.name.toLowerCase().contains(search) ||
                                      p.code.toLowerCase().contains(search) ||
                                      (p.barcode != null && p.barcode!.toLowerCase().contains(search)),
                                )
                                .toList();
                          }

                        final selectedIds = selectedItems
                            .map((i) => i['productId'] as int)
                            .toSet();
                        products = products
                            .where((p) => !selectedIds.contains(p.id))
                            .toList();

                        if (products.isEmpty) {
                          return const Center(
                            child: Text(
                              'لا توجد أصناف',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: products.length,
                          itemBuilder: (ctx, idx) {
                            final product = products[idx];
                            return ListTile(
                              leading: const Icon(PhosphorIconsBold.package),
                              title: Text(product.name),
                              subtitle: Text(
                                '${product.code} | الرصيد: ${product.currentStock.toStringAsFixed(0)}',
                              ),
                              trailing: Text(
                                '${product.salePrice.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                              ),
                              onTap: () {
                                selectedItems.add({
                                  'productId': product.id,
                                  'productName': product.name,
                                  'quantity': 1.0,
                                  'currentStock': product.currentStock,
                                });
                                setParentState(() {});
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}