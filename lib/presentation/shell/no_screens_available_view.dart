// حالةُ «لا توجد شاشات متاحة لحسابك» (B-7).
//
// مستخدمٌ لا يفتح أيَّ شاشة كان يقع في هيكلٍ فارغٍ بلا مخرج (أو تُحقَن له لوحةُ
// تحكّمٍ لا يملكها). الآن تُعرض رسالةٌ صريحةٌ مع زرّ تسجيل الخروج.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/data/providers/providers.dart';

class NoScreensAvailableView extends ConsumerWidget {
  const NoScreensAvailableView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 56, color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text(
                  tr('لا توجد شاشات متاحة لحسابك'),
                  key: const Key('no_screens_available_title'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('تواصل مع مدير النظام لمنحك صلاحية فتح شاشة.'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  key: const Key('no_screens_available_logout'),
                  onPressed: () => ref.read(authProvider.notifier).logout(),
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(tr('تسجيل الخروج')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}