// «دفاتر السندات» — تبويبٌ داخل سجلّ سندات القبض/الصرف (المرحلة هـ / E3).
//
// الدفترُ مدى أرقامٍ ورقيّة (`range_from..range_to`) بعهدة موظّف. الاستمارةُ
// تقترح الورقةَ التالية الحرّة وتقبل التحرير داخل المدى وحدَه؛ والمكرَّرُ
// والملغى يُرفضان في المحرّك. و«إلغاء ورقة» يحرق الرقمَ (تالف/ملغى) فلا
// يُقترَح ثانيةً.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/voucher_book.dart';
import '../../../web/web_write_guard.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../voucher_sources.dart';

/// دفاترُ نوعٍ واحد (`receipt`|`payment`) — كلُّ الحالات.
final voucherBooksListProvider = FutureProvider.autoDispose
    .family<List<VoucherBook>, String>(
        (ref, type) => ref.watch(databaseProvider).listVoucherBooks(type: type));

final _holdersProvider =
    FutureProvider.autoDispose<List<({int id, String name})>>(
        (ref) => ref.watch(databaseProvider).listVoucherBookHolders());

/// مبدِّلُ التبويب: «السندات» | «دفاتر السندات».
class VoucherRecordsTabSwitch extends StatelessWidget {
  const VoucherRecordsTabSwitch({
    super.key,
    required this.booksTab,
    required this.onChanged,
  });

  final bool booksTab;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      key: const Key('voucher_records_tabs'),
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: false,
          icon: const Icon(PhosphorIconsBold.listBullets, size: 15),
          label: Text(tr('السندات')),
        ),
        ButtonSegment(
          value: true,
          icon: const Icon(PhosphorIconsBold.books, size: 15),
          label: Text(tr('دفاتر السندات'), key: const Key('voucher_records_tab_books')),
        ),
      ],
      selected: {booksTab},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class VoucherBooksPanel extends ConsumerWidget {
  const VoucherBooksPanel({super.key, required this.type});

  /// `receipt` | `payment`.
  final String type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(voucherBooksListProvider(type));
    final holders = <int, String>{
      for (final h in ref.watch(_holdersProvider).value ??
          const <({int id, String name})>[])
        h.id: h.name,
    };
    final books = async.value ?? const <VoucherBook>[];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                type == 'receipt'
                    ? tr('دفاتر سندات القبض')
                    : tr('دفاتر سندات الصرف'),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.picposText),
              ),
            ),
            FilledButton.icon(
              key: const Key('voucher_books_new'),
              onPressed: () => _createBook(context, ref),
              icon: const Icon(PhosphorIconsBold.plus, size: 16),
              label: Text(tr('دفتر جديد')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (async.hasError)
          PicPosEmptyState(
            icon: PhosphorIconsBold.warning,
            title: tr('تعذّرت قراءة الدفاتر'),
            hint: '${async.error}',
          )
        else if (books.isEmpty && !async.isLoading)
          PicPosEmptyState(
            icon: PhosphorIconsBold.books,
            title: tr('لا دفاتر بعد'),
            hint: tr('افتح دفتراً وحدّد مداه وحامله'),
          )
        else
          for (final b in books) _bookCard(context, ref, b, holders),
      ],
    );
  }

  Widget _bookCard(BuildContext context, WidgetRef ref, VoucherBook b,
      Map<int, String> holders) {
    final statusColor = switch (b.status) {
      'active' => AppColors.success,
      'closed' => AppColors.info,
      _ => AppColors.error,
    };
    final statusLabel = switch (b.status) {
      'active' => tr('نشط'),
      'closed' => tr('مغلق'),
      _ => tr('ملغى'),
    };
    return Container(
      key: Key('voucher_book_${b.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.picposHairline),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(b.displayName,
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: context.picposText)),
          Text(tr('المدى {p0}–{p1}', {
            'p0': b.leafLabel(b.rangeFrom),
            'p1': b.leafLabel(b.rangeTo),
          })),
          Text(tr('التالي {p0}', {'p0': b.leafLabel(b.nextNumber)})),
          Text(tr('متبقٍّ {p0}', {'p0': b.remaining})),
          Text(tr('العهدة: {p0}',
              {'p0': holders[b.holderUserId] ?? '—'})),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(statusLabel,
                style: TextStyle(fontSize: 11, color: statusColor)),
          ),
          if (b.status == 'active') ...[
            OutlinedButton.icon(
              key: Key('voucher_book_cancel_leaf_${b.id}'),
              onPressed: () => _cancelLeaf(context, ref, b),
              icon: const Icon(PhosphorIconsBold.prohibit, size: 14),
              label: Text(tr('إلغاء ورقة')),
            ),
            TextButton(
              key: Key('voucher_book_close_${b.id}'),
              onPressed: () => _setStatus(context, ref, b, 'closed'),
              child: Text(tr('إغلاق الدفتر')),
            ),
          ],
        ],
      ),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(voucherBooksListProvider(type));
    ref.invalidate(voucherBookOptionsProvider(type));
  }

  Future<void> _setStatus(
      BuildContext context, WidgetRef ref, VoucherBook b, String status) async {
    if (!WebWriteGuard.allow(context, feature: tr('دفاتر السندات'))) return;
    await ref.read(databaseProvider).setVoucherBookStatus(b.id, status);
    _refresh(ref);
  }

  Future<void> _createBook(BuildContext context, WidgetRef ref) async {
    if (!WebWriteGuard.allow(context, feature: tr('دفاتر السندات'))) return;
    final holders = ref.read(_holdersProvider).value ?? const [];
    final result = await showDialog<_NewBook>(
      context: context,
      builder: (_) => _NewBookDialog(holders: holders),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(databaseProvider).createVoucherBook(
            type: type,
            rangeFrom: result.from,
            rangeTo: result.to,
            prefix: result.prefix,
            label: result.label,
            holderUserId: result.holderUserId,
            branchId: ref.read(activeBranchIdProvider).value,
          );
      _refresh(ref);
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, '$e', type: ToastType.error);
      }
    }
  }

  Future<void> _cancelLeaf(
      BuildContext context, WidgetRef ref, VoucherBook b) async {
    if (!WebWriteGuard.allow(context, feature: tr('دفاتر السندات'))) return;
    final db = ref.read(databaseProvider);
    final suggested = await db.suggestNextVoucherBookNumber(b.id);
    if (!context.mounted) return;
    final result = await showDialog<({int number, String reason})>(
      context: context,
      builder: (_) => _CancelLeafDialog(book: b, suggested: suggested),
    );
    if (result == null || !context.mounted) return;
    try {
      await db.cancelVoucherBookLeaf(
        bookId: b.id,
        number: result.number,
        reason: result.reason,
        userId: ref.read(authProvider).user?.id,
      );
      _refresh(ref);
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, '$e', type: ToastType.error);
      }
    }
  }
}

typedef _NewBook = ({
  int from,
  int to,
  String? prefix,
  String? label,
  int? holderUserId,
});

class _NewBookDialog extends StatefulWidget {
  const _NewBookDialog({required this.holders});
  final List<({int id, String name})> holders;

  @override
  State<_NewBookDialog> createState() => _NewBookDialogState();
}

class _NewBookDialogState extends State<_NewBookDialog> {
  final _prefix = TextEditingController();
  final _label = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  int? _holder;

  @override
  void dispose() {
    _prefix.dispose();
    _label.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label) => InputDecoration(
      labelText: label, isDense: true, border: const OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    final from = int.tryParse(_from.text.trim());
    final to = int.tryParse(_to.text.trim());
    final valid = from != null && to != null && from > 0 && to >= from;
    return AlertDialog(
      title: Text(tr('دفتر سندات جديد')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                key: const Key('voucher_book_label'),
                controller: _label,
                decoration: _dec(tr('اسم الدفتر'))),
            const SizedBox(height: 8),
            TextField(
                key: const Key('voucher_book_prefix'),
                controller: _prefix,
                decoration: _dec(tr('البادئة'))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('voucher_book_from'),
                  controller: _from,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: _dec(tr('من رقم')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('voucher_book_to'),
                  controller: _to,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: _dec(tr('إلى رقم')),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              key: const Key('voucher_book_holder'),
              initialValue: _holder,
              isExpanded: true,
              decoration: _dec(tr('العهدة (المندوب / المحاسب)')),
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(tr('بلا'))),
                for (final h in widget.holders)
                  DropdownMenuItem<int?>(value: h.id, child: Text(h.name)),
              ],
              onChanged: (v) => setState(() => _holder = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('إلغاء'))),
        FilledButton(
          key: const Key('voucher_book_save'),
          onPressed: valid
              ? () => Navigator.of(context).pop((
                    from: from,
                    to: to,
                    prefix: _prefix.text.trim().isEmpty
                        ? null
                        : _prefix.text.trim(),
                    label: _label.text.trim().isEmpty
                        ? null
                        : _label.text.trim(),
                    holderUserId: _holder,
                  ))
              : null,
          child: Text(tr('حفظ')),
        ),
      ],
    );
  }
}

class _CancelLeafDialog extends StatefulWidget {
  const _CancelLeafDialog({required this.book, required this.suggested});
  final VoucherBook book;
  final int? suggested;

  @override
  State<_CancelLeafDialog> createState() => _CancelLeafDialogState();
}

class _CancelLeafDialogState extends State<_CancelLeafDialog> {
  late final _number =
      TextEditingController(text: widget.suggested?.toString() ?? '');
  final _reason = TextEditingController();

  @override
  void dispose() {
    _number.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = int.tryParse(_number.text.trim());
    final valid = n != null && _reason.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(tr('إلغاء ورقة (تالفة / ملغاة)')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('voucher_leaf_number'),
              controller: _number,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('رقم الورقة'),
                helperText: tr('المدى {p0}–{p1}', {
                  'p0': widget.book.rangeFrom,
                  'p1': widget.book.rangeTo
                }),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('voucher_leaf_reason'),
              controller: _reason,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('السبب'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('رجوع'))),
        FilledButton(
          key: const Key('voucher_leaf_confirm'),
          onPressed: valid
              ? () => Navigator.of(context)
                  .pop((number: n, reason: _reason.text.trim()))
              : null,
          child: Text(tr('إلغاء الورقة')),
        ),
      ],
    );
  }
}
