import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../../../../core/constants/app_constants.dart';

/// Result class for invoice lookup actions
class InvoiceActionResult {
  final SalesInvoiceData invoice;
  final List<SalesInvoiceItem> items;

  const InvoiceActionResult({required this.invoice, required this.items});
}

/// Dialog for searching and viewing historical invoices
class InvoiceLookupDialog extends ConsumerStatefulWidget {
  final void Function(InvoiceActionResult result)? onViewDetails;
  final void Function(InvoiceActionResult result)? onPrint;

  const InvoiceLookupDialog({super.key, this.onViewDetails, this.onPrint});

  /// Show the invoice lookup dialog
  static Future<void> show({
    required BuildContext context,
    void Function(InvoiceActionResult result)? onViewDetails,
    void Function(InvoiceActionResult result)? onPrint,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => InvoiceLookupDialog(
        onViewDetails: onViewDetails != null
            ? (result) {
                Navigator.pop(ctx);
                onViewDetails(result);
              }
            : null,
        onPrint: onPrint != null
            ? (result) {
                Navigator.pop(ctx);
                onPrint(result);
              }
            : null,
      ),
    );
  }

  @override
  ConsumerState<InvoiceLookupDialog> createState() =>
      _InvoiceLookupDialogState();
}

class _InvoiceLookupDialogState extends ConsumerState<InvoiceLookupDialog> {
  final _searchController = TextEditingController();
  List<SalesInvoiceData> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;

    setState(() => _isSearching = true);

    final salesRepo = ref.read(salesRepositoryProvider);
    final results = await salesRepo.searchInvoicesByNumber(query);

    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  Future<List<SalesInvoiceItem>> _getInvoiceItems(int invoiceId) async {
    final salesRepo = ref.read(salesRepositoryProvider);
    return salesRepo.getSalesInvoiceItems(invoiceId);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.magnifyingGlass, color: AppColors.info),
            SizedBox(width: 8),
            Text('??????? ?? ??????'),
          ],
        ),
        content: SizedBox(
          width: 550,
          height: 450,
          child: Column(
            children: [
              _buildSearchField(),
              const SizedBox(height: 16),
              Expanded(child: _buildResultsList()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('?????'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        labelText: '??? ????????',
        hintText: '???? ??? ???????? ?????...',
        prefixIcon: const Icon(PhosphorIconsBold.invoice),
        suffixIcon: IconButton(
          icon: const Icon(PhosphorIconsBold.magnifyingGlass),
          onPressed: () => _search(_searchController.text),
        ),
      ),
      onSubmitted: _search,
    );
  }

  Widget _buildResultsList() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Text(
          '???? ?? ?????? ??????',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      itemCount: _searchResults.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final invoice = _searchResults[index];
        return _buildInvoiceTile(invoice);
      },
    );
  }

  Widget _buildInvoiceTile(SalesInvoiceData invoice) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.success.withValues(alpha: 0.1),
        child: const Icon(PhosphorIconsBold.receipt, color: AppColors.success),
      ),
      title: Text('?????? #${invoice.invoiceNumber}'),
      subtitle: Text(
        '${invoice.invoiceDate.day}/${invoice.invoiceDate.month}/${invoice.invoiceDate.year} - ${invoice.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onViewDetails != null)
            IconButton(
              icon: const Icon(PhosphorIconsBold.eye, color: AppColors.info),
              onPressed: () async {
                final items = await _getInvoiceItems(invoice.id);
                widget.onViewDetails!(
                  InvoiceActionResult(invoice: invoice, items: items),
                );
              },
              tooltip: '??? ????????',
            ),
          if (widget.onPrint != null)
            IconButton(
              icon: const Icon(
                PhosphorIconsBold.printer,
                color: AppColors.primary,
              ),
              onPressed: () async {
                final items = await _getInvoiceItems(invoice.id);
                widget.onPrint!(
                  InvoiceActionResult(invoice: invoice, items: items),
                );
              },
              tooltip: '????? ?????',
            ),
        ],
      ),
    );
  }
}
