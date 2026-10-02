import 'package:flutter/material.dart';

import '../domain/sale_math.dart';
import '../l10n/strings.dart';
import 'barcode_scanner.dart';
import 'common.dart';

/// New sale: barcode entry (hardware/keyboard-wedge scanners type into the
/// field) or camera scan, product picker, cart priced per customer/quantity
/// (price level, price-list tiers), cash/credit, collect now.
class SaleScreen extends StatefulWidget {
  const SaleScreen({super.key, required this.customerGlobalId, this.cameraScan = openCameraScanner});
  final String customerGlobalId;
  final CameraScan cameraScan;
  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  final _barcode = TextEditingController();
  final _paid = TextEditingController();
  final List<CartLine> _cart = [];
  bool _credit = false;
  bool _busy = false;

  DocTotals get _totals => AppScope.of(context).totalsOf(_cart);

  Future<void> _add(Map<String, Object?> p) async {
    final existing = _cart.where((l) => l.productGlobalId == p['globalId']).firstOrNull;
    if (existing != null) return _setQty(existing, existing.quantity + 1);
    final c = AppScope.of(context);
    final price = await c.unitPriceFor(p, widget.customerGlobalId, 1);
    if (!mounted) return;
    setState(() {
      _cart.add(CartLine(
        productGlobalId: p['globalId'] as String,
        name: '${p['name']}',
        unitPrice: price.price,
        taxRate: c.taxRateOf(p),
      ));
      if (!_credit) _paid.text = money(_totals.total);
    });
  }

  /// Quantity change re-resolves the price (price-list quantity tiers).
  Future<void> _setQty(CartLine l, double q) async {
    final c = AppScope.of(context);
    if (q <= 0) {
      setState(() {
        _cart.remove(l);
        if (!_credit) _paid.text = money(_totals.total);
      });
      return;
    }
    final p = await c.product(l.productGlobalId);
    final price = p == null ? null : await c.unitPriceFor(p, widget.customerGlobalId, q);
    if (!mounted) return;
    setState(() {
      l.quantity = q;
      if (price != null) l.unitPrice = price.price;
      if (!_credit) _paid.text = money(_totals.total);
    });
  }

  Future<void> _camera() async {
    final code = await widget.cameraScan(context);
    if (code != null && mounted) await _scan(code);
  }

  Future<void> _scan(String raw) async {
    final code = normalizeBarcode(raw);
    if (code.isEmpty) return;
    final p = await AppScope.of(context).productByBarcode(code);
    if (!mounted) return;
    _barcode.clear();
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).t('unknownBarcode'))));
      return;
    }
    await _add(p);
  }

  Future<void> _pick() async {
    final products = await AppScope.of(context).products();
    if (!mounted) return;
    final p = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        children: [
          for (final p in products)
            ListTile(
              title: Text('${p['name']}'),
              subtitle: Text('${p['barcode'] ?? ''}'),
              trailing: Text(money(p['salePrice'] as num)),
              onTap: () => Navigator.pop(context, p),
            ),
        ],
      ),
    );
    if (p != null) await _add(p);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final s = S.of(context);
    try {
      final paid = _credit ? (double.tryParse(_paid.text) ?? 0) : _totals.total;
      final e = await AppScope.of(context)
          .createSale(customerGlobalId: widget.customerGlobalId, lines: _cart, paid: paid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.t('saved')} — ${e.payload['number']}')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = _totals;
    final paid = _credit ? (double.tryParse(_paid.text) ?? 0) : t.total;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('newSale'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('barcode'),
                      controller: _barcode,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: s.t('scanBarcode'),
                        prefixIcon: const Icon(Icons.qr_code_scanner),
                      ),
                      onSubmitted: _scan,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    key: const Key('cameraScan'),
                    tooltip: s.t('cameraScan'),
                    icon: const Icon(Icons.photo_camera_outlined),
                    onPressed: _camera,
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: s.t('add'),
                    icon: const Icon(Icons.add),
                    onPressed: _pick,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _cart.isEmpty
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(s.t('emptyCart'), textAlign: TextAlign.center)))
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final l in _cart)
                          ListTile(
                            title: Text(l.name),
                            subtitle: Text('${s.t('quantity')}: ${l.quantity.toStringAsFixed(0)} × ${money(l.unitPrice)}'),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => _setQty(l, l.quantity - 1),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () => _setQty(l, l.quantity + 1),
                              ),
                            ]),
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
                    if (AppScope.of(context).pricesIncludeTax)
                      Text(s.t('pricesIncludeTax'), style: Theme.of(context).textTheme.bodySmall),
                    InfoRow(s.t('subtotal'), money(t.net)),
                    InfoRow(s.t('tax'), money(t.tax)),
                    InfoRow(s.t('total'), money(t.total)),
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: false, label: Text(s.t('cash')), icon: const Icon(Icons.payments)),
                        ButtonSegment(value: true, label: Text(s.t('credit')), icon: const Icon(Icons.schedule)),
                      ],
                      selected: {_credit},
                      onSelectionChanged: (v) => setState(() {
                        _credit = v.first;
                        _paid.text = _credit ? '0' : money(t.total);
                      }),
                    ),
                    if (_credit) ...[
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('paidNow'),
                        controller: _paid,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: s.t('collectNow')),
                        onChanged: (_) => setState(() {}),
                      ),
                      InfoRow(s.t('remaining'), money((t.total - paid).clamp(0, double.infinity))),
                    ],
                    const SizedBox(height: 8),
                    FilledButton(
                      key: const Key('saveSale'),
                      onPressed: _busy || _cart.isEmpty ? null : _save,
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
