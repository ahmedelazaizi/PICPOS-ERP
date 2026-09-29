import 'package:ural_erp/core/i18n/tr.dart';
// «قالب جديد» — النماذجُ الجاهزةُ كلُّها، لا ثمانيةٌ منها.
//
// هذه اللوحةُ هي المسارُ الذي كان مفقوداً: أحدَ عشرَ ملفَّ قالبٍ مشحونٍ مع
// التطبيق بلا طريقةٍ لإدخاله القاعدةَ — وفيها الفاتورةُ الضريبيّةُ
// والمرتجعاتُ وكشفا الحساب والتقريرُ العامّ. تُقرأ من [kReadyTemplateFiles]
// ويحرس تمامَها `template_files_are_complete_test`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/repository_providers.dart';
import '../../../data/providers/template_library_providers.dart';
import '../../picpos_shell/picpos_surface.dart';

/// يفتح لوحةَ النماذج الجاهزة. يُرجع مُعرِّفَ القالب المُنشَأ أو `null`.
Future<int?> showNewTemplateSheet(BuildContext context, WidgetRef ref) =>
    showDialog<int>(
      context: context,
      builder: (_) => const Dialog(child: _NewTemplateSheet()),
    );

class _NewTemplateSheet extends ConsumerStatefulWidget {
  const _NewTemplateSheet();

  @override
  ConsumerState<_NewTemplateSheet> createState() => _NewTemplateSheetState();
}

class _NewTemplateSheetState extends ConsumerState<_NewTemplateSheet> {
  String? _busyFile;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(invoiceTemplatesRepositoryProvider);
    final files = repo.getAvailableTemplateFiles();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SizedBox(
        width: 560,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 6),
              child: Row(
                children: [
                  Icon(PhosphorIconsBold.filePlus,
                      size: 18, color: context.picposBrandInk),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('قالب جديد'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: context.picposText,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(PhosphorIconsBold.x, size: 16),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                tr('ابدأ من نموذجٍ جاهز — كلُّها قابلةٌ للتعديل بالكامل بعد الإنشاء، وتُنشأ **بلا رابطات** فلا تخطف مستنداً.'),
                style: TextStyle(fontSize: 11.5, color: context.picposMuted),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
                child: Text(_error!,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.error)),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: files.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final f = files[i];
                  final busy = _busyFile == f['file'];
                  return ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: context.picposHairline),
                    ),
                    leading: Icon(_iconFor(f['type']),
                        size: 18, color: context.picposBrandInk),
                    title: Text(
                      f['name'] ?? f['file']!,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: context.picposText),
                    ),
                    subtitle: Text(
                      '${f['type']} · ${f['file']}',
                      style: TextStyle(
                          fontSize: 10.5, color: context.picposMuted),
                    ),
                    trailing: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(PhosphorIconsBold.caretLeft, size: 14),
                    onTap: busy ? null : () => _create(f['file']!),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(String file) async {
    setState(() {
      _busyFile = file;
      _error = null;
    });
    try {
      final json =
          await rootBundle.loadString('assets/invoice_templates/$file');
      final repo = ref.read(invoiceTemplatesRepositoryProvider);
      final id = await repo.importTemplateFromJson(json);

      ref.read(templateLibraryRefreshProvider.notifier).bump();
      ref.read(selectedTemplateIdProvider.notifier).set(id);
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      // الإخفاقُ يُقال ولا يُبتلع: لوحةٌ تُغلق بلا شيءٍ تبدو كأنها عملت.
      if (mounted) {
        setState(() {
          _busyFile = null;
          _error = tr('تعذّر إنشاءُ القالب من «{file}»: {e}', {'file': file, 'e': e});
        });
      }
    }
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'thermal':
        return PhosphorIconsBold.receipt;
      case 'kitchen':
        return PhosphorIconsBold.cookingPot;
      case 'statement':
        return PhosphorIconsBold.scroll;
      case 'report':
        return PhosphorIconsBold.chartBar;
      default:
        return PhosphorIconsBold.fileText;
    }
  }
}
