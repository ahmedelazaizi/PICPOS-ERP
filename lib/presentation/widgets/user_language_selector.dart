import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/i18n/locale_provider.dart';
import '../../core/i18n/tr.dart';
import '../../core/theme/app_colors.dart';

class UserLanguageToggle extends ConsumerWidget {
  const UserLanguageToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(userLocaleProvider);
    final isEnglish = locale.languageCode == 'en';
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _languageButton(
            ref,
            label: tr('العربية'),
            locale: defaultUserLocale,
            selected: !isEnglish,
          ),
          _languageButton(
            ref,
            label: tr('English'),
            locale: englishUserLocale,
            selected: isEnglish,
          ),
        ],
      ),
    );
  }

  Widget _languageButton(
    WidgetRef ref, {
    required String label,
    required Locale locale,
    required bool selected,
  }) {
    return Expanded(
      child: TextButton(
        onPressed: selected
            ? null
            : () => ref.read(userLocaleProvider.notifier).setLocale(locale),
        style: TextButton.styleFrom(
          foregroundColor: selected ? Colors.white : AppColors.textMuted,
          backgroundColor: selected
              ? AppColors.primary.withValues(alpha: 0.8)
              : Colors.transparent,
          disabledForegroundColor: Colors.white,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}

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
        items: [
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
