import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/database/database.dart' as db;

class PartialCollectionDialog extends StatefulWidget {
  final String paperNumber;
  final double totalAmount;
  final Future<List<db.Account>> accountsFuture;

  const PartialCollectionDialog({
    super.key,
    required this.paperNumber,
    required this.totalAmount,
    required this.accountsFuture,
  });

  @override
  State<PartialCollectionDialog> createState() => _PartialCollectionDialogState();
}

class _PartialCollectionDialogState extends State<PartialCollectionDialog> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  db.Account? _selectedAccount;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'تحصيل جزئي — شيك #${widget.paperNumber}',
        style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'إجمالي الورقة: ${widget.totalAmount.toStringAsFixed(2)}',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600, color: AppColors.success),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'المبلغ المحصّل *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<db.Account>>(
              future: widget.accountsFuture,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final accounts = snap.data ?? [];
                if (accounts.isEmpty) return const SizedBox.shrink();
                return Autocomplete<db.Account>(
                  optionsBuilder: (textValue) {
                    if (textValue.text.isEmpty) return accounts.take(20);
                    final q = textValue.text.toLowerCase();
                    return accounts.where((a) =>
                        a.name.toLowerCase().contains(q) ||
                        a.code.toLowerCase().contains(q));
                  },
                  displayStringForOption: (a) => '${a.code} - ${a.name}',
                  fieldViewBuilder: (ctx, controller, focusNode, onSubmitted) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'الحساب المقابل',
                        hintText: 'ابحث بالاسم أو الرمز...',
                        prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                    );
                  },
                  onSelected: (a) => setState(() => _selectedAccount = a),
                );
              },
            ),
            if (_selectedAccount != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsBold.checkCircle, size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                      '${_selectedAccount!.code} - ${_selectedAccount!.name}',
                      style: GoogleFonts.cairo(fontSize: 11, color: AppColors.success),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                labelText: 'ملاحظات',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            final amount = double.tryParse(_amountCtrl.text);
            if (amount == null || amount <= 0) {
              return; // Should show validation but handled in caller for now as per original code
            }
            Navigator.pop(context, {
              'confirmed': true,
              'amount': amount,
              'notes': _notesCtrl.text,
              'account': _selectedAccount,
            });
          },
          child: const Text('تأكيد التحصيل'),
        ),
      ],
    );
  }
}
