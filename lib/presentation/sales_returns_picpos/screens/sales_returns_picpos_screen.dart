import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:ural_erp/core/utils/app_error_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';

import '../../../data/providers/providers.dart';
import '../../../services/generators/thermal_receipt_generator.dart';

import '../../providers/sales_return_provider.dart';
import '../../../domain/entities/product_entity.dart';
import '../../widgets/permission_guard.dart'; // B5: Manager approval
import '../../widgets/common/common.dart';

import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_content_card.dart';

// ── Part files (منسوخة حرفياً من lib/presentation/screens/sales_returns/ —
// الشاشة الأصل `part of _SalesReturnsScreenState` خاصة فما ينفعش تتعمل import،
// فبتنتقل بنسخ حرفي هنا؛ راجع تعليق مصيدة النسخ في رأس كل ملف). ──────────────
part 'sales_returns_picpos_logic.dart';
part 'sales_returns_picpos_details.dart';

/// شاشة مرتجع المبيعات بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). تعيد استخدام نفس `salesReturnProvider` (وتوابعه
/// `SalesReturnState`/`SalesReturnNotifier`) و`ThermalReceiptGenerator` و
/// `SyncPendingBanner` من UralCash — فقط طبقة العرض تبدّلت لـ `picpos_shell`.
///
/// القائمة (`_buildInvoiceList`) inline كما في الأصل، ولوحة التفاصيل تأتي من
/// mixin منسوخ (`buildReturnDetailsPanel`). الشكل العام «قائمة + تفاصيل»
/// (Row بعمودين) محفوظ من الأصل بلا تغيير، وكذلك كل الإجراءات: حوار «سجل
/// المرتجعات» (`showReturnsHistoryDialog`)، تدفّق تأكيد الإرجاع/الطباعة،
/// وضع الاستبدال، وضع الإتلاف، تصنيف سبب الإرجاع، والموافقة الإدارية على
/// المرتجعات عالية القيمة.
///
/// راجع lib/presentation/screens/sales_returns_screen.dart (الأصل).
class SalesReturnsPicposScreen extends ConsumerStatefulWidget {
  final SalesInvoiceData? initialInvoice;

  const SalesReturnsPicposScreen({super.key, this.initialInvoice});

  @override
  ConsumerState<SalesReturnsPicposScreen> createState() =>
      _SalesReturnsPicposScreenState();
}

class _SalesReturnsPicposScreenState
    extends ConsumerState<SalesReturnsPicposScreen>
    with _SalesReturnsPicposLogic, _SalesReturnsPicposDetailsPanel {
  final _invoiceSearchController = TextEditingController();
  final _returnReasonController = TextEditingController();
  String _selectedReasonCategory = ''; // B4: Return reason categorization

  @override
  TextEditingController get returnReasonController => _returnReasonController;

  @override
  void initState() {
    super.initState();
    if (widget.initialInvoice != null) {
      Future.microtask(
        () => ref
            .read(salesReturnProvider.notifier)
            .selectInvoice(widget.initialInvoice!),
      );
    } else {
      Future.microtask(
        () => ref.read(salesReturnProvider.notifier).loadInvoices(),
      );
    }
  }

  @override
  void dispose() {
    _invoiceSearchController.dispose();
    _returnReasonController.dispose();
    super.dispose();
  }

  Future<void> _selectFromDate() async {
    final state = ref.read(salesReturnProvider);
    final date = await showDatePicker(
      context: context,
      initialDate: state.fromDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      ref.read(salesReturnProvider.notifier).setFromDate(date);
    }
  }

  Future<void> _selectToDate() async {
    final state = ref.read(salesReturnProvider);
    final date = await showDatePicker(
      context: context,
      initialDate: state.toDate,
      firstDate: state.fromDate,
      lastDate: DateTime.now(),
    );
    if (date != null) {
      ref.read(salesReturnProvider.notifier).setToDate(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(salesReturnProvider);
    final notifier = ref.read(salesReturnProvider.notifier);

    ref.listen(salesReturnProvider.select((s) => s.error), (previous, next) {
      if (next != null) {
        AppToast.show(context, next.toString(), type: ToastType.error);
        notifier.clearError();
      }
    });

    return PicPosScreenScaffold(
      title: 'مرتجع المبيعات',
      subtitle: 'تسجيل ومتابعة مرتجعات البيع',
      icon: PhosphorIconsBold.arrowUUpLeft,
      headerActions: [
        OutlinedButton.icon(
          onPressed: () => showReturnsHistoryDialog(),
          icon: const Icon(PhosphorIconsBold.clockCounterClockwise, size: 16),
          label: const Text('سجل المرتجعات'),
        ),
      ],
      body: state.isLoading && state.invoices.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left side - Invoice list
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SyncPendingBanner(
                        tableName: 'sales_returns',
                        label: 'مرتجع مبيعات',
                      ),
                      const SizedBox(height: 12),
                      // Date filter card
                      PicPosContentCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  PhosphorIconsBold.funnel,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'تصفية بالتاريخ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: _selectFromDate,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: AppColors.textMuted
                                              .withValues(alpha: 0.3),
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            PhosphorIconsBold.calendar,
                                            size: 18,
                                            color: AppColors.textMuted,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'من: ${state.fromDate.day}/${state.fromDate.month}/${state.fromDate.year}',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InkWell(
                                    onTap: _selectToDate,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: AppColors.textMuted
                                              .withValues(alpha: 0.3),
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            PhosphorIconsBold.calendar,
                                            size: 18,
                                            color: AppColors.textMuted,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'إلى: ${state.toDate.day}/${state.toDate.month}/${state.toDate.year}',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _invoiceSearchController,
                              decoration: InputDecoration(
                                hintText: 'البحث برقم الفاتورة...',
                                prefixIcon: const Icon(
                                  PhosphorIconsBold.magnifyingGlass,
                                  size: 18,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Invoice list header
                      Row(
                        children: [
                          const Icon(
                            PhosphorIconsBold.listDashes,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'الفواتير',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${state.invoices.length} فاتورة',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Invoice list
                      Expanded(
                        child: PicPosContentCard(
                          padding: const EdgeInsets.all(8),
                          child: _buildInvoiceList(state, notifier),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // Right side - Return details
                Expanded(
                  flex: 3,
                  child: state.selectedInvoice == null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                PhosphorIconsBold.arrowCounterClockwise,
                                size: 80,
                                color: AppColors.textMuted.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'اختر فاتورة من القائمة لعرض تفاصيلها',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        )
                      : state.isLoading
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: ShimmerLoading.list(itemCount: 6),
                            )
                          : buildReturnDetailsPanel(state, notifier),
                ),
              ],
            ),
    );
  }

  Widget _buildInvoiceList(
    SalesReturnState state,
    SalesReturnNotifier notifier,
  ) {
    return Builder(
      builder: (ctx) {
        var invoices = state.invoices;

        final searchText =
            _invoiceSearchController.text.trim().toLowerCase();
        if (searchText.isNotEmpty) {
          invoices = invoices
              .where(
                (inv) => inv.invoiceNumber
                    .toLowerCase()
                    .contains(searchText),
              )
              .toList();
        }

        if (invoices.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  PhosphorIconsBold.invoice,
                  size: 64,
                  color: AppColors.textMuted.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                const Text(
                  'لا توجد فواتير في هذه الفترة',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: invoices.length,
          itemBuilder: (ctx, index) {
            final invoice = invoices[index];
            final isSelected =
                state.selectedInvoice?.id == invoice.id;

            return Card(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: isSelected
                    ? const BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      )
                    : BorderSide.none,
              ),
              child: ListTile(
                onTap: () => notifier.selectInvoice(invoice),
                leading: CircleAvatar(
                  backgroundColor: isSelected
                      ? AppColors.primary
                      : AppColors.info.withValues(alpha: 0.1),
                  child: Icon(
                    PhosphorIconsBold.receipt,
                    size: 18,
                    color: isSelected ? Colors.white : AppColors.info,
                  ),
                ),
                title: Text(
                  '# ${invoice.invoiceNumber}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? AppColors.primary : null,
                  ),
                ),
                subtitle: Text(
                  '${state.customerNames[invoice.customerId] ?? 'عميل نقدي'} • ${invoice.invoiceDate.day}/${invoice.invoiceDate.month}',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${invoice.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(invoice.status).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getStatusLabel(invoice.status),
                        style: TextStyle(
                          fontSize: 10,
                          color: _getStatusColor(invoice.status),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'returned':
        return Colors.red;
      case 'partial_return':
        return Colors.orange;
      case 'voided':
        return Colors.grey;
      default:
        return AppColors.warning;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'مكتملة';
      case 'returned':
        return 'مرتجعة';
      case 'partial_return':
        return 'مرتجع جزئي';
      case 'voided':
        return 'ملغاة';
      default:
        return 'معلقة';
    }
  }
}
