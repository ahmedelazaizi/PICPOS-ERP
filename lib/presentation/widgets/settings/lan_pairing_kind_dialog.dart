import 'package:flutter/material.dart';

import 'package:picpos_erp/core/i18n/tr.dart';
import '../../../data/providers/providers.dart' show Branche;

/// What the administrator chose for the pairing code (plan 2026-10-24, M1):
/// the code carries the device kind (and the branch for branch devices), the
/// new device never picks either.
class LanPairingKindChoice {
  const LanPairingKindChoice(this.kind, this.branchId);
  final String kind;
  final int? branchId;
}

/// Kinds offered here: `warehouse` has its own flow (TLS-bound phone app).
const Map<String, String> _kindLabels = {
  'client': 'جهاز فرع (محاسب / مخزني / إداري)',
  'pos': 'نقطة بيع (كاشير / مندوب)',
  'mirror': 'كونسول مدير الفروع (المرآة)',
  'admin': 'تطبيق الإدارة على الهاتف',
};

bool _needsBranch(String kind) => kind == 'client' || kind == 'pos';

/// Asks which kind of device the code is for. Returns `null` when cancelled.
Future<LanPairingKindChoice?> showLanPairingKindDialog(
  BuildContext context,
  List<Branche> branches,
) {
  return showDialog<LanPairingKindChoice>(
    context: context,
    builder: (_) => _KindDialog(branches: branches),
  );
}

class _KindDialog extends StatefulWidget {
  const _KindDialog({required this.branches});
  final List<Branche> branches;

  @override
  State<_KindDialog> createState() => _KindDialogState();
}

class _KindDialogState extends State<_KindDialog> {
  String _kind = 'client';
  int? _branchId;

  @override
  Widget build(BuildContext context) {
    final needsBranch = _needsBranch(_kind);
    final canContinue = !needsBranch || _branchId != null;
    return AlertDialog(
      title: Text(tr('نوع الجهاز المراد إقرانه')),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<String>(
              groupValue: _kind,
              onChanged: (v) => setState(() => _kind = v ?? _kind),
              child: Column(
                children: [
                  for (final e in _kindLabels.entries)
                    RadioListTile<String>(
                      dense: true,
                      value: e.key,
                      title: Text(tr(e.value)),
                    ),
                ],
              ),
            ),
            if (needsBranch) ...[
              const SizedBox(height: 8),
              if (widget.branches.isEmpty)
                Text(tr('لا توجد فروع نشطة'))
              else
                DropdownButtonFormField<int>(
                  initialValue: _branchId,
                  decoration: InputDecoration(
                    labelText: tr('الفرع'),
                    hintText: tr('اختر الفرع'),
                    isDense: true,
                  ),
                  items: [
                    for (final b in widget.branches)
                      DropdownMenuItem(value: b.id, child: Text(b.name)),
                  ],
                  onChanged: (v) => setState(() => _branchId = v),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('إلغاء')),
        ),
        FilledButton(
          onPressed: canContinue
              ? () => Navigator.pop(
                    context,
                    LanPairingKindChoice(_kind, needsBranch ? _branchId : null),
                  )
              : null,
          child: Text(tr('متابعة')),
        ),
      ],
    );
  }
}
