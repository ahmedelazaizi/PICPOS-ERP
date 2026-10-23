import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/design_system/typography.dart';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_panel_groups.dart';
import '../../../core/constants/app_constants.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';

import '../../../services/license_service.dart';

class ActivationDialog extends ConsumerStatefulWidget {
  /// غلافُ PicPos (`PANELS.activate` في ملفّ التصميم) بدل `AlertDialog`.
  ///
  /// ⚠️ **رايةٌ لا استخراجُ جسم**، خلافاً لشاشات الإعدادات الفرعيّة: حوارٌ
  /// ورقةٌ في الشجرة، ومنطقُه (`_machineId` · `_handleActivate` · `_loading`)
  /// كلُّه في حالةٍ خاصّة. فاستخراجُ «جسمٍ» منه يعني تفكيكَ الحالة لا نقلَ
  /// ودجت. والرايةُ تبلغ الغرضَ بالشرط نفسِه: افتراضيّاً `false`، فحوارُ
  /// UralCash لا يتبدّل فيه بايت.
  final bool picposChrome;

  const ActivationDialog({super.key, this.picposChrome = false});

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
          tr('تم تفعيل النسخة الكاملة بنجاح!'),
          type: ToastType.success,
        );
      } else {
        AppToast.show(
          context,
          tr('كود التفعيل غير صحيح لهذه النسخة'),
          type: ToastType.error,
        );
      }
    }
  }

  /// لوحةُ `PANELS.activate` على هويّة PicPos.
  ///
  /// ⚠️ **وثلاثةُ فروقٍ عن التصميم، كلُّها لأنّ التصميمَ يصف ما لا يفعله
  /// البرنامج — ورسمُ ما لا يعمل أسوأُ من عدم رسمه:**
  ///
  /// ١. التصميمُ يعطي مجموعةَ مفاتيحَ «تفعيل عبر الإنترنت / تفعيل بملف
  ///    ترخيص». والتفعيلُ بملفٍّ **موجودٌ فعلاً** لكنّه ليس وضعاً يُبدَّل:
  ///    `LicenseService.isActivated()` يفحص `license.txt`/`activation.key`/
  ///    `license.key` بجانب التنفيذيّ **تلقائيّاً** في كلّ إقلاع. فمفتاحٌ
  ///    يوهم بالاختيار كذب — والصوابُ بيانٌ يشرح أين يوضع الملفّ.
  ///
  /// ٢. وتنبيهُ التصميم يقول إنّ النقلَ لجهازٍ آخر «يحتاج فك التفعيل أولاً
  ///    من الدعم الفني». و`deactivate` غيرُ موجودةٍ في البرنامج أصلاً، فما
  ///    يحتاجه النقلُ مفتاحٌ جديدٌ لا فكُّ تفعيل. صيغَ التنبيهُ على الواقع.
  ///
  /// ٣. ومجموعةُ `key` في التصميم أربعةُ صناديقَ من أربع خانات. المدخلُ هنا
  ///    حقلٌ واحدٌ واسعٌ يقبل المفتاح الموقّع الطويل —
  ///    وظيفيّاً هو هو، والتقسيمُ إلى أربعةٍ بندٌ مفتوحٌ لا عطب.
  Widget _buildPicposDialog(BuildContext context) {
    final muted = picposDialogMuted(context);
    final groups = _picposGroups(muted);
    return PicPosDialog(
      icon: PhosphorIconsBold.key,
      title: tr('تفعيل الترخيص'),
      subtitle: tr('أدخل مفتاح الترخيص المرسل من الدعم الفني'),
      width: 660,
      primaryAction: PicPosDialogAction(
        label: tr('تفعيل الآن'),
        icon: PhosphorIconsBold.sealCheck,
        busy: _loading,
        onPressed: _loading ? null : _handleActivate,
      ),
      indexLabels: picposPanelLabels(groups),
      body: picposPanelBody(groups),
    );
  }

  /// مجموعاتُ لوحة `PANELS.activate` بترتيبها — وهي **وحدَها** مصدرُ عمود
  /// الأرقام على جانب اللوحة، فلا يمكن أن يعِدَ العمودُ بمجموعةٍ لا وجودَ لها.
  List<PicPosPanelGroup> _picposGroups(Color muted) => [
        PicPosPanelGroup(
          label: tr('مفتاح الترخيص'),
          hint: tr('مفتاح موقّع طويل'),
          child: TextField(
            controller: _keyController,
            maxLength: 512,
            maxLines: 3,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTypography.mono,
              fontSize: 18,
              letterSpacing: 2.0,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              hintText: 'PP2-…',
              hintStyle: TextStyle(color: muted, fontSize: 14),
              prefixIcon: const Icon(PhosphorIconsBold.keyhole),
            ),
          ),
        ),
        PicPosPanelGroup(
          label: tr('بيانات هذا الجهاز'),
          hint: tr('أرسلها للدعم الفنّي'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              PicPosDialogSummary(
                rows: [
                  (
                    label: tr('رقم الجهاز'),
                    value: _machineId ?? tr('جاري التحميل...'),
                    color: AppColors.primary,
                  ),
                  (
                    label: tr('اسم الجهاز'),
                    value: Platform.localHostname,
                    color: null,
                  ),
                  (
                    label: tr('نظام التشغيل'),
                    value: Platform.operatingSystem,
                    color: null,
                  ),
                  (
                    label: tr('إصدار البرنامج'),
                    value: AppConstants.appVersion,
                    color: null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  icon: const Icon(PhosphorIconsBold.copy, size: 15),
                  label:  Text(tr('نسخ رقم التعريف')),
                  onPressed: _machineId == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: _machineId!));
                          AppToast.show(context, tr('تم نسخ رقم التعريف'));
                        },
                ),
              ),
            ],
          ),
        ),
        // ⚠️ التنبيهُ **مجموعةٌ بعنوان** لا لافتتان عاريتان: في التصميم
        //    `{label:'تنبيه', kind:'note'}`. ولو بقي بلا عنوانٍ لصار في
        //    اللوحة كتلةٌ ظاهرةٌ بلا رقمٍ يقابلها في العمود.
         PicPosPanelGroup(
          label: tr('تنبيه'),
          child:  Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              PicPosDialogBanner(
                icon: PhosphorIconsBold.fileText,
                color: AppColors.info,
                text: tr('للأجهزة المعزولة عن الإنترنت: ضع ملفّ الترخيص باسم «license.txt» أو «activation.key» أو «license.key» في نفس مجلّد البرنامج — يُقرأ تلقائيّاً عند التشغيل بلا إدخال مفتاح.'),
              ),
              const SizedBox(height: 12),
              PicPosDialogBanner(
                icon: PhosphorIconsBold.warning,
                color: AppColors.warning,
                text: tr('المفتاحُ مرتبطٌ برقم هذا الجهاز وحدَه. تشغيلُ البرنامج على جهازٍ آخر يحتاج مفتاحاً جديداً من الدعم الفنّي.'),
              ),
            ],
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    if (widget.picposChrome) return _buildPicposDialog(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title:  Row(
          children: [
            const Icon(PhosphorIconsBold.key, color: AppColors.primary),
            const SizedBox(width: 12),
            Text(tr('تفعيل النسخة الكاملة')),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Text(
                tr('للحصول على كود التفعيل، يرجى إرسال رقم تعريف الجهاز الموضح أدناه للمطور.'),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              // Machine ID Field
               Text(
                tr('رقم تعريف الجهاز (Machine ID):'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
                        _machineId ?? tr('جاري التحميل...'),
                        style: const TextStyle(
                          fontFamily: AppTypography.mono,
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
                              AppToast.show(context, tr('تم نسخ رقم التعريف'));
                            },
                      tooltip: tr('نسخ رقم التعريف'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Key Input Field
               Text(
                tr('كود التفعيل:'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _keyController,
                maxLength: 512,
                maxLines: 3,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTypography.mono,
                  fontSize: 18,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: 'PP2-…',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(PhosphorIconsBold.keyhole),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إلغاء')),
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
                :  Text(tr('تفعيل الآن')),
          ),
        ],
      ),
    );
  }
}

/// [picpos] `true` ⇒ غلافُ `PicPosDialog` بلوحة التصميم. الافتراضُ `false`
/// فنداءُ UralCash يبقى كما هو.
void showActivationDialog(BuildContext context, {bool picpos = false}) {
  showDialog(
    context: context,
    builder: (context) => ActivationDialog(picposChrome: picpos),
  );
}
