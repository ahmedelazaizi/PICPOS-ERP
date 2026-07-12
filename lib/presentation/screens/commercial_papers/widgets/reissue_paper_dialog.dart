import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../data/database/database.dart' as db;

class ReissuePaperDialog extends StatefulWidget {
  final String paperNumber;
  final double amount;
  final Future<List<db.Party>> partiesFuture;

  const ReissuePaperDialog({
    super.key,
    required this.paperNumber,
    required this.amount,
    required this.partiesFuture,
  });

  @override
  State<ReissuePaperDialog> createState() => _ReissuePaperDialogState();
}

class _ReissuePaperDialogState extends State<ReissuePaperDialog> {
  int? _newPartyId;
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'إعادة إصدار شيك',
        style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'شيك رقم ${widget.paperNumber} — ${widget.amount.toStringAsFixed(2)}',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<db.Party>>(
              future: widget.partiesFuture,
              builder: (ctx, snap) {
                final parties = snap.data ?? [];
                return Autocomplete<db.Party>(
                  optionsBuilder: (textValue) {
                    if (textValue.text.isEmpty) return parties;
                    return parties.where((p) =>
                        p.name.toLowerCase().contains(textValue.text.toLowerCase()) ||
                        (p.phone?.contains(textValue.text) ?? false));
                  },
                  displayStringForOption: (p) => p.name,
                  fieldViewBuilder: (ctx, controller, focusNode, onSubmitted) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'الطرف المستلم *',
                        hintText: 'ابحث بالاسم أو الهاتف...',
                        prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                    );
                  },
                  onSelected: (party) => setState(() => _newPartyId = party.id),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
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
        ElevatedButton.icon(
          icon: const Icon(PhosphorIconsBold.arrowBendDoubleUpRight, size: 16),
          label: const Text('إعادة إصدار'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepOrange,
            foregroundColor: Colors.white,
          ),
          onPressed: _newPartyId == null
              ? null
              : () {
                  Navigator.pop(context, {
                    'confirmed': true,
                    'partyId': _newPartyId,
                    'notes': _notesCtrl.text,
                  });
                },
        ),
      ],
    );
  }
}
