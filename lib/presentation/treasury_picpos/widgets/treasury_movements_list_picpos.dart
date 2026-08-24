// قائمةُ «آخر الحركات» بهويّة PicPos — **فوركٌ بقرار المالك 2026-08-22**.
//
// المصدر: `treasury/widgets/treasury_transactions_list.dart`، ويبقى بلا
// مساسٍ لشاشة UralCash.
//
// **الفرقُ عن الأصل — مقيسٌ من التصميم:** الأصلُ `ListTile` بعنوانٍ وسطرَين
// تحته؛ والتصميمُ شبكةُ خمسةِ أعمدة: أيقونةٌ ملوّنة · رقمُ السند والوقت ·
// الطرف · الصندوق · المبلغُ بإشارته.
//
// وحقلُ البحثُ وشرائحُ (الكل/قبض/صرف) الخاصّةُ بالأصل **لا تُنسخ**: التصميمُ
// يضع بحثاً واحداً في شريط التبويبات يخدم اللوحَين معاً، فيُمرَّر من الشاشة.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:ural_erp/core/utils/friendly_error.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:ural_erp/l10n/app_localizations.dart';

import '../../../core/config/brand.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../services/generators/thermal_receipt_generator.dart';
import '../../picpos_shell/picpos_surface.dart';
import 'treasury_picpos_tokens.dart';

/// أسماءُ الأطراف الظاهرةِ في قائمة الحركات — **دفعةٌ واحدةٌ لا استعلامٌ لكلّ
/// صفّ**.
///
/// ⚠️ **لماذا مزوِّدٌ خاصٌّ بدل تمرير القائمة من الودجت:**
/// `partyNamesMapProvider` عائليٌّ مفتاحُه `List<int>`، ومساواةُ القائمة في
/// Dart **بالهويّة لا بالمحتوى** — فتمريرُ قائمةٍ جديدةٍ من `build` يُنشئ
/// نسخةً جديدةً من المزوِّد في كلّ إعادةِ بناء. وهذه الحركاتُ تُعاد بثّاً مع
/// كلِّ بيعٍ وكلِّ سند.
///
/// فاشتقاقُ المعرِّفات **داخل** المزوِّد يجعل إعادةَ التشغيل مربوطةً ببثّ
/// الحركات وحدَه، و`autoDispose` يتخلّص من النسخة السابقة — فتبقى نسخةٌ حيّةٌ
/// واحدةٌ واستعلامٌ واحدٌ `WHERE id IN (…)` بحدٍّ أقصى ٥٠ معرِّفاً.
///
/// والمصدرُ `scopedRecentTransactionsProvider` **مسقوفٌ بنطاق الفرع** — نفسُ
/// المصدر الذي تقرؤه القائمةُ نفسُها، فلا يُسأل عن طرفٍ لا يظهر صفُّه.
final treasuryPicposPartyNamesProvider =
    FutureProvider.autoDispose<Map<int, String>>((ref) async {
  final txns = await ref.watch(scopedRecentTransactionsProvider.future);
  final ids = txns.map((t) => t.partyId).whereType<int>().toSet().toList()
    ..sort();
  if (ids.isEmpty) return const <int, String>{};
  return ref.watch(partyNamesMapProvider(ids).future);
});

/// وقتُ الحركة كما يعرضه التصميم (`t.time`).
///
/// دالّةٌ خالصةٌ تستقبل [now] صراحةً — فلا تعتمد على ساعة الجهاز في
/// الاختبار. «اليوم»/«أمس» تُقاسان بالتقويم لا بفارق ٢٤ ساعة: حركةٌ الساعةَ
/// ٢٣:٥٠ أمسِ تبقى «أمس» ولو مرّ عليها أقلُّ من يوم.
@visibleForTesting
String formatMovementTime(DateTime at, DateTime now) {
  final hm = DateFormat('HH:mm').format(at);
  final d0 = DateTime(now.year, now.month, now.day);
  final d1 = DateTime(at.year, at.month, at.day);
  final days = d0.difference(d1).inDays;
  if (days == 0) return 'اليوم $hm';
  if (days == 1) return 'أمس $hm';
  return '${DateFormat('d/M').format(at)} $hm';
}

class TreasuryMovementsListPicpos extends ConsumerStatefulWidget {
  const TreasuryMovementsListPicpos({
    super.key,
    required this.transactions,
    required this.safeNames,
    this.searchQuery = '',
  });

  final AsyncValue<List<TransactionData>> transactions;

  /// `معرِّفُ الصندوق → اسمُه`، محلولٌ في اللوح الحاوي من نفس قائمة الصناديق
  /// المعروضةِ يساراً. والقائمةُ **تُرشَّح بمفاتيحه**: صفٌّ لصندوقٍ خارجَ هذا
  /// التبويب لا يُعرض.
  ///
  /// ⚠️ ولهذا معنىً أمنيٌّ عرَضيّ: `TransactionData.safeName` يصل من المستودع
  /// **نصّاً فارغاً دائماً** (‏الوصلةُ غيرُ منفَّذة)، فلو قُرئ منه لظهر عمودُ
  /// الصندوق فارغاً في كلّ صفّ.
  final Map<int, String> safeNames;

  /// بحثُ الشاشة الواحد (شريطُ التبويبات في التصميم).
  final String searchQuery;

  @override
  ConsumerState<TreasuryMovementsListPicpos> createState() =>
      _TreasuryMovementsListPicposState();
}

class _TreasuryMovementsListPicposState
    extends ConsumerState<TreasuryMovementsListPicpos> {
  // Issue UX-SCROLL — نفسُ سببِ الأصل: هذه القائمةُ تُعاد بثّاً مع كلّ كتابةِ
  // `safe_transaction`، والمتحكّمُ الضمنيُّ يفقد موضعَ التمرير في كلّ بثّ.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _categoryLabel(BuildContext context, String category) {
    final l = AppLocalizations.of(context)!;
    return switch (category) {
      'customer_payment' => l.customerPayment,
      'supplier_payment' => l.supplierPayment,
      'sales' => l.sales,
      'purchase' => l.purchase,
      'expense' => l.expense,
      'salary' => l.salary,
      'advance' => l.advance,
      'loan' => l.loan,
      _ => l.other,
    };
  }

  Future<void> _printVoucher(TransactionData t) async {
    // ⚠️ **الطباعةُ تبقى** رغم غيابها عن التصميم: التصميمُ يرسم شكلاً، وهذه
    // وظيفةٌ قائمةٌ لا مدخلَ لها في PicPos غيرَ هذا الصفّ. إسقاطُها بحجّة
    // «مطابقةِ التصميم» يشحن نقصاناً صامتاً.
    final categoryLabel = _categoryLabel(context, t.category);
    try {
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final partiesRepo = ref.read(partiesRepositoryProvider);
      final companyName = await settingsRepo.getSetting('company_name') ??
          Brand.documentCompanyFallback;
      final companyPhone = await settingsRepo.getSetting('company_phone');

      String? partyName;
      if (t.partyId != null) {
        partyName = (await partiesRepo.getPartyById(t.partyId!))?.name;
      }

      await ThermalReceiptGenerator.printVoucher(
        voucherNumber: t.voucherNumber,
        voucherType: t.transactionType == 'receipt' ? 'receipt' : 'payment',
        amount: t.amount,
        date: t.createdAt,
        partyName: partyName,
        description: t.description != null
            ? '$categoryLabel - ${t.description}'
            : categoryLabel,
        companyName: companyName,
        companyPhone: companyPhone,
      );

      if (mounted) {
        AppToast.show(context, 'جاري الطباعة...', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في الطباعة: $e', type: ToastType.error);
      }
    }
  }

  bool _matches(TransactionData t, String partyName) {
    final q = widget.searchQuery;
    if (q.isEmpty) return true;
    if (t.voucherNumber.toLowerCase().contains(q)) return true;
    if ((t.description ?? '').toLowerCase().contains(q)) return true;
    if (partyName.toLowerCase().contains(q)) return true;
    if (t.amount.toStringAsFixed(AppConstants.decimalPlaces).contains(q)) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final partyNames =
        ref.watch(treasuryPicposPartyNamesProvider).value ?? const {};

    return widget.transactions.when(
      loading: () => const _MovementsFrame(
        count: null,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _MovementsFrame(
        count: null,
        child: Center(child: Text(friendlyError(e))),
      ),
      data: (all) {
        // اسمُ الطرف: الاسمُ المحلولُ إن وُجد، وإلّا **تصنيفُ الحركة** —
        // فأكثرُ الحركات (بيعٌ نقديٌّ، مصروف) بلا طرفٍ أصلاً، وخليّةٌ فارغةٌ
        // تُقرأ عطباً لا «لا طرفَ لها».
        String partyOf(TransactionData t) {
          final id = t.partyId;
          final name = id == null ? null : partyNames[id];
          return name ?? _categoryLabel(context, t.category);
        }

        final rows = all
            .where((t) => widget.safeNames.containsKey(t.safeId))
            .where((t) => _matches(t, partyOf(t)))
            .toList();

        if (rows.isEmpty) {
          return _MovementsFrame(
            count: 0,
            child: Center(
              child: Text(
                widget.searchQuery.isNotEmpty
                    ? 'لا توجد سندات مطابقة'
                    : AppLocalizations.of(context)!.noTransactions,
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
          );
        }

        final now = DateTime.now();
        return _MovementsFrame(
          count: rows.length,
          child: ListView.builder(
            controller: _scrollController,
            itemCount: rows.length,
            itemBuilder: (context, i) => _MovementRow(
              txn: rows[i],
              party: partyOf(rows[i]),
              safeName: widget.safeNames[rows[i].safeId] ?? '',
              time: formatMovementTime(rows[i].createdAt, now),
              onPrint: () => _printVoucher(rows[i]),
            ),
          ),
        );
      },
    );
  }
}

/// إطارُ اللوح: كرتٌ بترويسةٍ على أرضيّة `--field` ثمّ المحتوى.
class _MovementsFrame extends StatelessWidget {
  const _MovementsFrame({required this.count, required this.child});

  /// عددُ الصفوف المعروضة. `null` يعني «لم يُعرَف بعد» فلا يُكتب رقم.
  ///
  /// ⚠️ التصميمُ يكتب هنا «اليوم وأمس»، وهي **دعوى نطاقٍ لا يفي بها المصدر**:
  /// `watchRecentTransactionsForBranches` تُرجع آخرَ ٥٠ حركةً مهما قدُمت. فلو
  /// نُسخت العبارةُ حرفيّاً لقالت الشاشةُ ما لا تعرفه. والعددُ يُقاس فيُقال.
  final int? count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: TreasuryPicposTokens.hairlineOf(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: TreasuryPicposTokens.fieldOf(context),
              border: Border(
                bottom: BorderSide(color: TreasuryPicposTokens.hairlineOf(context)),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'آخر الحركات',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (count != null)
                  Text(
                    '$count حركة',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// صفُّ حركةٍ واحد — شبكةُ التصميم `34px 2fr 1.4fr 1.3fr 130px`.
@visibleForTesting
class TreasuryMovementRowPicpos extends StatelessWidget {
  const TreasuryMovementRowPicpos({
    super.key,
    required this.isReceipt,
    required this.voucherNumber,
    required this.time,
    required this.party,
    required this.safeName,
    required this.amount,
    this.onPrint,
  });

  final bool isReceipt;
  final String voucherNumber;
  final String time;
  final String party;
  final String safeName;
  final double amount;
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    final color = isReceipt ? AppColors.success : AppColors.error;
    final sign = isReceipt ? '+' : '−';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: TreasuryPicposTokens.hairlineOf(context)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              isReceipt
                  ? PhosphorIconsBold.arrowCircleDown
                  : PhosphorIconsBold.arrowCircleUp,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  voucherNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 14,
            child: Text(
              party,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 13,
            child: Text(
              safeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Text(
              '$sign ${NumberFormat('#,##0.00', 'ar').format(amount)}',
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (onPrint != null)
            IconButton(
              icon: const Icon(PhosphorIconsBold.printer, size: 18),
              color: AppColors.textMuted,
              visualDensity: VisualDensity.compact,
              tooltip: 'طباعة السند',
              onPressed: onPrint,
            ),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({
    required this.txn,
    required this.party,
    required this.safeName,
    required this.time,
    required this.onPrint,
  });

  final TransactionData txn;
  final String party;
  final String safeName;
  final String time;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    return TreasuryMovementRowPicpos(
      isReceipt: txn.transactionType == 'receipt',
      voucherNumber: txn.voucherNumber,
      time: time,
      party: party,
      safeName: safeName,
      amount: txn.amount,
      onPrint: onPrint,
    );
  }
}
