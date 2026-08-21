import 'package:flutter/material.dart';
import '../../../core/widgets/app_shortcuts.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../domain/models/branch_assignment_scope.dart';
// دفعة ٩ — حارس purchases_print على زرار الطباعة في قائمة الفواتير.
import '../../widgets/permission_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_state_view.dart';
import '../../../core/widgets/shimmer_loading.dart';

import '../../../data/providers/providers.dart';
import '../../../services/invoice_generator.dart';
import '../../../core/constants/app_constants.dart' hide InvoiceStatus;
import '../../../domain/entities/invoice_entity.dart';
import '../../../domain/repositories/purchases_repository.dart';
import '../../screens/purchases/purchase_invoices_controller.dart';
import '../../screens/purchase_orders_screen.dart';
import '../../../data/services/excel_service.dart';
import '../../screens/purchase_invoices/widgets/purchase_invoice_form.dart';
import '../../widgets/common/common.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
// تصميمُ 2026-08-21 — شاشةُ «فاتورة جديدة» المشتركة بين النمطَين.
import '../../invoice_form_picpos/picpos_invoice_form.dart';
import '../../../domain/models/picpos_invoice_draft.dart';
import '../../picpos_shell/picpos_content_card.dart';
// نمطُ ديالوجات PicPos — الغلافُ وحوارُ التأكيد المشتركان.
import '../../picpos_shell/picpos_dialog.dart';

// ── Part files (mixin-based extraction — faithful copy of the UralCash
// `part of` mixins; see purchases_picpos_crud.dart / purchases_picpos_details.dart
// for the copy-discipline note). ─────────────────────────────────────────
part 'purchases_picpos_crud.dart';
part 'purchases_picpos_details.dart';

// ── Design part files (تصميمُ PicPos 2026-08-21) — مرآةُ شكلٍ لثلاثةِ
// مكوّناتِ شاشة المبيعات، وفروقُها المقيسةُ موثَّقةٌ في رأس كلِّ ملفّ. ───────
part 'purchases_summary_cards.dart';
part 'purchases_filter_bar.dart';
part 'purchases_invoices_table.dart';

/// شاشة المشتريات بهوية PicPos. تُختار بالعلامة في app_main_screen (`Brand.isPicPos`).
/// أثقل fork حتى الآن: منطق الحفظ (`createNewInvoice` / `editInvoice` /
/// `_handleSavePurchaseSimple`) كان في mixin **خاص** (`part of`) داخل شاشة
/// UralCash الأصلية، فما ينفعش يتعمله import — اتنسخ حرفياً هنا بنفس أسلوب
/// `picpos_pos_operations.dart`. تنادي نفس `purchasesRepositoryProvider`
/// (`createInvoice`/`updateInvoice`)، نفس `PurchaseInvoiceForm`، نفس
/// `AppDataTable`/`AppKpiCard`/`AppStateView`. الهيدر يستبدل `AppBar`.
/// راجع lib/presentation/screens/purchase_invoices_screen.dart (الأصل).
class PurchasesPicposScreen extends ConsumerStatefulWidget {
  const PurchasesPicposScreen({super.key});

  @override
  ConsumerState<PurchasesPicposScreen> createState() =>
      _PurchasesPicposScreenState();
}

class _PurchasesPicposScreenState extends ConsumerState<PurchasesPicposScreen>
    with _PurchasesPicposDetails, _PurchasesPicposCrud {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_searchController.text.isNotEmpty) {
        ref
            .read(purchaseInvoicesControllerProvider.notifier)
            .updateSearchQuery(_searchController.text);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Edit with confirmation if invoice has payments — verbatim from
  /// purchase_invoices_screen.dart's `_confirmEditInvoice`.
  Future<void> _confirmEditInvoice(InvoiceEntity invoice) async {
    // Confirm on either risk factor: money already paid, OR the invoice is
    // already posted to the GL (isLocked). Editing a posted invoice is now
    // permitted without limit for permission holders, so the operator should
    // still see explicitly that the GL entry will be reversed and re-posted.
    if (invoice.paid > 0 || invoice.isLocked) {
      final isPosted = invoice.isLocked;
      // نمطُ ديالوجات PicPos — ونصُّ التأكيد لم يتغيّر حرفاً.
      final confirmed = await showPicPosConfirm(
        context,
        icon: PhosphorIconsBold.warning,
        accent: AppColors.warning,
        title: isPosted
            ? 'تعديل فاتورة مُرحّلة محاسبياً'
            : 'تعديل فاتورة مدفوعة',
        message: isPosted
            ? 'هذه الفاتورة مُرحّلة إلى دفتر الأستاذ. التعديل سيعكس القيد المحاسبي وحركة المخزون والتكلفة المتوسطة ثم يعيد ترحيلها بالقيم الجديدة، وسيُسجَّل في سجل التدقيق.\n\nهل تريد المتابعة؟'
            : 'هذه الفاتورة تم دفع مبلغ منها. التعديل سيؤدي إلى عكس القيود المحاسبية وحركة المخزون وإعادة تطبيقها.\n\nهل تريد المتابعة؟',
        confirmLabel: 'تعديل الفاتورة',
      );
      // `bool` غيرُ لاغٍ الآن، فـ`!confirmed` تكافئ `confirmed != true`
      // السابقةَ بلا اعتمادٍ على انتباه المستدعي إلى `null`.
      if (!confirmed) return;
    }
    editInvoice(invoice);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(purchaseInvoicesControllerProvider);
    final controller = ref.read(purchaseInvoicesControllerProvider.notifier);

    // Purchase-edit policy (owner decision 2026-07-22): the edit button is
    // gated by the `purchases_edit` permission ONLY — never by `isLocked`.
    // Identical gate to purchase_invoices_screen.dart.
    final canEditPurchase =
        ref.watch(hasPermissionProvider(PermissionCodes.purchasesEdit)).value ??
            false;

    return AppShortcuts(
      searchFocusNode: _searchFocusNode,
      searchController: _searchController,
      onNew: createNewInvoicePicPos, // شاشةُ التصميم الجديدة
      child: PicPosScreenScaffold(
        title: 'المشتريات',
        icon: PhosphorIconsBold.receipt,
        headerActions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.arrowClockwise),
            tooltip: 'تحديث',
            onPressed: () => ref.invalidate(purchaseInvoicesControllerProvider),
          ),
          const SizedBox(width: 8),
          _buildExcelMenu(context, ref),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PurchaseOrdersScreen()),
              );
            },
            icon: const Icon(PhosphorIconsBold.clipboardText, size: 16),
            label: const Text('طلبات الشراء'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: createNewInvoicePicPos,
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label: const Text('فاتورة جديدة'),
          ),
        ],
        // Day 11: unified loading / empty state via AppStateView.
        body: AppStateView(
          isLoading: state.isLoading,
          isEmpty: state.allInvoices.isEmpty && !state.isLoading,
          emptyMessage: 'لا توجد فواتير مشتريات',
          emptyIcon: PhosphorIconsBold.shoppingCart,
          child: Column(
            children: [
              const SyncPendingBanner(
                tableName: 'purchase_invoices',
                label: 'فاتورة مشتريات',
              ),
              // صفُّ الإجماليات — بطاقةٌ رئيسيّةٌ بالمعادلة + أربعُ ثانويّة.
              const PurchasesSummaryRow(),

              // شريطُ الترشيح — حبّاتٌ دائريّةٌ + شرائحُ حالةٍ بعدّادات.
              PurchasesFilterBar(
                searchController: _searchController,
                searchFocusNode: _searchFocusNode,
              ),
              const SizedBox(height: 16),

              // ملاحظةُ تخطيط: `PurchasesInvoicesTable` ترجع `Expanded` من
              // جوّاها، فلا تُلَفّ بـ`PicPosContentCard` — الـ`Container`
              // بينها وبين الـ`Flex` يكسر `ParentDataWidget` بتاع `Expanded`.
              // والبطاقاتُ ترسم حدودَها بنفسها، فلا فرقَ بصريَّ محسوس.
              PurchasesInvoicesTable(
                onView: showInvoiceDetails,
                onEdit: _confirmEditInvoice,
                onPrint: printInvoice,
                canEdit: canEditPurchase,
              ),
              if (state.selectedInvoices.isNotEmpty)
                _buildBatchActionBar(state, controller),
              const SizedBox(height: 16),
            ],
          ), // Column
        ), // AppStateView
      ),
    );
  }

  // ── Excel import/export menu — verbatim logic from the PopupMenuButton in
  // purchase_invoices_screen.dart (lines ~141-188), extracted as a helper. ──
  Widget _buildExcelMenu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(PhosphorIconsBold.fileXls),
      tooltip: 'استيراد / تصدير Excel',
      onSelected: (value) async {
        final excelService = ref.read(excelServiceProvider) as ExcelService?;
        if (excelService == null) return;
        if (value == 'export_template') {
          final path = await excelService.exportPurchaseInvoicesTemplate();
          if (context.mounted) {
            AppToast.show(
              context,
              path != null ? 'تم تصدير القالب بنجاح' : 'فشل تصدير القالب',
              type: path != null ? ToastType.success : ToastType.error,
            );
          }
        } else if (value == 'import') {
          final result = await excelService.importPurchaseInvoices();
          if (context.mounted) {
            AppToast.show(
              context,
              result.message,
              type: result.success ? ToastType.success : ToastType.error,
            );
            if (result.success) {
              ref.invalidate(purchaseInvoicesControllerProvider);
            }
          }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'export_template',
          child: ListTile(
            leading: Icon(PhosphorIconsBold.export),
            title: Text('تصدير قالب فارغ'),
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'import',
          child: ListTile(
            leading: Icon(PhosphorIconsBold.upload),
            title: Text('استيراد من Excel'),
            dense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildBatchActionBar(PurchaseInvoicesScreenState state, PurchaseInvoicesController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'تم تحديد ${state.selectedInvoices.length} فاتورة مسجلة',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  controller.clearSelection();
                },
                icon: const Icon(PhosphorIconsBold.x, color: Colors.white70),
                label: const Text('إلغاء التحديد', style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => _batchPrint(state),
                icon: const Icon(PhosphorIconsBold.printer, size: 18),
                label: const Text('طباعة المحددة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  // حوارُ تأكيدٍ مدمِّر — أحمرُ وأيقونةُ سلّة، والافتراضُ
                  // **الرفضُ** حتى لو أُغلق بالنقر في الفراغ.
                  final confirm = await showPicPosConfirm(
                    context,
                    icon: PhosphorIconsBold.warning,
                    danger: true,
                    title: 'تأكيد الحذف المجمع',
                    message: 'هل أنت متأكد من حذف '
                        '${state.selectedInvoices.length} '
                        'فاتورة مشتريات محددة؟',
                    confirmLabel: 'حذف الجميع',
                  );

                  if (confirm) {
                     // Delete in batch
                     for (final invoiceId in state.selectedInvoices) {
                        final inv = state.allInvoices.firstWhere((element) => element.id == invoiceId);
                        await controller.deleteInvoice(invoiceId, inv.invoiceNumber, inv.total);
                     }
                     controller.clearSelection();
                     if (context.mounted) {
                       AppToast.show(context, 'تم حذف الفواتير المحددة بنجاح', type: ToastType.success);
                     }
                  }
                },
                icon: const Icon(PhosphorIconsBold.trash, size: 18),
                label: const Text('حذف المحددة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  void _batchPrint(PurchaseInvoicesScreenState state) {
    final selected = state.selectedInvoices;
    if (selected.isEmpty) return;

    final invoicesToPrint = state.allInvoices
        .where((inv) => selected.contains(inv.id))
        .toList();

    if (invoicesToPrint.isEmpty) {
      AppToast.show(context, 'لم يتم العثور على الفواتير المحددة', type: ToastType.warning);
      return;
    }

    // Fire-and-forget each print — printInvoice() handles its own errors and toasts
    for (final invoice in invoicesToPrint) {
      printInvoice(invoice);
    }

    AppToast.show(
      context,
      'جاري طباعة ${invoicesToPrint.length} فاتورة...',
      type: ToastType.info,
    );
  }

}

/// Compact badge surfaced next to a purchase invoice number when the
/// invoice has been returned (fully or partially) via the returns-screen
/// flow. Verbatim copy of `_PurchaseReturnBadge` from
/// purchase_invoices_screen.dart — private class, separate library, no
/// name clash with the UralCash original.
class _PurchaseReturnBadge extends StatelessWidget {
  final bool full;
  const _PurchaseReturnBadge({required this.full});

  @override
  Widget build(BuildContext context) {
    final color = full ? AppColors.error : AppColors.warning;
    return Tooltip(
      message: full
          ? 'تم إرجاع الفاتورة بالكامل — راجع شاشة مرتجع المشتريات للتفاصيل'
          : 'تم إرجاع جزء من الفاتورة — راجع شاشة مرتجع المشتريات للتفاصيل',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              full ? Icons.undo_rounded : Icons.rotate_left_rounded,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 3),
            Text(
              full ? 'مُرتجعة' : 'مُرتجعة جزئياً',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
