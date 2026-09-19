// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: library_private_types_in_public_api
// منسوخ من lib/presentation/screens/widgets/sales_invoices/sales_invoice_dialogs.dart
// (extension SalesInvoiceDialogsExt on _SalesInvoicesScreenState في شاشة UralCash).
// التغيير الوحيد: السطر الأول واسم امتداد الحالة (_SalesInvoicesPicposScreenState).
// جسم الدوال بدون أي تعديل — أي إصلاح منطقي يتصلّح في المصدر أولاً ثم patch
// (مصيدة النسخ §٥.٨).
part of 'sales_invoices_picpos_screen.dart';

extension SalesInvoiceDialogsExt on _SalesInvoicesPicposScreenState {
  // DETAILS DIALOG
  // ══════════════════════════════════════════════════════

  /// غلافٌ يُظهر الإخفاقَ بدل أن يبتلعه — patch لنظيره في شاشة UralCash.
  ///
  /// بلاغٌ ميدانيّ (2026-08-20) على **هذه** الشاشة: «زرُّ عرض التفاصيل لا
  /// يفتح شيئاً». والجسمُ كان `void … async` — صيغةٌ **لا يُمسَك استثناؤها
  /// في أيّ موضع**: يُرمى في حلقة الأحداث فلا حوارَ يُفتح ولا رسالةَ تظهر،
  /// فيبدو الزرُّ معطوباً وهو يعمل. وقبل `showDialog` انتظاران يجلبان من
  /// القاعدة، وأيُّ إخفاقٍ فيهما كان يختفي بلا أثر.
  ///
  /// ومقيسٌ لا مفترَض: اختبارُ
  /// `test/widget/app_data_table_action_button_tap_test.dart` يُثبت أن
  /// النقرةَ تصل إلى الزرّ ولا تتسرّب إلى تحديد الصفّ — فالعطبُ هنا لا في
  /// الإيماءات.
  void _showInvoiceDetails(InvoiceEntity invoice) async {
    try {
      await _showInvoiceDetailsInner(invoice);
    } catch (e, st) {
      debugPrint('[SalesDetails] تعذّر فتح تفاصيل ${invoice.invoiceNumber}: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 8),
          content: Text('تعذّر فتح تفاصيل الفاتورة: $e'),
        ),
      );
    }
  }

  Future<void> _showInvoiceDetailsInner(InvoiceEntity invoice) async {
    final controller = ref.read(salesInvoicesControllerProvider.notifier);
    final items = await controller.getInvoiceItems(invoice.id!);
    final customer = invoice.partyId != null
        ? await controller.getCustomerById(invoice.partyId!)
        : null;
    final customerName = customer?.name ?? 'عميل نقدي';

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.receipt, color: AppColors.info),
              const SizedBox(width: 8),
              Text('فاتورة بيع #${invoice.invoiceNumber}'),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // حقائق الفاتورة كشبكة مدمجة بدل ١٢ سطر «تسمية … قيمة»
                  // مرصوصين فوق بعض — الأرقام المالية بقت تحت في كتلة
                  // مجاميع لوحدها، فالعين بتفرّق بين السياق والفلوس.
                  Builder(builder: (_) {
                    final state = ref.read(salesInvoicesControllerProvider);
                    final whId = invoice.warehouseId;
                    final whName = whId != null ? state.warehouseNames[whId] : null;
                    // Prefer direct branchId on the invoice (L3) with
                    // backward-compat fallback to warehouse → branch lookup.
                    final brId = invoice.branchId ??
                        (whId != null ? state.warehouseBranchId[whId] : null);
                    final brName = brId != null ? state.branchNames[brId] : null;
                    final ccName = invoice.costCenterId != null
                        ? state.costCenterNames[invoice.costCenterId]
                        : null;
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.picposField,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Wrap(
                        spacing: 26,
                        runSpacing: 10,
                        children: [
                          _metaField('العميل', customerName),
                          _metaField(
                            'التاريخ',
                            (invoice.createdAt ?? invoice.invoiceDate)
                                .toString()
                                .substring(0, 16),
                          ),
                          _metaField('الحالة', invoice.status.name),
                          if (brName != null) _metaField('الفرع', brName),
                          if (whName != null) _metaField('المخزن', whName),
                          if (ccName != null)
                            _metaField('مركز التكلفة', ccName),
                          if (invoice.originClientId != null &&
                              invoice.originClientId!.isNotEmpty)
                            _metaField('الجهاز', invoice.originClientId!),
                        ],
                      ),
                    );
                  }),
                  if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'ملاحظات: ${invoice.notes}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                  const Divider(height: 24),

                  // Margin Analysis
                  Consumer(
                    builder: (context, ref, child) {
                      final analysisStream = ref.watch(invoiceProfitAnalysisStreamProvider(invoice.id!));
                      return analysisStream.when(
                        data: (InvoiceProfitAnalysis? analysis) {
                          if (analysis == null) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ProfitMarginAnalysisWidget(analysis: analysis),
                              const Divider(height: 24),
                            ],
                          );
                        },
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (_, _) => const SizedBox.shrink(),
                      );
                    },
                  ),

                  const Text(
                    'الأصناف:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    const Text(
                      'لا توجد أصناف',
                      style: TextStyle(color: AppColors.textMuted),
                    )
                  else
                    DataTable(
                      columnSpacing: 20,
                      columns: const [
                        DataColumn(label: Text('الصنف')),
                        DataColumn(label: Text('الوحدة')),
                        DataColumn(label: Text('الكمية')),
                        DataColumn(label: Text('السعر')),
                        DataColumn(label: Text('الإجمالي')),
                      ],
                      rows: items
                          .map(
                            (item) => DataRow(
                              cells: [
                                DataCell(Text(item.displayName)),
                                DataCell(Text(item.item.unitName ?? 'قطعة')),
                                DataCell(
                                  Text(item.item.quantity.toStringAsFixed(AppConstants.decimalPlaces)),
                                ),
                                DataCell(
                                  Text(item.item.unitPrice.toStringAsFixed(AppConstants.decimalPlaces)),
                                ),
                                DataCell(
                                  Text(item.item.total.toStringAsFixed(AppConstants.decimalPlaces)),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 16),
                  // كتلة المجاميع محاذاة لآخر الصف ومحدودة العرض — الأرقام
                  // تحت بعضها تتقارن بالعين، بخلاف الأسطر العريضة اللي كانت
                  // بتباعد التسمية عن القيمة لعرض الديالوج كله.
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Column(
                        children: [
                          _totalRow('المجموع الفرعي', invoice.subtotal),
                          if (invoice.discountAmount != 0)
                            _totalRow('الخصم', invoice.discountAmount,
                                color: AppColors.warning),
                          if (invoice.taxAmount != 0)
                            _totalRow('الضريبة', invoice.taxAmount),
                          const Divider(height: 18),
                          _totalRow('الإجمالي', invoice.total,
                              emphasize: true),
                          _totalRow('المدفوع', invoice.paid,
                              color: AppColors.success),
                          _totalRow(
                            'المتبقي',
                            invoice.total - invoice.paid,
                            color: (invoice.total - invoice.paid) > 0.001
                                ? AppColors.error
                                : AppColors.success,
                            emphasize: (invoice.total - invoice.paid) > 0.001,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _printInvoice(invoice),
              icon: const Icon(PhosphorIconsBold.printer, size: 16),
              label: const Text('طباعة'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  /// حقيقة سياقية: تسمية صغيرة فوق القيمة. مصمّمة تترص في `Wrap`.
  Widget _metaField(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value,
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  /// سطر في كتلة المجاميع. القيم متنسّقة كعملة مش `toStringAsFixed` خام.
  Widget _totalRow(
    String label,
    double value, {
    Color? color,
    bool emphasize = false,
  }) {
    final style = TextStyle(
      fontSize: emphasize ? 15 : 13,
      fontWeight: emphasize ? FontWeight.bold : FontWeight.w500,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(NumberUtils.formatCurrency(value), style: style),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  // PRINT INVOICE
  // ══════════════════════════════════════════════════════

  /// إرسالُ الفاتورة على واتساب — البندُ الثاني (2026-09-12).
  ///
  /// ⚠️ **ورقمُ العميل يُقرأ من صفِّه لا من الفاتورة**: لا عمودَ هاتفٍ على
  /// الفاتورة، و«عميلٌ نقديٌّ» بلا صفٍّ لا رقمَ له — فيُقال ذلك صراحةً بدل
  /// فتح حوارٍ برقمٍ فارغٍ يظنّه الموظّفُ عطباً.
  Future<void> _sendInvoiceWhatsApp(InvoiceEntity invoice) async {
    final db = ref.read(databaseProvider);
    final shopName = await db.getSettingValue('company_name') ?? '';

    Party? party;
    if (invoice.partyId case final id? when id > 0) {
      party = await (db.select(db.parties)..where((p) => p.id.equals(id)))
          .getSingleOrNull();
    }
    if (!mounted) return;

    if (party == null) {
      AppToast.show(context, 'الفاتورةُ بلا عميلٍ مسجَّل — لا رقمَ يُرسَل إليه');
      return;
    }

    await WhatsAppSendDialog.show(
      context,
      ref,
      title: 'إرسال الفاتورة',
      rawPhone: party.phone,
      message: composeInvoiceMessage(
        shopName: shopName,
        customerName: party.name,
        invoiceNumber: invoice.invoiceNumber,
        total: invoice.total,
        issuedAt: invoice.invoiceDate,
      ),
      actionLogLabel: 'فاتورة ${invoice.invoiceNumber}',
    );
  }

  void _printInvoice(InvoiceEntity invoice) async {
    try {
      // Use PrintingService.printReceipt — the same unified path as POS.
      // This ensures the user's custom thermal/receipt template is applied
      // (falls back to default layout if no template exists).
      final printingService = ref.read(printingServiceProvider);
      // §٤‑٣ — `printReceipt` لا ترمي أبداً، فكان الإخفاقُ يمرّ **صامتاً
      // تماماً**: لا رسالةَ نجاحٍ ولا خطأ، والمستخدمُ ينتظر ورقةً لن تخرج.
      final printed = await printingService.printReceipt(invoice.id!);
      if (!printed && mounted) {
        AppToast.show(context, 'تعذّرت الطباعة — تأكد من الطابعة',
            type: ToastType.error);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
      }
    }
  }

  // ══════════════════════════════════════════════════════
  // CREATE NEW INVOICE
  // ══════════════════════════════════════════════════════

  void _createNewInvoice({
    QuotationEntity? editQuotation,
    bool isConvert = false,
  }) async {
    // ⚠️ انحرافٌ مقصودٌ عن الأصل المنسوخ: `sales_create` لم يكن له إنفاذٌ
    // محليٌّ — لا على الزرّ ولا على **F5** — وموضعُه الوحيد
    // `api_sales_handler` خلف رايةٍ مطفأةٍ افتراضياً. والفحصُ في القِمع
    // يغطّي المدخلَين وتحويلَ عرض السعر معاً.
    if (!await ensurePermission(ref, context, PermissionCodes.salesCreate,
        actionName: 'فاتورة بيع جديدة')) {
      return;
    }
    if (!mounted) return;
    final controller = ref.read(salesInvoicesControllerProvider.notifier);

    unawaited(DiagnosticLogger.log('SPEC-090-DIALOG',
        '_createNewInvoice entered — '
        'editQuotation=${editQuotation?.id} isConvert=$isConvert'));

    // Show a modal progress spinner while we pre-load customers/products/
    // categories/warehouses. getCustomers() and getActiveWarehouses() are
    // Stream.first calls that can hang indefinitely on a slow client→server
    // link — without this indicator the user just sees the previous screen
    // frozen (the "convert draft" freeze the user reported).
    //
    // Spec 090 hotfix +160: await the spinner's mount via a Completer
    // before kicking off the preload. The previous +159 attempt captured
    // spinnerCtx in the builder but didn't WAIT for the builder to run.
    // On fast preload paths (e.g. a warm local cache resolving in <16ms,
    // before Flutter scheduled a frame), the futures completed before the
    // spinner widget was mounted: closeLoading saw ctx=null and skipped,
    // then the spinner finally mounted with no one to close it. After the
    // form popped on save, the orphan spinner was revealed and froze the
    // screen. Field-reproduced on +159 startup, log line
    // "closeLoading — spinner ctx null or unmounted (ctx=null)".
    final spinnerCtxCompleter = Completer<BuildContext>();
    final spinnerRouteFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        if (!spinnerCtxCompleter.isCompleted) {
          spinnerCtxCompleter.complete(ctx);
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
    // Yield control until the dialog's builder has actually executed.
    // Bounded with a small timeout so a Navigator that never schedules
    // the dialog (defensive — shouldn't happen) can't hang the caller.
    BuildContext? spinnerCtx;
    try {
      spinnerCtx = await spinnerCtxCompleter.future
          .timeout(const Duration(milliseconds: 500));
    } on TimeoutException {
      unawaited(DiagnosticLogger.log('SPEC-090-DIALOG',
          'spinner mount await TIMED OUT after 500ms — proceeding without spinner handle'));
    }
    if (!mounted) return;

    var loadingClosed = false;
    void closeLoading() {
      if (loadingClosed) return;
      loadingClosed = true;
      final ctx = spinnerCtx;
      if (ctx != null && ctx.mounted) {
        unawaited(DiagnosticLogger.log(
            'SPEC-090-DIALOG', 'closeLoading — popping preload spinner'));
        Navigator.of(ctx).pop();
      } else {
        // Fall back to popping the topmost route from the screen context
        // so we never leave an orphan spinner on screen. If ctx is null
        // here the spinner mount timed out — popping a route is the only
        // way to guarantee no stuck overlay.
        unawaited(DiagnosticLogger.log('SPEC-090-DIALOG',
            'closeLoading — spinner ctx unavailable (ctx=$ctx); falling back to root navigator pop'));
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    }
    // Silence: the dialog future may complete after this scope; we don't
    // need to await it ourselves but the variable suppresses the unused-future
    // lint and lets us log dismissal for diagnostics.
    unawaited(spinnerRouteFuture);

    final List<Party> customersList;
    final List<Product> products;
    final List<Category> categories;
    final List<dynamic> warehousesList;
    final List<CostCenter> costCentersList;
    try {
      final loadedCustomers = controller.getCustomers();
      final loadedProducts = controller.getProducts();
      final loadedCategories = controller.getCategories();
      final loadedWarehouses = controller.getActiveWarehouses();
      final loadedCostCenters =
          ref.read(accountingRepositoryProvider).getActiveCostCenters();
      await Future.wait([
        loadedCustomers,
        loadedProducts,
        loadedCategories,
        loadedWarehouses,
        loadedCostCenters,
      ]).timeout(const Duration(seconds: 15));
      customersList = await loadedCustomers;
      products = await loadedProducts;
      categories = await loadedCategories;
      warehousesList = await loadedWarehouses;
      costCentersList = await loadedCostCenters;
    } on TimeoutException {
      closeLoading();
      if (mounted) {
        AppToast.show(
          context,
          'انتهت مهلة تحميل البيانات — تأكد من الاتصال بالسيرفر',
          type: ToastType.error,
        );
      }
      return;
    } catch (e) {
      closeLoading();
      if (mounted) {
        AppToast.show(
          context,
          'فشل تحميل بيانات الفاتورة: $e',
          type: ToastType.error,
        );
      }
      return;
    }

    closeLoading();
    if (!mounted) return;

    // Spec 090: open the extracted SalesInvoiceForm via showGeneralDialog +
    // Scaffold (mirrors the working PurchaseInvoiceForm pattern). The
    // form drives its own state via setState (no StatefulBuilder), exposes
    // explicit Cancel handling (no PopScope), and delegates persistence
    // back to _saveQuotation / _saveInvoice — the same handlers as before,
    // which already call Navigator.pop on success.
    //
    // Spec 090 hotfix +159: yield one frame between popping the preload
    // spinner and pushing the form so the navigator's animation queue
    // doesn't end up with both routes overlapping. Field report on +158
    // showed the form popping correctly on Save but a stray loading
    // spinner remained visible — consistent with the preload spinner not
    // being fully removed before the form was pushed on top of it.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    // ⚠️ **عرفان متعاكسان من إعدادٍ واحد**: `SalesInvoiceForm` تأخذ النسبةَ
    // **كسريّةً** (تضربها في ١٠٠ عند العرض)، و`PicPosInvoiceForm` تأخذها
    // **مئويّةً** كما `Products.taxRate` التي تجاورها في
    // `p.taxRate > 0 ? p.taxRate : widget.systemTaxRate`. فيُقرأ كلٌّ
    // بمزوّده بدل ضربةٍ يدويّةٍ تُنسى في أحد الفرعين.
    //
    // وكانت `ref.read(p).value` **قراءةً باردة**: `FutureProvider` يرجع
    // `null` قبل اكتمال مستقبَله، فتسقط إلى صفرٍ — أي فاتورةٌ بلا ضريبةٍ
    // إطلاقاً، صامتةً.
    //
    // ⚠️ **و`.future` وحدَها لا تكفي**: في Riverpod 3 كلُّ مزوّدٍ
    // `autoDispose` افتراضاً، و`ref.read(p.future)` **لا يُنشئ مستمعاً**
    // يُبقيه حيّاً — فتُرمى النسخةُ قبل أن يكتمل المستقبَل ولا يعود أبداً.
    // وهو عينُ التعلّق الموصوف في `purchases_picpos_crud`، فيُبقى حيّاً
    // ويُغلَق في `finally`.
    //
    // والإخفاقُ يسقط إلى الافتراض لا إلى صفر: حوارٌ لا يُفتح لأجل إعدادٍ
    // أسوأُ من نسبةٍ افتراضيّة، وصفرٌ صامتٌ أسوأُ من الاثنين.
    final keepTaxAlive =
        ref.listenManual(posDefaultTaxPercentProvider, (_, _) {});
    double systemTaxPercent;
    try {
      systemTaxPercent = await ref
          .read(posDefaultTaxPercentProvider.future)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      systemTaxPercent = kPosDefaultTaxPercentFallback;
      unawaited(DiagnosticLogger.log('SALES-FORM',
          'تعذّرت قراءةُ نسبة الضريبة — سقوطٌ إلى $systemTaxPercent٪ ($e)'));
    } finally {
      keepTaxAlive.close();
    }
    // `SalesInvoiceForm` كسريّةُ العقد — تُشتقّ من المئويّة فلا قراءةَ ثانية.
    final systemTaxRate = systemTaxPercent / 100;
    final activeWarehouses =
        warehousesList.whereType<WarehouseData>().toList();

    // Spec 103: in client mode restrict warehouses to the current branch so
    // the saved invoice's warehouseId resolves to the correct branchId and
    // appears in the branch's invoice list. القاعدةُ نفسُها في
    // `narrowWarehousesToClientBranch` — كانت منسوخةً هنا وفي التوأم الكامل،
    // وبقيت نافذةُ فاتورة المشتريات بلا حصر.
    // أسماءُ الفروع — لحقل «الفرع» المقفول على فرع المخزن.
    //
    // ⚠️ **يُقرأ من القاعدة لا من مزوِّدٍ بارد**: `allBranchesProvider` مجرىً
    //    `autoDispose`، و`.value` عليه قبل أن يبثّ تُرجع `null` فيبدو كلُّ
    //    مخزنٍ بلا فرع. وهذا المسارُ غيرُ متزامنٍ أصلاً فلا يدفع ثمناً.
    final branchNames = <int, String>{
      for (final b in await ref.read(databaseProvider).getBranches())
        b.id: b.name,
    };

    List<WarehouseData> filteredWarehouses = activeWarehouses;
    if (SyncInterceptor.isClientMode) {
      final prefs = await SharedPreferences.getInstance();
      filteredWarehouses = narrowWarehousesToClientBranch<WarehouseData>(
        warehouses: activeWarehouses,
        clientBranchId: prefs.getInt('client_branch_id'),
        branchIdOf: (w) => w.branchId,
      );
    }

    unawaited(DiagnosticLogger.log('SPEC-103-DIALOG',
        '_createNewInvoice preload done — '
        'costCenters=${costCentersList.length} '
        'warehousesAll=${activeWarehouses.length} '
        'warehousesFiltered=${filteredWarehouses.length} '
        'isClientMode=${SyncInterceptor.isClientMode}'));
    unawaited(DiagnosticLogger.log('SPEC-090-DIALOG',
        'about to showGeneralDialog — customers=${customersList.length} '
        'products=${products.length} categories=${categories.length} '
        'warehouses=${filteredWarehouses.length}'));

    final dialogFuture = showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Sales Invoice',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, _) => Scaffold(
        body: editQuotation != null
            ? SalesInvoiceForm(
          customers: customersList,
          initialProducts: products,
          categories: categories,
          warehouses: filteredWarehouses,
          costCenters: costCentersList,
          systemTaxRate: systemTaxRate,
          editQuotation: editQuotation,
          isConvert: isConvert,
          onSaveQuotation: ({
            required BuildContext dialogContext,
            required int? existingId,
            required String? existingNumber,
            required int? customerId,
            required String notes,
            required List<Map<String, dynamic>> invoiceItems,
            required double subtotal,
            required double discount,
            required double tax,
            required double total,
          }) async {
            await _saveQuotation(
              context: dialogContext,
              existingId: existingId,
              existingNumber: existingNumber,
              customerId: customerId,
              notes: notes,
              invoiceItems: invoiceItems,
              subtotal: subtotal,
              discount: discount,
              tax: tax,
              total: total,
            );
          },
          onSaveInvoice: ({
            required BuildContext dialogContext,
            required int? customerId,
            required String paymentMethod,
            required String notes,
            required List<Map<String, dynamic>> invoiceItems,
            required double subtotal,
            required double discount,
            required double tax,
            required double total,
            required double paid,
            required bool isReturnMode,
            required bool printAfterSave,
            required bool taxEnabled,
            int? convertingQuotationId,
            required List<Product> products,
            int? warehouseId,
            int? costCenterId,
          }) async {
            await _saveInvoice(
              context: dialogContext,
              customerId: customerId,
              paymentMethod: paymentMethod,
              notes: notes,
              invoiceItems: invoiceItems,
              subtotal: subtotal,
              discount: discount,
              tax: tax,
              total: total,
              paid: paid,
              isReturnMode: isReturnMode,
              printAfterSave: printAfterSave,
              taxEnabled: taxEnabled,
              convertingQuotationId: convertingQuotationId,
              products: products,
              warehouseId: warehouseId,
              costCenterId: costCenterId,
            );
          },
            )
            : _buildPicPosNewInvoice(
                ctx,
                customers: customersList,
                rawProducts: products,
                warehouses: filteredWarehouses,
                branchNames: branchNames,
                costCenters: costCentersList,
                systemTaxPercent: systemTaxPercent,
              ),
      ),
    );

    unawaited(dialogFuture.then((_) {
      unawaited(DiagnosticLogger.log('SPEC-090-DIALOG',
          'showGeneralDialog Future completed — sales-invoice form route popped'));
    }));
  }

  /// شاشةُ «فاتورة جديدة» على تصميم PicPos — للإنشاء وحدَه.
  ///
  /// ⚠️ **ولا تلمس مسارَ المال**: تنتهي إلى `_saveInvoice` و`_saveQuotation`
  /// نفسِهما بنفس الوسائط. وما تبدّل هو العرضُ وحدَه.
  ///
  /// و«حفظ كمسودة» هنا **عرضُ سعر** لا مسودّةُ فاتورة (قرارُ المالك
  /// 2026-08-21): يُحفَظ فيظهر في تبويب «عروض الأسعار»، فيُعدَّل لاحقاً أو
  /// يُحوَّل إلى فاتورة. والمسارُ قائمٌ بالكامل فلا سطرَ جديدٌ في أيّ عقد.
  Widget _buildPicPosNewInvoice(
    BuildContext ctx, {
    required List<Party> customers,
    required List<Product> rawProducts,
    required List<WarehouseData> warehouses,
    required Map<int, String> branchNames,
    required List<CostCenter> costCenters,
    /// **مئويّةٌ** (‏١٦) لا كسر (‏٠٫١٦) — انظر [posDefaultTaxPercentProvider].
    required double systemTaxPercent,
  }) {
    return PicPosInvoiceForm(
      kind: PicPosInvoiceKind.sales,
      parties: [
        for (final c in customers)
          PicPosPartyOption(
            id: c.id,
            name: c.name,
            meta: c.phone ?? '',
            // مصدرُ «تاريخ الاستحقاق» المعروض. وبدونه تقول الشاشةُ
            // «بلا مهلة متفقة» لعميلٍ له مهلةٌ فعلاً — والمحرّكُ
            // يختم الاستحقاقَ رغم ذلك.
            paymentTermsDays: c.paymentTermsDays,
          ),
      ],
      products: [
        for (final p in rawProducts)
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
          PicPosWarehouseOption(
            id: w.id,
            name: w.name,
            // مخزنٌ عامٌّ (`branch_id = NULL`) يُختَم على فاتورته فرعٌ فارغٌ
            // فتسقط من كلّ تقريرٍ مرشَّحٍ بفرع — والحقلُ يقولها قبل الحفظ.
            branchName: w.branchId == null ? null : branchNames[w.branchId],
          ),
      ],
      costCenters: [
        for (final c in costCenters)
          PicPosNamedOption(id: c.id, name: c.name),
      ],
      systemTaxRate: systemTaxPercent,
      invoiceNumberPreview: 'يُولَّد تلقائياً',
      userName: ref.read(authProvider).user?.displayName ?? '',
      initialWarehouseId: warehouses.length == 1 ? warehouses.first.id : null,
      // الأرصدةُ الحقيقيّةُ من `Products.currentStock` — فتنبيهُ الكفاية
      // يقول ما قِيس لا ما يُظنّ. ولولاها لَما ظهر التنبيهُ إطلاقاً.
      availableStock: {for (final p in rawProducts) p.id: p.currentStock},
      onCancel: () => Navigator.pop(ctx),
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
        // أوامرُ الشراء لا تخصّ المبيعات — والنموذجُ لا يعرضها في هذا النمط
        // أصلاً (`_canLinkPurchaseOrder`)، فتصل `null` دائماً.
        required int? sourceOrderId,
      }) async {
        await _saveInvoice(
          context: ctx,
          customerId: partyId,
          paymentMethod: paymentMethod,
          notes: notes,
          invoiceItems: items,
          subtotal: subtotal,
          discount: discount,
          tax: tax,
          total: net,
          paid: paid,
          isReturnMode: false,
          printAfterSave: printAfterSave,
          // الضريبةُ مفعَّلةٌ على مستوى السطر في هذه الشاشة، والمجموعُ
          // محسوبٌ منها. فالرايةُ صادقةٌ متى وُجدت ضريبةٌ فعليّة.
          taxEnabled: tax > 0,
          convertingQuotationId: null,
          products: rawProducts,
          warehouseId: warehouseId,
          costCenterId: costCenterId,
        );
      },
      // 🔴 **معاينةُ A4 قبل الحفظ** — قرارُ المالك على تصميم `12.02.29`.
      //
      //    والورقةُ **بلا رقمٍ وموسومةٌ «غير محفوظة»**: الرقمُ يُولَّد داخلَ
      //    معاملة الحفظ (‏Spec 066)، فتخمينُه يُخرج ورقةً تبدو مستنداً
      //    ضريبيّاً برقمٍ قد يذهب لفاتورة عميلٍ آخر. والقاعدةُ في
      //    `previewSalesInvoiceA4` لا هنا — فلا تُنسَخ في كلّ منادٍ.
      onPreviewA4: ({
        required int? partyId,
        required DateTime date,
        required List<Map<String, dynamic>> items,
        required double subtotal,
        required double discount,
        required double tax,
        required double net,
        required double paid,
        required String notes,
      }) async {
        final customer =
            customers.where((c) => c.id == partyId).firstOrNull;
        final ok = await ref.read(printingServiceProvider).previewSalesInvoiceA4(
              date: date,
              customerName: customer?.name,
              items: [
                for (final it in items)
                  print_models.InvoiceItem(
                    name: (it['productName'] as String?) ?? '',
                    quantity: (it['quantity'] as num?)?.toDouble() ?? 0,
                    price: (it['unitPrice'] as num?)?.toDouble() ?? 0,
                    // إجماليُّ السطر كما يعرضه الجدولُ — لا حسابٌ ثانٍ
                    // يعطي ورقةً تخالف الشاشة.
                    total: (it['lineTotal'] as num?)?.toDouble() ??
                        (((it['quantity'] as num?)?.toDouble() ?? 0) *
                            ((it['unitPrice'] as num?)?.toDouble() ?? 0)),
                  ),
              ],
              subtotal: subtotal,
              discount: discount,
              tax: tax,
              total: net,
              paid: paid,
              notes: notes,
            );
        if (!ok && ctx.mounted) {
          AppToast.show(ctx, 'تعذّرت معاينة الفاتورة',
              type: ToastType.warning);
        }
      },
      onSaveDraft: ({
        required int? partyId,
        required String notes,
        required List<Map<String, dynamic>> items,
        required double subtotal,
        required double discount,
        required double tax,
        required double net,
      }) async {
        await _saveQuotation(
          context: ctx,
          existingId: null,
          existingNumber: null,
          customerId: partyId,
          notes: notes,
          invoiceItems: items,
          subtotal: subtotal,
          discount: discount,
          tax: tax,
          total: net,
        );
      },
    );
  }

  // ======================================================
  // SAVE, EDIT & DELETE -- See sales_invoice_save_edit.dart
  // ======================================================
}
