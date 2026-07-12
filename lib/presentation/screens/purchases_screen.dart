import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'dart:ui' as ui;

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/providers.dart';
import '../../domain/entities/invoice_entity.dart';
import '../../services/invoice_generator.dart';
import 'purchases/purchases.dart';
import '../../../../../core/constants/app_constants.dart';

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _paidController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  final _supplierInvoiceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _paidController.dispose();
    _notesController.dispose();
    _supplierInvoiceController.dispose();
    super.dispose();
  }

  void _clearForm() {
    ref.read(purchasesFormProvider.notifier).clearForm();
    _paidController.text = '0';
    _notesController.clear();
    _supplierInvoiceController.clear();
  }

  Future<void> _handleSave() async {
    final notifier = ref.read(purchasesFormProvider.notifier);
    try {
      final success = await notifier.saveInvoice(
        paid: double.tryParse(_paidController.text) ?? 0,
        notes: _notesController.text,
        supplierInvoiceNumber: _supplierInvoiceController.text,
      );

      if (success && mounted) {
        AppToast.show(
          context,
          'تم حفظ الفاتورة بنجاح',
          type: ToastType.success,
        );
        _clearForm();
        _tabController.animateTo(0);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _handleEdit(InvoiceEntity invoice) async {
    if (invoice.id == null) return;

    final purchasesRepo = ref.read(purchasesRepositoryProvider);
    final rawInvoice = await purchasesRepo.getRawInvoiceById(invoice.id!);

    if (rawInvoice != null) {
      await ref.read(purchasesFormProvider.notifier).loadInvoiceForEdit(rawInvoice);
      _supplierInvoiceController.text = rawInvoice.supplierInvoiceNumber ?? '';
    }

    _paidController.text = invoice.paid.toStringAsFixed(AppConstants.decimalPlaces);
    _notesController.text = invoice.notes ?? '';
    _tabController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = ref.watch(purchasesFormProvider).isEditMode;
    final editNumber = ref.watch(purchasesFormProvider).editingInvoiceNumber;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('إدارة المشتريات'),
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              const Tab(
                icon: Icon(PhosphorIconsBold.chartBar),
                text: 'داشبورد',
              ),
              Tab(
                icon: Icon(
                  isEditMode
                      ? PhosphorIconsBold.pencilSimple
                      : PhosphorIconsBold.receipt,
                ),
                text: isEditMode ? 'تعديل #$editNumber' : 'فاتورة جديدة',
              ),
            ],
          ),
          actions: [
            if (_tabController.index == 0)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: IconButton(
                  onPressed: () {
                    _clearForm();
                    _tabController.animateTo(1);
                  },
                  icon: const Icon(
                    PhosphorIconsBold.filePlus,
                    color: Colors.white,
                  ),
                  tooltip: 'فاتورة شراء جديدة',
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            // Tabs Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  PurchaseDashboard(
                    tabController: _tabController,
                    onEdit: (InvoiceEntity inv) => _handleEdit(inv),
                    onView: (InvoiceEntity inv) =>
                        _showInvoiceDetails(inv),
                    onPrint: (InvoiceEntity inv) => _handlePrint(inv),
                    onPayment: (InvoiceEntity inv, double rem) =>
                        _showPaymentDialog(inv, rem),
                  ),
                  PurchaseForm(
                    onSave: _handleSave,
                    onCancel: () {
                      _clearForm();
                      _tabController.animateTo(0);
                    },
                    paidController: _paidController,
                    notesController: _notesController,
                    supplierInvoiceController: _supplierInvoiceController,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInvoiceDetails(InvoiceEntity invoice) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Text('تفاصيل فاتورة #${invoice.invoiceNumber}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(
                'التاريخ',
                '${invoice.invoiceDate.day}/${invoice.invoiceDate.month}/${invoice.invoiceDate.year}',
              ),
              _buildDetailRow(
                'الإجمالي',
                '${invoice.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
              ),
              _buildDetailRow(
                'المدفوع',
                '${invoice.paid.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
              ),
              _buildDetailRow(
                'المتبقي',
                '${(invoice.total - invoice.paid).toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                color: AppColors.error,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePrint(InvoiceEntity invoice) async {
    try {
      final purchasesRepo = ref.read(purchasesRepositoryProvider);
      final partiesRepo = ref.read(partiesRepositoryProvider);
      final supplier = await partiesRepo.getPartyById(invoice.partyId ?? 0);
      final items = await purchasesRepo.getInvoiceItemsWithProduct(invoice.id!);
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final String? companyName = await settingsRepo.getSetting('company_name');

      await InvoiceGenerator.printPurchaseInvoice(
        invoiceNumber: invoice.invoiceNumber,
        date: invoice.invoiceDate,
        supplierName: supplier?.name ?? 'غير محدد',
        items: items
            .map(
              (item) => InvoiceItem(
                name: item.product.name,
                quantity: item.item.quantity,
                price: item.item.unitCost,
                total: item.item.quantity * item.item.unitCost,
              ),
            )
            .toList(),
        total: invoice.total,
        paid: invoice.paid,
        companyName: companyName,
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
      }
    }
  }

  void _showPaymentDialog(InvoiceEntity invoice, double remaining) {
    final controller = TextEditingController(
      text: remaining.toStringAsFixed(AppConstants.decimalPlaces),
    );
    bool saving = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Directionality(
            textDirection: ui.TextDirection.rtl,
            child: AlertDialog(
              title: const Text('تسجيل دفعة للمورد'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'المتبقي: ${remaining.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'قيمة الدفعة',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: saving ? null : () async {
                    final amount = double.tryParse(controller.text) ?? 0;
                    final purchasesRepo = ref.read(purchasesRepositoryProvider);
                    if (amount > 0 && amount <= remaining) {
                      setDialogState(() => saving = true);
                      await purchasesRepo.recordPayment(invoice.id!, amount,
                          userId: ref.read(authProvider).user?.id);
                      if (context.mounted) Navigator.pop(context);
                      if (!context.mounted) return;
                      AppToast.show(
                        context,
                        'تم تسجيل الدفعة',
                        type: ToastType.success,
                      );
                    }
                  },
                  child: const Text('حفظ'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
