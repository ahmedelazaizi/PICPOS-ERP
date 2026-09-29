import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/party_balance_mismatch.dart';
import '../../../domain/repositories/parties_repository.dart';

void showPartyBalanceRepairDialog(
  BuildContext context, {
  required IPartiesRepository repository,
  required int userId,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => _PartyBalanceRepairDialog(
      repository: repository,
      userId: userId,
    ),
  );
}

class _PartyBalanceRepairDialog extends StatefulWidget {
  final IPartiesRepository repository;
  final int userId;

  const _PartyBalanceRepairDialog({
    required this.repository,
    required this.userId,
  });

  @override
  State<_PartyBalanceRepairDialog> createState() => _PartyBalanceRepairDialogState();
}

class _PartyBalanceRepairDialogState extends State<_PartyBalanceRepairDialog> {
  late Future<List<PartyBalanceMismatch>> _mismatches;
  bool _repairing = false;

  @override
  void initState() {
    super.initState();
    _mismatches = widget.repository.getPartyBalanceMismatches();
  }

  Future<void> _repair() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title:  Text(tr('تأكيد إعادة الاحتساب')),
        content:  Text(
          tr('سيتم تحديث أرصدة الأطراف لتطابق القيود المرحّلة غير المحذوفة. هل تريد المتابعة؟'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:  Text(tr('إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child:  Text(tr('إعادة الاحتساب')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _repairing = true);
    try {
      final repaired = await widget.repository
          .recalculatePartyBalancesFromLedger(widget.userId);
      if (!mounted) return;
      setState(() {
        _repairing = false;
        _mismatches = widget.repository.getPartyBalanceMismatches();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('تم إصلاح {repaired} من أرصدة الأطراف', {'repaired': repaired}))),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _repairing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('تعذر الإصلاح: {error}', {'error': error})),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:  Text(tr('تدقيق أرصدة الأطراف')),
      content: SizedBox(
        width: 620,
        child: FutureBuilder<List<PartyBalanceMismatch>>(
          future: _mismatches,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text(tr('تعذر تحميل الكاشف: {p0}', {'p0': snapshot.error}));
            }
            final rows = snapshot.data ?? const <PartyBalanceMismatch>[];
            if (rows.isEmpty) {
              return  Text(tr('لا توجد فروقات بين أرصدة الأطراف والأستاذ.'));
            }
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('عدد الفروقات: {p0}', {'p0': rows.length})),
                  const SizedBox(height: 8),
                  ...rows.map(
                    (row) => ListTile(
                      dense: true,
                      title: Text(row.partyName),
                      subtitle: Text(
                        tr('الرصيد: {p0} | الأستاذ: {p1}', {'p0': row.cardBalance.toStringAsFixed(2), 'p1': row.glBalance.toStringAsFixed(2)}),
                      ),
                      trailing: Text(row.delta.toStringAsFixed(2)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _repairing ? null : () => Navigator.pop(context),
          child:  Text(tr('إغلاق')),
        ),
        FilledButton.icon(
          onPressed: _repairing ? null : _repair,
          icon: _repairing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.autorenew),
          label:  Text(tr('إعادة احتساب الأرصدة من الأستاذ')),
        ),
      ],
    );
  }
}
