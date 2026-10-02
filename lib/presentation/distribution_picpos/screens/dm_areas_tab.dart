// تبويبُ «المناطق» — مناطقُ التوزيع (منفصلةٌ عن مناطق تجميع الفروع).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/distribution_model.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../distribution_picpos_providers.dart';

/// هل يملك المستخدمُ إدارةَ التوزيع (إنشاءً وتعديلاً وإسناداً)؟
bool dmCanManage(WidgetRef ref) =>
    ref.watch(hasPermissionProvider(PermissionCodes.distributionManage)).value ??
    false;

class DmAreasTab extends ConsumerWidget {
  const DmAreasTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areas = ref.watch(dmAreasProvider).value ?? const [];
    final routes = ref.watch(dmRoutesProvider).value ?? const [];
    final canManage = dmCanManage(ref);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        PicPosDataTable(
          title: tr('مناطق التوزيع'),
          subtitle: tr('كل مسار يتبع منطقة توزيع واحدة'),
          emptyLabel: tr('لا مناطق بعد'),
          headerAction: canManage
              ? FilledButton.icon(
                  key: const Key('dm_area_new'),
                  onPressed: () => showDmAreaDialog(context, ref),
                  icon: const Icon(PhosphorIconsBold.plus, size: 16),
                  label: Text(tr('منطقة جديدة')),
                )
              : null,
          columns: [
            PicPosTableColumn(tr('المنطقة'), flex: 2),
            PicPosTableColumn(tr('الكود')),
            PicPosTableColumn(tr('الحدود'), flex: 3),
            PicPosTableColumn(tr('المسارات'), align: PicPosCellAlign.end),
            PicPosTableColumn(tr('الحالة')),
            PicPosTableColumn(tr('إجراءات')),
          ],
          rows: [
            for (final a in areas)
              PicPosTableRow(cells: [
                PicPosTextCell(a.name,
                    icon: PhosphorIconsBold.mapPin, tint: AppColors.primary),
                PicPosTextCell(a.code ?? '—'),
                PicPosTextCell(a.boundary ?? '—'),
                PicPosTextCell(
                    '${routes.where((r) => r.areaId == a.id).length}'),
                PicPosPillCell(a.isActive ? tr('نشط') : tr('موقوف'),
                    a.isActive ? AppColors.success : AppColors.warning),
                PicPosButtonCell(
                  tr('تعديل'),
                  icon: PhosphorIconsBold.pencilSimple,
                  tint: AppColors.info,
                  onPressed: canManage
                      ? () => showDmAreaDialog(context, ref, area: a)
                      : null,
                ),
              ]),
          ],
        ),
      ],
    );
  }
}

Future<void> showDmAreaDialog(BuildContext context, WidgetRef ref,
    {DistributionArea? area}) async {
  final name = TextEditingController(text: area?.name);
  final code = TextEditingController(text: area?.code);
  final boundary = TextEditingController(text: area?.boundary);
  var active = area?.isActive ?? true;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(area == null ? tr('منطقة جديدة') : tr('تعديل المنطقة')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('dm_area_name'),
                controller: name,
                decoration: InputDecoration(labelText: tr('اسم المنطقة')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: code,
                decoration: InputDecoration(labelText: tr('الكود')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: boundary,
                maxLines: 2,
                decoration: InputDecoration(labelText: tr('وصف الحدود')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: active,
                onChanged: (v) => setState(() => active = v),
                title: Text(tr('نشط')),
              ),
            ],
          ),
        ),
        actions: [
          if (area != null)
            TextButton(
              onPressed: () async {
                try {
                  await ref
                      .read(databaseProvider)
                      .deleteDistributionArea(area.id);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    AppToast.show(ctx, '$e', type: ToastType.error);
                  }
                }
              },
              child: Text(tr('حذف'),
                  style: const TextStyle(color: AppColors.error)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('إلغاء'))),
          FilledButton(
            key: const Key('dm_area_save'),
            onPressed: () async {
              try {
                await ref.read(databaseProvider).saveDistributionArea(
                      id: area?.id,
                      name: name.text,
                      code: code.text,
                      boundary: boundary.text,
                      isActive: active,
                    );
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) AppToast.show(ctx, '$e', type: ToastType.error);
              }
            },
            child: Text(tr('حفظ')),
          ),
        ],
      ),
    ),
  );
  if (saved == true) refreshDistribution(ref);
}
