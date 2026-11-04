// النسخ الافتراضية لملصقات صنف: كمية آخر استلام (فاتورة شراء) أو 1.
import 'package:drift/drift.dart';

import 'barcode_label_spec.dart';

/// يملأ `copies` لكل صنف له `productId` من كمية آخر بند شراء، ويترك الباقي.
/// قراءة فقط؛ أي فشل يرجع القائمة كما هي (الافتراضي 1).
Future<List<BarcodeLabelItem>> withLastReceiptCopies(
    GeneratedDatabase db, List<BarcodeLabelItem> items) async {
  final ids = {
    for (final i in items)
      if (i.productId != null) i.productId!
  }.toList();
  if (ids.isEmpty) return items;
  try {
    final placeholders = ids.map((_) => '?').join(',');
    final rows = await db.customSelect(
      '''SELECT pi.product_id AS product_id, pi.quantity AS quantity
         FROM purchase_invoice_items pi
         JOIN purchase_invoices inv ON pi.invoice_id = inv.id
         WHERE pi.product_id IN ($placeholders) AND pi.deleted_at IS NULL
         ORDER BY pi.product_id, inv.invoice_date DESC, pi.id DESC''',
      variables: [for (final id in ids) Variable<int>(id)],
    ).get();
    final latest = <int, int>{};
    for (final r in rows) {
      final id = r.read<int>('product_id');
      if (latest.containsKey(id)) continue; // الأحدث أولاً
      final q = (r.data['quantity'] as num?)?.round() ?? 1;
      latest[id] = LabelLayout.clampCopies(q < 1 ? 1 : q);
    }
    return [
      for (final i in items)
        if (i.productId != null && latest.containsKey(i.productId))
          i.withCopies(latest[i.productId]!)
        else
          i,
    ];
  } catch (_) {
    return items;
  }
}
