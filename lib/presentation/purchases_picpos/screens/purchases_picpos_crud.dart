part of 'purchases_picpos_screen.dart';

// نسخة حرفية من lib/presentation/screens/purchase_invoices/purchase_invoice_crud.dart
// (mixin `_PurchaseInvoiceCrudMixin` في شاشة UralCash). الملف الأصل `part of`
// خاص فما ينفعش يتعمله import، فبينتقل بنسخ حرفي هنا — نفس الأسلوب المعتمد في
// picpos_pos_operations.dart. التغيير الوحيد: السطر الأول واسم الـ mixin/قيد
// `on`. جسم الدوال بدون أي تعديل.
//
// مصيدة النسخ (موثّقة): أي باج منطقي يُصلَّح هنا لاحقاً، افحص أصله في
// purchase_invoice_crud.dart — يُصلَّح بكوميت منفصل + patch لـ UralCash.
mixin _PurchasesPicposCrud on ConsumerState<PurchasesPicposScreen> {
  /// Create a new purchase invoice or return
  void createNewInvoice() async {
    if (!mounted) return;
    // ⚠️ انحرافٌ مقصودٌ عن الأصل المنسوخ (`purchase_invoice_crud.dart`):
    // `purchases_create` لم يكن له إنفاذٌ محليٌّ إطلاقاً — لا على الزرّ ولا
    // على **F5** (`AppShortcuts(onNew: createNewInvoice)`)، وموضعُه الوحيد
    // `api_purchase_handler` وهو خلف رايةٍ مطفأةٍ افتراضياً ولا وجودَ له على
    // تنصيبةٍ مستقلّة. فالفحصُ هنا في القِمع ليغطّي المدخلَين.
    if (!await ensurePermission(
        ref, context, PermissionCodes.purchasesCreate,
        actionName: 'فاتورة مشتريات جديدة')) {
      return;
    }
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
              paymentMethod: paymentMethod,
              safeId: safeId,
              printAfterSave: printAfterSave,
            );
          },
        ),
      ),
    );
  }

  /// «فاتورة جديدة» على تصميم PicPos (‏2026-08-21).
  ///
  /// ⚠️ **ولا تلمس مسارَ المال**: تنتهي إلى `_handleSavePurchaseSimple`
  /// نفسِها التي ينتهي إليها [createNewInvoice] القديم، بنفس الوسائط. فما
  /// تبدّل هو العرضُ وحدَه.
  ///
  /// والقديمُ [createNewInvoice] يبقى موصولاً بـ«تعديل» ولم يُحذَف: النموذجُ
  /// الجديدُ للإنشاء فقط (اقرأ رأس `picpos_invoice_form.dart`).
  Future<void> createNewInvoicePicPos() async {
    if (!mounted) return;
    // نفسُ حارسِ [createNewInvoice] — يغطّي الزرَّ و**F5** معاً.
    if (!await ensurePermission(
        ref, context, PermissionCodes.purchasesCreate,
        actionName: 'فاتورة مشتريات جديدة')) {
      return;
    }
    if (!mounted) return;

    // ═══ 🔴 «الزرُّ لا يستجيب» — بلاغُ المالك على البناء المنشور ═══
    //
    // كانت خمسةُ `await` عاريةٍ تسبق فتحَ الحوار. وأيُّ واحدٍ منها يرمي أو
    // يتعلّق يجعل الزرَّ **ميّتاً بصمت**: `onPressed` يرجع `Future` فلا أحدَ
    // يمسك رميَه، ولا رسالةَ ولا دوّارة — نقرةٌ لا يتبعها شيء.
    //
    // ونظيرُ المبيعات **لا ينتظر أصلاً**: يقرأ `.value ?? []` من مزوِّداتٍ
    // يراقبها شريطُ الفلاتر. ولهذا يعمل ذاك ويموت هذا — وهو الفرقُ الوحيدُ
    // بينهما.
    //
    // ═══ 🔴 والسببُ المقيسُ من بلاغ المالك الثاني ═══
    //
    // الرسالةُ التي أظهرها `try/catch` قالتها بالحرف:
    //
    //     Bad state: The provider StreamProvider<List<CostCenter>> was
    //     disposed during loading state, yet no value could be emitted.
    //
    // `allCostCentersProvider` **`autoDispose`**، و`ref.read(p.future)` **لا
    // يُنشئ مستمعاً يُبقيه حيّاً**. فتُبنى نسختُه، ويبدأ البثُّ، وتُرمى
    // النسخةُ قبل أن يصل أوّلُ عنصر — فلا يكتمل المستقبَلُ أبداً.
    //
    // وقاعدةُ المالك بلا مراكزِ تكلفةٍ أصلاً (`costCenters=0` في سجلّ
    // المبيعات)، فالبثُّ يتأخّر لحظةً قبل أن يُصدر قائمةً فارغة — وتلك
    // اللحظةُ تكفي.
    //
    // فالعلاجُ **إبقاءُ المزوِّدات حيّةً طوالَ الانتظار** بـ`listenManual`،
    // وإغلاقُها في `finally` فلا تتسرّب. والمهلةُ و`try/catch` يبقيان: هما
    // ما حوّلا الصمتَ إلى رسالةٍ قادت إلى هذا السطر.
    final keepAlive = <ProviderSubscription<Object?>>[
      ref.listenManual(allWarehousesProvider, (_, _) {}),
      ref.listenManual(allCostCentersProvider, (_, _) {}),
      // ⚠️ **المئويُّ هو المقروء، فهو الذي يُبقى حيّاً.** وإبقاءُ الخامِ
      // وحدَه لا يكفي: `posDefaultTaxPercentProvider` نسخةٌ مستقلّةٌ يُرمى
      // قبل أن يكتمل مستقبَلُه — وهو عينُ التعلّق الموصوف أعلاه. وإبقاؤه
      // يُبقي الخامَ تبعاً لأنّه يراقبه.
      ref.listenManual(posDefaultTaxPercentProvider, (_, _) {}),
    ];
    try {
      final controller = ref.read(purchaseInvoicesControllerProvider.notifier);
      // ⚠️ `getSuppliers()` تنتظر **أوّلَ بثٍّ** (`watchSuppliers().first`).
      // وبثٌّ لا يُصدر شيئاً يجعل هذا الانتظارَ أبديّاً — وهو أرجحُ مواضع
      // التعلّق في هذا المسار.
      final suppliers =
          await controller.getSuppliers().timeout(const Duration(seconds: 10));
      final products =
          await controller.getProducts().timeout(const Duration(seconds: 10));

      // ⚠️ `allCostCentersProvider` مزوِّدُ بثٍّ **`autoDispose`**، و
      // `ref.read(p.future)` عليه لا يُبقيه حيّاً بنفسِه. فإن لم يكن أحدٌ
      // يراقبه في تلك اللحظة، تُرمى نسختُه فور القراءة ولا يكتمل المستقبَلُ
      // أبداً. والمهلةُ تحوّل ذلك من تعلّقٍ صامتٍ إلى رسالةٍ تُقرأ.
      final warehouses = await ref
          .read(allWarehousesProvider.future)
          .timeout(const Duration(seconds: 10));
      final costCenters = await ref
          .read(allCostCentersProvider.future)
          .timeout(const Duration(seconds: 10));
      // النسبةُ من الإعداد لا رقمٌ مطبوع — «١٤٪» في التصميم قيمةُ عيّنة.
      //
      // ⚠️ **مئويّةٌ لا كسر**: `PicPosInvoiceForm` تعرضها بـ
      // `toStringAsFixed(0)` وتستعملها احتياطاً لصنفٍ بلا نسبةٍ خاصّةٍ بجوار
      // `Products.taxRate` المئويّة. وكان يُمرَّر هنا الكسرُ (‏٠٫١٦) فتعرض
      // الشريحةُ «ضريبة 0%» ويُحسَب السطرُ بـ٠٫١٦٪ بدل ١٦٪.
      final taxRate = await ref
          .read(posDefaultTaxPercentProvider.future)
          .timeout(const Duration(seconds: 10));

      // أوامرُ الشراء **المفتوحة** — «ربط أمر شراء» (قرارُ المالك 2026-09-18).
      //
      // ⚠️ **ولا تُحمَّل خارجَ نطاقِها**: `ScreenId.purchaseOrders` في
      // `ScreenRegistry.unified` وحدَه، ففي بقيّة الأنماط لا وجودَ للمستند
      // ولا لشاشته. والقائمةُ الفارغةُ تُخفي الشريطَ كلَّه.
      //
      // 🔴 **والمرشِّحُ `convertedToInvoiceId` لا الحالة**: الرابطُ هو
      // **واقعةُ** الاستهلاك، والحالةُ وسمٌ يُبدَّل بلا أن يقع شيء. وعرضُ
      // أمرٍ مستهلَكٍ يعِد المستخدمَ بسحبٍ سيرفضه المحرّكُ عند الحفظ.
      final openOrders = <PicPosPurchaseOrderOption>[];
      if (AppConfig.allowedScreenIds.contains(ScreenId.purchaseOrders)) {
        try {
          final poRepo = ref.read(purchaseOrdersRepositoryProvider);
          final rows = await poRepo
              .watchPurchaseOrders()
              .first
              .timeout(const Duration(seconds: 10));
          final byId = {for (final s in suppliers) s.id: s.name};
          for (final o in rows) {
            if (o.convertedToInvoiceId != null) continue;
            if (o.status == 'cancelled') continue;
            openOrders.add(PicPosPurchaseOrderOption(
              id: o.id,
              orderNumber: o.orderNumber,
              supplierId: o.supplierId,
              supplierName: byId[o.supplierId] ?? 'مورد #${o.supplierId}',
              orderDate: o.orderDate,
              total: o.total,
            ));
          }
        } catch (_) {
          // الفاتورةُ تعمل بلا ربط — ولا يُحجَب إنشاؤها لأجل قائمةٍ إضافيّة.
        }
      }
      if (!mounted) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'PicPos Purchase Invoice',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, anim1, anim2) => Scaffold(
        body: PicPosInvoiceForm(
          kind: PicPosInvoiceKind.purchase,
          parties: [
            for (final s in suppliers)
              PicPosPartyOption(
                id: s.id,
                name: s.name,
                meta: s.phone ?? '',
                // مصدرُ «تاريخ الاستحقاق» المعروض — وهو عينُ ما يقرؤه
                // `PartyDao.resolveInvoiceDueDate` وقتَ الحفظ.
                paymentTermsDays: s.paymentTermsDays,
              ),
          ],
          products: [
            for (final p in products)
              PicPosProductOption(
                id: p.id,
                name: p.name,
                sub: p.barcode ?? '',
                salePrice: p.salePrice,
                costPrice: p.costPrice,
                categoryId: p.categoryId,
                taxRate: p.taxRate,
                barcode: p.barcode ?? '',
              ),
          ],
          warehouses: [
            for (final w in warehouses)
              PicPosNamedOption(id: w.id, name: w.name),
          ],
          costCenters: [
            for (final c in costCenters)
              PicPosNamedOption(id: c.id, name: c.name),
          ],
          systemTaxRate: taxRate,
          // الرقمُ يولّده الخادمُ تسلسليّاً عند الحفظ، فلا يُدَّعى رقمٌ
          // بعينه قبل أن يُحجَز.
          invoiceNumberPreview: 'يُولَّد تلقائياً',
          initialWarehouseId:
              warehouses.length == 1 ? warehouses.first.id : null,
          onCancel: () => Navigator.pop(dialogContext),
          purchaseOrders: openOrders,
          // سحبُ البنود عند الاختيار وحدَه — الأمرُ الواحدُ قد يحمل عشرات،
          // والقائمةُ تُحمَّل لتُعرَض.
          //
          // ⚠️ **والكمّيّةُ كمّيّةُ الأمر لا المتبقّي منه**: `receivedQuantity`
          // يتحرّك باستلامٍ جزئيٍّ لا يوجد له مسارٌ اليوم، والأمرُ يُستهلَك
          // كاملاً بهذه الفاتورة — فسحبُ «المتبقّي» كان سيعِد باستلامٍ
          // جزئيٍّ لا يقع.
          onPullPurchaseOrder: (orderId) async {
            final poRepo = ref.read(purchaseOrdersRepositoryProvider);
            final items = await poRepo.getPurchaseOrderItems(orderId);
            final byId = {for (final p in products) p.id: p};
            return [
              for (final it in items)
                if (byId[it.productId] != null)
                  PicPosInvoiceLine(
                    productId: it.productId,
                    productName: byId[it.productId]!.name,
                    categoryId: byId[it.productId]!.categoryId,
                    quantity: it.quantity,
                    unitPrice: it.unitCost,
                    discount: it.discount,
                    taxRate: it.taxRate,
                    // الضريبةُ مشعلةٌ متى حمل السطرُ مبلغاً فعليّاً — وسطرٌ
                    // معفىً في الأمر يبقى معفىً في الفاتورة.
                    taxEnabled: it.taxAmount > 0,
                  ),
            ];
          },
          onSave: ({
            required int? partyId,
            required String supplierInvoiceNumber,
            required DateTime date,
            required double subtotal,
            required double discount,
            required double tax,
            required double net,
            required double paid,
            required String notes,
            required List<Map<String, dynamic>> items,
            required int? warehouseId,
            required int? costCenterId,
            required String paymentMethod,
            required bool printAfterSave,
            required int? sourceOrderId,
          }) async {
            await _handleSavePurchaseSimple(
              partyId: partyId,
              // فارغٌ ⇒ يولّد الخادمُ `PINV-N` — نفسُ سلوك النموذج القديم.
              invoiceNumber: '',
              supplierInvoiceNumber: supplierInvoiceNumber,
              date: date,
              total: subtotal,
              discount: discount,
              tax: tax,
              netAmount: net,
              paidAmount: paid,
              notes: notes,
              items: items,
              warehouseId: warehouseId,
              costCenterId: costCenterId,
              paymentMethod: paymentMethod,
              safeId: null,
              printAfterSave: printAfterSave,
              // 🔴 يصل المحرّكَ فيستهلك الأمرَ في **نفس معاملة الفاتورة**.
              // ولو سقط هنا لبقي الأمرُ مفتوحاً بعد أن دخلت بضاعتُه.
              sourceOrderId: sourceOrderId,
            );
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          // 🔴 **لا فعلَ مسوّدةٍ هنا** — قرارُ المالك 2026-09-19: خطوةٌ
          // واحدةٌ كما في مردود المشتريات.
          //
          // كان الزرُّ ينادي هذه الدالّةَ بـ`isDraft: true`، والمعاملُ
          // **مُعلَنٌ في ثلاث دوالَّ ولا يُقرأ في موضعٍ واحد**. فالمسوّدةُ
          // كانت فاتورةً آجلةً مرحَّلةً كاملةً: مخزونٌ يتحرّك وقيدٌ يُرحَّل
          // وذمّةُ مورّدٍ تُقيَّد — وعلى **أوّل مخزنٍ في النطاق** لأنّ
          // النداءَ كان يمرّر `warehouseId: null`، لا على ما اختاره
          // المستخدمُ في النموذج.
        ),
      ),
      );
    } catch (e) {
      // لا يبقى مسارٌ يفشل بلا أن يقول — راجع تعليقَ رأسِ الدالّة.
      if (mounted) {
        AppToast.show(
          context,
          'تعذّر فتحُ فاتورة المشتريات: $e',
          type: ToastType.error,
        );
      }
    } finally {
      for (final s in keepAlive) {
        s.close();
      }
    }
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
    required String paymentMethod,
    int? sourceOrderId,
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
        // خصمُ الصنف — يكتبه عمودُ «الخصم» في النموذج
        // (`PicPosInvoiceLine.toSaveMap`). وغيابُ المفتاح يعني نمطاً لا
        // يدعمه، فصفرٌ هو الصواب لا خطأ.
        discount: (item['discount'] as num?)?.toDouble() ?? 0,
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
          sourceOrderId: sourceOrderId,
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
            ? 'تعديل فاتورة مشتريات #$editInvoiceId'
            : 'إنشاء فاتورة مشتريات',
        amount: total,
      );

      if (mounted) {
        AppToast.show(
          context,
          'تم الحفظ بنجاح',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشلت العملية: $e', type: ToastType.error);
      }
    }
  }
}
