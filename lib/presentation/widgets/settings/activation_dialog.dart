import 'package:flutter/material.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';

import '../../../services/license_service.dart';

class ActivationDialog extends ConsumerStatefulWidget {
  const ActivationDialog({super.key});

  @override
  ConsumerState<ActivationDialog> createState() => _ActivationDialogState();
}

class _ActivationDialogState extends ConsumerState<ActivationDialog> {
  final _keyController = TextEditingController();
  bool _loading = false;
  String? _machineId;

  @override
  void initState() {
    super.initState();
    _loadMachineId();
  }

  Future<void> _loadMachineId() async {
    final id = await ref.read(licenseServiceProvider).getMachineId();
    if (mounted) {
      setState(() => _machineId = id);
    }
  }

  Future<void> _handleActivate() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;

    setState(() => _loading = true);

    final success = await ref.read(licenseServiceProvider).activate(key);

    if (mounted) {
      setState(() => _loading = false);
      if (success) {
        // Refresh activation status provider
        ref.invalidate(activationStatusProvider);
        Navigator.pop(context, true);
        AppToast.show(
          context,
          'تم تفعيل النسخة الكاملة بنجاح!',
          type: ToastType.success,
        );
      } else {
        AppToast.show(
          context,
          'كود التفعيل غير صحيح لهذه النسخة',
          type: ToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(PhosphorIconsBold.key, color: AppColors.primary),
            SizedBox(width: 12),
            Text('تفعيل النسخة الكاملة'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'للحصول على كود التفعيل، يرجى إرسال رقم تعريف الجهاز الموضح أدناه للمطور.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              // Machine ID Field
              const Text(
                'رقم تعريف الجهاز (Machine ID):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.picposHairline),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _machineId ?? 'جاري التحميل...',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 16,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(PhosphorIconsBold.copy, size: 18),
                      onPressed: _machineId == null
                          ? null
                          : () {
                              Clipboard.setData(
                                ClipboardData(text: _machineId!),
                              );
                              AppToast.show(context, 'تم نسخ رقم التعريف');
                            },
                      tooltip: 'نسخ رقم التعريف',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Key Input Field
              const Text(
                'كود التفعيل:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _keyController,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: 'XXXX-XXXX-XXXX-XXXX',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(PhosphorIconsBold.keyhole),
                ),
                inputFormatters: [
                  // Format: XXXX-XXXX-XXXX-XXXX
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: _loading ? null : _handleActivate,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('تفعيل الآن'),
          ),
        ],
      ),
    );
  }
}

void showActivationDialog(BuildContext context) {
  showDialog(context: context, builder: (context) => const ActivationDialog());
}
