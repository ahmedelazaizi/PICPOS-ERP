// J3 — اسمُ العميل لمرّةٍ واحدة في البيع السريع (PicPos).
//
// حين يكون طرفُ الفاتورة «عميل نقدي» النظاميّ (أو بيعاً بلا عميل)، يكتب
// الكاشير اسماً حرّاً اختياريّاً (+ هاتفاً) يُخزَّن على الفاتورة عبر حقلَي
// السلّة القائمين (`adhocCustomerName/Phone` ← `sales_invoices.adhoc_*`)
// ويُطبَع بدل «عميل نقدي». لا مسارَ حفظٍ جديد: `checkout_controller` يمرّرهما
// أصلاً.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../pos/providers/cart_controller.dart';

/// معرّفُ «عميل نقدي» النظاميّ — `null` حين لا يوجد (عميلٌ قبل أوّل سحب).
final posCashCustomerIdProvider = FutureProvider.autoDispose<int?>(
    (ref) => ref.watch(databaseProvider).systemPartyId(kSystemRoleCashCustomer));

/// زرُّ «اسم لمرّةٍ واحدة» بجوار سطر العميل — يظهر للعميل النقديّ وللبيع
/// بلا عميل فقط.
class PicPosOneTimeCustomerButton extends ConsumerWidget {
  const PicPosOneTimeCustomerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    final cashId = ref.watch(posCashCustomerIdProvider).value;
    final eligible =
        cart.selectedCustomerId == null || cart.selectedCustomerId == cashId;
    if (!eligible) return const SizedBox.shrink();
    final typed = cart.adhocCustomerName;
    final hasName = typed != null && typed.trim().isNotEmpty;
    return IconButton(
      key: const Key('picpos_one_time_customer_button'),
      tooltip: hasName ? typed : tr('اسم العميل (اختياري)'),
      visualDensity: VisualDensity.compact,
      icon: Icon(
        hasName ? PhosphorIconsBold.userCheck : PhosphorIconsBold.pencilSimple,
        size: 15,
        color: hasName ? AppColors.primary : AppColors.textMuted,
      ),
      onPressed: () async {
        final result = await showDialog<({String name, String phone})>(
          context: context,
          builder: (_) => _OneTimeCustomerDialog(
              name: typed ?? '', phone: cart.adhocCustomerPhone ?? ''),
        );
        if (result == null) return;
        String? clean(String v) => v.trim().isEmpty ? null : v.trim();
        ref.read(cartControllerProvider.notifier).setAdhocCustomer(
              name: clean(result.name),
              phone: clean(result.phone),
              note: cart.adhocCustomerNote,
            );
      },
    );
  }
}

class _OneTimeCustomerDialog extends StatefulWidget {
  const _OneTimeCustomerDialog({required this.name, required this.phone});
  final String name;
  final String phone;

  @override
  State<_OneTimeCustomerDialog> createState() => _OneTimeCustomerDialogState();
}

class _OneTimeCustomerDialogState extends State<_OneTimeCustomerDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _phone = TextEditingController(text: widget.phone);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('اسم العميل (اختياري)')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('picpos_pos_one_time_name'),
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: tr('اسم العميل')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: tr('الهاتف (اختياري)')),
            ),
            const SizedBox(height: 8),
            Text(tr('يُطبع الاسم على الفاتورة بدل «عميل نقدي»'),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(tr('إلغاء'))),
        FilledButton(
          onPressed: () => Navigator.pop<({String name, String phone})>(
              context, (name: _name.text, phone: _phone.text)),
          child: Text(tr('حفظ')),
        ),
      ],
    );
  }
}
