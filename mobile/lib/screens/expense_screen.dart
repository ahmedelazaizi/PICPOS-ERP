import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

import '../l10n/strings.dart';
import '../state/app_controller.dart';
import 'common.dart';

/// Takes a receipt photo and stores it in app-private storage; returns its
/// path, or null when the rep cancelled. Throws `AppFailure('photoTooLarge')`.
typedef PhotoTaker = Future<String?> Function(String globalIdHint);

/// Camera → JPEG (downscaled, quality 70) copied under the app's database
/// directory (`receipts/`), bounded to [kMaxExpensePhotoBytes].
Future<String?> takeReceiptPhoto(String name) async {
  final shot = await ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: 1280,
    maxHeight: 1280,
    imageQuality: 70,
    requestFullMetadata: false,
  );
  if (shot == null) return null;
  if (await shot.length() > kMaxExpensePhotoBytes) throw AppFailure('photoTooLarge');
  final dir = Directory(p.join(await getDatabasesPath(), 'receipts'));
  await dir.create(recursive: true);
  final path = p.join(dir.path, '$name.jpg');
  await shot.saveTo(path);
  return path;
}

/// K-1 — expense paid from the rep's custody with a leaf of his payment
/// voucher book (category from the desktop list, amount, note, optional
/// receipt photo). Saved offline; printed on save like the other vouchers.
class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key, this.takePhoto = takeReceiptPhoto});
  final PhotoTaker takePhoto;
  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _leaf = TextEditingController();
  List<Map<String, Object?>> _categories = [];
  List<Map<String, Object?>> _books = [];
  String? _category;
  Map<String, Object?>? _book;
  double? _custody;
  String _policy = 'flag';
  String? _photo;
  bool _loaded = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _leaf.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = AppScope.of(context);
    final cats = await c.expenseCategories();
    final books = await c.paymentBooks();
    final first = books.isEmpty ? null : books.first;
    final leaf = first == null ? null : await c.suggestLeaf(first);
    final custody = await c.custodyBalance();
    final policy = await c.overCustodyPolicy();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _books = books;
      _category = cats.isEmpty ? null : cats.first['globalId'] as String;
      _book = first;
      _leaf.text = leaf?.toString() ?? '';
      _custody = custody;
      _policy = policy;
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

  Future<void> _photoTap() async {
    try {
      final path = await widget.takePhoto(DateTime.now().millisecondsSinceEpoch.toString());
      if (path != null && mounted) setState(() => _photo = path);
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  double get _amountValue => double.tryParse(_amount.text.trim()) ?? 0;

  bool get _over => _custody != null && _amountValue > 0 && _custody! - _amountValue < -0.005;

  Future<void> _save() async {
    final s = S.of(context);
    if (_category == null) return showFailure(context, AppFailure('categoryRequired'));
    if (_amountValue <= 0) return showFailure(context, AppFailure('amountRequired'));
    setState(() => _saving = true);
    try {
      final e = await AppScope.of(context).createExpense(
        categoryGlobalId: _category!,
        amount: _amountValue,
        book: _book!,
        leaf: int.tryParse(_leaf.text) ?? -1,
        note: _note.text,
        photoPath: _photo,
      );
      if (!mounted) return;
      final flag = e.payload['_overCustody'] == true ? ' · ${s.t('overCustody')}' : '';
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${s.t('saved')} — ${_book!['prefix'] ?? ''}${e.payload['bookNumber']}$flag')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final en = !s.isAr;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('expense'))),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : _books.isEmpty
                ? Center(child: Text(s.t('noPaymentBook')))
                : _categories.isEmpty
                    ? Center(child: Text(s.t('noExpenseCategories')))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          InfoRow(s.t('custodyBalance'), _custody == null ? s.t('custodyUnknown') : money(_custody!)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            key: const Key('expenseCategory'),
                            initialValue: _category,
                            decoration: InputDecoration(labelText: s.t('expenseCategory')),
                            items: [
                              for (final c in _categories)
                                DropdownMenuItem(
                                  value: c['globalId'] as String,
                                  child: Text('${en && c['nameEn'] != null ? c['nameEn'] : c['name']}'),
                                ),
                            ],
                            onChanged: (v) => setState(() => _category = v),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('expenseAmount'),
                            controller: _amount,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(labelText: s.t('amount')),
                            onChanged: (_) => setState(() {}),
                          ),
                          if (_over)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                s.t(_policy == 'reject' ? 'custodyExceeded' : 'overCustodyWarn'),
                                key: const Key('overCustodyWarning'),
                                style: TextStyle(color: cs.error),
                              ),
                            ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('expenseNote'),
                            controller: _note,
                            maxLength: 500,
                            decoration: InputDecoration(labelText: s.t('note')),
                          ),
                          DropdownButtonFormField<Map<String, Object?>>(
                            initialValue: _book,
                            decoration: InputDecoration(labelText: s.t('paymentBook')),
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
                            key: const Key('expenseLeaf'),
                            controller: _leaf,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: s.t('leafNumber')),
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            OutlinedButton.icon(
                              key: const Key('takePhoto'),
                              onPressed: _photoTap,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: Text(s.t(_photo == null ? 'takePhoto' : 'receiptPhoto')),
                            ),
                            if (_photo != null) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.check_circle, color: Colors.green),
                              IconButton(
                                tooltip: s.t('removePhoto'),
                                onPressed: () => setState(() => _photo = null),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ]),
                          const SizedBox(height: 16),
                          FilledButton(
                            key: const Key('saveExpense'),
                            onPressed: _saving ? null : _save,
                            child: Text(s.t('save')),
                          ),
                        ],
                      ),
      ),
    );
  }
}
