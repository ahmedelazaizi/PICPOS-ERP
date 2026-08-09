import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';

/// Settings widget for configuring and managing fingerprint attendance devices.
///
/// Placed in Settings → "أجهزة الحضور والبصمة".
class FingerprintSettingsWidget extends ConsumerStatefulWidget {
  const FingerprintSettingsWidget({super.key});

  @override
  ConsumerState<FingerprintSettingsWidget> createState() =>
      _FingerprintSettingsWidgetState();
}

class _FingerprintSettingsWidgetState
    extends ConsumerState<FingerprintSettingsWidget> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '4370');
  final _nameController = TextEditingController(text: 'جهاز البصمة الرئيسي');
  bool _isExpanded = false;
  bool _isTesting = false;
  bool _isSyncing = false;
  bool _isUploading = false;
  int _lastSyncCount = 0;
  String? _statusMessage;
  bool _isStatusError = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final ip = await settingsRepo.getSetting('fingerprint_device_ip');
    final port = await settingsRepo.getSetting('fingerprint_device_port');
    final name = await settingsRepo.getSetting('fingerprint_device_name');
    if (mounted) {
      setState(() {
        if (ip != null) _ipController.text = ip;
        if (port != null) _portController.text = port;
        if (name != null) _nameController.text = name;
      });
    }
  }

  Future<void> _saveSettings() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.saveSetting('fingerprint_device_ip', _ipController.text.trim());
    await settingsRepo.saveSetting('fingerprint_device_port', _portController.text.trim());
    await settingsRepo.saveSetting('fingerprint_device_name', _nameController.text.trim());
  }

  Future<void> _testConnection() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 4370;

    if (ip.isEmpty) {
      AppToast.show(
        context,
        'الرجاء إدخال عنوان IP للجهاز',
        type: ToastType.warning,
      );
      return;
    }

    setState(() => _isTesting = true);

    final repo = ref.read(fingerprintRepositoryProvider);
    final success = await repo.testConnection(ip, port);

    if (mounted) {
      setState(() {
        _isTesting = false;
        if (success) {
          _statusMessage = 'تم الاتصال بنجاح ✅';
          _isStatusError = false;
        } else {
          _statusMessage = 'فشل الاتصال — تأكد من IP والمنفذ';
          _isStatusError = true;
        }
      });
      if (success) {
        await _saveSettings();
        if (!mounted) return;
        AppToast.show(
          context,
          'تم الاتصال بالجهاز بنجاح ✅',
          type: ToastType.success,
        );
      } else {
        AppToast.show(
          context,
          'فشل الاتصال بالجهاز — تأكد من IP والمنفذ',
          type: ToastType.error,
        );
      }
    }
  }

  Future<void> _syncAttendance() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 4370;

    if (ip.isEmpty) {
      AppToast.show(
        context,
        'الرجاء إدخال عنوان IP أولاً',
        type: ToastType.warning,
      );
      return;
    }

    setState(() => _isSyncing = true);

    try {
      final repo = ref.read(fingerprintRepositoryProvider);

      // Connect
      final connected = await repo.connect(ip, port);
      if (!connected) {
        if (mounted) {
          AppToast.show(context, 'فشل الاتصال بالجهاز', type: ToastType.error);
          setState(() {
            _isSyncing = false;
            _statusMessage = 'فشل الاتصال بالجهاز';
            _isStatusError = true;
          });
        }
        return;
      }

      // Fetch logs
      final logs = await repo.fetchLogs();

      // Import to database
      int imported = 0;

      for (final log in logs) {
        try {
          final employee = await repo.getEmployeeByDeviceUserId(log.uid);
          if (employee == null) continue;

          if (log.status == 0) {
            await repo.importCheckIn(employee.id, log.timestamp);
          } else {
            await repo.importCheckOut(employee.id, log.timestamp);
          }
          imported++;
        } catch (e) {
          debugPrint('[FP Sync] Error importing log: $e');
        }
      }

      await ref.read(settingsRepositoryProvider).saveSetting(
        'fingerprint_last_sync',
        DateTime.now().toIso8601String(),
      );
      await _saveSettings();
      await repo.disconnect();

      if (mounted) {
        setState(() {
          _isSyncing = false;
          _lastSyncCount = imported;
          _statusMessage = 'تم ترحيل $imported سجل حضور';
          _isStatusError = false;
        });
        AppToast.show(
          context,
          'تم ترحيل $imported سجل حضور من الجهاز',
          type: imported > 0 ? ToastType.success : ToastType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _statusMessage = 'خطأ في الترحيل: $e';
          _isStatusError = true;
        });
        AppToast.show(context, 'خطأ في الترحيل: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _uploadEmployees() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 4370;

    if (ip.isEmpty) {
      AppToast.show(
        context,
        'الرجاء إدخال عنوان IP أولاً',
        type: ToastType.warning,
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final repo = ref.read(fingerprintRepositoryProvider);
      final connected = await repo.connect(ip, port);
      if (!connected) {
        if (mounted) {
          AppToast.show(context, 'فشل الاتصال بالجهاز', type: ToastType.error);
          setState(() {
            _isUploading = false;
            _statusMessage = 'فشل الاتصال بالجهاز';
            _isStatusError = true;
          });
        }
        return;
      }

      // جهازُ البصمة في فرعٍ بعينه — فلا تُرفع إليه أسماءُ موظفي فروعٍ لا
      // يملكها صاحبُ الجهاز. وصاحبُ الوصول الكامل يرفع الجميع كما كان.
      final scope = await ref.read(branchScopeProvider.future);
      final employees = await repo.getAllEmployees(
        allowedBranchIds: scope.hasFullAccess ? null : scope.allowedBranchIds,
      );
      int uploaded = 0;

      for (final emp in employees) {
        if (!emp.isActive) continue;
        final uid = emp.deviceUserId ?? emp.id.toString();
        final success = await repo.uploadUser(uid, emp.name);
        if (success) uploaded++;
      }

      await repo.disconnect();

      if (mounted) {
        setState(() {
          _isUploading = false;
          _statusMessage = 'تم رفع $uploaded موظف إلى الجهاز';
          _isStatusError = false;
        });
        AppToast.show(
          context,
          'تم رفع $uploaded موظف إلى الجهاز',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _statusMessage = 'خطأ في رفع الموظفين: $e';
          _isStatusError = true;
        });
        AppToast.show(
          context,
          'خطأ في رفع الموظفين: $e',
          type: ToastType.error,
        );
      }
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(PhosphorIconsBold.fingerprint, color: AppColors.info),
      title: const Text('أجهزة الحضور والبصمة'),
      subtitle: const Text(
        'اضغط لإعداد جهاز البصمة',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      initiallyExpanded: _isExpanded,
      onExpansionChanged: (v) => setState(() => _isExpanded = v),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // Device Name
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم الجهاز',
                  hintText: 'مثال: جهاز بصمة الاستقبال',
                  prefixIcon: Icon(PhosphorIconsBold.tag),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _saveSettings(),
              ),
              const SizedBox(height: 12),
              // IP + Port
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'عنوان IP',
                        hintText: '192.168.1.201',
                        prefixIcon: Icon(PhosphorIconsBold.globe),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _saveSettings(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'المنفذ',
                        hintText: '4370',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _saveSettings(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Action Buttons
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ActionButton(
                    icon: PhosphorIconsBold.wifiHigh,
                    label: 'اختبار الاتصال',
                    color: AppColors.info,
                    isLoading: _isTesting,
                    onPressed: _isTesting ? null : _testConnection,
                  ),
                  _ActionButton(
                    icon: PhosphorIconsBold.arrowsClockwise,
                    label: 'ترحيل الحضور',
                    color: AppColors.success,
                    isLoading: _isSyncing,
                    onPressed: _isSyncing ? null : _syncAttendance,
                  ),
                  _ActionButton(
                    icon: PhosphorIconsBold.uploadSimple,
                    label: 'رفع الموظفين',
                    color: AppColors.primary,
                    isLoading: _isUploading,
                    onPressed: _isUploading ? null : _uploadEmployees,
                  ),
                ],
              ),
              // Status indicator
              if (_statusMessage != null || _lastSyncCount > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isStatusError
                        ? AppColors.error.withValues(alpha: 0.1)
                        : AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isStatusError
                            ? PhosphorIconsBold.warning
                            : PhosphorIconsBold.checkCircle,
                        color: _isStatusError
                            ? AppColors.error
                            : AppColors.success,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusMessage ?? 'آخر ترحيل: $_lastSyncCount سجل',
                          style: TextStyle(
                            fontSize: 12,
                            color: _isStatusError
                                ? AppColors.error
                                : AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact action button for fingerprint settings.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.isLoading = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onPressed,
    );
  }
}
