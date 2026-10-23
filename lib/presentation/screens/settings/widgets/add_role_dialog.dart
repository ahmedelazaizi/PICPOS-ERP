import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/providers/providers.dart';
import '../../../../data/database/sync_interceptor.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import '../../../picpos_shell/picpos_dialog.dart';
import '../../../picpos_shell/picpos_panel_groups.dart';
import 'package:picpos_erp/l10n/app_localizations.dart';

class AddRoleDialog extends AppFormDialog<bool> {
  const AddRoleDialog({super.key});

  @override
  AppFormDialogState<bool, AddRoleDialog> createState() => _AddRoleDialogState();
}

class _AddRoleDialogState extends AppFormDialogState<bool, AddRoleDialog> {
  late final nameController = registerController('');
  late final descController = registerController('');

  /// «نسخ الصلاحيات من» — معرِّفُ الدور المصدر، أو `null` = ابدأ فارغاً.
  int? copyFromRoleId;

  @override
  String get dialogTitle => tr('إضافة دور جديد');

  @override
  IconData get dialogIcon => PhosphorIconsBold.shieldPlus;

  @override
  String? get dialogSubtitle =>
      tr('ابدأ من دورٍ قائمٍ ثمّ عدّل الصلاحيات من «مصفوفة الأدوار»');

  @override
  String? get dialogSaveLabel => tr('إنشاء الدور');

  /// لوحةُ `PANELS.role`.
  ///
  /// ⚠️ **«نسخ الصلاحيات من» نُقلت لأنّها مسنودةٌ فعلاً**: القراءةُ
  /// `getPermissionsForRole` والكتابةُ `setRolePermissions` كلتاهما قائمتان،
  /// فالنسخُ نداءان لا ميزةٌ تُبنى. وكانت مُسقطةً في الجولة السابقة على أنّ
  /// «الحوارَ يكتب الاسمَ فقط» — وهذا وصفُ ما كان لا حدُّ ما يمكن.
  ///
  /// ⚠️ **و«الأولوية» ما زالت غائبة**: لا عمودَ لها في `Roles`، وحقلٌ لا
  /// يقرأه الحفظُ وعدٌ كاذب.
  ///
  /// ⚠️ **و«مجموعات الصلاحيات» بندُ سؤالٍ للمالك لا إسقاطٌ صامت**: التصميمُ
  /// يعرض ستَّ مجموعاتٍ بمفاتيح، والمزروعُ في البرنامج **تسعٌ وعشرون** فئةً.
  /// وقائمةٌ بتسعٍ وعشرين مفتاحاً في حوارِ إنشاءٍ تُكرّر ما تفعله «مصفوفة
  /// الأدوار والصلاحيات» بدقّةٍ أعلى. ونسخُ دورٍ قائمٍ يغطّي حاجةَ البداية.
  @override
  List<PicPosPanelGroup> buildPicposGroups(BuildContext context) {
    final roles = ref.watch(allRolesProvider).value ?? const <Role>[];
    return [
      PicPosPanelGroup(
        label: tr('تعريف الدور'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _nameField(),
            const SizedBox(height: 12),
            _descField(),
          ],
        ),
      ),
      PicPosPanelGroup(
        label: tr('نسخ الصلاحيات من'),
        hint: tr('يبدأ الدورُ الجديدُ بنفس صلاحيات المختار'),
        child: PicPosPanelChips(
          children: [
            PicPosPanelChip(
              label: tr('ابدأ فارغاً'),
              selected: copyFromRoleId == null,
              onTap: () => setState(() => copyFromRoleId = null),
            ),
            for (final r in roles)
              PicPosPanelChip(
                label: r.name,
                selected: copyFromRoleId == r.id,
                onTap: () => setState(() => copyFromRoleId = r.id),
              ),
          ],
        ),
      ),
       PicPosPanelGroup(
        label: tr('تنبيه'),
        child:  PicPosDialogBanner(
          icon: PhosphorIconsBold.warning,
          color: AppColors.warning,
          text: tr('تعديلُ صلاحيات دورٍ يسري فوراً على كلّ مستخدميه، وأيُّ مستخدمٍ مفتوحةٌ له جلسةٌ يُطبَّق عليه التغييرُ عند العملية التالية.'),
        ),
      ),
    ];
  }

  Widget _nameField() => TextField(
        controller: nameController,
        autofocus: true,
        decoration:  InputDecoration(
          labelText: tr('اسم الدور'),
          hintText: tr('مثلاً: مدير صالة، محاسب ثان'),
          prefixIcon: const Icon(PhosphorIconsLight.identificationCard, size: 20),
        ),
      );

  /// «الوصف» في التصميم — و`Roles.description` عمودٌ قائمٌ يقبله `insertRole`.
  Widget _descField() => TextField(
        controller: descController,
        decoration:  InputDecoration(
          labelText: tr('الوصف'),
          hintText: tr('وصفٌ مختصرٌ لمهامّ الدور'),
          prefixIcon: const Icon(PhosphorIconsLight.textAlignRight, size: 20),
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
    final desc = descController.text.trim();

    // In client mode: push role to server first so it gets a server-authoritative ID.
    // The server then broadcasts the role back via sync, and the local insertRole
    // is still performed to give instant UI feedback.
  // ignore: unused_local_variable
    int? serverId;
    if (SyncInterceptor.isClientMode) {
      serverId = await SyncInterceptor.instance!.createRole(name: name);
    }

    final authRepo = ref.read(authRepositoryProvider);
    final newRoleId = await authRepo.insertRole(
      name: name,
      description: desc.isEmpty ? null : desc,
    );

    // «نسخ الصلاحيات من» — قراءةٌ ثمّ كتابةٌ بواجهتَين قائمتَين.
    //
    // ومأمونٌ في وضع العميل رغم أنّ `newRoleId` معرِّفٌ **محلّيّ**:
    // `setRolePermissions` في المستودع تُرسل `roleGlobalId` و`roleName` مع
    // الطلب، فيحلُّ الخادمُ الدورَ بالمعرِّف العالميِّ لا بالرقم — و`insertRole`
    // تسكّ globalId عند الإنشاء.
    //
    // ⚠️ **ولا يُبتلَع فشلُ النسخ صامتاً.** الدورُ أُنشئ فعلاً قبل هذا
    //    السطر؛ فلو فشل النسخُ وسكتنا لخرج المشغّلُ بدورٍ **فارغِ
    //    الصلاحيات** وهو يظنّه نسخةً من المصدر. فيُبلَّغ بالفشل ويبقى
    //    الدورُ قائماً ليُكمله من المصفوفة.
    if (copyFromRoleId != null) {
      try {
        final src = await authRepo.getPermissionsForRole(copyFromRoleId!);
        await authRepo.setRolePermissions(
          newRoleId,
          src.map((p) => p.id).toList(),
        );
      } catch (e) {
        throw 'أُنشئ الدورُ «$name» لكن تعذّر نسخُ الصلاحيات: $e — '
            'اضبطها من «مصفوفة الأدوار والصلاحيات».';
      }
    }
    return true;
  }
}
