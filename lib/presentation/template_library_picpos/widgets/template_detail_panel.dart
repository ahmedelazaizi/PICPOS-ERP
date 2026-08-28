// لوحةُ تفاصيل القالب — التعريفُ والمستنداتُ المربوطةُ والإجراءات.
//
// وكلُّ إجراءٍ هنا يتبع `BUTTON-CONTRACT.md` بحرفه، وأخصُّ ثلاثةً منها ليست
// تجميليّةً وإن بدت:
//
//   · **رفضُ حذف قالبٍ مربوط** — بدونه تُطبع مستنداتٌ بلا قالبٍ بعد أسابيعَ
//     بلا سببٍ ظاهر. والرفضُ يقول **بكم رابطة** لا «مرفوض».
//   · **إلغاءُ الرابطة المتعارضة بإشعار** — الإلغاءُ الصامتُ يجعل المستخدمَ
//     يظنّ قالبين مفعَّلَين.
//   · **إبطالُ الذاكرة بعد كلِّ كتابة** — بدونه يعدّل المستخدمُ ويرى القديم،
//     فيظنّ أنّ الحفظَ لم يعمل.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/repository_providers.dart';
import '../../../data/providers/template_library_providers.dart';
import '../../../domain/models/picpos_template_card.dart';
import '../../print_test_picpos/screens/print_test_picpos_screen.dart';
import '../../template_editor_picpos/screens/template_editor_picpos_screen.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../screens/template_library_picpos_screen.dart'
    show templateStatusLabel, templateStatusTone;

class TemplateDetailPanel extends ConsumerWidget {
  const TemplateDetailPanel({super.key, required this.card});

  final TemplateCard? card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = card;
    if (c == null) {
      return const PicPosContentCard(
        child: PicPosEmptyState(
          icon: PhosphorIconsBold.cursorClick,
          title: 'اختر قالباً',
          hint: 'تفاصيلُه ورابطاتُه وإجراءاتُه تظهر هنا',
        ),
      );
    }

    return PicPosContentCard(
      child: ListView(
        children: [
          PicPosSectionHeader(
            title: c.name,
            subtitle: c.meta,
            icon: PhosphorIconsBold.fileText,
          ),
          const SizedBox(height: 4),
          _Spec(label: 'الورق', value: '${c.paperLabel} · ${c.paperWidthMm.toStringAsFixed(0)}مم'),
          _Spec(label: 'النوع', value: '${c.type} · ${c.category}'),
          _Spec(label: 'العناصر', value: '${c.elementCount}'),
          _Spec(label: 'الأعمدة', value: '${c.columnCount}'),
          _Spec(
            label: 'نسخةُ التخطيط',
            value: c.layoutVersion >= 2 ? '٢ — نطاقاتٌ بإحداثيّات' : '١ — تدفّق',
          ),
          _Spec(label: 'الحالة', value: templateStatusLabel(c),
              tone: templateStatusTone(c)),

          const SizedBox(height: 14),
          PicPosSectionHeader(
            title: 'المستندات المربوطة',
            subtitle: c.isBound ? '${c.bindings.length} رابطة' : 'لا رابطة',
            icon: PhosphorIconsBold.gitFork,
          ),
          if (!c.isBound)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'هذا القالبُ لا يخرج على ورقٍ حتى يُربط بمستند.',
                style: TextStyle(fontSize: 12, color: context.picposMuted),
              ),
            )
          else
            for (final b in c.bindings)
              _BindingRow(
                binding: b,
                onRelease: () => _release(context, ref, b),
              ),

          const SizedBox(height: 14),
          const PicPosSectionHeader(
            title: 'إجراءات',
            icon: PhosphorIconsBold.lightning,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // «تحرير» في عقد الأزرار §٢ — يفتح المحرّرَ على هذا القالب
              // بتمرير `templateId`. وهو المدخلُ الأوّلُ للمحرّر.
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        TemplateEditorPicposScreen(templateId: c.id),
                  ),
                ),
                icon: const Icon(PhosphorIconsBold.pencilSimple, size: 15),
                label: const Text('تحرير'),
              ),
              // «طباعة تجريبية» في عقد الأزرار §٢ — تفتح المعاينةَ على هذا
              // القالب بعينه، فتُفحص حالاتُه الحدّيّةُ قبل التفعيل.
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PrintTestPicposScreen(templateId: c.id),
                  ),
                ),
                icon: const Icon(PhosphorIconsBold.testTube, size: 15),
                label: const Text('معاينة تجريبية'),
              ),
              OutlinedButton.icon(
                onPressed: () => _duplicate(context, ref, c),
                icon: const Icon(PhosphorIconsBold.copy, size: 15),
                label: const Text('نسخة'),
              ),
              OutlinedButton.icon(
                onPressed: () => _delete(context, ref, c),
                icon: const Icon(PhosphorIconsBold.trash, size: 15),
                label: const Text('حذف'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _duplicate(
      BuildContext context, WidgetRef ref, TemplateCard c) async {
    final repo = ref.read(invoiceTemplatesRepositoryProvider);
    try {
      final id = await repo.duplicateTemplate(c.id);
      ref.read(templateLibraryRefreshProvider.notifier).bump();
      ref.read(selectedTemplateIdProvider.notifier).set(id);
      if (context.mounted) {
        _toast(context, 'أُنشئت نسخةٌ من «${c.name}» — بلا رابطات',
            AppColors.success);
      }
    } catch (e) {
      if (context.mounted) _toast(context, 'تعذّر النسخ: $e', AppColors.error);
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, TemplateCard c) async {
    final repo = ref.read(invoiceTemplatesRepositoryProvider);
    try {
      await repo.deleteTemplateGuarded(c.id);
      ref.read(templateLibraryRefreshProvider.notifier).bump();
      ref.read(selectedTemplateIdProvider.notifier).set(null);
      if (context.mounted) {
        _toast(context, 'حُذف «${c.name}»', AppColors.success);
      }
    } catch (e) {
      // الرفضُ يقول بكم رابطة — لا «مرفوض» مجرَّداً.
      if (context.mounted) {
        _toast(
          context,
          'لا يُحذف «${c.name}»: مربوطٌ بـ${c.bindings.length} مستند. '
          'فُكَّ الرابطةَ أوّلاً.',
          AppColors.error,
        );
      }
    }
  }

  Future<void> _release(
      BuildContext context, WidgetRef ref, TemplateBindingView b) async {
    final repo = ref.read(invoiceTemplatesRepositoryProvider);
    final n = await repo.deactivateBinding(documentType: b.documentType);
    ref.read(templateLibraryRefreshProvider.notifier).bump();
    if (context.mounted) {
      _toast(
        context,
        n > 0
            ? 'فُكَّت رابطةُ «${b.documentLabel}» — يعود إلى القالب الافتراضيّ'
            : 'لا رابطةَ لِـ«${b.documentLabel}» لتُفكّ',
        n > 0 ? AppColors.warning : AppColors.textMuted,
      );
    }
  }

  void _toast(BuildContext context, String msg, Color tone) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: tone,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _Spec extends StatelessWidget {
  const _Spec({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: TextStyle(fontSize: 11.5, color: context.picposMuted),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: tone ?? context.picposText,
                ),
              ),
            ),
          ],
        ),
      );
}

class _BindingRow extends StatelessWidget {
  const _BindingRow({required this.binding, required this.onRelease});

  final TemplateBindingView binding;
  final VoidCallback onRelease;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: context.picposField,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: context.picposHairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    binding.documentLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.picposText,
                    ),
                  ),
                  Text(
                    binding.scope,
                    style:
                        TextStyle(fontSize: 10.5, color: context.picposMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'فكُّ الرابطة',
              onPressed: onRelease,
              icon: const Icon(PhosphorIconsBold.linkBreak, size: 15),
              color: AppColors.warning,
            ),
          ],
        ),
      );
}
