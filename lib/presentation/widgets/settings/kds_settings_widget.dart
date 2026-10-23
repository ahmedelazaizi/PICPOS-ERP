import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/kitchen_repository.dart';

/// KDS Settings Widget - Manage kitchen stations and category-station mapping
class KdsSettingsWidget extends ConsumerStatefulWidget {
  const KdsSettingsWidget({super.key});

  @override
  ConsumerState<KdsSettingsWidget> createState() => _KdsSettingsWidgetState();
}

class _KdsSettingsWidgetState extends ConsumerState<KdsSettingsWidget> {
  final Set<int> _savingMappingCategoryIds = {};

  @override
  Widget build(BuildContext context) {
    final kitchenRepo = ref.watch(kitchenRepositoryProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: const Icon(PhosphorIconsBold.chefHat, color: AppColors.primary),
        title:  Text(
          tr('إعدادات شاشة المطبخ (KDS)'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle:  Text(tr('ربط التصنيفات بمحطات المطبخ')),
        children: [
          const Divider(height: 1),
          // Stations list
          _buildStationsSection(kitchenRepo),
          const Divider(height: 1),
          // Category → Station mapping
          _buildMappingSection(kitchenRepo),
        ],
      ),
    );
  }

  Widget _buildStationsSection(KitchenRepository kitchenRepo) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsBold.house, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
               Text(tr('محطات المطبخ'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showAddStationDialog(kitchenRepo),
                icon: const Icon(PhosphorIconsBold.plus, size: 16),
                label:  Text(tr('إضافة محطة')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<KitchenStation>>(
            stream: kitchenRepo.watchStations(),
            builder: (context, snapshot) {
              final stations = snapshot.data ?? [];
              if (stations.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.picposField,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:  Center(
                    child: Text(
                      tr('لا توجد محطات — أضف أول محطة (مثل: مطبخ، بار، حلويات)'),
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: stations.map((s) => Chip(
                  avatar: const Icon(PhosphorIconsBold.cookingPot, size: 16),
                  label: Text(trData(s.name)),
                  deleteIcon: const Icon(PhosphorIconsBold.x, size: 14),
                  onDeleted: () => _confirmDeleteStation(kitchenRepo, s),
                )).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMappingSection(KitchenRepository kitchenRepo) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Row(
            children: [
              const Icon(PhosphorIconsBold.arrowsLeftRight, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(tr('ربط التصنيف بالمحطة'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 4),
           Text(
            tr('عند إرسال الطلب للمطبخ، يتم توزيع الأصناف تلقائياً على المحطات حسب تصنيفها'),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Consumer(
            builder: (context, ref, _) {
              final categoriesAsync = ref.watch(allCategoriesProvider);
              return categoriesAsync.when(
                data: (categories) {
                  return FutureBuilder<List<KitchenStation>>(
                    future: kitchenRepo.getActiveStations(),
                    builder: (context, stSnap) {
                      if (!stSnap.hasData) return const SizedBox.shrink();
                      final stations = stSnap.data!;
                      if (stations.isEmpty) {
                        return  Text(
                          tr('أضف محطات أولاً لبدء الربط'),
                          style: const TextStyle(color: AppColors.textMuted),
                        );
                      }

                      return FutureBuilder<List<Map<String, dynamic>>>(
                        future: kitchenRepo.getAllCategoryStationMappings(),
                        builder: (context, mappingSnap) {
                          final mappings = mappingSnap.data ?? [];
                          final mappingMap = {
                            for (final m in mappings) m['categoryId'] as int: m['stationId'] as int,
                          };

                          return Column(
                            children: categories.map((cat) {
                              final currentStationId = mappingMap[cat.id];

                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                leading: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: _parseColor(cat.color).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    PhosphorIconsBold.tag,
                                    size: 16,
                                    color: _parseColor(cat.color),
                                  ),
                                ),
                                title: Text(cat.name, style: const TextStyle(fontSize: 13)),
                                trailing: SizedBox(
                                  width: 180,
                                  child: DropdownButtonFormField<int?>(
                                    initialValue: currentStationId,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      isDense: true,
                                    ),
                                    hint:  Text(tr('تلقائي (مطبخ)'), style: const TextStyle(fontSize: 12)),
                                    items: [
                                       DropdownMenuItem<int?>(
                                        value: null,
                                        child: Text(tr('تلقائي (مطبخ)'), style: const TextStyle(fontSize: 12)),
                                      ),
                                      ...stations.map((s) => DropdownMenuItem<int?>(
                                        value: s.id,
                                        child: Text(trData(s.name), style: const TextStyle(fontSize: 12)),
                                      )),
                                    ],
                                    onChanged: _savingMappingCategoryIds.contains(cat.id) ? null : (stationId) async {
                                      setState(() => _savingMappingCategoryIds.add(cat.id));
                                      try {
                                        if (stationId == null) {
                                          await kitchenRepo.removeCategoryStationMapping(cat.id);
                                        } else {
                                          await kitchenRepo.setCategoryStationMapping(cat.id, stationId);
                                        }
                                      } finally {
                                        if (mounted) setState(() {
                                          _savingMappingCategoryIds.remove(cat.id);
                                        });
                                      }
                                    },
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      );
                    },
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              );
            },
          ),
        ],
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.primary;
    }
  }

  void _showAddStationDialog(KitchenRepository kitchenRepo) {
    final nameC = TextEditingController();
    final codeC = TextEditingController();
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title:  Text(tr('إضافة محطة مطبخ')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration:  InputDecoration(
                  labelText: tr('اسم المحطة'),
                  hintText: tr('مثال: البار، الشواء، الحلويات'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: codeC,
                decoration:  InputDecoration(
                  labelText: tr('رمز المحطة'),
                  hintText: tr('مثال: BAR, GRILL, DESSERT'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: saving ? null : () async {
                if (nameC.text.isEmpty || codeC.text.isEmpty) return;
                setDialogState(() => saving = true);
                try {
                  await kitchenRepo.createStation(
                    name: nameC.text.trim(),
                    code: codeC.text.trim().toUpperCase(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) setState(() {});
                } catch (_) {
                  setDialogState(() => saving = false);
                  rethrow;
                }
              },
              child:  Text(tr('إضافة')),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteStation(KitchenRepository kitchenRepo, KitchenStation station) {
    bool saving = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title:  Text(tr('حذف المحطة')),
          content: Text(tr('هل تريد حذف محطة "{p0}"؟', {'p0': station.name})),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: saving ? null : () async {
                setDialogState(() => saving = true);
                try {
                  await kitchenRepo.deleteStation(station.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) setState(() {});
                } catch (_) {
                  setDialogState(() => saving = false);
                  rethrow;
                }
              },
              child:  Text(tr('حذف')),
            ),
          ],
        ),
      ),
    );
  }
}
