import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/repository_providers.dart';

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
            onPressed: () => _backupDatabase(context, ref),
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
            onPressed: () => _showRestoreDialog(context, ref),
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

  // ═══════════════════════════════════════════════════════════════════════
  // الودجت دي كانت بتعمل عمليات الملفات بنفسها وعلى اسم داتابيز **مكتوب
  // بالإيد** (`cashier_market.db` — اسم من قبل إعادة التسمية). النتيجة:
  //
  //   * زرار «نسخ احتياطي» كان **بيفشل دايماً** برسالة «قاعدة البيانات غير
  //     موجودة» — على العلامتين، مش PicPos بس.
  //   * زرار «استعادة» كان بينسخ النسخة على ملف التطبيق **مبيقراهوش**،
  //     وبيقول «تمت الاستعادة بنجاح» ويطلب إعادة التشغيل. يعني حد بيستعيد
  //     بعد كارثة كان يفتكر إن بياناته رجعت وهي ما رجعتش.
  //   * ونسخة ما قبل الاستعادة كانت بتتاخد من نفس الملف الوهمي، فمفيش حتى
  //     شبكة أمان قبل الكتابة.
  //   * واسم النسخة كان `monexia_backup_*` — اسم علامة تالتة خالص.
  //
  // الحل مش تصليح الاسم هنا: طبقة العرض أصلاً ممنوعة تلمس `data/database`
  // (الدستور §IV، ويحرسه `presentation_db_import_guard_test`). فكل العمليات
  // بقت من `ISettingsRepository`، وهي اللي بتعرف مسار الداتابيز الصح.
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _backupDatabase(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(settingsRepositoryProvider);

      String? selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: 'اختر مجلد حفظ النسخة الاحتياطية',
      );

      if (selectedDirectory == null) return;

      // نسخة طازة الأول، وبعدين تصدير الأحدث للمجلد اللي المستخدم اختاره —
      // كده الملف المُصدَّر بيعبّر عن الحالة دلوقتي مش عن آخر نسخة قديمة.
      final created = await repo.createBackup();
      if (created == null) {
        if (context.mounted) {
          AppToast.show(
            context,
            'تعذّر إنشاء النسخة الاحتياطية',
            type: ToastType.error,
          );
        }
        return;
      }

      final exported = await repo.exportBackup(selectedDirectory);

      if (context.mounted) {
        AppToast.show(
          context,
          exported
              ? 'تم حفظ النسخة الاحتياطية في: $selectedDirectory'
              : 'تعذّر نسخ الملف إلى المجلد المحدد',
          type: exported ? ToastType.success : ToastType.error,
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

  void _showRestoreDialog(BuildContext context, WidgetRef ref) async {
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

      _confirmRestore(context, ref, selectedFile.path!, filename);
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    }
  }

  void _confirmRestore(
    BuildContext context,
    WidgetRef ref,
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
                        'سيتم استبدال جميع البيانات الحالية. الاستعادة تُطبَّق '
                        'عند إعادة تشغيل البرنامج — قبلها لا يتغيّر شيء. '
                        'وتُؤخذ نسخة احتياطية من الحالة الراهنة أولاً.',
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
                await _restoreDatabase(context, ref, backupPath);
              },
              child: const Text('استعادة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreDatabase(
    BuildContext context,
    WidgetRef ref,
    String backupPath,
  ) async {
    try {
      final repo = ref.read(settingsRepositoryProvider);

      if (!await File(backupPath).exists()) {
        if (context.mounted) {
          AppToast.show(
            context,
            'ملف النسخة الاحتياطية غير موجود',
            type: ToastType.error,
          );
        }
        return;
      }

      // شبكة أمان قبل الكتابة فوق الداتابيز الحالية: لو المستخدم استعاد نسخة
      // غلط، الحالة اللي كان فيها لسه موجودة في مجلد النسخ.
      await repo.createBackup();

      final ok = await repo.restoreBackup(backupPath);

      if (context.mounted) {
        // الاستعادة **متجدولة** مش منفَّذة: مينفعش نكتب فوق داتابيز مفتوحة،
        // فبتتطبّق عند الإقلاع الجاي. الرسالة لازم تقول ده بالظبط — «تمت»
        // وهي لسه ما تمّتش هي نفس الكذبة اللي كانت في الكود القديم.
        AppToast.show(
          context,
          ok
              ? 'تم تجهيز الاستعادة. أغلق البرنامج وأعد تشغيله لتطبيقها.'
              : 'فشل تجهيز الاستعادة — البيانات الحالية لم تتغيّر.',
          type: ok ? ToastType.success : ToastType.error,
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, 'خطأ في الاستعادة: $e', type: ToastType.error);
      }
    }
  }
}
