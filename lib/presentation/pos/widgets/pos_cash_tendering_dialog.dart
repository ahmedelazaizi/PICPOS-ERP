import 'package:picpos_erp/core/i18n/tr.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/number_utils.dart';

/// Cash tendering dialog — shows the total, lets cashier enter amount paid,
/// and calculates change to give back.
/// Returns true if confirmed, null if cancelled.
class PosCashTenderingDialog extends StatefulWidget {
  final double totalAmount;

  /// أزرارُ الفئات السريعة (٥ · ١٠ · ٢٠ · ٥٠ · ١٠٠) ظاهرةٌ أم لا.
  ///
  /// ⚠️ **الافتراضُ `true` عمداً، وهو تعاقدٌ لا تفضيل**: هذا الحوارُ
  /// مشترَكٌ مع شاشة UralCash، والعملُ عليها موقوف. فالنداءُ الذي لا يمرّر
  /// شيئاً يسلك سلوكَ اليوم حرفاً بحرف، ولا يملك هذا الوسيطُ أن يغيّرها.
  ///
  /// ومن يطفئها هو نداءُ PicPos وحدَه، بسياسة «لوحة مبالغ سريعة» (§٤
  /// `pos_quick_amounts_enabled`).
  final bool showQuickAmounts;

  const PosCashTenderingDialog({
    super.key,
    required this.totalAmount,
    this.showQuickAmounts = true,
  });

  /// Show the dialog. Returns true if confirmed, null if cancelled.
  static Future<bool?> show(
    BuildContext context, {
    required double totalAmount,
    bool showQuickAmounts = true,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PosCashTenderingDialog(
        totalAmount: totalAmount,
        showQuickAmounts: showQuickAmounts,
      ),
    );
  }

  @override
  State<PosCashTenderingDialog> createState() => _PosCashTenderingDialogState();
}

class _PosCashTenderingDialogState extends State<PosCashTenderingDialog> {
  final _controller = TextEditingController();
  double _amountPaid = 0;

  double get _change => _amountPaid - widget.totalAmount;
  bool get _isValid => _amountPaid >= widget.totalAmount;

  @override
  void initState() {
    super.initState();
    // Pre-fill with the total amount
    _controller.text = widget.totalAmount.toStringAsFixed(AppConstants.decimalPlaces);
    _amountPaid = widget.totalAmount;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(PhosphorIconsBold.money, color: AppColors.success, size: 24),
            ),
            const SizedBox(width: 12),
             Text(tr('الدفع نقدي')),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Total amount display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                     Text(
                      tr('المبلغ المطلوب:'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      '${widget.totalAmount.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbol}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Amount paid input
              TextField(
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                autofocus: true,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: tr('المبلغ المدفوع'),
                  suffixText: AppConstants.currencySymbolEn,
                  prefixIcon: const Icon(PhosphorIconsBold.wallet, color: AppColors.success),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.success, width: 2),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    // BUG-U24/U14: accept Arabic-locale input (comma / Arabic
                    // digits) instead of silently collapsing to 0.
                    _amountPaid = NumberUtils.tryParseLocale(value) ?? 0;
                  });
                },
                onSubmitted: (_) => _isValid ? _confirm() : null,
              ),

              const SizedBox(height: 16),

              // Change display
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  color: _isValid
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isValid ? AppColors.success : AppColors.error,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _isValid
                                  ? PhosphorIconsBold.arrowUDownLeft
                                  : PhosphorIconsBold.warning,
                              color: _isValid ? AppColors.success : AppColors.error,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isValid ? tr('الباقي (الفكة):') : tr('المبلغ غير كافي!'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _isValid ? AppColors.success : AppColors.error,
                              ),
                            ),
                          ],
                        ),
                        if (_isValid)
                          Text(
                            '${_change.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: _change > 0 ? 24 : 18,
                              color: AppColors.success,
                            ),
                          ),
                      ],
                    ),
                    if (_change > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        tr('أعط العميل {p0} {p1} فكة', {'p0': _change.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn}),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Quick amount buttons
              //
              // الحقلُ نفسُه يبقى: الإطفاءُ يخفي **الاختصارَ** لا وسيلةَ
              // الإدخال. ومحلٌّ لا يتعامل بهذه الفئات كان يرى أزراراً لا
              // يضغطها أحدٌ أبداً، وهي تزاحم لوحةَ الأرقام على الشاشة.
              if (widget.showQuickAmounts) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: _buildQuickAmountButtons(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.pop(context, null),
            child:  Text(tr('إلغاء')),
          ),
          ElevatedButton.icon(
            onPressed: (_isValid && !_isSubmitting) ? _confirm : null,
            icon: _isSubmitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(PhosphorIconsBold.checkCircle, size: 18),
            label:  Text(tr('تأكيد الدفع')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildQuickAmountButtons() {
    final total = widget.totalAmount;
    // Cluster 024 / Issue 5 — show the standard JOD/EGP cash denominations
    // (5, 10, 20, 50, 100) instead of derived "rounded up to nearest"
    // amounts. Operators told us they want to record what the customer
    // physically handed over, not the smallest multiple-of-5 above the
    // total. The exact-total chip stays as the first button so a single
    // tap still completes a no-change sale. Anything ≥ total is allowed
    // (the exact + each denomination, plus any larger ones for big
    // invoices). Smaller denominations are hidden when total > 100 so
    // the operator never sees a non-actionable button.
    final amounts = <double>{};
    amounts.add(total); // Exact amount — first chip
    for (final d in const [5, 10, 20, 50, 100, 200]) {
      if (d >= total) amounts.add(d.toDouble());
    }

    // Sort, keep max 5
    final sorted = amounts.toList()..sort();
    final display = sorted.take(5).toList();

    return display.map((amount) {
      final isSelected = (_amountPaid - amount).abs() < 0.01;
      return ActionChip(
        label: Text(
          amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : AppConstants.decimalPlaces),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : AppColors.primary,
          ),
        ),
        backgroundColor: isSelected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.1),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
        onPressed: () {
          setState(() {
            _amountPaid = amount;
            _controller.text = amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : AppConstants.decimalPlaces);
          });
        },
      );
    }).toList();
  }

  bool _isSubmitting = false;

  void _confirm() {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    Navigator.pop(context, true);
  }
}
