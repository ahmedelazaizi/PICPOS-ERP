// المرحلة 7: عرضُ مزوّد المرحلة 6ب داخل حوار «مراجعة الأرصدة».
//
// قسمُ «الخزائن» في الحوار يقارن رصيدَ الصندوق بسجلّ حركاته فقط؛ أمّا مقارنةُ
// الصندوق بحسابه في الأستاذ — ومعها حسابُ النقدية الأب 1111 غيرُ المرتبط —
// فكان مزوّدُها `cashBoxLedgerReconciliationProvider` بلا أيّ مستهلك، فلا
// يظهر 1111 مهما كان رصيده. قراءةٌ فقط: لا إصلاحَ ولا كتابة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_surface.dart';

class CashBoxLedgerReconciliationCard extends ConsumerWidget {
  const CashBoxLedgerReconciliationCard({super.key});

  static bool _hasDifference(CashBoxLedgerComparison c) =>
      c.difference.abs() >= 0.005;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cashBoxLedgerReconciliationProvider);
    final rows = async.value ?? const <CashBoxLedgerComparison>[];
    final issues = rows.where(_hasDifference).length;
    final hasIssues = issues > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(
          hasIssues ? PhosphorIconsBold.warning : PhosphorIconsBold.checkCircle,
          color: hasIssues ? AppColors.warning : AppColors.success,
          size: 20,
        ),
        title: Text(tr('الخزائن مقابل دفتر الأستاذ'),
            style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        subtitle: Text(
          async.hasError
              ? tr('تعذّرت قراءة الأستاذ')
              : tr('تم فحص {p0} — {p1} فرق{p2}',
                  {'p0': rows.length, 'p1': issues, 'p2': ''}),
          style: GoogleFonts.cairo(fontSize: 11, color: context.picposMuted),
        ),
        children: [for (final c in rows) _row(c)],
      ),
    );
  }

  Widget _row(CashBoxLedgerComparison c) {
    String f(double v) => v.toStringAsFixed(AppConstants.decimalPlaces);
    final title = c.accountCode == null
        ? c.displayName
        : '${c.displayName} — ${c.accountCode}';
    return ListTile(
      dense: true,
      title: Text(title, style: GoogleFonts.cairo(fontSize: 12)),
      subtitle: Text(
        tr('الصندوق: {p0} | الأستاذ: {p1} | فرق: {p2}',
            {'p0': f(c.safeBalance), 'p1': f(c.ledgerBalance), 'p2': f(c.difference)}),
        style: GoogleFonts.cairo(
            fontSize: 11,
            color: _hasDifference(c) ? AppColors.error : AppColors.success),
      ),
    );
  }
}
