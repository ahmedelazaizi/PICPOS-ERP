part of 'picpos_pos_screen.dart';

/// مُحدِّدُ الفاتورة لِـ«مرتجع سريع» — يسرد فواتير قابلةً للإرجاع (‏نفسُ
/// استبعاد `returnsRepository.getInvoicesForReturn`: مرحّلةٌ، غيرُ ملغاة،
/// غيرُ مرتجعةٍ بالكامل سلفاً) بلا سقفٍ زمنيّ — قرارُ المالك 2026-08-16
/// نفسُه المتَّبَع في شاشة «مرتجعات المبيعات» المستقلّة
/// (‏`sales_returns_picpos_logic.dart`): الإرجاعُ جائزٌ بعد فترةٍ، وسقفُ
/// أيامٍ كان يُخفي فاتورةً أقدمَ منه.
///
/// ويستبعد فواتيرَ التوصيل (‏`deliveryStatus` غيرُ فارغ) — I1، جولةُ إصلاح
/// ١: `getInvoicesForReturn` نفسُها لا تفلترها، والشاشةُ المستقلّةُ
/// (‏`sales_return_provider.selectInvoice`) ترفضها صراحةً («لا يمكن إرجاع
/// فواتير التوصيل»)؛ فبلا هذا الفلتر كان مسارُ «مرتجع سريع» يفتح ما تقفله
/// الشاشةُ المستقلّةُ عمداً.
///
/// يرجع الفاتورةَ المختارةَ عبر `Navigator.pop(context, invoice)`، أو
/// `null` عند الإلغاء.
class _QuickReturnInvoicePickerDialog extends ConsumerStatefulWidget {
  const _QuickReturnInvoicePickerDialog();

  @override
  ConsumerState<_QuickReturnInvoicePickerDialog> createState() =>
      _QuickReturnInvoicePickerDialogState();
}

class _QuickReturnInvoicePickerDialogState
    extends ConsumerState<_QuickReturnInvoicePickerDialog> {
  String _query = '';
  late final Future<List<SalesInvoiceData>> _invoicesFuture;

  // `future:` مبنيّةٌ **مرّةً واحدةً** في `initState` لا داخل `build` —
  // لو بُنيت داخل `build` كانت ستُعاد مع كلّ `setState` (كلّ ضغطةٍ في خانة
  // البحث)، فيرجع `FutureBuilder` إلى `ConnectionState.waiting` ويومض
  // مؤشّرَ تحميلٍ على كلّ حرف يكتبه الكاشير. الفلترةُ نفسُها محليّةٌ
  // (‏`_query`) فوق نتيجةٍ واحدةٍ مسحوبة.
  @override
  void initState() {
    super.initState();
    _invoicesFuture = ref
        .read(returnsRepositoryProvider)
        .getInvoicesForReturn(
          fromDate: DateTime(2000),
          toDate: DateTime.now(),
        )
        .then((invoices) => invoices
            .where((inv) =>
                inv.deliveryStatus == null || inv.deliveryStatus!.isEmpty)
            .toList());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title:  Row(
          children: [
            const Icon(PhosphorIconsBold.arrowUUpLeft, color: AppColors.error),
            const SizedBox(width: 8),
            Text(tr('اختر فاتورةً للمرتجع')),
          ],
        ),
        content: SizedBox(
          width: 480,
          height: 480,
          child: Column(
            children: [
              TextField(
                decoration:  InputDecoration(
                  hintText: tr('بحث برقم الفاتورة'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<SalesInvoiceData>>(
                  future: _invoicesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                          child: Text(tr('تعذّر التحميل: {p0}', {'p0': snapshot.error})));
                    }
                    var invoices = snapshot.data ?? const <SalesInvoiceData>[];
                    if (_query.isNotEmpty) {
                      final q = _query.toLowerCase();
                      invoices = invoices
                          .where((inv) =>
                              inv.invoiceNumber.toLowerCase().contains(q))
                          .toList();
                    }
                    if (invoices.isEmpty) {
                      return  Center(
                        child: Text(tr('لا توجد فواتيرُ قابلةٌ للإرجاع')),
                      );
                    }
                    return ListView.separated(
                      itemCount: invoices.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final inv = invoices[i];
                        return ListTile(
                          leading: const Icon(PhosphorIconsBold.receipt,
                              color: AppColors.info),
                          title: Text(tr('فاتورة #{p0}', {'p0': inv.invoiceNumber})),
                          subtitle: Text(inv.total.toStringAsFixed(2)),
                          onTap: () => Navigator.pop(context, inv),
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
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إلغاء')),
          ),
        ],
      ),
    );
  }
}
