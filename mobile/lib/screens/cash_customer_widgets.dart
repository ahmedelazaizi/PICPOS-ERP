import 'package:flutter/material.dart';

import '../l10n/strings.dart';

/// J3 — one-time customer name/phone on a cash-customer sale and the
/// «حفظ كعميل دائم» action.
class CashCustomerFields extends StatelessWidget {
  const CashCustomerFields({
    super.key,
    required this.name,
    required this.phone,
    required this.onChanged,
    required this.onSaveAsPermanent,
  });
  final TextEditingController name;
  final TextEditingController phone;
  final VoidCallback onChanged;

  /// `null` until a name is typed.
  final VoidCallback? onSaveAsPermanent;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              key: const Key('oneTimeName'),
              controller: name,
              decoration: InputDecoration(labelText: s.t('oneTimeName'), isDense: true),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('oneTimePhone'),
              controller: phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: s.t('oneTimePhone'), isDense: true),
              onChanged: (_) => onChanged(),
            ),
          ),
        ]),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('saveAsPermanent'),
            icon: const Icon(Icons.person_add_alt_1),
            label: Text(s.t('saveAsPermanent')),
            onPressed: onSaveAsPermanent,
          ),
        ),
      ],
    );
  }
}

typedef PermanentCustomerInput = ({String name, String? phone, String? address});

/// Collects the new customer's data (name prefilled from the one-time name).
Future<PermanentCustomerInput?> showPermanentCustomerSheet(BuildContext context,
    {required String name, String? phone}) {
  return showModalBottomSheet<PermanentCustomerInput>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _PermanentCustomerSheet(name: name, phone: phone),
  );
}

class _PermanentCustomerSheet extends StatefulWidget {
  const _PermanentCustomerSheet({required this.name, this.phone});
  final String name;
  final String? phone;

  @override
  State<_PermanentCustomerSheet> createState() => _PermanentCustomerSheetState();
}

class _PermanentCustomerSheetState extends State<_PermanentCustomerSheet> {
  late final _name = TextEditingController(text: widget.name.trim());
  late final _phone = TextEditingController(text: widget.phone?.trim() ?? '');
  final _address = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    String? clean(String v) => v.trim().isEmpty ? null : v.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.t('saveAsPermanent'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            key: const Key('permanentName'),
            controller: _name,
            decoration: InputDecoration(labelText: s.t('customerName')),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: s.t('oneTimePhone')),
          ),
          TextField(
            controller: _address,
            decoration: InputDecoration(labelText: s.t('address')),
          ),
          const SizedBox(height: 8),
          Text(s.t('permanentHint'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('permanentSave'),
            onPressed: _name.text.trim().isEmpty
                ? null
                : () => Navigator.pop<PermanentCustomerInput>(
                    context, (name: _name.text.trim(), phone: clean(_phone.text), address: clean(_address.text))),
            child: Text(s.t('save')),
          ),
        ],
      ),
    );
  }
}
