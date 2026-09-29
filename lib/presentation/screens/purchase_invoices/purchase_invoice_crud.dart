part of '../purchase_invoices_screen.dart';

mixin _PurchaseInvoiceCrudMixin on ConsumerState<PurchaseInvoicesScreen> {
  /// Create a new purchase invoice or return
  void createNewInvoice() async {
    if (!mounted) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Purchase Invoice',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) => Scaffold(
        body: PurchaseInvoiceForm(
          onSave: ({
            required int? partyId,
            required String invoiceNumber,
            required String supplierInvoiceNumber,
            required DateTime date,
            required double total,
            required double discount,
            required double tax,
            required double netAmount,
            required double paidAmount,
            required String notes,
            required List<Map<String, dynamic>> items,
            required int? warehouseId,
            required int? costCenterId,
            required bool isDraft,
            required String paymentMethod,
            int? safeId,
            bool printAfterSave = false,
          }) async {
            await _handleSavePurchaseSimple(
              partyId: partyId,
              invoiceNumber: invoiceNumber,
              supplierInvoiceNumber: supplierInvoiceNumber,
              date: date,
              total: total,
              discount: discount,
              tax: tax,
              netAmount: netAmount,
              paidAmount: paidAmount,
              notes: notes,
              items: items,
              warehouseId: warehouseId,
              costCenterId: costCenterId,
              isDraft: isDraft,
              paymentMethod: paymentMethod,
              safeId: safeId,
              printAfterSave: printAfterSave,
            );
          },
        ),
      ),
    );
  }

  /// Edit existing invoice
  void editInvoice(InvoiceEntity invoice) async {
    final purchasesRepo = ref.read(purchasesRepositoryProvider);
    
    // Fetch the raw invoice data for editing
    final rawInvoice = await purchasesRepo.getRawInvoiceById(invoice.id!);

    if (!mounted || rawInvoice == null) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Edit Purchase Invoice',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) => Scaffold(
        body: PurchaseInvoiceForm(
          editInvoice: rawInvoice,
          onSave: ({
            required int? partyId,
            required String invoiceNumber,
            required String supplierInvoiceNumber,
            required DateTime date,
            required double total,
            required double discount,
            required double tax,
            required double netAmount,
            required double paidAmount,
            required String notes,
            required List<Map<String, dynamic>> items,
            required int? warehouseId,
            required int? costCenterId,
            required bool isDraft,
            required String paymentMethod,
            int? safeId,
            bool printAfterSave = false,
          }) async {
            await _handleSavePurchaseSimple(
              partyId: partyId,
              invoiceNumber: invoiceNumber,
              supplierInvoiceNumber: supplierInvoiceNumber,
              date: date,
              total: total,
              discount: discount,
              tax: tax,
              netAmount: netAmount,
              paidAmount: paidAmount,
              notes: notes,
              items: items,
              warehouseId: warehouseId,
              costCenterId: costCenterId,
              isDraft: isDraft,
              editInvoiceId: invoice.id,
              paymentMethod: paymentMethod,
              safeId: safeId,
              printAfterSave: printAfterSave,
            );
          },
        ),
      ),
    );
  }

  /// Centralized handler for saving
  Future<void> _handleSavePurchaseSimple({
    required int? partyId,
    required String invoiceNumber,
    required String supplierInvoiceNumber,
    required DateTime date,
    required double total,
    required double discount,
    required double tax,
    required double netAmount,
    required double paidAmount,
    required String notes,
    required List<Map<String, dynamic>> items,
    required int? warehouseId,
    required int? costCenterId,
    required bool isDraft,
    required String paymentMethod,
    int? editInvoiceId,
    int? safeId,
    bool printAfterSave = false,
  }) async {
    // ترشيحُ المنتقي يحرس **المعروض**، وهذا يحرس **المحفوظ**: المخزنُ يُحسَم
    // من نفسِ المصدرِ الذي عرضه المنتقي، فلا يُختم على الفاتورةِ مخزنٌ خارجَ
    // نطاقِ فرعِ الجهاز — ومنه يُشتقُّ فرعُها ومركزُ تكلفتها
    // (`purchase_dao.dart:589-594`). وكان `warehouseId ?? 1` يخترع المخزنَ
    // رقم ١ حين لا اختيار.
    //
    // ورميٌ لا رسالة: هذه الدالةُ تبتلع أخطاءَها في `catch` أدناه، فالعودةُ
    // منها تبدو للنموذجِ نجاحاً فيُغلق ويضيع ما أدخله المستخدم. والرمي قبل
    // `try` يبلغ `catch` النموذجِ فيبقى مفتوحاً برسالةِ الحارس.
    //
    // ومسارُ التعديل يمرّ كما هو: `null` هناك تعني «اترك المخزنَ كما هو»
    // (`UpdatePurchaseInvoiceParams.warehouseId` قابلٌ للعدم بهذا المعنى)،
    // وما هو مختومٌ فعلاً لا يُجمَّد وإلا تعذّر تحريرُ فاتورةِ فرعٍ آخر.
    final int? resolvedWarehouseId = editInvoiceId != null
        ? warehouseId
        : resolveAssignedWarehouseId(
            selected: warehouseId,
            scopedWarehouseIds:
                (await ref.read(assignableWarehousesProvider(null).future))
                    .map((w) => w.id)
                    .toList(),
          );

    try {
      final purchasesRepo = ref.read(purchasesRepositoryProvider);

      // Convert items to PurchaseItemParams
      final purchaseItems = items.map((item) => PurchaseItemParams(
        productId: item['productId'] as int,
        quantity: (item['quantity'] as num).toDouble(),
        unitCost: (item['unitCost'] as num).toDouble(),
        salePrice: 0,
        taxRate: (item['taxRate'] as num?)?.toDouble() ?? 0,
        taxAmount: (item['taxAmount'] as num?)?.toDouble() ?? 0,
        unitName: item['selectedUnitName'] as String?,
      )).toList();

      final auth = ref.read(authProvider);
      int savedInvoiceId = editInvoiceId ?? 0;
      if (editInvoiceId != null) {
        // Update existing invoice
        await purchasesRepo.updateInvoice(UpdatePurchaseInvoiceParams(
          invoiceId: editInvoiceId,
          supplierId: partyId,
          warehouseId: warehouseId,
          items: purchaseItems,
          paid: paidAmount,
          paymentMethod: paymentMethod,
          notes: notes.isEmpty ? null : notes,
          supplierInvoiceNumber: supplierInvoiceNumber.isEmpty ? invoiceNumber : supplierInvoiceNumber,
          costCenterId: costCenterId,
          // Purchase-edit policy — the `purchases_edit` gate in the DAO is
          // evaluated against this id. Omitting it denied every edit.
          userId: auth.user?.id,
          // ح-1: the edit branch dropped the discount the same form collects,
          // so re-saving a discounted invoice restored its gross total.
          discount: discount,
        ));
      } else {
        // Create new invoice — returns the new invoice ID so we can auto-print.
        savedInvoiceId = await purchasesRepo.createInvoice(CreatePurchaseInvoiceParams(
          supplierId: partyId ?? 0,
          // محسومٌ بحارسِ رأسِ الدالة — لا اختراعَ لمخزنٍ هنا.
          warehouseId: resolvedWarehouseId!,
          items: purchaseItems,
          paid: paidAmount,
          paymentMethod: paymentMethod,
          notes: notes.isEmpty ? null : notes,
          supplierInvoiceNumber: supplierInvoiceNumber.isEmpty ? invoiceNumber : supplierInvoiceNumber,
          date: date,
          costCenterId: costCenterId,
          safeId: safeId,
          userId: auth.user?.id,
          createdByUsername: auth.user?.username,
          // ح-1: was collected by the form and silently dropped here.
          discount: discount,
        ));
      }

      // Auto-print A4 purchase invoice when the user clicked "حفظ وطباعة".
      // Mirrors the sales-invoice flow; POS path is unaffected.
      if (printAfterSave && savedInvoiceId > 0) {
        final printingService = ref.read(printingServiceProvider);
        await printingService.printPurchaseInvoiceA4(savedInvoiceId);
      }

      // Log Activity
      final activityLogRepo = ref.read(activityLogRepositoryProvider);
      await activityLogRepo.logActivity(
        userId: auth.user?.id,
        userName: auth.user?.displayName ?? 'Admin',
        action: editInvoiceId != null ? 'edit_purchase' : 'create_purchase',
        entityType: 'purchase_invoice',
        description: editInvoiceId != null
            ? tr('تعديل فاتورة مشتريات #{editInvoiceId}', {'editInvoiceId': editInvoiceId})
            : tr('إنشاء فاتورة مشتريات'),
        amount: total,
      );

      if (mounted) {
        AppToast.show(
          context,
          tr('تم الحفظ بنجاح'),
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('فشلت العملية: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }
}

