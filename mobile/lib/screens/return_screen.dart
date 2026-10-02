import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../state/app_controller.dart';
import 'common.dart';

/// Sales return: pick one of the customer's recent invoices, then return
/// quantities against its lines (≤ sold − already returned). Amounts come
/// from the original lines; the settlement (offset vs cash refund) follows
/// the desktop rule and is shown before saving.
class ReturnScreen extends StatefulWidget {
  const ReturnScreen({super.key, required this.customerGlobalId});
  final String customerGlobalId;
  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  Future<List<Map<String, Object?>>>? _invoices;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _invoices ??= AppScope.of(context).returnableInvoices(widget.customerGlobalId);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('salesReturn'))),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: _invoices,
          builder: (context, snap) {
            final list = snap.data;
            if (list == null) return const Center(child: CircularProgressIndicator());
            if (list.isEmpty) {
              return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(s.t('noReturnableInvoices'), textAlign: TextAlign.center)),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(s.t('pickInvoice'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final inv in list)
                  Card(
                    child: ListTile(
                      key: Key('invoice-${inv['number']}'),
                      title: Text('${inv['number']}', textDirection: TextDirection.ltr),
                      subtitle: Text('${'${inv['date']}'.split('T').first} · ${s.t('total')}: ${money(inv['total'] as num)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                        builder: (_) => ReturnLinesScreen(invoice: inv),
                      )),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class ReturnLinesScreen extends StatefulWidget {
  const ReturnLinesScreen({super.key, required this.invoice});
  final Map<String, Object?> invoice;
  @override
  State<ReturnLinesScreen> createState() => _ReturnLinesScreenState();
}

class _Row {
  _Row(this.productGlobalId, this.name, this.sold, this.returnable);
  final String productGlobalId, name;
  final double sold, returnable;
  double qty = 0;
}

class _ReturnLinesScreenState extends State<ReturnLinesScreen> {
  List<_Row>? _rows;
  ReturnPreview? _preview;
  String? _reason;
  bool _busy = false;

  String get _gid => widget.invoice['globalId'] as String;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rows == null) _load();
  }

  Future<void> _load() async {
    final c = AppScope.of(context);
    final sold = await c.soldProducts(_gid);
    final rows = <_Row>[];
    for (final e in sold.entries) {
      final p = await c.product(e.key);
      rows.add(_Row(e.key, '${p?['name'] ?? e.key}', e.value.soldQty, e.value.returnableQty));
    }
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _setQty(_Row r, double q) async {
    if (q < 0 || q > r.returnable + 1e-9) return;
    setState(() => r.qty = q);
    final p = await AppScope.of(context)
        .previewReturn(_gid, {for (final x in _rows!) if (x.qty > 0) x.productGlobalId: x.qty});
    if (mounted) setState(() => _preview = p);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final s = S.of(context);
    try {
      final e = await AppScope.of(context).createReturn(
        invoiceGlobalId: _gid,
        quantities: {for (final x in _rows!) if (x.qty > 0) x.productGlobalId: x.qty},
        reason: _reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.t('saved')} — ${e.payload['number']}')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _q(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final rows = _rows;
    final p = _preview;
    final any = rows?.any((r) => r.qty > 0) ?? false;
    return Scaffold(
      appBar: AppBar(title: Text('${s.t('salesReturn')} · ${widget.invoice['number']}')),
      body: SafeArea(
        child: rows == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final r in rows)
                          ListTile(
                            key: Key('ret-${r.productGlobalId}'),
                            title: Text(r.name),
                            subtitle: Text('${s.t('sold')}: ${_q(r.sold)} · ${s.t('returnable')}: ${_q(r.returnable)}'),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: r.qty > 0 ? () => _setQty(r, r.qty - 1) : null,
                              ),
                              Text(_q(r.qty), style: Theme.of(context).textTheme.titleMedium),
                              IconButton(
                                key: Key('ret-inc-${r.productGlobalId}'),
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: r.qty + 1 <= r.returnable + 1e-9 ? () => _setQty(r, r.qty + 1) : null,
                              ),
                            ]),
                          ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _reason,
                          decoration: InputDecoration(labelText: s.t('returnReason')),
                          items: [
                            for (final k in const ['damaged', 'expired', 'wrong_item', 'customer_request', 'other'])
                              DropdownMenuItem(value: k, child: Text(s.t('ret_$k'))),
                          ],
                          onChanged: (v) => setState(() => _reason = v),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InfoRow(s.t('tax'), money(p?.tax ?? 0)),
                          InfoRow(s.t('returnTotal'), money(p?.total ?? 0)),
                          InfoRow(s.t('arOffset'), money(p?.arOffset ?? 0)),
                          InfoRow(s.t('cashRefund'), money(p?.cashRefund ?? 0)),
                          const SizedBox(height: 8),
                          FilledButton(
                            key: const Key('saveReturn'),
                            onPressed: _busy || !any ? null : _save,
                            child: Text(s.t('save')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
