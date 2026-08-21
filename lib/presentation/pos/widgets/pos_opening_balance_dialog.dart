import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';

/// Dialog to prompt for opening balance when starting a new shift.
/// Returns a double (the opening balance) or null if cancelled.
class PosOpeningBalanceDialog extends StatefulWidget {
  final String userName;

  /// سببُ ظهورِ الديالوج الآن، حين لا يكون فتحَ ورديّةٍ اعتياديّاً عند الدخول.
  ///
  /// مثالُه: كاشيرٌ ضغط «تنفيذ المرتجع» فوجد ديالوجَ ورديّةٍ بلا مقدّمة —
  /// بدون سطرٍ يشرح، يبدو الأمرُ عطلاً لا إجراءً مطلوباً.
  final String? subtitle;

  const PosOpeningBalanceDialog({
    super.key,
    required this.userName,
    this.subtitle,
  });

  @override
  State<PosOpeningBalanceDialog> createState() => _PosOpeningBalanceDialogState();
}

class _PosOpeningBalanceDialogState extends State<PosOpeningBalanceDialog> {
  final _controller = TextEditingController(text: '0');

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
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(PhosphorIconsBold.cashRegister, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            const Text('افتتاح وردية جديدة'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsBold.user, size: 16, color: AppColors.info),
                    const SizedBox(width: 8),
                    Text(
                      'الكاشير: ${widget.userName}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(PhosphorIconsBold.info,
                        size: 16, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.subtitle!,
                        style: const TextStyle(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'أدخل الرصيد الافتتاحي للصندوق:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                autofocus: true,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  suffixText: 'JOD',
                  prefixIcon: const Icon(PhosphorIconsBold.money, color: AppColors.primary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
                onSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: 8),
              const Text(
                'يمكنك إدخال 0 إذا لم يكن هناك رصيد افتتاحي',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: _confirm,
            icon: const Icon(PhosphorIconsBold.play),
            label: const Text('بدء الوردية'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _confirm() {
    final amount = double.tryParse(_controller.text) ?? 0;
    Navigator.pop(context, amount);
  }
}
