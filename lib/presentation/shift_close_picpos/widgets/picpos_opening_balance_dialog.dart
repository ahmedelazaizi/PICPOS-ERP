import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';

// منطق منسوخ من lib/presentation/pos/widgets/pos_opening_balance_dialog.dart
// (الأصل، ١٢٤ سطر) — أي إصلاح منطقي يتصلّح في المصدر أولاً ثم patch (مصيدة
// النسخ §٥.٨). النسخ من ملفنا الموجود في هذا الريبو — أبداً من D:\URAL-ERP.
//
// `_controller` و`_confirm` (يرجع `double?` — نفس القيمة/السلوك بالضبط بلا أي
// تغيير) منسوخان حرفياً. المتغيّر الوحيد هو الـ chrome البصري: هوية PicPos
// (كارت أنظف حول اسم الكاشير، حدود/ألوان AppColors نفسها لأنها بالفعل تتكيّف
// حسب العلامة) بدل شكل الحوار الأصل. اسم الكلاس تغيّر لـ
// `PicposOpeningBalanceDialog`.
/// حوار طلب الرصيد الافتتاحي عند بدء وردية جديدة — نسخة PicPos.
/// يرجع `double` (الرصيد الافتتاحي) أو `null` لو أُلغي.
class PicposOpeningBalanceDialog extends StatefulWidget {
  final String userName;

  const PicposOpeningBalanceDialog({super.key, required this.userName});

  @override
  State<PicposOpeningBalanceDialog> createState() =>
      _PicposOpeningBalanceDialogState();
}

class _PicposOpeningBalanceDialogState
    extends State<PicposOpeningBalanceDialog> {
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
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header — أيقونة داخل مربع بلون العلامة + عنوان، بنفس أسلوب
              // PicPosPageHeader (شريحة لونية سفلية بدل ظل).
              Container(
                padding: const EdgeInsets.only(bottom: 14),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.primary, width: 2.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        PhosphorIconsBold.cashRegister,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'افتتاح وردية جديدة',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // بطاقة الكاشير — PicPosContentCard-style (بلا ظل، حد شعري).
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      PhosphorIconsBold.user,
                      size: 16,
                      color: AppColors.info,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'الكاشير: ${widget.userName}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'أدخل الرصيد الافتتاحي للصندوق:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                autofocus: true,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  suffixText: 'JOD',
                  prefixIcon: const Icon(
                    PhosphorIconsBold.money,
                    color: AppColors.primary,
                  ),
                  filled: true,
                  fillColor: AppColors.posBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
                onSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: 8),
              const Text(
                'يمكنك إدخال 0 إذا لم يكن هناك رصيد افتتاحي',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _confirm,
                    icon: const Icon(PhosphorIconsBold.play),
                    label: const Text('بدء الوردية'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirm() {
    final amount = double.tryParse(_controller.text) ?? 0;
    Navigator.pop(context, amount);
  }
}
