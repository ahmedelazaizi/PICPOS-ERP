import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/providers/providers.dart';
import '../../../../services/api/api_handler_base.dart';
import '../../../../services/network_service.dart';
import '../../../widgets/dialogs/app_form_dialog.dart';
import 'package:ural_erp/l10n/app_localizations.dart';

class WarehouseAccessDialog extends AppFormDialog<bool> {
  final User user;

  const WarehouseAccessDialog({super.key, required this.user});

  @override
  AppFormDialogState<bool, WarehouseAccessDialog> createState() =>
      _WarehouseAccessDialogState();
}

class _WarehouseAccessDialogState extends AppFormDialogState<bool, WarehouseAccessDialog> {
  late Set<int> selected;

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
      final current = await branchRepo.getUserAccessibleWarehouseIds(widget.user.id);
      selected = current.toSet();
    } catch (e) {
      debugPrint('Error loading warehouse access: $e');
      selected = {};
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  String get dialogTitle => 'إدارة مخازن المستخدم ${widget.user.displayName}';

  @override
  IconData get dialogIcon => PhosphorIconsBold.warehouse;

  @override
  String? get dialogSubtitle =>
      'تحديدُ نطاق العمل — المخازنُ التي يراها المستخدم';

  @override
  String? get dialogSaveLabel => 'حفظ النطاق';

  @override
  Widget buildFormContent(BuildContext context, AppLocalizations localizations) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final allWarehouses = ref.watch(allWarehousesProvider).value ?? [];

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
                  'عدم تحديد أي مخزن = وصول لجميع المخازن تلقائياً.',
                  style: TextStyle(fontSize: 12, color: Colors.amber),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...allWarehouses.map((wh) => CheckboxListTile(
              title: Text(wh.name),
              subtitle: wh.location != null ? Text(wh.location!) : null,
              secondary: Icon(
                wh.isDefault ? PhosphorIconsBold.star : PhosphorIconsLight.warehouse,
                color: wh.isDefault ? AppColors.warning : AppColors.textMuted,
                size: 20,
              ),
              value: selected.contains(wh.id),
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    selected.add(wh.id);
                  } else {
                    selected.remove(wh.id);
                  }
                });
              },
              dense: true,
            )),
      ],
    );
  }

  @override
  Future<bool> onSave() async {
    final branchRepo = ref.read(branchRepositoryProvider);
    await branchRepo.setUserWarehouseAccess(widget.user.id, selected.toList());

    // Phase 6 follow-up — admin saved on the server. Push a WebSocket
    // nudge so paired clients pull the new warehouse-access rows within
    // ~ms instead of waiting for their next auto-sync tick. No-op if
    // no clients are connected, and skipped on a client device (the
    // dialog is server-only by architectural directive but the guard
    // is cheap).
    if (!NetworkService.instance.isClient) {
      ApiHandlerBase.notifyTableChangedFromAdmin('user_warehouse_access');
    }
    return true;
  }
}
