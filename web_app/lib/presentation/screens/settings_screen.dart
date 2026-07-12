import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('الإعدادات'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // User info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.primary,
                    child: Icon(PhosphorIconsBold.user, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authState.user?.fullName ?? authState.user?.username ?? 'مستخدم',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'الصلاحية: ${authState.user?.role ?? "غير معروف"}',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Theme toggle
          Card(
            child: ListTile(
              leading: Icon(
                isDarkMode ? PhosphorIconsBold.moon : PhosphorIconsBold.sun,
                color: AppColors.primary,
              ),
              title: const Text('الوضع الليلي'),
              subtitle: Text(isDarkMode ? 'مفعل' : 'معطل'),
              trailing: Switch(
                value: isDarkMode,
                onChanged: (value) {
                  ref.read(themeModeProvider.notifier).setDarkMode(value);
                },
                activeThumbColor: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // App info
          Card(
            child: ListTile(
              leading: const Icon(PhosphorIconsBold.info, color: AppColors.info),
              title: const Text('عن التطبيق'),
              subtitle: const Text('UralCash Web v1.0.0'),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'UralCash Web',
                  applicationVersion: '1.0.0',
                  applicationLegalese: '© 2024 Ural Solutions',
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Logout
          Card(
            child: ListTile(
              leading: const Icon(PhosphorIconsBold.signOut, color: AppColors.danger),
              title: const Text('تسجيل الخروج'),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('تسجيل الخروج'),
                    content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('إلغاء'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          ref.read(authProvider.notifier).logout();
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                        child: const Text('تسجيل الخروج'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
