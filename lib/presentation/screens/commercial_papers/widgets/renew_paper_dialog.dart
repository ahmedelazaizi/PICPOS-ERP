import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class RenewPaperDialog extends StatefulWidget {
  final String paperNumber;
  final DateTime initialDueDate;

  const RenewPaperDialog({
    super.key,
    required this.paperNumber,
    required this.initialDueDate,
  });

  @override
  State<RenewPaperDialog> createState() => _RenewPaperDialogState();
}

class _RenewPaperDialogState extends State<RenewPaperDialog> {
  late DateTime _newDueDate;
  final _notesCtrl = TextEditingController();
  final _dateFormat = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    _newDueDate = widget.initialDueDate.add(const Duration(days: 30));
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        tr('تجديد شيك #{p0}', {'p0': widget.paperNumber}),
        style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _newDueDate,
                firstDate: DateTime.now(),
                lastDate: DateTime(2030),
              );
              if (d != null) setState(() => _newDueDate = d);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: tr('تاريخ الاستحقاق الجديد'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(_dateFormat.format(_newDueDate)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: InputDecoration(
              labelText: tr('ملاحظات'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:  Text(tr('إلغاء')),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, {
              'confirmed': true,
              'newDueDate': _newDueDate,
              'notes': _notesCtrl.text,
            });
          },
          child:  Text(tr('تأكيد التجديد')),
        ),
      ],
    );
  }
}
