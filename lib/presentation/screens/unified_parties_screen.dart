import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../core/widgets/shimmer_loading.dart';
import '../../core/constants/app_constants.dart';
import '../../data/providers/providers.dart';
import 'party_statement_screen.dart';
import '../treasury/widgets/receipt_voucher_dialog.dart';
import '../treasury/widgets/payment_voucher_dialog.dart';
import 'parties/party_helpers.dart';
import 'parties/party_dialogs.dart';
import 'parties/party_groups_screen.dart';

/// Unified Customers & Suppliers Management Screen
/// Merges both customers and suppliers into a single view with type filtering
class UnifiedPartiesScreen extends ConsumerStatefulWidget {
  const UnifiedPartiesScreen({super.key});

  @override
  ConsumerState<UnifiedPartiesScreen> createState() =>
      _UnifiedPartiesScreenState();
}

class _UnifiedPartiesScreenState extends ConsumerState<UnifiedPartiesScreen> {
  final _searchController = TextEditingController();
  String _typeFilter = 'all'; // all, customer, supplier, both

  // Spec 115 diagnostic — counts how many times the screen rebuilds. A
  // healthy session shows a handful of builds (filter changes, data
  // arrivals); the "screen keeps flickering" symptom should show this
  // number climbing rapidly into the dozens within a few seconds.
  int _buildCount = 0;
  DateTime _lastBuildLogAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    final now = DateTime.now();
    // Log every 5 builds OR every 2 seconds, whichever comes first, so a
    // tight rebuild loop fills the diagnostic log with a clear signal
    // without burying the file under thousands of identical lines.
    if (_buildCount % 5 == 0 ||
        now.difference(_lastBuildLogAt).inMilliseconds > 2000) {
      _lastBuildLogAt = now;
      unawaited(DiagnosticLogger.log(
        'PARTIES-BUILD',
        'UnifiedPartiesScreen build #$_buildCount',
      ));
    }
    // Spec 136 ISS-4 — do NOT watch allPartiesProvider at screen scope. The
    // stream re-emits on every parties-table change (a voucher/statement
    // dialog that touches balances cascades several emissions), and a top-
    // level watch rebuilt the ENTIRE Scaffold (header + buttons + filters)
    // each time — the field "build #5..#55 on dialog open/close" symptom.
    // The watch now lives in a child Consumer wrapping only the list Card, so
    // data emissions rebuild just the list; the header/filters build once.

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 16),
              _buildFilters(context),
              const SizedBox(height: 16),
              Expanded(
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: RepaintBoundary(
                    child: Consumer(
                      builder: (context, ref, _) {
                        final partiesAsync = ref.watch(allPartiesProvider);
                        return partiesAsync.when(
                          data: (list) => _buildPartiesList(list),
                          loading: () => Padding(
                            padding: const EdgeInsets.all(16),
                            child: ShimmerLoading.list(itemCount: 6),
                          ),
                          error: (e, _) => Center(child: Text('خطأ: $e')),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        const Icon(
          PhosphorIconsBold.usersThree,
          size: 32,
          color: AppColors.primary,
        ),
        const SizedBox(width: 12),
        Text(
          'العملاء والموردين',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.headlineMedium?.color,
          ),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PartyStatementScreen(isCustomer: true),
            ),
          ),
          icon: const Icon(PhosphorIconsBold.user, size: 18),
          label: const Text('كشف حساب عميل'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PartyStatementScreen(isSupplier: true),
            ),
          ),
          icon: const Icon(PhosphorIconsBold.truck, size: 18),
          label: const Text('كشف حساب مورد'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.warning,
          ),
        ),
        const SizedBox(width: 8),
        // Phase 2: entry point to the Party Groups management screen.
        // Lives in the same header as the statement buttons because
        // groups are a peer master-data entity to parties themselves.
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PartyGroupsScreen(),
            ),
          ),
          icon: const Icon(PhosphorIconsBold.usersThree, size: 18),
          label: const Text('المجموعات'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.info,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => showExcelOptionsDialog(context, ref, isExport: true),
          icon: const Icon(PhosphorIconsBold.fileArrowUp, size: 18),
          label: const Text('تصدير'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => showExcelOptionsDialog(context, ref, isExport: false),
          icon: const Icon(PhosphorIconsBold.fileArrowDown, size: 18),
          label: const Text('استيراد'),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () => showAddPartyDialog(context, ref),
          icon: const Icon(PhosphorIconsBold.plus),
          label: const Text('إضافة'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FILTERS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildFilters(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'البحث بالاسم أو رقم الهاتف...',
              prefixIcon: const Icon(
                PhosphorIconsBold.magnifyingGlass,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('الكل')),
            ButtonSegment(
              value: 'customer',
              label: Text('عملاء'),
              icon: Icon(PhosphorIconsBold.user, size: 16),
            ),
            ButtonSegment(
              value: 'supplier',
              label: Text('موردين'),
              icon: Icon(PhosphorIconsBold.truck, size: 16),
            ),
            ButtonSegment(
              value: 'delivery',
              label: Text('توصيل'),
              icon: Icon(PhosphorIconsBold.moped, size: 16),
            ),
            ButtonSegment(
              value: 'both',
              label: Text('عميل مورد'),
              icon: Icon(PhosphorIconsBold.usersThree, size: 16),
            ),
          ],
          selected: {_typeFilter},
          onSelectionChanged: (val) {
            setState(() => _typeFilter = val.first);
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PARTIES LIST
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPartiesList(List<Party> list) {
    var filtered = list.where((p) {
      if (_typeFilter == 'customer' && !p.isCustomer) return false;
      if (_typeFilter == 'supplier' && !p.isSupplier) return false;
      if (_typeFilter == 'delivery' && (p.isDeliveryCompany != true)) return false;
      if (_typeFilter == 'both' && !(p.isCustomer && p.isSupplier)) return false;

      if (_searchController.text.isNotEmpty) {
        final query = _searchController.text.toLowerCase();
        if (!p.name.toLowerCase().contains(query) &&
            !(p.phone?.contains(query) ?? false)) {
          return false;
        }
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIconsBold.users,
              size: 64,
              color: AppColors.textMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'لا يوجد أطراف',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      separatorBuilder: (_, index) => const Divider(),
      itemBuilder: (context, index) {
        final party = filtered[index];
        return _buildPartyTile(party);
      },
    );
  }

  Widget _buildPartyTile(Party party) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: getPartyTypeColor(party).withValues(alpha: 0.1),
        child: Icon(
          getPartyIcon(party),
          color: getPartyTypeColor(party),
        ),
      ),
      title: Row(
        children: [
          Text(
            party.name,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: getPartyTypeColor(party).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              getPartyTypeLabel(party),
              style: TextStyle(
                fontSize: 10,
                color: getPartyTypeColor(party),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      // Spec 029 corrective patch (2026-05-10) — moved balance + credit
      // limit OUT of `ListTile.trailing` and into the subtitle. The
      // previous layout stuffed [balance Column] + [4 IconButtons] into
      // `trailing`; total intrinsic width was ~400px which overflowed
      // the ListTile's default trailing constraint on RTL desktop. The
      // inner icons (money + statement) ended up clipped/unhittable
      // while the outer two (edit + trash) stayed visible — exactly the
      // symptom the operator reported on 2026-05-10. Putting balance in
      // the subtitle row keeps it visually adjacent to the party name
      // (and its credit limit), and frees `trailing` for compact icons.
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              party.phone ?? 'لا يوجد رقم',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${party.balance.toStringAsFixed(AppConstants.decimalPlaces)} '
                '${AppConstants.currencySymbolEn}',
            style: TextStyle(
              color: party.balance >= 0
                  ? AppColors.success
                  : AppColors.error,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '(حد ${party.creditLimit.toStringAsFixed(0)})',
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
          // Compact icons — `padding: zero` + `constraints` keep each
          // button at ~32×32, so all four together stay well under the
          // ListTile's trailing width budget. Removes the clipping that
          // made the inner icons (money + statement) unhittable.
          IconButton(
            icon: const Icon(PhosphorIconsBold.money),
            iconSize: 20,
            color: AppColors.success,
            tooltip: 'سند مالي',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () {
              // Spec 115 diagnostic — DiagnosticLogger writes to the log
              // file in release builds; debugPrint does not, which is why
              // build 182 produced no log lines despite the user tapping.
              unawaited(DiagnosticLogger.log('PARTIES-ACTION',
                  'voucher tap partyId=${party.id} name="${party.name}" '
                  'isSupplier=${party.isSupplier} '
                  'isCustomer=${party.isCustomer}'));
              try {
                showDialog(
                  context: context,
                  builder: (context) {
                    if (party.isSupplier && !party.isCustomer) {
                      return PaymentVoucherDialog(initialParty: party);
                    } else {
                      return ReceiptVoucherDialog(initialParty: party);
                    }
                  },
                ).then((_) => unawaited(DiagnosticLogger.log('PARTIES-ACTION',
                    'voucher dialog closed partyId=${party.id}')));
              } catch (e, st) {
                unawaited(DiagnosticLogger.log('PARTIES-ACTION',
                    'voucher dialog threw partyId=${party.id}: $e\n$st'));
              }
            },
          ),
          IconButton(
            icon: const Icon(PhosphorIconsBold.fileText),
            iconSize: 20,
            color: AppColors.info,
            tooltip: 'كشف حساب',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () {
              unawaited(DiagnosticLogger.log('PARTIES-ACTION',
                  'statement tap partyId=${party.id} name="${party.name}" '
                  'isSupplier=${party.isSupplier}'));
              try {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PartyStatementScreen(
                      isSupplier: party.isSupplier,
                      partyId: party.id,
                      partyName: party.name,
                    ),
                  ),
                ).then((_) => unawaited(DiagnosticLogger.log('PARTIES-ACTION',
                    'statement route popped partyId=${party.id}')));
              } catch (e, st) {
                unawaited(DiagnosticLogger.log('PARTIES-ACTION',
                    'statement route threw partyId=${party.id}: $e\n$st'));
              }
            },
          ),
          IconButton(
            icon: const Icon(PhosphorIconsBold.pencil),
            iconSize: 20,
            color: AppColors.primary,
            tooltip: 'تعديل',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () {
              unawaited(DiagnosticLogger.log('PARTIES-ACTION',
                  'edit tap partyId=${party.id} name="${party.name}"'));
              try {
                showEditPartyDialog(context, ref, party);
              } catch (e, st) {
                unawaited(DiagnosticLogger.log('PARTIES-ACTION',
                    'edit dialog threw partyId=${party.id}: $e\n$st'));
              }
            },
          ),
          IconButton(
            icon: const Icon(PhosphorIconsBold.trash),
            iconSize: 20,
            color: AppColors.error,
            tooltip: 'حذف',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () {
              unawaited(DiagnosticLogger.log('PARTIES-ACTION',
                  'delete tap partyId=${party.id} name="${party.name}"'));
              try {
                showDeletePartyDialog(context, ref, party);
              } catch (e, st) {
                unawaited(DiagnosticLogger.log('PARTIES-ACTION',
                    'delete dialog threw partyId=${party.id}: $e\n$st'));
              }
            },
          ),
        ],
      ),
    );
  }
}
