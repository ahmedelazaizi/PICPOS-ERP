import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../services/api/table_bill_token.dart';

/// رقمُ جلسةِ الطاولة المختارة — ليقولَه النادلُ للضيف.
///
/// ⚠️ **ولا يظهر إلّا حين يُطلَب فعلاً**: أي حين يكون الخادمُ منشوراً على
/// دومينٍ عامّ. فعلى شبكة المحلّ الحاجزُ هو الشبكةُ نفسُها، ورقمٌ معروضٌ بلا
/// حاجةٍ إليه يصير ضجيجاً يتعلّم النادلُ تجاهلَه — ثمّ لا يراه يوم يلزم.
///
/// ⚠️ **وهو مقروءٌ من الشاشة لا مطبوعٌ على الورقة.** الورقةُ ملصوقةٌ على
/// الخشب ولا تتغيّر، ورقمٌ مطبوعٌ عليها يُبطل نفسَه: من صوّرها يملكه أبداً.
/// وهذا الرقمُ يتبدّل مع كلّ جلسةٍ بلا عملٍ من أحد — وهو المقصود.
class TableSessionPinCard extends ConsumerWidget {
  const TableSessionPinCard({super.key, required this.tableId});

  final int? tableId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tableId == null) return const SizedBox.shrink();
    final pin = ref.watch(tableSessionPinProvider(tableId!)).asData?.value;
    if (pin == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(PhosphorIconsBold.password,
                  size: 14, color: AppColors.primary),
              SizedBox(width: 6),
              Text(
                'رقمُ الجلسة',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            pin,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
              color: AppColors.primary,
            ),
          ),
          const Text(
            'قُلْه للضيف ليطلب الحساب من هاتفه',
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// رقمُ جلسةِ [tableId]، أو `null` إن لم يكن مطلوباً أو لا طلبَ مفتوحاً.
///
/// ⚠️ **ويُشتقّ على الجهاز لا يُطلَب من الخادم**: مفتاحُ التوقيع مشتقٌّ من
/// بذرة الجهاز، وهي **واحدةٌ لكلّ جهاز**. فعلى جهازٍ عميلٍ لا يساوي الرقمُ
/// المشتقُّ محلّيّاً ما يتحقّق منه الخادم — ولذلك يُشترَط أن يكون هذا الجهازُ
/// هو الخادمَ نفسَه، وإلّا لم يُعرَض رقمٌ كاذب.
final tableSessionPinProvider =
    FutureProvider.autoDispose.family<String?, int>((ref, tableId) async {
  if (!TableBillToken.isReady) return null;

  final db = ref.watch(databaseProvider);
  final published = normalizeTableBillBaseUrl(
    await db.getSettingValue(kTableBillPublicBaseUrlKey),
  );
  if (published == null) return null;
  if ((await db.getSettingValue(kTableBillQrEnabledKey)) != 'true') return null;

  final rows = await (db.select(db.tableOrders)
        ..where((o) => o.tableId.equals(tableId))
        ..where((o) => o.status.isIn(['open', 'bill_requested']))
        ..orderBy([(o) => OrderingTerm.desc(o.openedAt)])
        ..limit(1))
      .get();
  if (rows.isEmpty) return null;

  return TableBillToken.sessionPin(
    orderId: rows.first.id,
    openedAt: rows.first.openedAt,
  );
});
