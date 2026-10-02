import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'common.dart';

/// Collection (receipt voucher) with a leaf from the rep's voucher book.
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key, required this.customerGlobalId});
  final String customerGlobalId;
  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final _amount = TextEditingController();
  final _leaf = TextEditingController();
  List<Map<String, Object?>> _books = [];
  Map<String, Object?>? _book;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  Future<void> _load() async {
    final c = AppScope.of(context);
    final books = await c.voucherBooks();
    final first = books.isEmpty ? null : books.first;
    final leaf = first == null ? null : await c.suggestLeaf(first);
    if (!mounted) return;
    setState(() {
      _books = books;
      _book = first;
      _leaf.text = leaf?.toString() ?? '';
    });
  }

  Future<void> _selectBook(Map<String, Object?>? b) async {
    if (b == null) return;
    final leaf = await AppScope.of(context).suggestLeaf(b);
    setState(() {
      _book = b;
      _leaf.text = leaf?.toString() ?? '';
    });
  }

  Future<void> _save() async {
    final s = S.of(context);
    try {
      final e = await AppScope.of(context).createCollection(
        customerGlobalId: widget.customerGlobalId,
        amount: double.tryParse(_amount.text) ?? 0,
        book: _book!,
        leaf: int.tryParse(_leaf.text) ?? -1,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${s.t('saved')} — ${_book!['prefix'] ?? ''}${e.payload['bookNumber']}')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('collect'))),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : _books.isEmpty
                ? Center(child: Text(s.t('noBook')))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        key: const Key('amount'),
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: s.t('amount')),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<Map<String, Object?>>(
                        initialValue: _book,
                        decoration: InputDecoration(labelText: s.t('voucherBook')),
                        items: [
                          for (final b in _books)
                            DropdownMenuItem(
                              value: b,
                              child: Text('${b['label'] ?? ''} ${b['prefix'] ?? ''}${b['rangeFrom']}–${b['rangeTo']}'),
                            ),
                        ],
                        onChanged: _selectBook,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('leaf'),
                        controller: _leaf,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: s.t('leafNumber')),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(key: const Key('saveCollection'), onPressed: _save, child: Text(s.t('save'))),
                    ],
                  ),
      ),
    );
  }
}
