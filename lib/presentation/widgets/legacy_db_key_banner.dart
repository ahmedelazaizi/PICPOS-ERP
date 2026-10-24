import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../data/providers/providers.dart';
import '../../services/db_encryption_actions.dart';
import '../settings_picpos/widgets/database_encryption_block.dart';

/// SEC-005 — true while the local database is still encrypted with the legacy
/// device-derived key (derivable by anyone who can read the device id + the
/// public pepper). Upgraded installs stay on it until an admin migrates
/// ("no automatic migration" owner decision), so the admin is warned
/// persistently instead.
final legacyDbKeyWarningProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(dbEncryptionSupportedProvider)) return false;
  final status = await ref.read(dbEncryptionActionsProvider).status();
  return status.state == DbEncryptionState.legacy;
});

/// Persistent, NON-dismissable banner for administrators while
/// [legacyDbKeyWarningProvider] is true. Collapses to nothing otherwise
/// (other users never see it; it disappears once the migration is confirmed).
class LegacyDbKeyBanner extends ConsumerWidget {
  const LegacyDbKeyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(currentUserPermissionsProvider).maybeWhen(
          data: (codes) => codes.contains('system_admin') || codes.contains('*'),
          orElse: () => false,
        );
    final legacy = ref.watch(legacyDbKeyWarningProvider).maybeWhen(
          data: (v) => v,
          orElse: () => false,
        );
    if (!isAdmin || !legacy) return const SizedBox.shrink();
    return Material(
      color: Colors.orange.shade800,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(PhosphorIconsBold.shieldWarning, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('قاعدة البيانات مشفّرة بمفتاح قديم مشتق من الجهاز. رحّلها إلى مفتاح عشوائي من الإعدادات ← الأمان ← تشفير قاعدة البيانات.'),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
