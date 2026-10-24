// فرعُ جهاز العميل: رقمُه ومخزنُه الافتراضيّ وبادئاتُ ترقيم المستندات من رمز الفرع.
//
// خرج حرفياً من `SetupFinishRunner._clientBranch` ليستعمله المعالجان (‏القديمُ
// والجديدُ) بلا نسخةٍ ثانية. الترتيبُ والمفاتيحُ كما كانت.
library;

import '../../../data/providers/providers.dart' show Branche;
import 'setup_finish_runner.dart';

Future<void> writeClientBranchSettings(
  SetupPersistence p, {
  required int branchId,
  required List<Branche> syncedBranches,
}) async {
  await p.saveClientBranchId(branchId);
  final warehouses = await p.getWarehousesByBranch(branchId);
  final clientWarehouseId = warehouses.isEmpty
      ? null
      : warehouses.where((w) => w.isDefault).map((w) => w.id).firstOrNull ??
          warehouses.first.id;
  if (clientWarehouseId != null) {
    await p.saveSetting(
      'pos_default_warehouse_branch_$branchId',
      clientWarehouseId.toString(),
    );
    await p.saveSetting(
      'pos_default_warehouse_id',
      clientWarehouseId.toString(),
    );
  }
  Branche? selected;
  for (final b in syncedBranches) {
    if (b.id == branchId) {
      selected = b;
      break;
    }
  }
  final code = selected?.code?.trim() ?? '';
  if (code.isEmpty) return;
  await p.saveSetting('invoice_code_prefix', '$code-POS');
  await p.saveSetting('prefix_sales_pos', '$code-POS');
  await p.saveSetting('prefix_sales_manual', '$code-SINV');
  await p.saveSetting('prefix_sales_return', '$code-SRET');
  await p.saveSetting('prefix_purchase', '$code-PINV');
  await p.saveSetting('prefix_purchase_return', '$code-PRET');
  await p.saveSetting('prefix_receipt_voucher', '$code-RCPT');
  await p.saveSetting('prefix_payment_voucher', '$code-PMT');
  await p.saveSetting('prefix_quotation', '$code-QUOT');
}
