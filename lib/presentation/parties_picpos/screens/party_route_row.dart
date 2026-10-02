// المرحلة و — صفُّ «المسار · المنطقة · المندوب» على بطاقة العميل.
//
// المندوبُ **مشتقٌّ** من مسار العميل الحاليّ ولا يُخزَّن على الطرف؛ والإسنادُ
// يمرّ بقاعدة «مسارٌ واحدٌ للعميل» في المحرّك.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/models/picpos_party_view.dart';

class PartyRouteRow extends StatelessWidget {
  const PartyRouteRow({super.key, required this.party, this.onAssign});

  final PicPosPartyCard party;

  /// `null` = بلا صلاحيّة إدارة التوزيع — يُعرَض ولا يُسنَد.
  final void Function(PicPosPartyCard)? onAssign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color ?? AppColors.textMuted;
    final onRoute = party.routeName != null;

    Widget cell(String label, String? value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 9.5, fontWeight: FontWeight.w700, color: muted)),
              Text(
                value ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
        );

    return Container(
      key: Key('party-route-${party.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: .07),
        border: Border.all(color: AppColors.info.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          if (onRoute) ...[
            cell(tr('المسار'), party.routeName),
            cell(tr('المنطقة'), party.areaName),
            cell(tr('المندوب'), party.repName),
          ] else
            Expanded(
              child: Text(
                tr('ليس على مسار'),
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: muted),
              ),
            ),
          if (onAssign != null)
            SizedBox(
              width: 26,
              height: 26,
              child: IconButton(
                key: Key('party-assign-route-${party.id}'),
                tooltip: tr('إسناد إلى مسار'),
                padding: EdgeInsets.zero,
                onPressed: () => onAssign!(party),
                icon: const Icon(PhosphorIconsBold.path,
                    size: 14, color: AppColors.info),
              ),
            ),
        ],
      ),
    );
  }
}
