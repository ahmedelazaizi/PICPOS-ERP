import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../data/providers/providers.dart';
import '../../../../services/api/api_handler_base.dart';
import '../../../../services/client_write_interceptor.dart';
import '../../../../services/network_service.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import '../../../picpos_shell/picpos_dialog.dart';
import '../../../picpos_shell/picpos_panel_groups.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:picpos_erp/l10n/app_localizations.dart';

class BranchAccessDialog extends AppFormDialog<bool> {
  final User user;

  const BranchAccessDialog({super.key, required this.user});

  @override
  AppFormDialogState<bool, BranchAccessDialog> createState() =>
      _BranchAccessDialogState();
}

class _BranchAccessDialogState extends AppFormDialogState<bool, BranchAccessDialog> {
  late Set<int> selected;
  List<Branche> allBranches = [];

  @override
  void initState() {
    super.initState();
    selected = {};
    _loadCurrentAccess();
  }

  Future<void> _loadCurrentAccess() async {
    setState(() => isLoading = true);
    try {
      final branchRepo = ref.read(branchRepositoryProvider);
      final current = await branchRepo.getUserAccessibleBranchIds(widget.user.id);
      final branches = await branchRepo.getAllBranches();
      selected = current.toSet();
      allBranches = branches;
    } catch (e) {
      debugPrint('Error loading branch access: $e');
      selected = {};
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  String get dialogTitle => tr('إدارة فروع المستخدم {p0}', {'p0': widget.user.displayName});

  @override
  IconData get dialogIcon => PhosphorIconsBold.buildings;

  @override
  String? get dialogSubtitle => tr('تحديدُ نطاق العمل — الفروعُ التي يراها المستخدم');

  @override
  String? get dialogSaveLabel => tr('حفظ النطاق');

  /// لوحةُ `PANELS.access` — مجموعةُ شرائحَ ثمّ تنبيه، كما في التصميم.
  ///
  /// ⚠️ **الشريحةُ بديلُ `CheckboxListTile` لا زينةٌ فوقه**: التصميمُ يرسم
  /// الفروعَ `kind:'chips'`، وصفٌّ من مربّعات اختيارٍ بارتفاع ٥٦ لكلِّ فرعٍ
  /// يملأ اللوحةَ بثلاثة فروع. والعنوانُ الثاني (‏عنوانُ الفرع) لم يُحذَف
  /// بل صار تلميحاً — فالنقلُ تنسيقٌ لا إنقاصُ بيان.
  ///
  /// وقائمةٌ فارغةٌ أثناء التحميل ⇒ يتولّى [buildFormContent] عرضَ الدوّارة.
  @override
  List<PicPosPanelGroup> buildPicposGroups(BuildContext context) {
    if (allBranches.isEmpty) return const [];
    return [
      PicPosPanelGroup(
        label: tr('الفروع'),
        hint: tr('الفروعُ التي يراها المستخدم'),
        child: PicPosPanelChips(
          children: [
            for (final b in allBranches)
              PicPosPanelChip(
                label: b.name,
                tooltip: b.address,
                selected: selected.contains(b.id),
                onTap: () => setState(() {
                  if (!selected.remove(b.id)) selected.add(b.id);
                }),
              ),
          ],
        ),
      ),
       PicPosPanelGroup(
        label: tr('تنبيه'),
        child: PicPosDialogBanner(
          icon: PhosphorIconsBold.info,
          color: AppColors.warning,
          text: tr('المسؤولون (Admins) لديهم وصولٌ كاملٌ لكلّ الفروع تلقائيّاً.'),
        ),
      ),
    ];
  }

  @override
  Widget buildFormContent(BuildContext context, AppLocalizations localizations) {
    if (isLoading && allBranches.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child:  Row(
            children: [
              const Icon(PhosphorIconsBold.info, size: 16, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('المسؤولين (Admins) لديهم وصول كامل لجميع الفروع تلقائياً.'),
                  style: const TextStyle(fontSize: 12, color: Colors.amber),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...allBranches.map((branch) => CheckboxListTile(
              title: Text(trData(branch.name)),
              subtitle: Text(branch.address ?? ''),
              value: selected.contains(branch.id),
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    selected.add(branch.id);
                  } else {
                    selected.remove(branch.id);
                  }
                });
              },
            )),
      ],
    );
  }

  @override
  Future<bool> onSave() async {
    final intercepted = await ClientWriteInterceptor.updateUser(
      widget.user.id,
      {'branchIds': selected.toList()},
    );

    if (!intercepted) {
      final branchRepo = ref.read(branchRepositoryProvider);
      await branchRepo.setUserBranchAccess(widget.user.id, selected.toList());

      // Phase 6 follow-up — admin saved on the server (intercepted == false
      // means we're NOT in client mode). Push a WebSocket nudge so paired
      // clients pull the new assignments within ~ms instead of waiting for
      // their next auto-sync tick. No-op if no clients are connected.
      if (!NetworkService.instance.isClient) {
        ApiHandlerBase.notifyTableChangedFromAdmin('user_branch_access');
      }
    }
    return true;
  }
}
