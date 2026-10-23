import 'package:picpos_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/database/database.dart' as db;

class DepositForCollectionDialog extends StatefulWidget {
  final String paperNumber;
  final double amount;
  final Future<List<dynamic>> banksFuture; // SafeData list
  final Future<List<db.Account>> accountsFuture;

  const DepositForCollectionDialog({
    super.key,
    required this.paperNumber,
    required this.amount,
    required this.banksFuture,
    required this.accountsFuture,
  });

  @override
  State<DepositForCollectionDialog> createState() => _DepositForCollectionDialogState();
}

class _DepositForCollectionDialogState extends State<DepositForCollectionDialog> {
  int? _selectedBankId;
  db.Account? _selectedAccount;

  @override
  Widget build(BuildContext context) {
  // ignore: unused_local_variable
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        tr('إيداع برسم التحصيل'),
        style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('شيك رقم {p0} — {p1}', {'p0': widget.paperNumber, 'p1': widget.amount.toStringAsFixed(2)}),
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<dynamic>>(
              future: widget.banksFuture,
              builder: (ctx, snap) {
                final banks = snap.data ?? [];
                if (banks.isEmpty && snap.connectionState == ConnectionState.done) {
                  return Text(
                    tr('لا توجد خزن بنكية — أضف بنك من إعدادات الخزينة أولاً'),
                    style: GoogleFonts.cairo(color: AppColors.error),
                  );
                }
                return DropdownButtonFormField<int>(
                  decoration: InputDecoration(
                    labelText: tr('اختر البنك *'),
                    prefixIcon: const Icon(PhosphorIconsBold.bank, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  items: banks
                      .map((b) => DropdownMenuItem<int>(
                            value: b.id as int,
                            child: Text(b.name as String),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedBankId = v),
                );
              },
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
                        labelText: tr('الحساب المقابل'),
                        hintText: tr('ابحث بالاسم أو الرمز...'),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:  Text(tr('إلغاء')),
        ),
        ElevatedButton.icon(
          icon: const Icon(PhosphorIconsBold.bank, size: 16),
          label:  Text(tr('إيداع')),
          onPressed: _selectedBankId == null
              ? null
              : () {
                  Navigator.pop(context, {
                    'confirmed': true,
                    'bankId': _selectedBankId,
                    'account': _selectedAccount,
                  });
                },
        ),
      ],
    );
  }
}
