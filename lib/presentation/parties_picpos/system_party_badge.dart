// J3 — شارةُ «نظامي» للأطراف النظاميّة («عميل نقدي» / «مورد نقدي») ومزوِّدُ
// أدوارها. القراءةُ عبر `databaseProvider` لا استيراداً لـ`data/database`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/tr.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';

/// partyId → `parties.system_role`، ويُعاد حسابُه مع كلّ تغيّرٍ في الأطراف.
final systemPartyRolesProvider =
    FutureProvider.autoDispose<Map<int, String>>((ref) {
  ref.watch(allPartiesProvider);
  return ref.watch(databaseProvider).systemPartyRoles();
});

/// الشارةُ نفسُها — صغيرةٌ بجوار الاسم.
class SystemPartyBadge extends StatelessWidget {
  const SystemPartyBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tr('طرف نظامي — لا يُحذف'),
      child: Container(
        key: const Key('system-party-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          tr('نظامي'),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: AppColors.info,
          ),
        ),
      ),
    );
  }
}
