import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../data/database/database.dart' as db;

class EndorsePaperDialog extends StatefulWidget {
  final String paperNumber;
  final double amount;
  final Future<List<db.Party>> partiesFuture;

  const EndorsePaperDialog({
    super.key,
    required this.paperNumber,
    required this.amount,
    required this.partiesFuture,
  });

  @override
  State<EndorsePaperDialog> createState() => _EndorsePaperDialogState();
}

class _EndorsePaperDialogState extends State<EndorsePaperDialog> {
  int? _endorsedToPartyId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('تظهير الشيك', style: GoogleFonts.cairo()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'تظهير الشيك رقم ${widget.paperNumber} بمبلغ ${widget.amount.toStringAsFixed(2)}',
            style: GoogleFonts.cairo(fontSize: 13),
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
                      labelText: 'تظهير إلى (عميل/مورد)',
                      hintText: 'ابحث بالاسم أو الهاتف...',
                      prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  );
                },
                onSelected: (party) => setState(() => _endorsedToPartyId = party.id),
              );
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _endorsedToPartyId == null
              ? null
              : () {
                  Navigator.pop(context, {
                    'confirmed': true,
                    'partyId': _endorsedToPartyId,
                  });
                },
          child: const Text('تأكيد التظهير'),
        ),
      ],
    );
  }
}
