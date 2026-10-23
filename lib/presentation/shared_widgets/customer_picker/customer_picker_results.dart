import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart' show Party;
import '../../widgets/permission_guard.dart';

/// لوحةُ نتائج المنتقي: العملاءُ المطابقون، ثم «+ عميل جديد: "…"» و«ضيف بلا
/// تسجيل» كعنصرين ثابتين في آخر القائمة. الفهرسُ [highlight] للأسهم/Enter:
/// 0..n-1 العملاء، n الإضافة السريعة، n+1 الضيف.
class CustomerPickerResults extends StatelessWidget {
  const CustomerPickerResults({
    super.key,
    required this.parties,
    required this.query,
    required this.highlight,
    required this.onPick,
    required this.onAddNew,
    required this.onGuest,
    this.loading = false,
  });

  final List<Party> parties;
  final String query;
  final int highlight;
  final bool loading;
  final ValueChanged<Party> onPick;
  final VoidCallback onAddNew;
  final VoidCallback onGuest;

  /// عددُ عناصر الملاحة (العملاء + إضافة + ضيف).
  static int itemCount(int partiesLength) => partiesLength + 2;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('customer_picker_results'),
      elevation: 2,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            if (loading && parties.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            for (var i = 0; i < parties.length; i++)
              _row(
                context,
                key: ValueKey('customer_result_${parties[i].id}'),
                selected: highlight == i,
                icon: PhosphorIconsBold.user,
                title: parties[i].name,
                subtitle: parties[i].phone,
                onTap: () => onPick(parties[i]),
              ),
            if (!loading && parties.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(tr('لا يوجد عميل مطابق'),
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            const Divider(height: 1),
            // الإضافة السريعة تحتاج customers_add: معطَّلةٌ لا مخفيّة.
            PermissionGuard(
              permission: PermissionCodes.customersAdd,
              showDisabled: true,
              child: _row(
                context,
                key: const ValueKey('customer_result_new'),
                selected: highlight == parties.length,
                icon: PhosphorIconsBold.userPlus,
                title: tr('+ عميل جديد: {p0}', {'p0': '"${query.trim()}"'}),
                onTap: onAddNew,
              ),
            ),
            _row(
              context,
              key: const ValueKey('customer_result_guest'),
              selected: highlight == parties.length + 1,
              icon: PhosphorIconsBold.userCircleDashed,
              title: tr('ضيف بلا تسجيل'),
              onTap: onGuest,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required Key key,
    required bool selected,
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: key,
      onTap: onTap,
      child: Container(
        color: selected ? scheme.primary.withValues(alpha: .10) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            if (subtitle != null && subtitle.isNotEmpty)
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }
}
