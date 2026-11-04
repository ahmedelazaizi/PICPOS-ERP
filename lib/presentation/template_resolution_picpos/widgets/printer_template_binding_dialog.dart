import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/data/providers/repository_providers.dart';
import 'package:picpos_erp/services/printing/paper_compatibility.dart';
import 'package:picpos_erp/services/printing/template_resolver.dart';

typedef _PrinterOption = ({
  int id,
  String name,
  bool isActive,
  String printerType,
  double? paperWidthMm,
});
typedef _TemplateOption = ({
  int id,
  String name,
  String type,
  String templateCategory,
  double paperWidth,
});

/// Picker for an explicit document/printer/template binding.
class PrinterTemplateBindingDialog extends ConsumerStatefulWidget {
  const PrinterTemplateBindingDialog({
    required this.documentType,
    required this.branchId,
    required this.locale,
    super.key,
  });

  final String documentType;
  final int? branchId;
  final String locale;

  @override
  ConsumerState<PrinterTemplateBindingDialog> createState() =>
      _PrinterTemplateBindingDialogState();
}

class _PrinterTemplateBindingDialogState
    extends ConsumerState<PrinterTemplateBindingDialog> {
  _PrinterOption? _printer;
  _TemplateOption? _template;
  List<_PrinterOption> _printers = [];
  List<_TemplateOption> _templates = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final printers = await ref.read(printersRepositoryProvider).getPrinters();
      final templates = await ref
          .read(invoiceTemplatesRepositoryProvider)
          .getAllTemplates();
      if (!mounted) return;
      setState(() {
        _printers = [
          for (final p in printers)
            if (p.isActive)
              (
                id: p.id,
                name: p.name,
                isActive: p.isActive,
                printerType: p.printerType,
                paperWidthMm: p.paperWidthMm,
              ),
        ];
        _templates = [
          for (final t in templates)
            (
              id: t.id,
              name: t.name,
              type: t.type,
              templateCategory: t.templateCategory,
              paperWidth: t.paperWidth,
            ),
        ];
        _printer = _printers.isEmpty ? null : _printers.first;
        _template = _templates.isEmpty ? null : _templates.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  List<_TemplateOption> get _contextTemplates {
    final ctx = TemplateResolver.documentContexts[widget.documentType];
    if (ctx == null) return const [];
    return _templates
        .where((t) => t.type == ctx.type && t.templateCategory == ctx.category)
        .toList();
  }

  PaperFitVerdict _fit(_TemplateOption template, _PrinterOption printer) =>
      checkPaperFit(
        templateWidthMm: template.paperWidth,
        printerWidthMm: printer.paperWidthMm,
      );

  Future<void> _save() async {
    final printer = _printer;
    final template = _template;
    if (printer == null || template == null) return;
    final fit = _fit(template, printer);
    if (fit.isRejected) {
      setState(() => _error = fit.reason);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(invoiceTemplatesRepositoryProvider)
          .activateBinding(
            templateId: template.id,
            documentType: widget.documentType,
            branchId: widget.branchId,
            printerId: printer.id,
            locale: widget.locale,
            printerWidthMm: printer.paperWidthMm,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedPrinter = _printer;
    final compatible = selectedPrinter == null
        ? <_TemplateOption>[]
        : _contextTemplates
              .where((t) => !_fit(t, selectedPrinter).isRejected)
              .toList();
    final incompatible = selectedPrinter == null
        ? <_TemplateOption>[]
        : _contextTemplates
              .where((t) => _fit(t, selectedPrinter).isRejected)
              .toList();
    final fitWarning = selectedPrinter != null && _template != null
        ? _fit(_template!, selectedPrinter)
        : null;
    return AlertDialog(
      title: Text(tr('ربط القالب بطابعة')),
      content: SizedBox(
        width: 540,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _printers.isEmpty
            ? Text(_error ?? tr('لا توجد طابعات معرفة'))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<_PrinterOption>(
                    key: const ValueKey('binding-printer-picker'),
                    value: _printer,
                    decoration: InputDecoration(labelText: tr('الطابعة')),
                    items: [
                      for (final p in _printers)
                        DropdownMenuItem(
                          value: p,
                          child: Text(
                            '${p.name} · ${p.paperWidthMm == null ? tr('عرض غير معروف') : '${p.paperWidthMm} مم'}',
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _printer = v;
                      final compatibleNow = v == null
                          ? <_TemplateOption>[]
                          : _contextTemplates
                                .where((t) => !_fit(t, v).isRejected)
                                .toList();
                      _template = compatibleNow.isEmpty
                          ? null
                          : compatibleNow.first;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<_TemplateOption>(
                    key: const ValueKey('binding-template-picker'),
                    value: compatible.contains(_template) ? _template : null,
                    decoration: InputDecoration(labelText: tr('القالب')),
                    items: [
                      for (final t in compatible)
                        DropdownMenuItem(
                          value: t,
                          child: Text(
                            '${t.name} · ${t.paperWidth} مم',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      for (final t in incompatible)
                        DropdownMenuItem<_TemplateOption>(
                          value: t,
                          enabled: false,
                          child: SizedBox(
                            width: 470,
                            child: Text(
                              '${t.name} · ${_fit(t, selectedPrinter!).reason}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _template = v;
                      _error = null;
                    }),
                  ),
                  if (fitWarning?.isWarning == true) ...[
                    const SizedBox(height: 10),
                    Text(
                      fitWarning!.reason,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(tr('إلغاء')),
        ),
        FilledButton(
          onPressed:
              _saving || _loading || _printer == null || _template == null
              ? null
              : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(tr('حفظ الربط')),
        ),
      ],
    );
  }
}
