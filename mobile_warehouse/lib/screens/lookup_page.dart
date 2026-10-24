import 'package:flutter/material.dart';
import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../scan/camera_scan_view.dart';
import '../session/wh_session.dart';

/// Read-only item and stock lookup. Needs the desktop (no offline catalog yet);
/// when it cannot be reached it says so instead of showing stale numbers.
/// A hardware (wedge) scanner types the code and presses Enter into the field.
class LookupPage extends StatefulWidget {
  const LookupPage({super.key, required this.session, this.scanner = scanWithCamera});
  final WhSession session;
  final Future<String?> Function(BuildContext context, {bool qr}) scanner;

  @override
  State<LookupPage> createState() => _LookupPageState();
}

class _LookupPageState extends State<LookupPage> {
  final _field = TextEditingController();
  List<WhItem>? _items;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  bool _looksLikeBarcode(String s) => RegExp(r'^[0-9A-Za-z\-]{6,}$').hasMatch(s) && RegExp(r'\d').hasMatch(s);

  Future<void> _search([String? scanned]) async {
    final text = (scanned ?? _field.text).trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = widget.session.client!;
      final items = scanned != null || _looksLikeBarcode(text)
          ? await api.itemsByBarcode(normalizeScan(text))
          : await api.searchItems(text);
      if (mounted) setState(() => _items = items);
    } on Object catch (e) {
      await widget.session.refresh().catchError((_) {}); // revoked/expired -> routed by the session
      if (mounted) {
        setState(() {
          _items = null;
          _error = errorCode(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _camera() async {
    final code = await widget.scanner(context, qr: false);
    if (code == null || !mounted) return;
    _field.text = code;
    await _search(code);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PicPosPageHeader(title: t('navLookup'), subtitle: t('lookupSub'), icon: Icons.qr_code_scanner),
      Padding(
        padding: const EdgeInsets.all(PicPosSpacing.lg),
        child: Row(children: [
          Expanded(
            child: TextField(
              key: const Key('lookup.field'),
              controller: _field,
              autofocus: true,
              textDirection: TextDirection.ltr,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(labelText: t('scanOrType'), prefixIcon: const Icon(Icons.search)),
            ),
          ),
          const SizedBox(width: PicPosSpacing.sm),
          IconButton.filled(
            key: const Key('lookup.camera'),
            tooltip: t('scanCamera'),
            onPressed: _busy ? null : _camera,
            icon: const Icon(Icons.photo_camera_outlined),
          ),
        ]),
      ),
      Expanded(
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(PicPosSpacing.lg),
                    child: Text(S.errorText(context, _error!),
                        key: const Key('lookup.error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  )
                : _items == null
                    ? EmptyState(icon: Icons.qr_code_scanner, title: t('navLookup'), message: t('lookupHint'))
                    : _items!.isEmpty
                        ? EmptyState(icon: Icons.search_off, title: t('navLookup'), message: t('lookupNone'))
                        : ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
                            for (final item in _items!)
                              PicPosBlock(
                                title: item.name,
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${item.code}${item.barcode == null ? '' : ' · ${item.barcode}'}',
                                      textDirection: TextDirection.ltr, style: tt.bodySmall),
                                  const SizedBox(height: PicPosSpacing.sm),
                                  if (item.stock.isEmpty) Text(t('noStockInScope')),
                                  for (final s in item.stock)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(children: [
                                        Expanded(child: Text(t('stockIn', {'wh': s.warehouse ?? '${s.warehouseId}'}))),
                                        Text(s.quantity, textDirection: TextDirection.ltr, style: tt.titleMedium),
                                      ]),
                                    ),
                                ]),
                              ),
                          ]),
      ),
    ]);
  }
}
