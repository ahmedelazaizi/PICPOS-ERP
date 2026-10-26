// The banners stacked above the app shell body: SEC-005 (admin-only, legacy
// database key) and the branch-device offline-login grace warning. Both
// self-collapse, so an ordinary session sees nothing.
import 'package:flutter/material.dart';

import 'legacy_db_key_banner.dart';
import 'offline_login_expiry_banner.dart';

class ShellBanners extends StatelessWidget {
  const ShellBanners({super.key});

  @override
  Widget build(BuildContext context) => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [LegacyDbKeyBanner(), OfflineLoginExpiryBanner()],
      );
}