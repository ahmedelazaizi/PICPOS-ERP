import 'package:flutter/material.dart';

import '../l10n.dart';
import '../tokens.dart';
import 'basics.dart';

/// Connection chip «محلي / سحابي / غير متصل» (ARCHITECTURE-M §3.1).
enum PicPosConnection { local, cloud, offline }

class ConnectionChip extends StatelessWidget {
  const ConnectionChip({super.key, required this.connection});
  final PicPosConnection connection;

  @override
  Widget build(BuildContext context) {
    final t = Tr.of(context, picposUiStrings);
    return switch (connection) {
      PicPosConnection.local => StatusPill(label: t('connLocal'), tone: PicPosTone.success, icon: Icons.lan_outlined),
      PicPosConnection.cloud => StatusPill(label: t('connCloud'), tone: PicPosTone.brand, icon: Icons.cloud_outlined),
      PicPosConnection.offline => StatusPill(label: t('connOffline'), tone: PicPosTone.neutral, icon: Icons.cloud_off_outlined),
    };
  }
}

/// Language (العربية / English) and theme (light / dark) selectors bound to
/// the nearest [PicPosSettingsScope].
class PicPosLanguageThemeControls extends StatelessWidget {
  const PicPosLanguageThemeControls({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tr.of(context, picposUiStrings);
    final s = PicPosSettingsScope.of(context);
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(t('language'), style: tt.labelLarge),
      const SizedBox(height: PicPosSpacing.sm),
      SegmentedButton<String>(
        key: const Key('picpos.language'),
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: 'ar', label: Text(t('arabic'))),
          ButtonSegment(value: 'en', label: Text(t('english'))),
        ],
        selected: {s.isArabic ? 'ar' : 'en'},
        onSelectionChanged: (v) => s.locale = Locale(v.first),
      ),
      const SizedBox(height: PicPosSpacing.lg),
      Text(t('theme'), style: tt.labelLarge),
      const SizedBox(height: PicPosSpacing.sm),
      SegmentedButton<ThemeMode>(
        key: const Key('picpos.theme'),
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode_outlined), label: Text(t('light'))),
          ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_outlined), label: Text(t('dark'))),
        ],
        selected: {s.isDark ? ThemeMode.dark : ThemeMode.light},
        onSelectionChanged: (v) => s.themeMode = v.first,
      ),
    ]);
  }
}
