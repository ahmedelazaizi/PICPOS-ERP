// J3 — حوارُ «حفظ كعميل دائم» من فاتورة «عميل نقدي».
//
// يجمع بيانات العميل الجديد (الاسم والهاتف والعنوان اختياريّاً) ومسارَ
// المندوب الذي يُضاف العميلُ إلى **نهاية** تسلسله (والمنطقةُ منطقةُ المسار).
// عرضٌ خالص: الإنشاءُ عند المنادي — وحدُّ الائتمان صفرٌ حتى تضبطه الإدارة.
import 'package:flutter/material.dart';

import '../../../core/i18n/tr.dart';
import '../../../domain/models/distribution_model.dart';

/// ما أدخله المستخدم — `routeId == null` ⇒ بلا مسار.
typedef PermanentCustomerInput = ({
  String name,
  String? phone,
  String? address,
  int? routeId,
});

Future<PermanentCustomerInput?> showPermanentCustomerDialog(
  BuildContext context, {
  required String name,
  String? phone,
  required List<DistributionRoute> routes,
  int? preferredRouteId,
}) {
  return showDialog<PermanentCustomerInput>(
    context: context,
    builder: (_) => _PermanentCustomerDialog(
        name: name,
        phone: phone,
        routes: routes,
        preferredRouteId: preferredRouteId),
  );
}

class _PermanentCustomerDialog extends StatefulWidget {
  const _PermanentCustomerDialog({
    required this.name,
    required this.phone,
    required this.routes,
    this.preferredRouteId,
  });
  final String name;
  final String? phone;
  final List<DistributionRoute> routes;

  /// J4 — مسارُ المندوب الحاليّ (من ربط المستخدم بموظفه) يُختار مسبقاً،
  /// ويبقى المنتقي لمن ليس مندوباً أو لمن يريد غيره.
  final int? preferredRouteId;

  @override
  State<_PermanentCustomerDialog> createState() =>
      _PermanentCustomerDialogState();
}

class _PermanentCustomerDialogState extends State<_PermanentCustomerDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _phone = TextEditingController(text: widget.phone ?? '');
  final _address = TextEditingController();
  late int? _routeId = widget.routes
          .any((r) => r.id == widget.preferredRouteId)
      ? widget.preferredRouteId
      : (widget.routes.length == 1 ? widget.routes.single.id : null);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  String _routeLabel(DistributionRoute r) => [
        r.name,
        if (r.repName != null && r.repName!.isNotEmpty) r.repName!,
        if (r.areaName != null && r.areaName!.isNotEmpty) r.areaName!,
      ].join(' — ');

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    String? clean(String v) => v.trim().isEmpty ? null : v.trim();
    Navigator.pop<PermanentCustomerInput>(context, (
      name: name,
      phone: clean(_phone.text),
      address: clean(_address.text),
      routeId: _routeId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('حفظ كعميل دائم')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('permanent_customer_name'),
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: tr('اسم العميل')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: tr('الهاتف (اختياري)')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _address,
              decoration: InputDecoration(labelText: tr('العنوان (اختياري)')),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              key: const Key('permanent_customer_route'),
              initialValue: _routeId,
              isExpanded: true,
              decoration:
                  InputDecoration(labelText: tr('مسار المندوب والمنطقة')),
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(tr('بدون مسار'))),
                for (final r in widget.routes)
                  DropdownMenuItem<int?>(
                    value: r.id,
                    child: Text(_routeLabel(r), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _routeId = v),
            ),
            const SizedBox(height: 8),
            Text(
              tr('يُضاف العميل إلى نهاية تسلسل المسار، وحد ائتمانه صفر (نقدي) حتى تضبطه الإدارة.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('إلغاء')),
        ),
        FilledButton(
          key: const Key('permanent_customer_save'),
          onPressed: _name.text.trim().isEmpty ? null : _submit,
          child: Text(tr('حفظ')),
        ),
      ],
    );
  }
}
