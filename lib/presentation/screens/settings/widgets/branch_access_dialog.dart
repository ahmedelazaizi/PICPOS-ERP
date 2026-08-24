import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../data/providers/providers.dart';
import '../../../../services/api/api_handler_base.dart';
import '../../../../services/client_write_interceptor.dart';
import '../../../../services/network_service.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import 'package:ural_erp/l10n/app_localizations.dart';

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
  String get dialogTitle => 'إدارة فروع المستخدم ${widget.user.displayName}';

  @override
  IconData get dialogIcon => PhosphorIconsBold.buildings;

  @override
  String? get dialogSubtitle => 'تحديدُ نطاق العمل — الفروعُ التي يراها المستخدم';

  @override
  String? get dialogSaveLabel => 'حفظ النطاق';

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
          child: const Row(
            children: [
              Icon(PhosphorIconsBold.info, size: 16, color: Colors.amber),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'المسؤولين (Admins) لديهم وصول كامل لجميع الفروع تلقائياً.',
                  style: TextStyle(fontSize: 12, color: Colors.amber),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...allBranches.map((branch) => CheckboxListTile(
              title: Text(branch.name),
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
