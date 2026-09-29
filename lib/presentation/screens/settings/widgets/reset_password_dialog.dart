import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../services/security_service.dart';
import '../../../../data/providers/providers.dart';
import '../../../../services/client_write_interceptor.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import '../../../picpos_shell/picpos_dialog.dart';
import '../../../picpos_shell/picpos_panel_groups.dart';
import '../../../settings_picpos/widgets/settings_blocks.dart';
import 'package:ural_erp/l10n/app_localizations.dart';

class ResetPasswordDialog extends AppFormDialog<bool> {
  final User user;

  const ResetPasswordDialog({super.key, required this.user});

  @override
  AppFormDialogState<bool, ResetPasswordDialog> createState() =>
      _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends AppFormDialogState<bool, ResetPasswordDialog> {
  late final passwordController = registerController();
  bool forcePasswordChange = true;

  @override
  String get dialogTitle => tr('إعادة تعيين كلمة مرور {p0}', {'p0': widget.user.displayName});

  @override
  IconData get dialogIcon => PhosphorIconsBold.key;

  @override
  // نصُّ التصميم: يقول أثرَ الحفظ على المستخدم بدل وصفٍ عامّ.
  String? get dialogSubtitle =>
      tr(' — لن يستطيع الدخولَ بكلمته القديمة بعد الحفظ');

  @override
  String? get dialogSaveLabel => tr('حفظ كلمة المرور');

  /// لوحةُ `PANELS.resetpw` — القوّةُ ثمّ الخياراتُ ثمّ التنبيه.
  ///
  /// ⚠️ **ومفتاحان من ثلاثةٍ في التصميم لم يُرسَما**: «إنهاء جلساته
  /// المفتوحة» و«إبلاغه على واتساب» لا مقابلَ لهما في الحفظ — والحفظُ هنا
  /// يكتب كلمةَ المرور وعلمَ التغيير الإجباريِّ وحدَهما. ومفتاحٌ لا يفعل
  /// شيئاً أسوأُ من غيابه.
  ///
  /// وشبكةُ القواعد تُقرأ من `SecurityService.passwordRules` لا تُحسَب هنا،
  /// فتبقى السياسةُ في مكانٍ واحد.
  @override
  List<PicPosPanelGroup> buildPicposGroups(BuildContext context) {
    final pwd = passwordController.text;
    final result = SecurityService.validatePassword(pwd);
    return [
      PicPosPanelGroup(
        label: tr('كلمة المرور الجديدة'),
        hint: tr('مؤشّرُ القوّة إرشاديٌّ وليس إلزاميّاً'),
        child: PicPosPanelStrength(
          field: _passwordField(),
          strength: pwd.isEmpty ? 0 : result.strength,
          strengthLabel: pwd.isEmpty
              ? ''
              : SecurityService.getPasswordStrengthLabel(result.strength),
          // ⚠️ لا شبكةَ قواعدَ قبل أن يكتب شيئاً: ستُّ قواعدَ حمراءَ على حقلٍ
          //    فارغٍ تُقرأ خطأً لا إرشاداً.
          rules: pwd.isEmpty
              ? const []
              : [
                  for (final r in SecurityService.passwordRules(pwd))
                    (label: r.label, ok: r.ok),
                ],
        ),
      ),
      PicPosPanelGroup(
        label: tr('خيارات'),
        child: PicPosPanelBox(
          children: [
            SettingsSwitchRow(
              first: true,
              icon: PhosphorIconsBold.arrowsClockwise,
              title: tr('فرض التغيير عند الدخول القادم'),
              sub: tr('سيُطلب منه تعيينُ كلمةٍ يعرفها هو وحدَه'),
              value: forcePasswordChange,
              onChanged: (v) => setState(() => forcePasswordChange = v),
            ),
          ],
        ),
      ),
      // «تنبيه» في `PANELS.resetpw` — ونصُّه مقيسٌ لا منقولٌ على عواهنه:
      // كلمةُ المرور تُحفَظ بـ`updateUserPassword`، والـPIN يُحفَظ بـ
      // `updateUserPin` من حوارٍ آخر. فالجملةُ تصف فصلاً قائماً في الكود.
       PicPosPanelGroup(
        label: tr('تنبيه'),
        child:  PicPosDialogBanner(
          icon: PhosphorIconsBold.info,
          color: AppColors.info,
          text: tr('كلمةُ المرور للدخول للبرنامج، وهي غيرُ الـPIN المستخدَم على نقطة البيع — عيّنِ الـPIN من زرِّ القفل في صفِّ المستخدم.'),
        ),
      ),
    ];
  }

  Widget _passwordField() => TextField(
        controller: passwordController,
        obscureText: true,
        onChanged: (_) => setState(() {}),
        decoration:  InputDecoration(
          labelText: tr('كلمة المرور الجديدة'),
          prefixIcon: const Icon(PhosphorIconsLight.lock),
        ),
      );

  @override
  Widget buildFormContent(BuildContext context, AppLocalizations localizations) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // الحقلُ نفسُه الذي يلفّه صندوقُ القوّة في فرع PicPos.
        _passwordField(),
        if (passwordController.text.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildPasswordStrength(),
        ],
        const SizedBox(height: 12),
        CheckboxListTile(
          title:  Text(tr('فرض تغيير كلمة المرور عند الدخول القادم')),
          subtitle:  Text(tr('سيُطلب من المستخدم تغيير كلمة المرور فور تسجيل دخوله التالي')),
          value: forcePasswordChange,
          onChanged: (v) => setState(() => forcePasswordChange = v ?? true),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppColors.primary,
        ),
      ],
    );
  }

  Widget _buildPasswordStrength() {
    final result = SecurityService.validatePassword(passwordController.text);
    final strengthLabel = SecurityService.getPasswordStrengthLabel(result.strength);
    final strengthColor = result.strength < 30
        ? AppColors.error
        : result.strength < 50
            ? Colors.orange
            : result.strength < 70
                ? Colors.amber
                : result.strength < 90
                    ? Colors.lightGreen
                    : Colors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: result.strength / 100,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(strengthColor),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              strengthLabel,
              style: TextStyle(
                fontSize: 11,
                color: strengthColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (!result.isValid) ...[
          const SizedBox(height: 6),
          ...result.errors.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    const Icon(Icons.close, size: 14, color: AppColors.error),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(e, style: const TextStyle(fontSize: 11, color: AppColors.error)),
                    ),
                  ],
                ),
              )),
        ],
      ],
    );
  }

  @override
  Future<bool> onSave() async {
    final password = passwordController.text;

    if (password.isEmpty) {
      throw 'يرجى إدخال كلمة مرور جديدة';
    }

    // Password strength indicator is shown as a guide only — no enforcement
    // final passwordValidation = SecurityService.validatePassword(password);

    final authRepo = ref.read(authRepositoryProvider);
    
    // Route through interceptor in client mode
    final intercepted = await ClientWriteInterceptor.updateUser(widget.user.id, {
      'password': password,
    });
    
    if (!intercepted) {
      await authRepo.updateUserPassword(
        userId: widget.user.id,
        newPassword: password,
      );

      // If force change is requested, we need to set the flag
      // (Because updateUserPassword clears it by default)
      if (forcePasswordChange) {
        await authRepo.updateUserInfo(
          userId: widget.user.id,
          displayName: widget.user.displayName,
          roleId: widget.user.roleId,
          maxDiscountPercent: widget.user.maxDiscountPercent,
          discountLimitIsPercent: widget.user.discountLimitIsPercent,
          cardCode: widget.user.cardCode,
          defaultScreen: widget.user.defaultScreen,
          forcePasswordChange: true,
        );
      }
    }

    // #Forensic Log: Password reset
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logUserEdit(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        widget.user.displayName,
        tr('إعادة تعيين كلمة المرور'),
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }

    return true;
  }
}
