// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_colors.dart';

import '../../../presentation/settings/providers/settings_controller.dart';

/// Widget for managing database backups
class BackupSettingsWidget extends ConsumerStatefulWidget {
  const BackupSettingsWidget({super.key});

  @override
  ConsumerState<BackupSettingsWidget> createState() =>
      _BackupSettingsWidgetState();
}

class _BackupSettingsWidgetState extends ConsumerState<BackupSettingsWidget> {
  // List<FileSystemEntity> _backups = []; // Removed - now using state
  bool _isLoading = true;
  bool _isBackingUp = false;
  bool _isExporting = false;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => _isLoading = true);
    try {
      final stats = await ref.read(settingsControllerProvider.notifier).getBackupStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with Create Backup button
        Row(
          children: [
            const Icon(PhosphorIconsBold.database, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text(
              'إدارة النسخ الاحتياطي',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            // Export button
            OutlinedButton.icon(
              onPressed: _isExporting || ref.watch(settingsControllerProvider).availableBackups.isEmpty
                  ? null
                  : _exportBackup,
              icon: _isExporting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(PhosphorIconsBold.export, size: 16),
              label: Text(_isExporting ? 'جاري التصدير...' : 'تصدير'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.info,
                side: const BorderSide(color: AppColors.info),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isBackingUp ? null : _createBackup,
              icon: _isBackingUp
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(PhosphorIconsBold.plus, size: 16),
              label: Text(
                _isBackingUp ? 'جاري النسخ...' : 'إنشاء نسخة احتياطية',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Stats Card
        _buildStatsCard(),
        const SizedBox(height: 16),

        // Backups List
        ...(_isLoading
            ? [const Center(child: CircularProgressIndicator())]
            : ref.watch(settingsControllerProvider).availableBackups.isEmpty
            ? [_buildEmptyState()]
            : ref.watch(settingsControllerProvider).availableBackups
                  .asMap()
                  .entries
                  .map((entry) => _buildBackupTile(entry.value, entry.key == 0))
                  .toList()),
      ],
    );
  }

  Widget _buildStatsCard() {
    final count = _stats['count'] ?? 0;
    final totalSize = _stats['totalSize'] ?? 0;
    final lastBackup = _stats['lastBackup'] as DateTime?;
    final sizeInMB = (totalSize / (1024 * 1024)).toStringAsFixed(1);
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          _buildStatChip(PhosphorIconsBold.archive, '$count', 'نسخة'),
          const SizedBox(width: 24),
          _buildStatChip(
            PhosphorIconsBold.hardDrive,
            '$sizeInMB MB',
            'الحجم الإجمالي',
          ),
          const SizedBox(width: 24),
          _buildStatChip(
            PhosphorIconsBold.clockCounterClockwise,
            lastBackup != null ? dateFormat.format(lastBackup) : 'لا يوجد',
            'آخر نسخة',
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIconsBold.check,
                  size: 14,
                  color: AppColors.success,
                ),
                SizedBox(width: 4),
                Text(
                  'النسخ التلقائي مُفعّل',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(PhosphorIconsLight.archive, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'لا توجد نسخ احتياطية',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'اضغط "إنشاء نسخة احتياطية" للبدء',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupTile(String backupPath, bool isLatest) {
    final file = File(backupPath);
    final name = backupPath.split(Platform.pathSeparator).last;
    final stat = file.statSync();
    final sizeKB = (stat.size / 1024).toStringAsFixed(0);
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isLatest ? PhosphorIconsBold.star : PhosphorIconsBold.archive,
          color: isLatest ? AppColors.warning : AppColors.textMuted,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
            if (isLatest) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'الأحدث',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.warning,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${dateFormat.format(stat.modified)} • $sizeKB KB',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(
                PhosphorIconsBold.arrowCounterClockwise,
                color: AppColors.info,
                size: 20,
              ),
              tooltip: 'استعادة',
              onPressed: () => _restoreBackup(backupPath),
            ),
            IconButton(
              icon: const Icon(
                PhosphorIconsBold.trash,
                color: AppColors.error,
                size: 20,
              ),
              tooltip: 'حذف',
              onPressed: () => _deleteBackup(backupPath),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createBackup() async {
    setState(() => _isBackingUp = true);
    try {
      final path = await ref.read(settingsControllerProvider.notifier).createBackup();
      if (path != null && mounted) {
        AppToast.show(
          context,
          'تم إنشاء النسخة الاحتياطية بنجاح',
          type: ToastType.success,
        );
        await _loadBackups();
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          'خطأ في إنشاء النسخة: $e',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _exportBackup() async {
    setState(() => _isExporting = true);
    try {
      final result = await FilePicker.getDirectoryPath(
        dialogTitle: 'اختر مجلد لتصدير النسخة الاحتياطية',
      );
      if (result != null) {
        final success = await ref.read(settingsControllerProvider.notifier).exportBackup(result);
        if (mounted && success) {
          AppToast.show(
            context,
            'تم تصدير النسخة بنجاح',
            type: ToastType.success,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في التصدير: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _restoreBackup(String backupPath) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الاستعادة'),
          content: const Text(
            'هل أنت متأكد؟ سيتم استبدال قاعدة البيانات الحالية بالنسخة الاحتياطية.\nيُنصح بإنشاء نسخة احتياطية قبل الاستعادة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
              ),
              child: const Text('استعادة'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        final success = await ref.read(settingsControllerProvider.notifier).restoreBackup(backupPath);
        if (success && mounted) {
          AppToast.show(
            context,
            'تمت الاستعادة بنجاح. يرجى إعادة تشغيل التطبيق.',
            type: ToastType.success,
          );
        }
      } catch (e) {
        if (mounted) {
          AppToast.show(context, 'خطأ في الاستعادة: $e', type: ToastType.error);
        }
      }
    }
  }

  Future<void> _deleteBackup(String backupPath) async {
    final name = backupPath.split(Platform.pathSeparator).last;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل تريد حذف النسخة الاحتياطية "$name"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        final success = await ref.read(settingsControllerProvider.notifier).deleteBackup(backupPath);
        if (success && mounted) {
          AppToast.show(
            context,
            'تم حذف النسخة بنجاح',
            type: ToastType.success,
          );
          await _loadBackups();
        }
      } catch (e) {
        if (mounted) {
          AppToast.show(context, 'خطأ في الحذف: $e', type: ToastType.error);
        }
      }
    }
  }
}