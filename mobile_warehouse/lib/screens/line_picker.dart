import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../sync/wh_ops.dart';
import '../sync/wh_outbox.dart';
import '../widgets/wh_widgets.dart';

class PickedLine {
  PickedLine({required this.productId, required this.name, required this.qty, this.batch, this.expiry}) : id = newId('line');
  final String id;
  final int productId;
  final String name;
  final String qty;
  final String? batch;
  final String? expiry;

  Map<String, Object?> toJson() => {
        'lineGlobalId': id,
        'productId': productId,
        'quantity': qty,
        if (batch != null) 'batchNumber': batch,
        if (expiry != null) 'expiryDate': expiry,
      };
}

/// Scan an item, enter a quantity, repeat. Resolves the item through the
/// office (`itemsByBarcode`), so it needs a connection to ADD a line; the
/// finished document then goes through the outbox. [askBatch] also asks for
/// an optional batch and expiry (incoming vouchers).
class LinePicker extends StatefulWidget {
  const LinePicker({super.key, required this.ops, required this.lines, required this.onChanged, this.askBatch = false});
  final WhOps ops;
  final List<PickedLine> lines;
  final VoidCallback onChanged;
  final bool askBatch;
  @override
  State<LinePicker> createState() => _LinePickerState();
}

class _LinePickerState extends State<LinePicker> {
  Future<void> _scanned(String code) async {
    final t = S.of(context);
    try {
      final items = await widget.ops.online((c) => c.itemsByBarcode(code));
      if (!mounted) return;
      if (items.isEmpty) return showDone(context, t('lookupNone'));
      final item = items.first;
      final qty = await askQuantity(context, title: item.name);
      if (qty == null || !mounted) return;
      String? batch, expiry;
      if (widget.askBatch) {
        final r = await showDialog<(String, String)>(context: context, builder: (_) => const _BatchDialog());
        if (r != null && r.$1.isNotEmpty) {
          batch = r.$1;
          expiry = r.$2.isEmpty ? null : r.$2;
        }
      }
      widget.lines.add(PickedLine(productId: item.id, name: item.name, qty: qty, batch: batch, expiry: expiry));
      widget.onChanged();
    } on Object catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ScanField(ops: widget.ops, onScan: _scanned),
      const SizedBox(height: PicPosSpacing.sm),
      for (final l in widget.lines)
        ListTile(
          key: Key('picked.${l.productId}'),
          title: Text('${l.name} × ${l.qty}'),
          subtitle: l.batch == null ? null : Text('${l.batch} ${l.expiry ?? ''}', textDirection: TextDirection.ltr),
          trailing: IconButton(
            tooltip: t('remove'),
            onPressed: () {
              widget.lines.remove(l);
              widget.onChanged();
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ),
    ]);
  }
}

class _BatchDialog extends StatefulWidget {
  const _BatchDialog();
  @override
  State<_BatchDialog> createState() => _BatchDialogState();
}

class _BatchDialogState extends State<_BatchDialog> {
  final _b = TextEditingController();
  final _e = TextEditingController();
  @override
  void dispose() {
    _b.dispose();
    _e.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return AlertDialog(
      title: Text(t('batchOptional')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _b, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: t('batchNo'))),
        TextField(controller: _e, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: t('expiryDate'), hintText: '2027-01-31')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, ('', '')), child: Text(t('skip'))),
        FilledButton(onPressed: () => Navigator.pop(context, (_b.text.trim(), _e.text.trim())), child: Text(t('add'))),
      ],
    );
  }
}
