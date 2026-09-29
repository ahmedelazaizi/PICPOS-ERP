import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/i18n/locale_provider.dart';
import '../../core/i18n/tr.dart';

class UserLanguageSelector extends ConsumerWidget {
  const UserLanguageSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(userLocaleProvider);
    return ListTile(
      leading: const Icon(PhosphorIconsBold.translate),
      title: Text(tr('لغة الواجهة')),
      subtitle: Text(tr('تُحفظ لكل مستخدم وتغيّر اتجاه الشاشة تلقائياً')),
      trailing: DropdownButton<Locale>(
        value: locale,
        underline: const SizedBox.shrink(),
        items:  [
          DropdownMenuItem(
            value: defaultUserLocale,
            child: Text(tr('العربية')),
          ),
          const DropdownMenuItem(
            value: englishUserLocale,
            child: Text('English'),
          ),
        ],
        onChanged: (next) {
          if (next != null) {
            ref.read(userLocaleProvider.notifier).setLocale(next);
          }
        },
      ),
    );
  }
}
