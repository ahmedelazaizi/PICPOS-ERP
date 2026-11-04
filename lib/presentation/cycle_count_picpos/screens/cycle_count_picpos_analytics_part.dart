// جزء من شاشة الجرد (cycle_count_picpos_screen.dart) — تبويب التحليلات، بلا تغيير سلوكي.
part of 'cycle_count_picpos_screen.dart';

extension _CycleCountAnalyticsTab on _CycleCountPicposScreenState {
  // ─── Analytics ──

  Widget _buildAnalyticsTab(ThemeData theme, ICycleCountRepository repo, CycleCountState state) {
    return FutureBuilder<double>(
      future: repo.getCountAccuracy(),
      builder: (ctx, snap) {
        final accuracy = snap.data ?? 100.0;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Text(tr('دقة الجرد'),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: accuracy / 100,
                      strokeWidth: 12,
                      backgroundColor: theme.colorScheme.surfaceContainerHigh,
                      color: accuracy >= 95 ? Colors.green : accuracy >= 80 ? Colors.amber : AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('${accuracy.toStringAsFixed(1)}%',
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              _statCard(theme, tr('إجمالي الخطط'), state.plans.length.toString(),
                  PhosphorIconsBold.listChecks, Colors.blue),
              const SizedBox(width: 12),
              _statCard(theme, tr('المهام المكتملة'),
                  state.tasks.where((t) => t.status == 'completed').length.toString(),
                  PhosphorIconsBold.checkCircle, Colors.green),
              const SizedBox(width: 12),
              _statCard(theme, tr('المهام المعلقة'),
                  state.tasks.where((t) => t.status == 'pending').length.toString(),
                  PhosphorIconsBold.clock, Colors.amber),
            ]),
          ]),
        );
      },
    );
  }

  Widget _statCard(ThemeData theme, String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}
