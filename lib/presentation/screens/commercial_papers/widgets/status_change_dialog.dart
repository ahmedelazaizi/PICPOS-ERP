import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/database/database.dart' as db;

class StatusChangeDialog extends StatefulWidget {
  final String statusLabel;
  final Future<List<db.Account>> accountsFuture;

  const StatusChangeDialog({
    super.key,
    required this.statusLabel,
    required this.accountsFuture,
  });

  @override
  State<StatusChangeDialog> createState() => _StatusChangeDialogState();
}

class _StatusChangeDialogState extends State<StatusChangeDialog> {
  final _notesCtrl = TextEditingController();
  db.Account? _selectedAccount;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'تأكيد — ${widget.statusLabel}',
        style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'هل تريد تغيير حالة الورقة إلى "${widget.statusLabel}"؟',
              style: GoogleFonts.cairo(),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<db.Account>>(
              future: widget.accountsFuture,
              builder: (ctx, snap) {
                final accounts = snap.data ?? [];
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
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
                        labelText: 'الحساب المقابل *',
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
                labelText: 'ملاحظات (اختياري)',
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
            Navigator.pop(context, {
              'confirmed': true,
              'notes': _notesCtrl.text,
              'account': _selectedAccount,
            });
          },
          child: Text('تأكيد ${widget.statusLabel}'),
        ),
      ],
    );
  }
}
