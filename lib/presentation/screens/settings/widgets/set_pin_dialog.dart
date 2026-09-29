import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../data/providers/providers.dart';
import '../../../../services/client_write_interceptor.dart';
import '../../../../services/login_rate_limiter.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import '../../../picpos_shell/picpos_dialog.dart';
import '../../../picpos_shell/picpos_panel_groups.dart';
import '../../../settings_picpos/widgets/settings_blocks.dart';
import '../../../../core/theme/app_colors.dart';
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
      ? tr('تغيير PIN للمستخدم {p0}', {'p0': widget.user.displayName})
      : tr('تعيين PIN للمستخدم {p0}', {'p0': widget.user.displayName});

  @override
  IconData get dialogIcon => PhosphorIconsBold.password;

  // ⚠️ كان «أربعةُ أرقام» بينما التلميحُ والحفظُ يقبلان من أربعةٍ إلى ستّة —
  //    سطران في الحوار نفسِه يقولان عددَين. والمقيسُ هو ما يقبله الحفظ.
  @override
  String? get dialogSubtitle =>
      tr('{p0} — من ٤ إلى ٦ أرقامٍ للدخول السريع على نقطة البيع', {'p0': widget.user.displayName});

  @override
  String? get dialogSaveLabel => tr('حفظ الـ PIN');

  /// لوحةُ `PANELS.pin` — الرقمُ ثمّ الخياراتُ ثمّ التنبيه.
  ///
  /// ⚠️ **ولوحةُ المفاتيح الرقميّةُ في التصميم لم تُنقَل**: هي في التصميم
  /// أربعُ نقاطٍ ولوحةُ ٣×٤، وهنا حقلٌ يقبل من أربعة إلى ستّة أرقامٍ —
  /// فلوحةُ مفاتيحَ من أربعِ خاناتٍ تكذب على ما يقبله الحفظ. والتلميحُ يقول
  /// المدى الحقيقيَّ بدل «أربعةُ أرقام» الذي كان يعِد بأضيقَ ممّا يقبل.
  ///
  /// ونصُّ التنبيه هو نصُّ البرنامج لا نصُّ التصميم: التصميمُ يجزم بأنّ
  /// الـPIN «لا يُستخدم للدخول لشاشة الإعدادات أو التقارير المالية»، وهو
  /// جزمٌ لم أقِسه — فبقي ما كان مكتوباً ومقيساً.
  @override
  List<PicPosPanelGroup> buildPicposGroups(BuildContext context) => [
        PicPosPanelGroup(
          label: tr('الرقم السري الجديد'),
          hint: tr('من ٤ إلى ٦ أرقام'),
          child: _pinField(),
        ),
        PicPosPanelGroup(
          label: tr('خيارات'),
          child: PicPosPanelBox(
            children: [
              // ⚠️ **مفتاحٌ معطَّلٌ لا مفتاحٌ يعمل — والفرقُ مقصود.** التصميمُ
              //    يرسم «قفل الحساب بعد ٥ محاولات» مفتاحاً لكلّ مستخدم،
              //    والبرنامجُ ينفّذه **سياسةً عامّةً دائمةَ التفعيل** في
              //    `LoginRateLimiter` — لا عمودَ لكلّ مستخدم يُطفئها.
              //
              //    فإخفاؤه كان سيُخفي حمايةً قائمةً، ورسمُه قابلاً للتبديل
              //    كان سيَعِد بتحكّمٍ لا وجودَ له. والعددان مقروءان من الثابت
              //    نفسِه فلا يكذبان لو تغيّر.
              SettingsSwitchRow(
                first: true,
                icon: PhosphorIconsBold.shieldWarning,
                title: tr('قفل الحساب بعد {p0} محاولاتٍ فاشلة', {'p0': LoginRateLimiter.maxAttempts}),
                sub: tr('سياسةٌ عامّةٌ مفعَّلةٌ دائماً — القفلُ {p0} دقيقة', {'p0': LoginRateLimiter.lockoutDuration.inMinutes}),
                value: true,
                onChanged: null,
              ),
            ],
          ),
        ),
         PicPosPanelGroup(
          label: tr('تنبيه'),
          child:  PicPosDialogBanner(
            icon: PhosphorIconsBold.info,
            color: AppColors.info,
            text: tr('يُستخدم رمزُ PIN لتسجيل الدخول السريع في البيع السريع (POS).'),
          ),
        ),
      ];

  Widget _pinField() => TextField(
        controller: pinController,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration:  InputDecoration(
          labelText: tr('رمز PIN (أرقام فقط)'),
          hintText: tr('مثال: 1234'),
          prefixIcon: const Icon(PhosphorIconsLight.hash),
        ),
      );

  @override
  Widget buildFormContent(BuildContext context, AppLocalizations localizations) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // الحقلُ نفسُه الذي تلفّه المجموعةُ في فرع PicPos — لا نسختان منه.
        _pinField(),
         Text(
          tr('تنبيه: يُستخدم رمز PIN لتسجيل الدخول السريع في البيع السريع (POS).'),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
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
        pin.isEmpty ? tr('إزالة PIN') : tr('تغيير PIN'),
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }

    return true;
  }
}
