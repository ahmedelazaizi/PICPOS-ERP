import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';

/// Settings card wrapper widget
class SettingsCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Widget> children;

  const SettingsCard({
    super.key,
    required this.title,
    this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: AppColors.primary, size: 24),
                  const SizedBox(width: 12),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Backup item widget
class BackupListItem extends StatelessWidget {
  final String backupPath;
  final VoidCallback onRestore;
  final VoidCallback? onDelete;

  const BackupListItem({
    super.key,
    required this.backupPath,
    required this.onRestore,
    this.onDelete,
  });

  String get _filename {
    return backupPath.split('/').last.split('\\').last;
  }

  String get _formattedDate {
    // Extract date from filename: backup_2026-01-17T12-30-45.db
    final match = RegExp(
      r'backup_(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})',
    ).firstMatch(_filename);
    if (match != null) {
      return '${match.group(3)}/${match.group(2)}/${match.group(1)} ${match.group(4)}:${match.group(5)}';
    }
    return _filename;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.info.withValues(alpha: 0.1),
        child: const Icon(PhosphorIconsBold.database, color: AppColors.info),
      ),
      title: Text(_formattedDate),
      subtitle: Text(
        _filename,
        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            icon: const Icon(PhosphorIconsBold.arrowCounterClockwise),
            label:  Text(tr('استعادة')),
            onPressed: onRestore,
          ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(PhosphorIconsBold.trash, color: AppColors.error),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

/// Setting toggle tile
class SettingToggleTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingToggleTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppColors.primary,
      ),
    );
  }
}
