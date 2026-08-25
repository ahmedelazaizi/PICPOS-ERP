import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_toast.dart';
import 'package:ural_erp/l10n/app_localizations.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/core/config/brand.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_panel_groups.dart';

/// Standard form-based dialog for the UralCash ERP system.
/// Extends the logic of base forms with a more premium design.
abstract class AppFormDialog<T> extends ConsumerStatefulWidget {
  const AppFormDialog({super.key});
}

abstract class AppFormDialogState<T, W extends AppFormDialog<T>>
    extends ConsumerState<W> {
  // ── Template Methods ──

  String get dialogTitle;
  IconData get dialogIcon;
  Color get dialogIconColor => AppColors.primary;
  double get dialogWidth => 500;

  /// السطرُ الخافتُ تحت العنوان في غلاف PicPos (`PANELS[*].sub` في التصميم).
  ///
  /// `null` ⇒ بلا سطر. لا أثرَ له في غلاف UralCash — هناك عنوانٌ وحدَه.
  String? get dialogSubtitle => null;

  /// نصُّ زرِّ الحفظ في غلاف PicPos (`PANELS[*].save`).
  ///
  /// الافتراضُ `localizations.save` كما في غلاف UralCash، ويُتجاوَز حين
  /// يعطي التصميمُ اسماً أدقّ («حفظ المستخدم» · «إنشاء الدور» · «حفظ الـPIN»).
  String? get dialogSaveLabel => null;

  Widget buildFormContent(BuildContext context, AppLocalizations localizations);

  /// مجموعاتُ الجسم في غلاف PicPos — لوحةُ التصميم بمجموعاتٍ معنونةٍ بدل
  /// قائمةِ حقولٍ عارية. قائمةٌ فارغةٌ ⇒ يبقى [buildFormContent] كما هو.
  ///
  /// ⚠️ **ولا يُلمَس [buildFormContent] حين تُتجاوَز هذه.** الحواراتُ هنا
  /// مشتركةٌ مع UralCash، والشرطُ الذي يجعل النقلَ إلى هويّة PicPos مشروعاً
  /// أنّ مسارَ UralCash لا يتبدّل فيه بايت — فالبنيةُ الجديدةُ **تُضاف**
  /// بجانب القديمة لا تحلّ محلَّها.
  ///
  /// ⚠️ **ومنها يُبنى الجسمُ وعمودُ الأرقام معاً** — مصدرٌ واحدٌ لا اثنان،
  /// فلا يستطيع العمودُ أن يعِد بمجموعةٍ لا وجودَ لها.
  ///
  /// وتُستدعى مرّةً واحدةً في كلّ بناء، فلا بأسَ بأن تُنشئ ودجتاتِها فيها.
  List<PicPosPanelGroup> buildPicposGroups(BuildContext context) => const [];

  Future<T> onSave();

  // ── Infrastructure ──

  bool isLoading = false;
  final formKey = GlobalKey<FormState>();
  final List<TextEditingController> _controllers = [];

  TextEditingController registerController([String? initialText]) {
    final ctrl = TextEditingController(text: initialText);
    _controllers.add(ctrl);
    return ctrl;
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (formKey.currentState?.validate() == false) return;

    setState(() => isLoading = true);
    try {
      final result = await onSave();
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) AppToast.show(context, '$e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// غلافُ PicPos — `PicPosDialog` بدل `AlertDialog` المرسومةِ يدويّاً.
  ///
  /// ⚠️ **هذه أعلى رافعةٍ في تنسيق اللوحات**: ثلاثةَ عشرَ حواراً ترث هذه
  /// القاعدة، ومنها خمسٌ من لوحات التصميم مباشرةً — `pin` و`resetpw`
  /// و`access` (‏الفروعُ والمخازن) و`role` و`user`. فتنسيقُها هنا مرّةً
  /// واحدةً يُلبسها الهويّةَ كلَّها، وتنسيقُ كلٍّ على حدةٍ كان سيعني خمسَ
  /// نسخٍ تنحرف بأوّل تعديل — وهو عينُ ما بُني `PicPosDialog` ليمنعه.
  ///
  /// و`Form` باقٍ حولَ المحتوى: `formKey.currentState?.validate()` في
  /// [_handleSave] يقرأ منه، وإسقاطُه يجعل كلَّ تحقّقٍ من الحقول يمرّ صامتاً.
  Widget _buildPicposDialog(BuildContext context, AppLocalizations l) {
    final groups = buildPicposGroups(context);
    final content = groups.isEmpty
        ? buildFormContent(context, l)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: picposPanelBody(groups),
          );
    return PicPosDialog(
      icon: dialogIcon,
      accent: dialogIconColor,
      title: dialogTitle,
      subtitle: dialogSubtitle,
      width: dialogWidth < 660 ? 660 : dialogWidth,
      cancelLabel: l.cancel,
      onCancel: isLoading ? null : () => Navigator.pop(context),
      primaryAction: PicPosDialogAction(
        label: dialogSaveLabel ?? l.save,
        icon: dialogIcon,
        busy: isLoading,
        onPressed: isLoading ? null : _handleSave,
      ),
      indexLabels: picposPanelLabels(groups),
      body: [
        Form(key: formKey, child: content),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    if (Brand.isPicPos) return _buildPicposDialog(context, localizations);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.all(0),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: dialogIconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(dialogIcon, color: dialogIconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  dialogTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: dialogWidth,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8),
              child: buildFormContent(context, localizations),
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(localizations.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : _handleSave,
                  icon: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(dialogIcon, size: 18),
                  label: Text(localizations.save),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
