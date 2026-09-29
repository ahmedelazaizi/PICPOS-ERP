import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/database/database.dart';
import '../../../services/scale_service.dart';
import '../../../../../../core/constants/app_constants.dart';

/// Dialog for entering weight for weighted products
///
/// Features:
/// - Live weight from scale (when connected)
/// - Manual weight input
/// - Calculated total display
class WeightInputDialog extends StatefulWidget {
  final Product product;
  final void Function(double weight) onWeightConfirmed;

  const WeightInputDialog({
    super.key,
    required this.product,
    required this.onWeightConfirmed,
  });

  /// Show the weight input dialog
  static Future<void> show({
    required BuildContext context,
    required Product product,
    required void Function(double weight) onWeightConfirmed,
  }) {
    return showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: WeightInputDialog(
          product: product,
          onWeightConfirmed: (weight) {
            Navigator.pop(dialogContext);
            onWeightConfirmed(weight);
          },
        ),
      ),
    );
  }

  @override
  State<WeightInputDialog> createState() => _WeightInputDialogState();
}

class _WeightInputDialogState extends State<WeightInputDialog> {
  final _weightController = TextEditingController();

  double get pricePerUnit =>
      widget.product.pricePerUnit ?? widget.product.salePrice;
  // BUG-U14: accept Arabic-locale input (comma / Arabic digits) for weight.
  double get weight => NumberUtils.tryParseLocale(_weightController.text) ?? 0;
  double get total => weight * pricePerUnit;

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(PhosphorIconsBold.scales, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.product.name, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // BUG-U01: restored Arabic. BUG-U28: Arabic currency symbol.
          Text(
            tr('سعر الوحدة: {p0} {p1}', {'p0': pricePerUnit.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbol}),
          ),
          const SizedBox(height: 16),

          // Live Weight Display (when scale connected)
          if (ScaleService.instance.isConnected) ...[
            _buildLiveWeightSection(),
            const SizedBox(height: 12),
            const Divider(),
             Text(
              tr('أو أدخل الوزن يدوياً:'),
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
          ],

          // Manual Weight Input
          _buildManualWeightInput(),
          const SizedBox(height: 16),

          // Calculated Total
          _buildTotalSection(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:  Text(tr('إلغاء')),
        ),
        ElevatedButton.icon(
          onPressed: weight > 0 ? () => widget.onWeightConfirmed(weight) : null,
          icon: const Icon(PhosphorIconsBold.shoppingCart, size: 18),
          label:  Text(tr('إضافة للسلة')),
        ),
      ],
    );
  }

  Widget _buildLiveWeightSection() {
    return StreamBuilder<double>(
      stream: ScaleService.instance.weightStream,
      builder: (context, snapshot) {
        final liveWeight = snapshot.data ?? 0.0;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.success.withValues(alpha: 0.1),
                AppColors.success.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.success, width: 2),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: snapshot.hasData
                          ? AppColors.success
                          : AppColors.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr('القراءة المباشرة من الميزان'),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.success.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                tr('{p0} كجم', {'p0': liveWeight.toStringAsFixed(3)}),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: liveWeight > 0
                      ? () {
                          _weightController.text = liveWeight.toStringAsFixed(
                            3,
                          );
                          setState(() {});
                        }
                      : null,
                  icon: const Icon(PhosphorIconsBold.check, size: 16),
                  label:  Text(tr('استخدام هذا الوزن')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildManualWeightInput() {
    return TextField(
      controller: _weightController,
      decoration: InputDecoration(
        labelText: tr('الوزن (كجم)'),
        hintText: '0.000',
        prefixIcon: const Icon(PhosphorIconsBold.scales),
        suffixText: tr('كجم'),
        // BUG-U26: explain why the "إضافة للسلة" button stays disabled.
        helperText:
            weight <= 0 ? tr('أدخل وزناً أكبر من صفر لتفعيل الإضافة') : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      autofocus: !ScaleService.instance.isConnected,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildTotalSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
           Text(
            tr('الإجمالي:'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            '${total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbol}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
