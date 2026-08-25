import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../data/providers/providers.dart';
import '../../../../data/database/sync_interceptor.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import '../../../picpos_shell/picpos_panel_groups.dart';
import 'package:ural_erp/l10n/app_localizations.dart';

class AddRoleDialog extends AppFormDialog<bool> {
  const AddRoleDialog({super.key});

  @override
  AppFormDialogState<bool, AddRoleDialog> createState() => _AddRoleDialogState();
}

class _AddRoleDialogState extends AppFormDialogState<bool, AddRoleDialog> {
  late final nameController = registerController('');

  @override
  String get dialogTitle => 'إضافة دور جديد';

  @override
  IconData get dialogIcon => PhosphorIconsBold.shieldPlus;

  /// ⚠️ التصميمُ يعطي لوحةَ `role` مجموعتَي «نسخ الصلاحيات من» و«مجموعات
  /// الصلاحيات». وهذا الحوارُ **يُنشئ الدورَ وحدَه** ثمّ تُضبَط صلاحياتُه من
  /// «إدارة الصلاحيات» — فالوصفُ يقول ذلك بدل أن يعد بما لا يفعله.
  @override
  String? get dialogSubtitle =>
      'عرِّف الدورَ ثمّ اضبط صلاحياته من «إدارة الصلاحيات»';

  @override
  String? get dialogSaveLabel => 'إنشاء الدور';

  /// لوحةُ `PANELS.role` — مجموعةٌ واحدةٌ لأنّ الحوارَ يُنشئ الدورَ وحدَه.
  ///
  /// ⚠️ **ومجموعتا التصميم الأخريان لم تُنقلا عمداً**: «نسخ الصلاحيات من»
  /// و«مجموعات الصلاحيات» تَعِدان بضبطِ ١٤٢ صلاحيةً من هنا، والحوارُ يكتب
  /// اسمَ الدور فقط ثمّ تُضبَط صلاحياتُه من «إدارة الصلاحيات». ومجموعةٌ لا
  /// تُحفَظ أسوأُ من غيابها.
  ///
  /// ومجموعةٌ واحدةٌ ⇒ لا عمودَ أرقام — فهرسٌ برقمٍ واحدٍ لا يفهرس شيئاً.
  @override
  List<PicPosPanelGroup> buildPicposGroups(BuildContext context) => [
        PicPosPanelGroup(label: 'تعريف الدور', child: _nameField()),
      ];

  Widget _nameField() => TextField(
        controller: nameController,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'اسم الدور',
          hintText: 'مثلاً: مدير صالة، محاسب ثان',
          prefixIcon: Icon(PhosphorIconsLight.identificationCard, size: 20),
        ),
      );

  /// جسمُ UralCash — الحقلُ نفسُه بلا رأسِ مجموعة.
  ///
  /// وهو **عينُ** الحقل الذي تلفّه المجموعةُ في فرع PicPos، فلا نسختان منه:
  /// الفرقُ بين الفرعَين هنا رأسُ المجموعة وحدَه، لا الحقل.
  @override
  Widget buildFormContent(BuildContext context, AppLocalizations localizations) {
    return _nameField();
  }

  @override
  Future<bool> onSave() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      throw 'يرجى إدخال اسم الدور';
    }

    // In client mode: push role to server first so it gets a server-authoritative ID.
    // The server then broadcasts the role back via sync, and the local insertRole
    // is still performed to give instant UI feedback.
    int? serverId;
    if (SyncInterceptor.isClientMode) {
      serverId = await SyncInterceptor.instance!.createRole(name: name);
    }

    final authRepo = ref.read(authRepositoryProvider);
    await authRepo.insertRole(name: name);
    return true;
  }
}
