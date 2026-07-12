import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';

import '../../../core/design_system/typography.dart';

/// Widget for database backup and restore operations
class BackupRestoreWidget extends ConsumerWidget {
  const BackupRestoreWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(
            PhosphorIconsBold.cloudArrowUp,
            color: AppColors.success,
          ),
          title: const Text('نسخ احتياطي', style: AppTypography.bodyLarge),
          subtitle: const Text(
            'حفظ نسخة من قاعدة البيانات',
            style: AppTypography.bodySmall,
          ),
          trailing: ElevatedButton(
            onPressed: () => _backupDatabase(context),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsBold.download, size: 16),
                SizedBox(width: 4),
                Text('نسخ'),
              ],
            ),
          ),
        ),
        ListTile(
          leading: const Icon(
            PhosphorIconsBold.cloudArrowDown,
            color: AppColors.info,
          ),
          title: const Text('استعادة', style: AppTypography.bodyLarge),
          subtitle: const Text(
            'استعادة نسخة احتياطية سابقة',
            style: AppTypography.bodySmall,
          ),
          trailing: OutlinedButton(
            onPressed: () => _showRestoreDialog(context),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsBold.upload, size: 16),
                SizedBox(width: 4),
                Text('استعادة'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _backupDatabase(BuildContext context) async {
    try {
      final dbFolder = await getApplicationDocumentsDirectory();
      final sourceFile = File('${dbFolder.path}/cashier_market.db');

      if (!await sourceFile.exists()) {
        if (context.mounted) {
          AppToast.show(
            context,
            'قاعدة البيانات غير موجودة',
            type: ToastType.error,
          );
        }
        return;
      }

      String? selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: 'اختر مجلد حفظ النسخة الاحتياطية',
      );

      if (selectedDirectory == null) return;

      final timestamp = DateFormat(
        'yyyy-MM-dd_HH-mm-ss',
      ).format(DateTime.now());
      final backupFile = File(
        '$selectedDirectory/monexia_backup_$timestamp.db',
      );
      await sourceFile.copy(backupFile.path);

      if (context.mounted) {
        AppToast.show(
          context,
          'تم حفظ النسخة الاحتياطية في: ${backupFile.path}',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(
          context,
          'خطأ في النسخ الاحتياطي: $e',
          type: ToastType.error,
        );
      }
    }
  }

  void _showRestoreDialog(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
        dialogTitle: 'اختر ملف النسخة الاحتياطية',
      );

      if (result == null || result.files.isEmpty) return;

      final selectedFile = result.files.first;
      if (selectedFile.path == null) return;

      final filename = selectedFile.name;

      if (!context.mounted) return;

      _confirmRestore(context, selectedFile.path!, filename);
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    }
  }

  void _confirmRestore(
    BuildContext context,
    String backupPath,
    String filename,
  ) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.warning, color: AppColors.warning),
              SizedBox(width: 8),
              Text('تأكيد الاستعادة'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('هل تريد استعادة النسخة: $filename؟'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(PhosphorIconsBold.warning, color: AppColors.warning),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'سيتم استبدال جميع البيانات الحالية. يرجى إعادة تشغيل البرنامج بعد الاستعادة.',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await _restoreDatabase(context, backupPath);
              },
              child: const Text('استعادة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreDatabase(BuildContext context, String backupPath) async {
    try {
      final dbFolder = await getApplicationDocumentsDirectory();
      final targetFile = File('${dbFolder.path}/cashier_market.db');
      final backupFile = File(backupPath);

      if (await targetFile.exists()) {
        final timestamp = DateFormat(
          'yyyy-MM-dd_HH-mm-ss',
        ).format(DateTime.now());
        final backupDir = Directory('${dbFolder.path}/backups');
        if (!await backupDir.exists()) await backupDir.create();
        await targetFile.copy('${backupDir.path}/pre_restore_$timestamp.db');
      }

      await backupFile.copy(targetFile.path);

      if (context.mounted) {
        AppToast.show(
          context,
          'تمت الاستعادة بنجاح. يرجى إعادة تشغيل البرنامج.',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, 'خطأ في الاستعادة: $e', type: ToastType.error);
      }
    }
  }
}
