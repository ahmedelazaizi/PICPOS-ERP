import 'package:flutter/material.dart';
import 'package:picpos_device/picpos_device.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../session/wh_session.dart' show errorCode;
import '../sync/wh_ops.dart';
import '../sync/wh_outbox.dart';

/// Minimum touch target for primary actions (plan §B.3: >= 56 dp).
const double kBigTarget = 56;

/// Scan-first input: focused on open, a hardware (wedge) scanner types the
/// code and presses Enter; the camera button is the fallback. The soft
/// keyboard is not forced open by the scanner's input.
class ScanField extends StatefulWidget {
  const ScanField({super.key, required this.ops, required this.onScan, this.label});
  final WhOps ops;
  final ValueChanged<String> onScan;
  final String? label;

  @override
  State<ScanField> createState() => _ScanFieldState();
}

class _ScanFieldState extends State<ScanField> {
  final _c = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final code = normalizeScan(raw);
    _c.clear();
    if (code.isNotEmpty) widget.onScan(code);
    _focus.requestFocus();
  }

  Future<void> _camera() async {
    final code = await widget.ops.scanner(context, qr: false);
    if (code != null && mounted) _submit(code);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Row(children: [
      Expanded(
        child: TextField(
          key: const Key('scan.field'),
          controller: _c,
          focusNode: _focus,
          autofocus: true,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.done,
          onSubmitted: _submit,
          decoration: InputDecoration(labelText: widget.label ?? t('scanOrType'), prefixIcon: const Icon(Icons.qr_code_scanner)),
        ),
      ),
      const SizedBox(width: PicPosSpacing.sm),
      IconButton.filled(
        key: const Key('scan.camera'),
        tooltip: t('scanCamera'),
        constraints: const BoxConstraints.tightFor(width: kBigTarget, height: kBigTarget),
        onPressed: _camera,
        icon: const Icon(Icons.photo_camera_outlined),
      ),
    ]);
  }
}

/// Big numeric keypad (digits, decimal point, backspace). The value is a
/// string so decimals are never rounded on the phone.
class QtyKeypad extends StatelessWidget {
  const QtyKeypad({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  void _press(String k) {
    if (k == '<') return onChanged(value.isEmpty ? '' : value.substring(0, value.length - 1));
    if (k == '.' && (value.contains('.') || value.isEmpty)) return onChanged(value.isEmpty ? '0.' : value);
    if (value == '0' && k != '.') return onChanged(k);
    if (value.length < 12) onChanged('$value$k');
  }

  @override
  Widget build(BuildContext context) {
    const keys = ['7', '8', '9', '4', '5', '6', '1', '2', '3', '.', '0', '<'];
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value.isEmpty ? '0' : value, key: const Key('qty.display'), style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: PicPosSpacing.sm),
        for (var r = 0; r < 4; r++)
          Row(children: [
            for (var c = 0; c < 3; c++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: SizedBox(
                    height: kBigTarget,
                    child: FilledButton.tonal(
                      key: Key('qty.key.${keys[r * 3 + c]}'),
                      onPressed: () => _press(keys[r * 3 + c]),
                      child: keys[r * 3 + c] == '<' ? const Icon(Icons.backspace_outlined) : Text(keys[r * 3 + c], style: Theme.of(context).textTheme.headlineSmall),
                    ),
                  ),
                ),
              ),
          ]),
      ]),
    );
  }
}

/// Bottom sheet with the keypad. Returns the confirmed quantity or null.
Future<String?> askQuantity(BuildContext context, {required String title, String initial = ''}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _QtySheet(title: title, initial: initial),
  );
}

class _QtySheet extends StatefulWidget {
  const _QtySheet({required this.title, required this.initial});
  final String title;
  final String initial;
  @override
  State<_QtySheet> createState() => _QtySheetState();
}

class _QtySheetState extends State<_QtySheet> {
  late String _v = widget.initial;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final ok = (double.tryParse(_v) ?? -1) >= 0 && _v.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(PicPosSpacing.lg, 0, PicPosSpacing.lg, PicPosSpacing.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: PicPosSpacing.sm),
          QtyKeypad(value: _v, onChanged: (v) => setState(() => _v = v)),
          const SizedBox(height: PicPosSpacing.md),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(kBigTarget)),
                  onPressed: () => Navigator.pop(context),
                  child: Text(t('cancel'))),
            ),
            const SizedBox(width: PicPosSpacing.md),
            Expanded(
              child: FilledButton(
                key: const Key('qty.confirm'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(kBigTarget)),
                onPressed: ok ? () => Navigator.pop(context, _v.endsWith('.') ? _v.substring(0, _v.length - 1) : _v) : null,
                child: Text(t('confirm')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Persistent strip under the app bar: offline / sign-in needed / queue size.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.sync});
  final WhSyncState sync;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final text = sync.needsLogin
            ? t('bannerLogin', {'n': '${sync.pending}'})
            : !sync.online
                ? t('bannerOffline', {'n': '${sync.pending}'})
                : sync.pending > 0
                    ? t('bannerPending', {'n': '${sync.pending}'})
                    : null;
        if (text == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Material(
          key: const Key('banner'),
          color: sync.online && !sync.needsLogin ? scheme.secondaryContainer : scheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: PicPosSpacing.lg, vertical: PicPosSpacing.sm),
            child: Row(children: [
              Icon(sync.online && !sync.needsLogin ? Icons.sync : Icons.cloud_off, size: 18),
              const SizedBox(width: PicPosSpacing.sm),
              Expanded(child: Text(text)),
            ]),
          ),
        );
      },
    );
  }
}

/// Shows a refusal with its reason text (no raw server messages).
void showFailure(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(S.errorText(context, errorCode(error))),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
}

void showDone(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
