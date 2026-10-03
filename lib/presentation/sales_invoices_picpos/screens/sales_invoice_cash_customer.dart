// J3 — «عميل نقدي» في فاتورة المبيعات: تحميلُ الطرف النظاميّ ومسارات
// المناديب، و«حفظ كعميل دائم» (عميلٌ حقيقيٌّ على نهاية مسار المندوب،
// حدُّ ائتمانه صفر) تنتقل إليه الفاتورةُ قبل الحفظ.
part of 'sales_invoices_picpos_screen.dart';

extension SalesInvoiceCashCustomerExt on _SalesInvoicesPicposScreenState {
  Future<({int? cashCustomerId, List<DistributionRoute> routes})>
      _loadCashCustomerContext() async {
    final db = ref.read(databaseProvider);
    try {
      final cashId = await db.systemPartyId(kSystemRoleCashCustomer);
      final routes = cashId == null
          ? const <DistributionRoute>[]
          : [
              for (final r in await db.listDistributionRoutes())
                if (r.isActive) r,
            ];
      return (cashCustomerId: cashId, routes: routes);
    } catch (e) {
      unawaited(DiagnosticLogger.log(
          'SALES-FORM', 'تعذّر تحميل العميل النقدي/المسارات: $e'));
      return (cashCustomerId: null, routes: const <DistributionRoute>[]);
    }
  }

  Future<PicPosPartyOption?> _createPermanentCustomer(
    BuildContext context, {
    required String name,
    String? phone,
    required List<DistributionRoute> routes,
  }) async {
    final input = await showPermanentCustomerDialog(context,
        name: name, phone: phone, routes: routes);
    if (input == null || !context.mounted) return null;
    final db = ProviderScope.containerOf(context, listen: false)
        .read(databaseProvider);
    try {
      final id = await db.createPermanentCustomerFromCashSale(
        name: input.name,
        phone: input.phone,
        address: input.address,
        routeId: input.routeId,
      );
      if (context.mounted) {
        AppToast.show(context, tr('تم إنشاء العميل الدائم «{p0}»', {'p0': input.name}),
            type: ToastType.success);
      }
      return PicPosPartyOption(id: id, name: input.name, meta: input.phone ?? '');
    } catch (e, st) {
      if (context.mounted) AppErrorHandler.handle(context, e, st);
      return null;
    }
  }
}
