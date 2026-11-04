// لوحةُ «مجموعات التصنيفات» في أدوات المطوّر (بند 10): حذفٌ ناعمٌ آمن.
//
// ⚠️ تُركَّب خلفَ `DeveloperPasswordGate` فقط (تُسجَّل في `DeveloperToolsPanels`).
// المنطقُ كلُّه في `CategoryDeleteDao` — هنا عرضٌ وتأكيدٌ وتسجيلٌ فقط.
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';

import '../../../core/config/developer_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../products/providers/categories_controller.dart';
import 'category_delete_reasons.dart';

class DeveloperCategoriesSection extends ConsumerStatefulWidget {
  const DeveloperCategoriesSection({super.key});

  @override
  ConsumerState<DeveloperCategoriesSection> createState() =>
      _DeveloperCategoriesSectionState();
}

class _DeveloperCategoriesSectionState
    extends ConsumerState<DeveloperCategoriesSection> {
  List<CategoryDeleteAnalysis> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final cats = await (db.select(db.categories)
          ..where((c) => c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .get();
    final rows = <CategoryDeleteAnalysis>[
      for (final c in cats) await db.analyzeCategoryDelete(c.id),
    ];
    if (!mounted) return;
    setState(() {
      _rows = rows.where((r) => r.category != null).toList();
      _loading = false;
    });
  }

  Future<void> _delete(CategoryDeleteAnalysis shown) async {
    final cat = shown.category!;
    final db = ref.read(databaseProvider);
    // نُعيد الفحصَ لحظةَ الفتح فلا نعتمد على أعدادٍ قديمة.
    final fresh = await db.analyzeCategoryDelete(cat.id);
    if (!mounted || fresh.category == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => CategoryDeleteDialog(analysis: fresh),
    );
    if (ok != true || !mounted) return;

    // فحصٌ أخيرٌ بعد التأكيد: لو دخل صنفٌ في الأثناء يُرفض الحذف.
    final last = await db.analyzeCategoryDelete(cat.id);
    if (last.category == null || last.strictBlocks.isNotEmpty) {
      if (mounted) {
        AppToast.show(
          context,
          tr('تغيّر التصنيف أثناء التأكيد ولم يعد قابلاً للحذف.'),
          type: ToastType.error,
        );
        _load();
      }
      return;
    }
    final done = await ref
        .read(categoriesControllerProvider.notifier)
        .deleteCategory(cat.id, cat.name);
    if (!mounted) return;
    if (!done) {
      AppToast.show(context, tr('تعذّر حذف التصنيف.'), type: ToastType.error);
      return;
    }
    // سجلُّ النشاط مُنتظَر (لا unawaited) ويحمل الأعداد والمعرّف العالمي.
    final user = ref.read(authProvider).user;
    try {
      await ref.read(productRepositoryProvider).logActivity(
            userId: user?.id,
            userName: user?.displayName ?? tr('مستخدم'),
            action: 'category_delete_dev',
            entityId: cat.id,
            description: categoryDeleteAuditText(last),
          );
    } catch (_) {/* فشلُ السجلّ لا يُلغي حذفاً تمّ */}
    ref.read(developerSessionProvider.notifier).extend();
    if (!mounted) return;
    AppToast.show(context, tr('تم حذف التصنيف: {name}', {'name': cat.name}));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('مجموعات التصنيفات'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              tr('حذف ناعم: يُسمح فقط للتصنيف الفارغ غير الافتراضي وغير المقفل.'),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_rows.isEmpty)
              Text(tr('لا توجد تصنيفات.'))
            else
              for (final r in _rows)
                ListTile(
                  key: ValueKey('dev-cat-${r.category!.id}'),
                  dense: true,
                  title: Text(r.category!.name),
                  subtitle: Text(tr(
                    '{n} صنف · {c} تصنيف فرعي',
                    {'n': r.totalProducts, 'c': r.activeChildren},
                  )),
                  trailing: IconButton(
                    key: ValueKey('dev-cat-del-${r.category!.id}'),
                    tooltip: tr('حذف التصنيف'),
                    icon: const Icon(Icons.delete_outline),
                    color: AppColors.error,
                    onPressed: () => _delete(r),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// حوارُ التأكيد: يعرض أسبابَ المنع إن وُجدت، وإلّا يطلب كتابةَ اسم التصنيف.
class CategoryDeleteDialog extends StatefulWidget {
  final CategoryDeleteAnalysis analysis;
  const CategoryDeleteDialog({super.key, required this.analysis});

  @override
  State<CategoryDeleteDialog> createState() => _CategoryDeleteDialogState();
}

class _CategoryDeleteDialogState extends State<CategoryDeleteDialog> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.analysis;
    final name = a.category!.name;
    final blocks = a.strictBlocks;
    final matches = _ctl.text.trim() == name.trim();
    return AlertDialog(
      title: Text(tr('حذف تصنيف "{name}"', {'name': name})),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (blocks.isNotEmpty) ...[
              Text(tr('لا يمكن حذف هذا التصنيف للأسباب التالية:'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final b in blocks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• ${categoryDeleteBlockText(b, a)}'),
                ),
            ] else ...[
              Text(tr(
                'سيتم حذف التصنيف "{name}" حذفاً ناعماً ويختفي من كل الأجهزة بعد المزامنة. اكتب اسم التصنيف للتأكيد:',
                {'name': name},
              )),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('dev-cat-confirm-field'),
                controller: _ctl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr('إلغاء')),
        ),
        if (blocks.isEmpty)
          FilledButton(
            key: const ValueKey('dev-cat-confirm-btn'),
            onPressed: matches ? () => Navigator.pop(context, true) : null,
            child: Text(tr('تأكيد الحذف')),
          ),
      ],
    );
  }
}
