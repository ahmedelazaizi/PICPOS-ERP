import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import 'widgets/dialogs/region_edit_dialog.dart';

/// Region Management Screen — إدارة المناطق
class RegionManagementScreen extends ConsumerWidget {
  const RegionManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regionsAsync = ref.watch(allRegionsProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('إدارة المناطق'),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.plus),
            tooltip: 'إضافة منطقة',
            onPressed: () => _showRegionDialog(context, ref, null),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: regionsAsync.when(
          data: (regions) {
            if (regions.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      PhosphorIconsBold.mapPin,
                      size: 64,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'لا توجد مناطق مضافة بعد',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(PhosphorIconsBold.plus),
                      label: const Text('إضافة منطقة'),
                      onPressed: () => _showRegionDialog(context, ref, null),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: regions.length,
              itemBuilder: (ctx, i) => _RegionCard(region: regions[i]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('خطأ: $e')),
        ),
      ),
    );
  }

  static Future<void> _showRegionDialog(
    BuildContext context,
    WidgetRef ref,
    RegionData? region,
  ) async {
    await showDialog(
      context: context,
      builder: (_) => RegionEditDialog(region: region),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Region Card with ExpansionTile showing branches
// ─────────────────────────────────────────────────────────────────────────────

class _RegionCard extends ConsumerWidget {
  final RegionData region;

  const _RegionCard({required this.region});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchesAsync = ref.watch(regionBranchesProvider(region.id));

    final branchCount = branchesAsync.maybeWhen(
      data: (branches) => branches.length,
      orElse: () => 0,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: const Icon(
            PhosphorIconsBold.mapPin,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        title: Text(
          region.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (region.address != null)
              Text(
                region.address!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            Text(
              '$branchCount فرع',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.pencil, size: 18),
              color: AppColors.primary,
              tooltip: 'تعديل',
              onPressed: () => showDialog(
                context: context,
                builder: (_) => RegionEditDialog(region: region),
              ),
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.trash, size: 18),
              color: AppColors.error,
              tooltip: 'تعطيل',
              onPressed: () => _confirmDeactivate(context, ref),
            ),
          ],
        ),
        children: [
          branchesAsync.when(
            data: (branches) {
              if (branches.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'لا توجد فروع مرتبطة بهذه المنطقة',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                );
              }
              return Column(
                children: branches
                    .map(
                      (b) => ListTile(
                        leading: const Icon(
                          PhosphorIconsBold.storefront,
                          size: 18,
                          color: AppColors.info,
                        ),
                        title: Text(b.name),
                        subtitle: b.address != null
                            ? Text(
                                b.address!,
                                style: const TextStyle(fontSize: 11),
                              )
                            : null,
                        dense: true,
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeactivate(BuildContext context, WidgetRef ref) async {
    // Cluster 027 (Issue 4 — region freeze): use a saving-guard bool
    // declared OUTSIDE the StatefulBuilder (ENGINEERING_GUIDELINES.md R2). Without this,
    // double-clicking the "تعطيل" button used to fire deactivateRegion
    // twice in parallel and the second one could deadlock against the
    // first inside Drift's write lock — the operator saw the entire app
    // freeze. Now the second click is no-op until the first completes.
    bool saving = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocalState) => AlertDialog(
            title: const Text('تعطيل المنطقة'),
            content: Text(
              'هل تريد تعطيل منطقة "${region.name}"؟ لا يمكن تعطيلها إذا كان لديها فروع أو مخازن نشطة.',
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: saving
                    ? null
                    : () {
                        setLocalState(() => saving = true);
                        Navigator.pop(ctx, true);
                      },
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('تعطيل'),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await ref.read(regionRepositoryProvider).deactivateRegion(region.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تعطيل المنطقة "${region.name}"'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is Exception ? e.toString().replaceFirst('Exception: ', '') : '$e',
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
}
