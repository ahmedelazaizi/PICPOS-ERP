import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../data/providers/providers.dart';
import '../../../../services/client_write_interceptor.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import 'package:ural_erp/l10n/app_localizations.dart';

class SetPinDialog extends AppFormDialog<bool> {
  final User user;

  const SetPinDialog({super.key, required this.user});

  @override
  AppFormDialogState<bool, SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends AppFormDialogState<bool, SetPinDialog> {
  late final pinController = registerController(widget.user.pin);

  @override
  String get dialogTitle => widget.user.pin != null
      ? 'تغيير PIN للمستخدم ${widget.user.displayName}'
      : 'تعيين PIN للمستخدم ${widget.user.displayName}';

  @override
  IconData get dialogIcon => PhosphorIconsBold.password;

  @override
  String? get dialogSubtitle => 'أربعةُ أرقامٍ للدخول السريع على نقطة البيع';

  @override
  String? get dialogSaveLabel => 'حفظ الـ PIN';

  @override
  Widget buildFormContent(BuildContext context, AppLocalizations localizations) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'رمز PIN (أرقام فقط)',
            hintText: 'مثال: 1234',
            prefixIcon: Icon(PhosphorIconsLight.hash),
          ),
        ),
        const Text(
          'تنبيه: يُستخدم رمز PIN لتسجيل الدخول السريع في البيع السريع (POS).',
          style: TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  Future<bool> onSave() async {
    final pin = pinController.text.trim();

    if (pin.isNotEmpty && (pin.length < 4)) {
      throw 'يجب أن يتكون رمز PIN من 4 أرقام على الأقل';
    }

    if (pin.isNotEmpty && double.tryParse(pin) == null) {
      throw 'يجب أن يتكون رمز PIN من أرقام فقط';
    }

    final authRepo = ref.read(authRepositoryProvider);
    
    // Route through interceptor in client mode
    final intercepted = await ClientWriteInterceptor.updateUser(widget.user.id, {
      'pin': pin.isEmpty ? null : pin,
    });
    
    if (!intercepted) {
      await authRepo.updateUserPin(widget.user.id, pin.isEmpty ? null : pin);
    }

    // #Forensic Log: PIN change
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserEdit(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        widget.user.displayName,
        pin.isEmpty ? 'إزالة PIN' : 'تغيير PIN',
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }

    return true;
  }
}
