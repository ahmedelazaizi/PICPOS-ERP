import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../picpos_shell/picpos_danger_confirm.dart';
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
          title:  Text(tr('نسخ احتياطي'), style: AppTypography.bodyLarge),
          subtitle:  Text(
            tr('حفظ نسخة من قاعدة البيانات'),
            style: AppTypography.bodySmall,
          ),
          trailing: ElevatedButton(
            onPressed: () => _backupDatabase(context, ref),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child:  Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsBold.download, size: 16),
                const SizedBox(width: 4),
                Text(tr('نسخ')),
              ],
            ),
          ),
        ),
        ListTile(
          leading: const Icon(
            PhosphorIconsBold.cloudArrowDown,
            color: AppColors.info,
          ),
          title:  Text(tr('استعادة'), style: AppTypography.bodyLarge),
          subtitle:  Text(
            tr('استعادة نسخة احتياطية سابقة'),
            style: AppTypography.bodySmall,
          ),
          trailing: OutlinedButton(
            onPressed: () => _showRestoreDialog(context, ref),
            child:  Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsBold.upload, size: 16),
                const SizedBox(width: 4),
                Text(tr('استعادة')),
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
        dialogTitle: tr('اختر مجلد حفظ النسخة الاحتياطية'),
      );

      if (selectedDirectory == null) return;

      // نسخة طازة الأول، وبعدين تصدير الأحدث للمجلد اللي المستخدم اختاره —
      // كده الملف المُصدَّر بيعبّر عن الحالة دلوقتي مش عن آخر نسخة قديمة.
      final created = await repo.createBackup();
      if (created == null) {
        if (context.mounted) {
          AppToast.show(
            context,
            tr('تعذّر إنشاء النسخة الاحتياطية'),
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
              ? tr('تم حفظ النسخة الاحتياطية في: {selectedDirectory}', {'selectedDirectory': selectedDirectory})
              : tr('تعذّر نسخ الملف إلى المجلد المحدد'),
          type: exported ? ToastType.success : ToastType.error,
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(
          context,
          tr('خطأ في النسخ الاحتياطي: {e}', {'e': e}),
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
        dialogTitle: tr('اختر ملف النسخة الاحتياطية'),
      );

      if (result == null || result.files.isEmpty) return;

      final selectedFile = result.files.first;
      if (selectedFile.path == null) return;

      final filename = selectedFile.name;

      if (!context.mounted) return;

      _confirmRestore(context, ref, selectedFile.path!, filename);
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  /// ⚠️ **حاجزُ كلمةٍ لا زرَّ تأكيد.** الاستعادةُ تستبدل قاعدةَ البيانات
  /// كلَّها، وكانت تُنفَّذ بضغطةٍ واحدة.
  ///
  /// والعرضُ هنا **عمودٌ واحدٌ بتسلسل الخطوات** لا قائمتَي أثر: ما يقلق
  /// المستعيدَ هو ترتيبُ ما سيحدث ومتى يفقد جلسته، لا مقابلةُ محذوفٍ بباقٍ.
  /// وهو نفسُ ما يعرضه التصميمُ في `restore`.
  Future<void> _confirmRestore(
    BuildContext context,
    WidgetRef ref,
    String backupPath,
    String filename,
  ) async {
    final confirmed = await showPicPosDangerConfirm(
      context,
      icon: PhosphorIconsBold.arrowCounterClockwise,
      title: tr('استعادة نسخة احتياطية'),
      subtitle: filename,
      message: tr('يُستبدل محتوى قاعدة البيانات الحاليّة بمحتوى النسخة المختارة. والاستعادةُ تكتمل عند إعادة تشغيل البرنامج — قبلها لا يتغيّر شيءٌ على الشاشة.'),
      actionLabel: tr('استعادة النسخة'),
      typedWord: tr('استعادة'),
      warnTone: true,
      willDeleteLabel: tr('ما سيحدث بالترتيب'),
      willDelete:  [
        tr('تُؤخذ نسخةُ أمانٍ تلقائيّةٌ من الوضع الحاليّ أوّلاً'),
        tr('يُستبدَل ملفُّ قاعدة البيانات بمحتوى النسخة المختارة'),
        tr('تكتمل الاستعادةُ عند إعادة تشغيل البرنامج'),
      ],
    );
    if (!confirmed || !context.mounted) return;
    await _restoreDatabase(context, ref, backupPath);
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
            tr('ملف النسخة الاحتياطية غير موجود'),
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
              ? tr('تم تجهيز الاستعادة. أغلق البرنامج وأعد تشغيله لتطبيقها.')
              : tr('فشل تجهيز الاستعادة — البيانات الحالية لم تتغيّر.'),
          type: ok ? ToastType.success : ToastType.error,
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, tr('خطأ في الاستعادة: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }
}
