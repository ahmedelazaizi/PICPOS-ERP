import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../state/app_controller.dart';

/// Inherited access to the controller (no extra state package in I-1).
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

String money(num v) => v.toStringAsFixed(2);

void showFailure(BuildContext context, Object e) {
  final s = S.of(context);
  final msg = e is AppFailure ? s.t(e.code) : s.t('error');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Label + value row used on cards (tabular figures for amounts).
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Text(value,
              style: t.titleMedium?.copyWith(
                  color: valueColor, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
