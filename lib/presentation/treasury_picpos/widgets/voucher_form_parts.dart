// أجزاءُ استمارة السند الحديثة — المرحلة هـ / E2 + E3.
//
// • [VoucherDocHeader]: العنوانُ والرقمُ وشارةُ الحالة، على نمط رأس الفاتورة
//   (`picpos_invoice_layout.dart`).
// • [VoucherAccountField]: منتقي حسابٍ من **دليل الحسابات** بالبحث بالرمز أو
//   الاسم — للمستفيد وللخزينة معاً (قرارُ المالك: أيُّ حسابٍ تفصيليٍّ نشط).
// • [VoucherBookSection]: دفترُ السندات ورقمُ الورقة المقترح.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_surface.dart';

/// حسابٌ تفصيليٌّ يُعرَض في المنتقي.
///
/// [partyId] حين يكون الحسابُ حسابَ طرف — فيُختار الطرفُ نفسُه ويبقى كشفه.
/// [safeId] حين يكون حسابَ خزنة — فيمضي السندُ بحركة خزنة؛ وإلّا فهو تحويل.
typedef VoucherAccountOption = ({
  int id,
  String code,
  String name,
  int? partyId,
  int? safeId,
});

/// دفترُ سنداتٍ ساري — [suggested] الورقةُ التالية الحرّة.
typedef VoucherBookOption = ({
  int id,
  String label,
  String? prefix,
  int rangeFrom,
  int rangeTo,
  int? suggested,
});

/// رأسُ المستند: العنوانُ + الرقمُ + شارةُ الحالة (+ شارةُ التحويل).
class VoucherDocHeader extends StatelessWidget {
  const VoucherDocHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.numberText,
    this.isTransfer = false,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final String numberText;
  final bool isTransfer;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(icon, size: 22, color: accent),
        Text(title,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: context.picposText)),
        Text(numberText,
            key: const Key('voucher_header_number'),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.picposMuted)),
        _chip(context, tr('مسودة'), AppColors.warning,
            const Key('voucher_status_chip')),
        if (isTransfer)
          _chip(context, tr('تحويل محاسبي — بلا حركة خزنة'), AppColors.info,
              const Key('voucher_transfer_chip')),
      ],
    );
  }

  Widget _chip(BuildContext context, String text, Color color, Key key) =>
      Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          border: Border.all(color: color.withValues(alpha: .4)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: color)),
      );
}

/// حقلُ حسابٍ يفتح منتقياً قابلاً للبحث.
class VoucherAccountField extends StatelessWidget {
  const VoucherAccountField({
    super.key,
    required this.label,
    required this.accounts,
    required this.selectedId,
    required this.onChanged,
    this.helper,
  });

  final String label;
  final List<VoucherAccountOption> accounts;
  final int? selectedId;
  final ValueChanged<VoucherAccountOption> onChanged;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final picked = accounts.where((a) => a.id == selectedId).firstOrNull;
    return InkWell(
      onTap: () async {
        final chosen = await showVoucherAccountPicker(context,
            title: label, accounts: accounts);
        if (chosen != null) onChanged(chosen);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(PhosphorIconsBold.treeStructure, size: 15),
        ),
        child: Text(
          picked == null
              ? tr('اختر من دليل الحسابات')
              : '${picked.code} · ${trData(picked.name)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: picked == null ? context.picposMuted : context.picposText),
        ),
      ),
    );
  }
}

/// منتقي الحساب — بحثٌ بالرمز أو الاسم (والاسمُ المزروع يُترجَم بـ`trData`).
Future<VoucherAccountOption?> showVoucherAccountPicker(
  BuildContext context, {
  required String title,
  required List<VoucherAccountOption> accounts,
}) {
  return showDialog<VoucherAccountOption>(
    context: context,
    builder: (_) => _AccountPickerDialog(title: title, accounts: accounts),
  );
}

class _AccountPickerDialog extends StatefulWidget {
  const _AccountPickerDialog({required this.title, required this.accounts});
  final String title;
  final List<VoucherAccountOption> accounts;

  @override
  State<_AccountPickerDialog> createState() => _AccountPickerDialogState();
}

class _AccountPickerDialogState extends State<_AccountPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final rows = widget.accounts.where((a) {
      if (q.isEmpty) return true;
      return a.code.toLowerCase().contains(q) ||
          a.name.toLowerCase().contains(q) ||
          trData(a.name).toLowerCase().contains(q);
    }).toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const Key('voucher_account_search'),
              autofocus: true,
              decoration: InputDecoration(
                hintText: tr('ابحث بالرمز أو الاسم'),
                isDense: true,
                prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 15),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text(tr('لا نتائج')))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final a = rows[i];
                        return ListTile(
                          key: Key('voucher_account_${a.id}'),
                          dense: true,
                          // التدرّجُ برمز الحساب يُظهر موضعَه في الشجرة.
                          contentPadding: EdgeInsetsDirectional.only(
                              start: 8.0 * (a.code.length.clamp(1, 6) - 1)),
                          leading: Icon(
                            a.safeId != null
                                ? PhosphorIconsBold.vault
                                : a.partyId != null
                                    ? PhosphorIconsBold.user
                                    : PhosphorIconsBold.fileText,
                            size: 16,
                          ),
                          title: Text('${a.code} · ${trData(a.name)}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.of(context).pop(a),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('إلغاء')),
        ),
      ],
    );
  }
}

/// دفترُ السندات + رقمُ الورقة. الرقمُ يُقترَح ويُحرَّر **داخل المدى وحدَه**.
class VoucherBookSection extends StatelessWidget {
  const VoucherBookSection({
    super.key,
    required this.books,
    required this.bookId,
    required this.numberCtrl,
    required this.onBookChanged,
    required this.onNumberChanged,
  });

  final List<VoucherBookOption> books;
  final int? bookId;
  final TextEditingController numberCtrl;
  final ValueChanged<int?> onBookChanged;
  final VoidCallback onNumberChanged;

  @override
  Widget build(BuildContext context) {
    final book = books.where((b) => b.id == bookId).firstOrNull;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<int?>(
            key: const Key('voucher_book'),
            initialValue: bookId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr('دفتر السندات'),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<int?>(
                  value: null, child: Text(tr('بلا دفتر'))),
              for (final b in books)
                DropdownMenuItem<int?>(value: b.id, child: Text(b.label)),
            ],
            onChanged: onBookChanged,
          ),
        ),
        if (book != null)
          SizedBox(
            width: 200,
            child: TextField(
              key: const Key('voucher_book_number'),
              controller: numberCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => onNumberChanged(),
              decoration: InputDecoration(
                labelText: tr('رقم الورقة'),
                helperText: tr('المدى {p0}–{p1}',
                    {'p0': book.rangeFrom, 'p1': book.rangeTo}),
                prefixText: book.prefix,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
      ],
    );
  }
}
