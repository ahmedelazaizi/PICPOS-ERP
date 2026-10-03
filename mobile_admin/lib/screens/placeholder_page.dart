import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';

/// A destination whose screens arrive in a later phase.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title, required this.subtitle, required this.icon, required this.message});
  final String title;
  final String subtitle;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PicPosPageHeader(
        title: title,
        subtitle: subtitle,
        icon: icon,
        actions: const [ConnectionChip(connection: PicPosConnection.offline)],
      ),
      Expanded(child: EmptyState(icon: icon, title: t('comingTitle'), message: message)),
    ]);
  }
}
