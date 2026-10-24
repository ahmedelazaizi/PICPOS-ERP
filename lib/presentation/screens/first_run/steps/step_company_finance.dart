// العملةُ والضريبةُ والفوترةُ الإلكترونيّة والسنةُ الماليّة.
//
// UX-001/UX-004: الشرائحُ هي `CurrencyInfo.all` بالضبط (JOD وEGP) — لا رمزَ
// يتحوّل صامتاً إلى JOD — **بلا اختيارٍ مسبق**. والعملةُ تشتقّ افتراضاتِ
// الضريبة والفوترة ما لم يغيّرها المستخدمُ بيده.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart' show CurrencyInfo;
import '../../../../core/i18n/tr.dart';
import '../../../../domain/models/first_run/first_run_currency.dart';
import '../../../picpos_shell/picpos_surface.dart';
import '../first_run_controller.dart';
import '../widgets/first_run_callout.dart';
import '../widgets/first_run_choice_card.dart';
import '../widgets/first_run_field.dart';

String _eInvoiceTitle(FirstRunEInvoice e) => switch (e) {
      FirstRunEInvoice.jordan => tr('الأردن — JoFotara'),
      FirstRunEInvoice.egypt => tr('مصر — ETA'),
      FirstRunEInvoice.none => tr('بدون'),
    };

String _eInvoiceSub(FirstRunEInvoice e) => switch (e) {
      FirstRunEInvoice.jordan => tr('نظام الفوترة الوطني الأردني'),
      FirstRunEInvoice.egypt => tr('منظومة الفاتورة الإلكترونية المصرية'),
      FirstRunEInvoice.none => tr('يمكن تفعيلها لاحقاً من الإعدادات'),
    };

class StepCompanyFinance extends ConsumerWidget {
  const StepCompanyFinance({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(firstRunControllerProvider.select((s) => s.draft));
    final ctl = ref.read(firstRunControllerProvider.notifier);
    final defaults = currencyDefaultsFor(d.currency);
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            t,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: context.picposText,
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label(tr('العملة الأساسية')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in CurrencyInfo.all)
              ChoiceChip(
                key: Key('first_run_currency_${c.code}'),
                selected: d.currency == c.code,
                onSelected: (_) => ctl.setCurrency(c.code),
                label: Text('${c.nameAr} (${c.code})'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (defaults != null)
          Text(
            tr('الخانات العشرية: {p0} — تتبع العملة تلقائياً',
                {'p0': defaults.decimals}),
            key: const Key('first_run_currency_decimals'),
            style: TextStyle(fontSize: 12, color: context.picposMuted),
          ),
        const SizedBox(height: 8),
        FirstRunCallout(
          title: tr('العملة قرار نهائي'),
          body: tr('تدخل كلَّ فاتورةٍ وكلَّ قيدٍ محاسبيّ، ولا تحويلَ بأثرٍ رجعيّ. تبديلُها بعد أوّل فاتورةٍ يترك دفتراً بعملتَين.'),
          tone: FirstRunTone.danger,
          icon: Icons.warning_amber_rounded,
        ),
        const SizedBox(height: 18),
        label(tr('ضريبة القيمة المضافة')),
        SwitchListTile(
          key: const Key('first_run_vat_enabled'),
          contentPadding: EdgeInsets.zero,
          title: Text(tr('تفعيل ضريبة القيمة المضافة')),
          subtitle: Text(tr('إضافة الضريبة تلقائياً على الفواتير')),
          value: d.vatEnabled,
          onChanged: (v) => ctl.update((x) => x.copyWith(vatEnabled: v)),
        ),
        if (d.vatEnabled) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in kFirstRunVatRates)
                ChoiceChip(
                  key: Key('first_run_vat_${r.toInt()}'),
                  selected: d.currency.isNotEmpty && d.vatRate == r,
                  onSelected: (_) => ctl.update(
                    (x) => x.copyWith(vatRate: r, vatRateTouched: true),
                  ),
                  label: Text('${r.toInt()}%'),
                ),
            ],
          ),
          SwitchListTile(
            key: const Key('first_run_prices_include_tax'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('الأسعار شاملة الضريبة')),
            value: d.pricesIncludeTax,
            onChanged: (v) =>
                ctl.update((x) => x.copyWith(pricesIncludeTax: v)),
          ),
        ],
        const SizedBox(height: 14),
        label(tr('الفوترة الإلكترونية')),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth >= 640 ? (c.maxWidth - 20) / 3 : c.maxWidth;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final e in FirstRunEInvoice.values)
                SizedBox(
                  width: w,
                  child: FirstRunChoiceCard(
                    key: Key('first_run_einvoice_${e.name}'),
                    icon: e == FirstRunEInvoice.none
                        ? Icons.block
                        : Icons.qr_code_2,
                    title: _eInvoiceTitle(e),
                    subtitle: _eInvoiceSub(e),
                    selected: d.eInvoice == e,
                    onTap: () => ctl.update(
                      (x) => x.copyWith(eInvoice: e, eInvoiceTouched: true),
                    ),
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: 14),
        SizedBox(
          width: 220,
          child: FirstRunField(
            key: const Key('first_run_fiscal_year'),
            label: tr('السنة المالية'),
            value: d.fiscalYear == 0 ? '' : '${d.fiscalYear}',
            ltr: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final n = int.tryParse(v.trim());
              ctl.update((x) => x.copyWith(fiscalYear: n ?? 0));
            },
          ),
        ),
      ],
    );
  }
}
