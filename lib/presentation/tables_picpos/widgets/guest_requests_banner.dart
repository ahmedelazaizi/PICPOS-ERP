import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/guest_order_requests_provider.dart';
import '../../../data/providers/providers.dart';
import '../../../services/api/api_handler_base.dart';
import '../../../services/guest_order_approval.dart';
import '../../../services/guest_order_requests.dart';
import '../../../services/network_service.dart';
import '../../../services/server_proxy.dart';

/// شريطٌ يظهر **فقط** حين ينتظر طلبُ ضيفٍ اعتماداً.
///
/// ⚠️ **ولا يظهر فارغاً**: شريطٌ دائمٌ يقول «لا طلبات» يصير جزءاً من الخلفيّة
/// فلا يُرى حين يمتلئ. وظهورُه هو الإشعار.
class GuestRequestsBanner extends ConsumerWidget {
  const GuestRequestsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(guestOrderRequestsProvider).asData?.value;
    if (pending == null || pending.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => GuestRequestsDialog.show(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(PhosphorIconsBold.bellRinging,
                    color: AppColors.warning, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${pending.length} طلبُ ضيفٍ ينتظر الاعتماد '
                    '(${pending.map((r) => r.tableName).toSet().join('، ')})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                 Text(tr('مراجعة'),
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    )),
                const Icon(PhosphorIconsBold.caretLeft,
                    color: AppColors.warning, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// مراجعةُ طلبات الضيوف — اعتمادٌ أو رفض.
class GuestRequestsDialog extends ConsumerWidget {
  const GuestRequestsDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
        context: context,
        builder: (_) => const GuestRequestsDialog(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending =
        ref.watch(guestOrderRequestsProvider).asData?.value ?? const [];
    final names = ref.watch(_productNamesProvider).asData?.value ?? const {};

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title:  Row(
          children: [
            const Icon(PhosphorIconsBold.bellRinging, color: AppColors.warning),
            const SizedBox(width: 8),
            Text(tr('طلباتُ الضيوف')),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: pending.isEmpty
              ?  Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(tr('لا طلباتٍ معلَّقة'), textAlign: TextAlign.center),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: pending.length,
                  separatorBuilder: (_, _) => const Divider(height: 18),
                  itemBuilder: (context, i) =>
                      _RequestTile(request: pending[i], names: names),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إغلاق')),
          ),
        ],
      ),
    );
  }
}

class _RequestTile extends ConsumerStatefulWidget {
  const _RequestTile({required this.request, required this.names});

  final GuestOrderRequest request;
  final Map<int, String> names;

  @override
  ConsumerState<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<_RequestTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                r.tableName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${r.at.hour.toString().padLeft(2, '0')}:'
              '${r.at.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final line in r.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '• ${widget.names[line.productId] ?? 'صنف #${line.productId}'}'
              ' × ${line.quantity.toStringAsFixed(line.quantity % 1 == 0 ? 0 : 2)}'
              '${line.note == null ? '' : ' — ${line.note}'}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _act(approve: false),
                icon: const Icon(PhosphorIconsBold.x, size: 15),
                label:  Text(tr('رفض')),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : () => _act(approve: true),
                icon: const Icon(PhosphorIconsBold.check, size: 15),
                label:  Text(tr('اعتماد')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// ⚠️ **مسارانِ ومحرّكٌ واحد.** جهازُ الخادم يعتمد من الذاكرة مباشرةً —
  /// الطابورُ عنده — وجهازُ العميل يسأل الخادم. وكلاهما ينتهي إلى
  /// [GuestOrderApproval] نفسِها، فلا يختلف ما يُكتَب باختلاف الجهاز.
  Future<void> _act({required bool approve}) async {
    setState(() => _busy = true);
    String? error;

    if (NetworkService.instance.isServer) {
      final service = GuestOrderApproval(ref.read(databaseProvider));
      if (approve) {
        error = switch (await service.approve(widget.request.id)) {
          GuestApprovalOutcome.approved => null,
          GuestApprovalOutcome.notPending => tr('الطلبُ لم يعد معلَّقاً'),
          GuestApprovalOutcome.orderClosed => tr('الطاولةُ أُغلقت'),
          GuestApprovalOutcome.failed => tr('تعذّر الاعتماد'),
        };
      } else {
        error = service.reject(widget.request.id) ? null : tr('الطلبُ لم يعد معلَّقاً');
      }
      // ⚠️ والبثُّ من هنا: الكتابةُ لم تمرّ بطبقة HTTP، فبدونه لا يعلم أيُّ
      // جهازٍ مقترنٍ بالبند الجديد حتى دورةِ المزامنة التالية.
      if (error == null) {
        ApiHandlerBase.notifyTableChangedFromAdmin('table_orders');
        ApiHandlerBase.notifyTableChangedFromAdmin('restaurant_tables');
      }
    } else {
      error = approve
          ? await ServerProxy.instance.approveGuestOrderRequest(widget.request.id)
          : await ServerProxy.instance.rejectGuestOrderRequest(widget.request.id);
      ref.invalidate(guestOrderRequestsProvider);
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) AppToast.show(context, error);
  }
}

/// أسماءُ الأصناف — الطابورُ يحمل معرِّفاتٍ لا أسماء.
final _productNamesProvider = FutureProvider.autoDispose<Map<int, String>>(
  (ref) async {
    final db = ref.watch(databaseProvider);
    return {for (final p in await db.select(db.products).get()) p.id: p.name};
  },
);
