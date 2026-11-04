import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/no_invoice_return_policy.dart';
import '../../../domain/models/quick_sale_policy.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'quick_sale_settings_chrome.dart';

/// بطاقةُ «المرتجع السريع بلا فاتورة» في خطوة «الدفع» من إعدادات البيع السريع.
///
/// صفٌّ واحد: سقفُ قيمةِ الاسترداد النقديّ. فوقه يطلب الكاشيرُ موافقةَ مسؤول
/// (نفسُ آلية «تأكيد مدير» القائمة). مستقلّةٌ عن `kQuickSaleRows` لسببٍ مشروحٍ
/// في `no_invoice_return_policy.dart`.
class NoInvoiceReturnCapCard extends StatelessWidget {
  /// القيمُ **المدموجةُ مع المسوّدة** — كي يتحرّك المنزلقُ فور السحب.
  final QuickSalePolicyValues values;

  /// يستقبل ما يُكتب في المسوّدة (يُحفَظ عند «حفظ» الشاشة).
  final void Function(Map<String, String> entries) onChanged;

  const NoInvoiceReturnCapCard({
    super.key,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cap = noInvoiceReturnCap(values)
        .clamp(0.0, kNoInvoiceReturnCapSliderMax)
        .toDouble();
    return QuickSaleGroupCard(
      label: tr('المرتجع السريع بلا فاتورة'),
      tint: AppColors.error,
      note: tr('الاسترداد نقداً فقط'),
      rows: [
        QuickSaleSettingRow(
          icon: PhosphorIconsBold.arrowUUpLeft,
          tint: AppColors.error,
          title: tr('سقف قيمة المرتجع بلا فاتورة'),
          settingKey: kNoInvoiceReturnCapKey,
          sub: tr('ما فوقه لا يُحفَظ إلا بموافقة مسؤول، والصفر يعني أن كل مرتجع يحتاج مسؤولاً'),
          isLast: true,
          control: SizedBox(
            width: 230,
            child: Row(children: [
              Expanded(
                child: Slider(
                  key: const ValueKey('no-invoice-return-cap-slider'),
                  value: cap,
                  min: 0,
                  max: kNoInvoiceReturnCapSliderMax,
                  divisions: (kNoInvoiceReturnCapSliderMax /
                          kNoInvoiceReturnCapStep)
                      .round(),
                  label: cap.round().toString(),
                  onChanged: (v) => onChanged(writeNoInvoiceReturnCap(v)),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  cap.round().toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: context.picposText,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
