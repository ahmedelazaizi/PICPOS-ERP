import 'package:picpos_erp/core/i18n/tr.dart';
// «ملصق جديد» — اسمٌ ومقاسٌ مخصّصٌ بالمليمتر، ثمّ يُفتح في قماش الملصق.
//
// المقاساتُ الجاهزةُ هي نفسُ مقاسات الملصقات المبذورة، والمخصَّصُ حرٌّ بين
// [kLabelMinMm] و[kLabelMaxMm] — حدودُ ما يحمل باركوداً ويسعه عرضُ A4.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/repository_providers.dart';
import '../../../data/providers/template_library_providers.dart';
import '../../../domain/printing/label_design.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../template_editor_picpos/screens/template_editor_picpos_screen.dart';

const _presets = <(double, double)>[
  (50, 25),
  (50, 30),
  (60, 40),
  (40, 20),
  (30, 15),
  (100, 50),
];

/// يُنشئ ملصقاً ويفتحه في المحرّر. يُرجع مُعرِّفَه أو `null` عند الإلغاء.
Future<int?> showNewLabelDialog(BuildContext context, WidgetRef ref) async {
  final id = await showDialog<int>(
    context: context,
    builder: (_) => const Dialog(child: _NewLabelDialog()),
  );
  if (id != null && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TemplateEditorPicposScreen(templateId: id, labelMode: true),
    ));
  }
  return id;
}

class _NewLabelDialog extends ConsumerStatefulWidget {
  const _NewLabelDialog();

  @override
  ConsumerState<_NewLabelDialog> createState() => _NewLabelDialogState();
}

class _NewLabelDialogState extends ConsumerState<_NewLabelDialog> {
  final _name = TextEditingController();
  final _w = TextEditingController(text: '50');
  final _h = TextEditingController(text: '25');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SizedBox(
        width: 440,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(PhosphorIconsBold.barcode,
                      size: 18, color: context.picposBrandInk),
                  const SizedBox(width: 8),
                  Text(tr('ملصق باركود جديد'),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: context.picposText)),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('new-label-name'),
                controller: _name,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: tr('اسم الملصق'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in _presets)
                    ActionChip(
                      label: Text('${p.$1.toInt()}×${p.$2.toInt()}',
                          textDirection: TextDirection.ltr),
                      onPressed: () => setState(() {
                        _w.text = p.$1.toInt().toString();
                        _h.text = p.$2.toInt().toString();
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _mm(const Key('new-label-w'), _w, tr('العرض (مم)'))),
                  const SizedBox(width: 10),
                  Expanded(child: _mm(const Key('new-label-h'), _h, tr('الارتفاع (مم)'))),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(fontSize: 12, color: AppColors.error)),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(tr('إلغاء')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('new-label-create'),
                    onPressed: _busy ? null : _create,
                    icon: const Icon(PhosphorIconsBold.plus, size: 15),
                    label: Text(tr('إنشاء وفتح')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mm(Key key, TextEditingController c, String label) => TextField(
        key: key,
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      );

  Future<void> _create() async {
    final w = double.tryParse(_w.text.trim());
    final h = double.tryParse(_h.text.trim());
    if (w == null || h == null ||
        w < kLabelMinMm || h < kLabelMinMm ||
        w > kLabelMaxMm || h > kLabelMaxMm) {
      setState(() => _error = tr('المقاسُ بين {min} و{max} مم', {
            'min': kLabelMinMm.toInt(),
            'max': kLabelMaxMm.toInt(),
          }));
      return;
    }
    final name = _name.text.trim().isEmpty
        ? tr('ملصق {w}×{h}', {'w': _w.text.trim(), 'h': _h.text.trim()})
        : _name.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(invoiceTemplatesRepositoryProvider)
          .createLabelTemplate(name: name, widthMm: w, heightMm: h);
      ref.read(templateLibraryRefreshProvider.notifier).bump();
      ref.read(selectedTemplateIdProvider.notifier).set(id);
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('تعذّر إنشاءُ الملصق: {e}', {'e': e});
        });
      }
    }
  }
}
