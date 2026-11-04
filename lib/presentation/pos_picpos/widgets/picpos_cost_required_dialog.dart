import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/utils/number_utils.dart';
import '../../../data/providers/providers.dart' show CostRequiredException;
import '../../../domain/entities/cart_item_entity.dart';

/// نتيجةُ حفظٍ يعيد المحاولةَ بتكاليفَ مؤقتة.
enum CostRetryResult { saved, failed, cancelled }

/// تكلفةٌ صالحةٌ (> 0 ومنتهية) من نصّ الحقل، وإلا `null`. يقبل الأرقامَ
/// العربيّةَ والفاصلةَ العشريّة. لا يُستعمل سعرُ البيع بديلاً أبداً.
double? parseProvisionalCost(String? raw) {
  final v = NumberUtils.tryParseLocale(raw);
  if (v == null || !v.isFinite || v <= 0) return null;
  return v;
}

/// التكلفةُ المُدخَلة لوحدة السطر ⇒ لوحدة الأساس (ما يخزّنه السطرُ والصنف).
double provisionalCostPerBase(
  List<CartItemEntity> items,
  int productId,
  double entered,
) {
  for (final i in items) {
    if (i.productId == productId && i.quantityInBase > 0) {
      return entered / i.quantityInBase;
    }
  }
  return entered;
}

/// يحاول الحفظ؛ كلّما فشل بـ`CostRequiredException` سأل [askCost] وأعاد
/// المحاولةَ بالتكلفة المؤقتة. `null` من [askCost] = إلغاءٌ (السلّةُ سليمة).
/// صنفٌ سُئل عنه ورُفض ثانيةً ⇒ `failed` (لا حلقةَ لا نهائيّة).
Future<CostRetryResult> saveWithCostRetry({
  required Future<bool> Function(Map<int, double> costs) attempt,
  required CostRequiredException? Function() pendingCost,
  required Future<double?> Function(CostRequiredException e) askCost,
}) async {
  final costs = <int, double>{};
  while (true) {
    if (await attempt(Map.unmodifiable(costs))) return CostRetryResult.saved;
    final need = pendingCost();
    if (need == null || costs.containsKey(need.productId)) {
      return CostRetryResult.failed;
    }
    final cost = await askCost(need);
    if (cost == null) return CostRetryResult.cancelled;
    costs[need.productId] = cost;
  }
}

/// «تكلفة الصنف غير معروفة» — يرجع التكلفةَ (> 0) أو `null` عند الإلغاء.
/// الحقلُ فارغٌ عمداً: لا افتراضَ من سعر البيع.
Future<double?> showCostRequiredDialog(
  BuildContext context, {
  required String productName,
}) {
  return showDialog<double>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CostRequiredDialog(productName: productName),
  );
}

class _CostRequiredDialog extends StatefulWidget {
  const _CostRequiredDialog({required this.productName});
  final String productName;

  @override
  State<_CostRequiredDialog> createState() => _CostRequiredDialogState();
}

class _CostRequiredDialogState extends State<_CostRequiredDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = parseProvisionalCost(_controller.text);
    if (v == null) {
      setState(() => _error = tr('أدخل تكلفة أكبر من صفر'));
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('تكلفة الصنف غير معروفة: {p0} — أدخل تكلفة الوحدة لإكمال البيع',
                  {'p0': widget.productName}),
              key: const Key('cost_required_message'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('cost_required_field'),
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩.,٫،]')),
              ],
              decoration: InputDecoration(
                labelText: tr('تكلفة الوحدة'),
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('cost_required_cancel'),
            onPressed: () => Navigator.pop(context),
            child: Text(tr('إلغاء')),
          ),
          ElevatedButton(
            key: const Key('cost_required_confirm'),
            onPressed: _submit,
            child: Text(tr('تأكيد')),
          ),
        ],
      ),
    );
  }
}
