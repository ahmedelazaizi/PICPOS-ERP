// منطق منسوخ من unified_parties_screen.dart (monolith) — أي إصلاح منطقي
// يتصلّح في المصدر أولاً ثم patch (مصيدة النسخ §٥.٨).
//
// الشاشة الأصل (lib/presentation/screens/unified_parties_screen.dart)
// مونوليث ~500 سطر بلا `part of` files. الـ State (_UnifiedPartiesScreenState)
// بما فيها منطق الفلاتر (`_buildFilters` بـ SegmentedButton لنوع الطرف) وبناء
// القائمة (`_buildPartiesList`) وبطاقة الطرف (`_buildPartyTile` بأزرار سند
// مالي/كشف حساب/تعديل/حذف مع سجلات DiagnosticLogger) كل ده مكتوب inline.
// بما إنه مفيش part نقدر نستوردها، فالفورك هنا بينسخ جسم الدوال دي حرفياً
// بلا أي تعديل منطقي — يتغيّر بس اسم الكلاس وطبقة العرض (تستخدم picpos_shell
// بدل Scaffold+Padding يدوي). عداد إعادة البناء التشخيصي (`_buildCount` /
// DiagnosticLogger('PARTIES-BUILD', ...)) في `build()` الأصلي هو تشخيص
// خاص بمشكلة إعادة بناء الـ Scaffold كامل في الأصل (Spec 115) — الأصل أصلاً
// عالجها بنقل الـ watch لـ Consumer داخلي حول الكارت بس، وهو نفس الهيكل اللي
// الفورك ده بيستخدمه من الأول، فمفيش داعي لعداد التشخيص في طبقة العرض الجديدة.
// `allPartiesProvider` (داخل Consumer يلفّ الكارت فقط)، الحوارات
// (`showAddPartyDialog`/`showEditPartyDialog`/`showDeletePartyDialog`/
// `showExcelOptionsDialog`) من `parties/party_dialogs.dart`، الـ helpers
// (`getPartyTypeLabel`/`getPartyTypeColor`/`getPartyIcon`) من
// `parties/party_helpers.dart`، و`ReceiptVoucherDialog`/`PaymentVoucherDialog`
// و`PartyStatementScreen`/`PartyGroupsScreen` مُعاد استخدامهم من UralCash زي
// ما هم (import، مش نسخ).
import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/providers/providers.dart';
import '../../screens/party_statement_screen.dart';
import '../../treasury/widgets/receipt_voucher_dialog.dart';
import '../../treasury/widgets/payment_voucher_dialog.dart';
import '../../screens/parties/party_helpers.dart';
import '../../screens/parties/party_dialogs.dart';
import '../../screens/parties/party_groups_screen.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_content_card.dart';

/// شاشة العملاء والموردين بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). تعيد استخدام نفس `allPartiesProvider` (عبر Consumer
/// يلفّ الكارت فقط، مش على مستوى الشاشة كلها) والحوارات من
/// `parties/party_dialogs.dart` وHelpers من `parties/party_helpers.dart`
/// و`ReceiptVoucherDialog`/`PaymentVoucherDialog` و`PartyStatementScreen`/
/// `PartyGroupsScreen` من UralCash — فقط طبقة العرض تبدّلت لـ picpos_shell
/// (هيدر PicPosScreenScaffold بدل Row يدوي، وPicPosContentCard حول القائمة
/// بدل Card+elevation).
///
/// FULL PARITY مع الأصل: فلتر نوع الطرف (الكل/عملاء/موردين/توصيل/عميل مورد
/// عبر SegmentedButton)، البحث بالاسم أو الهاتف، قائمة الأطراف مع بطاقة كل
/// طرف (الرصيد + حد الائتمان + أزرار سند مالي/كشف حساب/تعديل/حذف)، إضافة/
/// تعديل/حذف طرف، تصدير/استيراد إكسل، التنقّل لكشف حساب عميل/مورد وشاشة
/// المجموعات.
///
/// راجع lib/presentation/screens/unified_parties_screen.dart (الأصل).
class PartiesPicposScreen extends ConsumerStatefulWidget {
  const PartiesPicposScreen({super.key});

  @override
  ConsumerState<PartiesPicposScreen> createState() =>
      _PartiesPicposScreenState();
}

class _PartiesPicposScreenState extends ConsumerState<PartiesPicposScreen> {
  final _searchController = TextEditingController();
  String _typeFilter = 'all'; // all, customer, supplier, both

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PicPosScreenScaffold(
      title: 'العملاء والموردين',
      subtitle: 'إدارة الأطراف والأرصدة',
      icon: PhosphorIconsBold.usersThree,
      headerActions: [
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
        // Phase 2: entry point to the Party Groups management screen. Lives
        // in the same header as the statement buttons because groups are a
        // peer master-data entity to parties themselves.
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilters(context),
          const SizedBox(height: 16),
          Expanded(
            child: PicPosContentCard(
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
