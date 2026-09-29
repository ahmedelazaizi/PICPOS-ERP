import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart' show Category;

/// منتقي تصنيف قابل للبحث — نسخة PicPos العامة من الحوار الخاص في
/// product_search_header.dart. يرجّع Category المختار، أو sentinel «الكل».
class PicPosCategoryPicker {
  /// يرجّع (true, null) لو اختار «كل التصنيفات»، (true, cat) لتصنيف، null لو ألغى.
  static Future<(bool, Category?)?> show(
    BuildContext context, {
    required List<Category> categories,
    required int? selectedId,
  }) {
    return showDialog<(bool, Category?)>(
      context: context,
      builder: (_) => _PicPosCategoryDialog(
        categories: categories,
        selectedId: selectedId,
      ),
    );
  }
}

class _PicPosCategoryDialog extends StatefulWidget {
  final List<Category> categories;
  final int? selectedId;
  const _PicPosCategoryDialog({required this.categories, required this.selectedId});
  @override
  State<_PicPosCategoryDialog> createState() => _PicPosCategoryDialogState();
}

class _PicPosCategoryDialogState extends State<_PicPosCategoryDialog> {
  final _ctrl = TextEditingController();
  String _query = '';
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.categories
        : widget.categories.where((c) => c.name.toLowerCase().contains(q)).toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title:  Text(tr('اختر التصنيف')),
        content: SizedBox(
          width: 420,
          height: 500,
          child: Column(
            children: [
              TextField(
                controller: _ctrl,
                autofocus: true,
                decoration:  InputDecoration(
                  hintText: tr('ابحث عن تصنيف...'),
                  prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return ListTile(
                        leading: const Icon(PhosphorIconsBold.listBullets),
                        title:  Text(tr('كل التصنيفات')),
                        selected: widget.selectedId == null,
                        onTap: () => Navigator.pop(context, (true, null)),
                      );
                    }
                    final cat = filtered[i - 1];
                    return ListTile(
                      title: Text(cat.name),
                      selected: cat.id == widget.selectedId,
                      trailing: cat.id == widget.selectedId
                          ? const Icon(PhosphorIconsBold.check, color: AppColors.success)
                          : null,
                      onTap: () => Navigator.pop(context, (true, cat)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إلغاء')),
          ),
        ],
      ),
    );
  }
}
