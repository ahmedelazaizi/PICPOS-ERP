import 'package:picpos_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../data/database/database.dart' as db;

class CreatePaperDialog extends StatefulWidget {
  final String direction; // 'received' or 'issued'
  final Future<List<db.Party>> partiesFuture;
  final Future<List<dynamic>> banksFuture; // SafeData list

  const CreatePaperDialog({
    super.key,
    required this.direction,
    required this.partiesFuture,
    required this.banksFuture,
  });

  @override
  State<CreatePaperDialog> createState() => _CreatePaperDialogState();
}

class _CreatePaperDialogState extends State<CreatePaperDialog> {
  final _numberCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _dateFormat = DateFormat('yyyy/MM/dd');

  int? _selectedPartyId;
  int? _selectedBankSafeId;
  String? _selectedBankName;
  DateTime _issueDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));
  String _paperType = 'cheque';

  @override
  void dispose() {
    _numberCtrl.dispose();
    _amountCtrl.dispose();
    _accountNumberCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.direction == 'received' ? tr('شيك وارد جديد') : tr('شيك صادر جديد'),
        style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _paperType,
                decoration: InputDecoration(
                  labelText: tr('النوع'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
                items:  [
                  DropdownMenuItem(value: 'cheque', child: Text(tr('شيك'))),
                  DropdownMenuItem(value: 'promissory_note', child: Text(tr('كمبيالة'))),
                  DropdownMenuItem(value: 'bill_of_exchange', child: Text(tr('سند لأمر'))),
                ],
                onChanged: (v) => setState(() => _paperType = v ?? 'cheque'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _numberCtrl,
                decoration: InputDecoration(
                  labelText: tr('رقم الشيك *'),
                  prefixIcon: const Icon(PhosphorIconsBold.hash, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('المبلغ *'),
                  prefixIcon: const Icon(PhosphorIconsBold.currencyCircleDollar, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<db.Party>>(
                future: widget.partiesFuture,
                builder: (ctx, snap) {
                  final parties = snap.data ?? [];
                  final partyLabel = widget.direction == 'received'
                      ? tr('المسحوب عليه (العميل) *')
                      : tr('المستفيد (المورد) *');
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
                          labelText: partyLabel,
                          hintText: tr('ابحث بالاسم أو الهاتف...'),
                          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                        ),
                      );
                    },
                    onSelected: (party) => setState(() => _selectedPartyId = party.id),
                  );
                },
              ),
              const SizedBox(height: 12),
              // Conditional Bank Section
              if (widget.direction == 'received') ...[
                TextField(
                  onChanged: (v) => _selectedBankName = v,
                  decoration: InputDecoration(
                    labelText: tr('اسم البنك المسحوب عليه'),
                    prefixIcon: const Icon(PhosphorIconsBold.bank, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
              ] else ...[
                FutureBuilder<List<dynamic>>(
                  future: widget.banksFuture,
                  builder: (ctx, snap) {
                    final banks = snap.data ?? [];
                    return DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: tr('البنك المسحوب منه *'),
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
                      onChanged: (v) => setState(() => _selectedBankSafeId = v),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _accountNumberCtrl,
                decoration: InputDecoration(
                  labelText: tr('رقم الحساب البنكي'),
                  prefixIcon: const Icon(PhosphorIconsBold.creditCard, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _issueDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (d != null) setState(() => _issueDate = d);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: tr('تاريخ التحرير'),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                        ),
                        child: Text(_dateFormat.format(_issueDate), style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _dueDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (d != null) setState(() => _dueDate = d);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: tr('تاريخ الاستحقاق'),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                        ),
                        child: Text(_dateFormat.format(_dueDate), style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: tr('ملاحظات إضافية'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:  Text(tr('إلغاء')),
        ),
        ElevatedButton(
          onPressed: () {
            final amount = double.tryParse(_amountCtrl.text);
            if (_numberCtrl.text.isEmpty || amount == null || _selectedPartyId == null) {
              return; // Should show validation but handled in caller for now 
            }
            Navigator.pop(context, {
              'confirmed': true,
              'type': _paperType,
              'number': _numberCtrl.text,
              'amount': amount,
              'partyId': _selectedPartyId,
              'bankName': _selectedBankName,
              'bankSafeId': _selectedBankSafeId,
              'accountNumber': _accountNumberCtrl.text,
              'issueDate': _issueDate,
              'dueDate': _dueDate,
              'notes': _notesCtrl.text,
            });
          },
          child:  Text(tr('إضافة الورقة')),
        ),
      ],
    );
  }
}