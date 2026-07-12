import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:ural_erp/core/constants/app_constants.dart';

/// Discount dialog with percentage and value tabs
class CartDiscountDialog extends StatefulWidget {
  final double subtotal;
  final double currentDiscountPercent;
  final double? maxDiscountPercent;
  final Function(double percent) onApply;
  final VoidCallback onRemove;

  const CartDiscountDialog({
    super.key,
    required this.subtotal,
    required this.currentDiscountPercent,
    this.maxDiscountPercent,
    required this.onApply,
    required this.onRemove,
  });

  @override
  State<CartDiscountDialog> createState() => _CartDiscountDialogState();
}

class _CartDiscountDialogState extends State<CartDiscountDialog> {
  bool _isPercentMode = true;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentDiscountPercent > 0
          ? widget.currentDiscountPercent.toString()
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('الخصم'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Toggle tabs
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildTab('نسبة %', true)),
                  Expanded(
                    child: _buildTab(
                      'قيمة ${AppConstants.currencySymbolEn}',
                      false,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Max discount warning
            if (widget.maxDiscountPercent != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.orange,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'الحد الأقصى: ${widget.maxDiscountPercent!.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

            // Input field
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _isPercentMode ? 'نسبة الخصم' : 'قيمة الخصم',
                suffixText: _isPercentMode
                    ? '%'
                    : AppConstants.currencySymbolEn,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                errorText: _getValidationError(),
              ),
              onChanged: (_) => setState(() {}),
            ),

            // Preview
            if (_controller.text.isNotEmpty && widget.subtotal > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'قيمة الخصم:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_calculateDiscountAmount().toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Quick buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _isPercentMode
                  ? [5, 10, 15, 20, 25]
                        .map((v) => _buildQuickButton('$v%', v.toDouble()))
                        .toList()
                  : [10, 20, 50, 100]
                        .map(
                          (v) => _buildQuickButton(
                            '$v ${AppConstants.currencySymbolEn}',
                            v.toDouble(),
                          ),
                        )
                        .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: widget.onRemove,
            child: const Text('إزالة الخصم'),
          ),
          ElevatedButton(onPressed: _apply, child: const Text('تطبيق')),
        ],
      ),
    );
  }

  Widget _buildTab(String label, bool isPercent) {
    final isSelected = _isPercentMode == isPercent;
    return GestureDetector(
      onTap: () {
        setState(() {
          _isPercentMode = isPercent;
          _controller.clear();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickButton(String label, double value) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        _controller.text = value.toString();
        setState(() {});
      },
    );
  }

  double _calculateDiscountAmount() {
    final inputValue = double.tryParse(_controller.text) ?? 0;
    if (_isPercentMode) {
      return widget.subtotal * (inputValue / 100);
    } else {
      return inputValue;
    }
  }

  String? _getValidationError() {
    if (widget.maxDiscountPercent == null) return null;
    final inputValue = double.tryParse(_controller.text) ?? 0;
    if (inputValue <= 0) return null;

    double percent;
    if (_isPercentMode) {
      percent = inputValue;
    } else {
      percent = widget.subtotal > 0 ? (inputValue / widget.subtotal * 100) : 0;
    }

    if (percent > widget.maxDiscountPercent!) {
      return 'تجاوز الحد الأقصى (${widget.maxDiscountPercent!.toStringAsFixed(0)}%)';
    }
    return null;
  }

  void _apply() {
    final inputValue = double.tryParse(_controller.text) ?? 0;
    double percent;

    if (_isPercentMode) {
      percent = inputValue.clamp(0, 100);
    } else {
      // Convert value to percentage
      if (widget.subtotal > 0) {
        percent = (inputValue / widget.subtotal * 100).clamp(0, 100);
      } else {
        percent = 0;
      }
    }

    // Enforce max discount limit
    final maxPercent = widget.maxDiscountPercent;
    if (maxPercent != null && percent > maxPercent) {
      percent = maxPercent;
    }

    widget.onApply(percent);
    if (context.mounted) Navigator.pop(context);
  }
}
