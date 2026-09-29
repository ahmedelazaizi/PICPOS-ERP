import 'package:ural_erp/core/i18n/tr.dart';
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
      return  PicPosContentCard(
        child: PicPosEmptyState(
          icon: PhosphorIconsBold.cursorClick,
          title: tr('اختر قالباً'),
          hint: tr('تفاصيلُه ورابطاتُه وإجراءاتُه تظهر هنا'),
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
          _Spec(label: tr('الورق'), value: tr('{p0} · {p1}مم', {'p0': c.paperLabel, 'p1': c.paperWidthMm.toStringAsFixed(0)})),
          _Spec(label: tr('النوع'), value: '${c.type} · ${c.category}'),
          _Spec(label: tr('العناصر'), value: '${c.elementCount}'),
          _Spec(label: tr('الأعمدة'), value: '${c.columnCount}'),
          _Spec(
            label: tr('نسخةُ التخطيط'),
            value: c.layoutVersion >= 2 ? tr('٢ — نطاقاتٌ بإحداثيّات') : tr('١ — تدفّق'),
          ),
          _Spec(label: tr('الحالة'), value: templateStatusLabel(c),
              tone: templateStatusTone(c)),

          const SizedBox(height: 14),
          PicPosSectionHeader(
            title: tr('المستندات المربوطة'),
            subtitle: c.isBound ? tr('{p0} رابطة', {'p0': c.bindings.length}) : tr('لا رابطة'),
            icon: PhosphorIconsBold.gitFork,
          ),
          if (!c.isBound)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                tr('هذا القالبُ لا يخرج على ورقٍ حتى يُربط بمستند.'),
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
           PicPosSectionHeader(
            title: tr('إجراءات'),
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
                label:  Text(tr('تحرير')),
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
                label:  Text(tr('معاينة تجريبية')),
              ),
              OutlinedButton.icon(
                onPressed: () => _duplicate(context, ref, c),
                icon: const Icon(PhosphorIconsBold.copy, size: 15),
                label:  Text(tr('نسخة')),
              ),
              OutlinedButton.icon(
                onPressed: () => _delete(context, ref, c),
                icon: const Icon(PhosphorIconsBold.trash, size: 15),
                label:  Text(tr('حذف')),
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
        _toast(context, tr('أُنشئت نسخةٌ من «{p0}» — بلا رابطات', {'p0': c.name}),
            AppColors.success);
      }
    } catch (e) {
      if (context.mounted) _toast(context, tr('تعذّر النسخ: {e}', {'e': e}), AppColors.error);
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
        _toast(context, tr('حُذف «{p0}»', {'p0': c.name}), AppColors.success);
      }
    } catch (e) {
      // الرفضُ يقول بكم رابطة — لا «مرفوض» مجرَّداً.
      if (context.mounted) {
        _toast(
          context,
          tr('لا يُحذف «{p0}»: مربوطٌ بـ{p1} مستند. فُكَّ الرابطةَ أوّلاً.', {'p0': c.name, 'p1': c.bindings.length}),
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
            ? tr('فُكَّت رابطةُ «{p0}» — يعود إلى القالب الافتراضيّ', {'p0': b.documentLabel})
            : tr('لا رابطةَ لِـ«{p0}» لتُفكّ', {'p0': b.documentLabel}),
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
              tooltip: tr('فكُّ الرابطة'),
              onPressed: onRelease,
              icon: const Icon(PhosphorIconsBold.linkBreak, size: 15),
              color: AppColors.warning,
            ),
          ],
        ),
      );
}
