part of 'loyalty_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TRANSACTIONS TAB
// ═══════════════════════════════════════════════════════════════════════════

class _TransactionsTab extends StatefulWidget {
  final WidgetRef ref;
  final String searchQuery;
  const _TransactionsTab({required this.ref, this.searchQuery = ''});
  @override
  State<_TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<_TransactionsTab> {
  String _filterType = 'all'; // all, earn, redeem, adjust, expire

  @override
  Widget build(BuildContext context) {
    final repo = widget.ref.watch(loyaltyRepositoryProvider);
    final partiesRepo = widget.ref.watch(partiesRepositoryProvider);
    final dateFormat = DateFormat('yyyy/MM/dd hh:mm a', 'ar');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                PhosphorIconsBold.clockCounterClockwise,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Text(
                'سجل حركات النقاط',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // Filter chips
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('الكل')),
                  ButtonSegment(value: 'earn', label: Text('كسب')),
                  ButtonSegment(value: 'redeem', label: Text('استبدال')),
                  ButtonSegment(value: 'adjust', label: Text('تعديل')),
                ],
                selected: {_filterType},
                onSelectionChanged: (v) =>
                    setState(() => _filterType = v.first),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(
                    TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<LoyaltyTransaction>>(
            future: repo.getTransactions(type: _filterType),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final txs = snapshot.data!;
              if (txs.isEmpty) {
                return Center(
                  child: Text(
                    _filterType == 'all'
                        ? 'لا توجد حركات'
                        : 'لا توجد حركات من نوع ${_typeName(_filterType)}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: txs.length,
                itemBuilder: (context, i) {
                  final tx = txs[i];
  // ignore: unused_local_variable
                  final isEarn = tx.type == 'earn';
  // ignore: unused_local_variable
                  final isRedeem = tx.type == 'redeem';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _typeColor(tx.type).withValues(
                          alpha: 0.1,
                        ),
                        child: Icon(
                          _typeIcon(tx.type),
                          color: _typeColor(tx.type),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(_typeName(tx.type)),
                          const SizedBox(width: 8),
                          // Show customer name
                          Expanded(
                            child: FutureBuilder<Party?>(
                              future: partiesRepo.getPartyById(tx.customerId),
                              builder: (ctx, snap) => Text(
                                snap.data?.name ?? '',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        tx.notes ?? dateFormat.format(tx.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        '${tx.points > 0 ? "+" : ""}${tx.points}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: tx.points > 0 ? Colors.green : AppColors.error,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }



  IconData _typeIcon(String t) => switch (t) {
    'earn' => PhosphorIconsBold.plus,
    'redeem' => PhosphorIconsBold.arrowsCounterClockwise,
    'expire' => PhosphorIconsBold.clockCountdown,
    'adjust' => PhosphorIconsBold.pencilSimple,
    _ => PhosphorIconsBold.circle,
  };

  Color _typeColor(String t) => switch (t) {
    'earn' => Colors.green,
    'redeem' => Colors.orange,
    'expire' => AppColors.error,
    'adjust' => Colors.blue,
    _ => Colors.grey,
  };

  String _typeName(String t) => switch (t) {
    'earn' => 'كسب نقاط',
    'redeem' => 'استبدال',
    'expire' => 'انتهاء صلاحية',
    'adjust' => 'تعديل يدوي',
    _ => 'تعديل',
  };
}
