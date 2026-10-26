// Leftover #1b: the branch-device warning about the offline-login grace.
//
//  * within 2 days of the end of the grace: "N days left - connect to the main
//    to renew";
//  * grace over (or device clock rolled back): "offline login expired - connect
//    to the main".
// Collapses to nothing everywhere else (the main, standalone, nobody signed in,
// plenty of time left). The countdown comes from the credential stamps through
// [offlineStandingProvider]; the view itself is a pure widget over a standing.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/tr.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/offline_login_providers.dart';
import '../../services/auth/offline_login_standing.dart';
import '../picpos_shell/picpos_surface.dart';

class OfflineLoginExpiryBanner extends ConsumerWidget {
  const OfflineLoginExpiryBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(offlineStandingProvider).value;
    if (s == null) return const SizedBox.shrink();
    return OfflineLoginExpiryBannerView(standing: s);
  }
}

String offlineExpiryText(OfflineStanding s) => switch (s.kind) {
      OfflineStandingKind.expired =>
        tr('انتهت مدة الدخول دون اتصال. اتصل بالنظام الرئيسي لتجديدها.'),
      OfflineStandingKind.expiring => s.daysLeft <= 1
          ? tr('آخر يوم للدخول دون اتصال. اتصل بالنظام الرئيسي لتجديد التحقق.')
          : tr('بقي يومان للدخول دون اتصال. اتصل بالنظام الرئيسي لتجديد التحقق.'),
      OfflineStandingKind.hidden => '',
    };

class OfflineLoginExpiryBannerView extends StatelessWidget {
  const OfflineLoginExpiryBannerView({super.key, required this.standing});

  final OfflineStanding standing;

  @override
  Widget build(BuildContext context) {
    if (!standing.visible) return const SizedBox.shrink();
    final expired = standing.kind == OfflineStandingKind.expired;
    final color = expired ? AppColors.error : AppColors.warning;
    return Container(
      key: Key(expired ? 'offline_expiry_expired' : 'offline_expiry_warning'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.picposIsDark ? 0.22 : 0.12),
        border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          Icon(expired ? Icons.wifi_off : Icons.schedule, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              offlineExpiryText(standing),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: context.picposText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}