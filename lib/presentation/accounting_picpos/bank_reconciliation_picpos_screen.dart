// شاشةُ «المطابقة البنكية» بهويّة PicPos — المهمّةُ ٤: الرأسُ والجلسةُ
// والمؤشّراتُ وحدَها. الاستيرادُ والمطابقةُ الآليّةُ (٥) والقائمتان
// المتجاورتان (٦) مهمّتان لاحقتان — لا يبنيهما هذا الملفّ.
//
// ═══ العقدُ الذي تستهلكه هذه الشاشة ═══
//
// `IAccountingRepository.createReconciliation` تفتح جلسةً على حسابٍ بنكيٍّ
// (لا خزنة) لفترةٍ ورصيدِ كشفٍ معلوم، و`getReconciliationReport` تعيد
// أرصدةَ الجلسة وفرقَها وعدَّ المطابَق/غيرِ المطابَق — المفاتيحُ موثّقةٌ في
// `domain/repositories/accounting_repository.dart` (قسمُ Bank Reconciliation).
//
// ⚠️ **خزنةٌ بنكيّةٌ بلا حسابٍ مرتبطٍ لا يمكن مطابقتُها**: المطابقةُ تقع على
// حساب دفترٍ (‏`bankAccountId`)، فخزنةٌ بلا `linkedAccountId` لا دفترَ لها
// يُقارَن بكشف البنك. وإسقاطُها بصمتٍ يجعلها تبدو مفقودةً من النظام —
// فتُقصى مع سطرِ شرحٍ يُقال، لا صمتٍ.
//
// ⚠️ **ولا تُدخل `databaseProvider` في أيّ مزوّدٍ هنا**: اختبارُ الودجت
// يتجاوز المستودعَ لا القاعدة، فأيُّ مزوّدٍ يلمس `databaseProvider` يفتح
// قاعدةً حقيقيّةً ويتعلّق `pumpAndSettle` إلى الأبد.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/repositories/treasury_repository.dart' show SafeData;
import '../picpos_shell/picpos_empty_state.dart';
import '../picpos_shell/picpos_hub_kpi.dart';
import '../picpos_shell/picpos_option_picker.dart';
import '../picpos_shell/picpos_report_bar.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import '../picpos_shell/picpos_surface.dart';

final _money = NumberFormat('#,##0.00', 'en');

/// الخزائنُ البنكيّةُ القابلةُ للمطابقة، وعددُ المُقصى منها لغياب حسابٍ
/// مرتبط.
///
/// ⚠️ **الترشيحُ حرفيٌّ لا اجتهاديّ**: `safeType == 'bank' && isActive &&
/// linkedAccountId != null` — الثلاثةُ معاً. وعدُّ [excluded] عن خزائن
/// بنكيّةٍ **نشطة** فقط (‏غيرُ النشطة ولا البنكيّة أصلاً ليست موضوعَ سطرِ
/// الشرح، فحسابها معه كان سيَعُدّ خزائنَ لا علاقةَ لها بالمطابقة).
final _bankSafesProvider =
    FutureProvider.autoDispose<({List<SafeData> safes, int excluded})>(
        (ref) async {
  final all = await ref.watch(treasuryRepositoryProvider).getSafesList();
  final bankActive =
      all.where((s) => s.safeType == 'bank' && s.isActive).toList();
  final withAccount =
      bankActive.where((s) => s.linkedAccountId != null).toList();
  return (safes: withAccount, excluded: bankActive.length - withAccount.length);
});

class BankReconciliationPicposScreen extends ConsumerStatefulWidget {
  const BankReconciliationPicposScreen({super.key});

  @override
  ConsumerState<BankReconciliationPicposScreen> createState() =>
      _BankReconciliationPicposScreenState();
}

class _BankReconciliationPicposScreenState
    extends ConsumerState<BankReconciliationPicposScreen> {
  int? _safeId;
  int? _accountId;
  late DateTimeRange _period;
  int? _sessionId;

  final _statementBalanceController = TextEditingController();
  bool _creatingSession = false;

  @override
  void initState() {
    super.initState();
    _period = _lastMonthRange();

    // ⚠️ لا خزنةَ مختارةً افتراضيّاً، والقائمةُ تصل بعد إطارٍ واحدٍ على
    // الأقلّ (نداءٌ غيرُ متزامن للمستودع). فتُختار أوّلُ خزنةٍ قابلةٍ
    // للمطابقة تلقائيّاً كي لا تبدأ الشاشةُ بلا شيءٍ مختار — على نمط
    // `_selectedBranchId` في `financial_statements_picpos_screen.dart`.
    Future.microtask(() async {
      try {
        final result = await ref.read(_bankSafesProvider.future);
        if (!mounted) return;
        if (_safeId == null && result.safes.isNotEmpty) {
          final first = result.safes.first;
          setState(() {
            _safeId = first.id;
            _accountId = first.linkedAccountId;
          });
        }
      } catch (_) {
        // يُقال بالفعل عبر `banksAsync.when(error: ...)` في build() — هنا
        // فقط يُمنَع رميٌ غيرُ مُمسَكٍ يُسقط الاختيارَ التلقائيَّ بلا داعٍ.
      }
    });
  }

  @override
  void dispose() {
    _statementBalanceController.dispose();
    super.dispose();
  }

  static DateTimeRange _lastMonthRange() {
    final now = DateTime.now();
    final firstOfThisMonth = DateTime(now.year, now.month, 1);
    final lastMonthEnd =
        firstOfThisMonth.subtract(const Duration(days: 1));
    final lastMonthStart = DateTime(lastMonthEnd.year, lastMonthEnd.month, 1);
    return DateTimeRange(start: lastMonthStart, end: lastMonthEnd);
  }

  @override
  Widget build(BuildContext context) {
    final banksAsync = ref.watch(_bankSafesProvider);

    return banksAsync.when(
      data: (result) => PicPosScreenScaffold(
        title: 'المطابقة البنكية',
        icon: PhosphorIconsBold.bank,
        subHeader: _buildHeader(context, result.safes, result.excluded),
        body: _buildBody(),
      ),
      loading: () => const PicPosScreenScaffold(
        title: 'المطابقة البنكية',
        icon: PhosphorIconsBold.bank,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => PicPosScreenScaffold(
        title: 'المطابقة البنكية',
        icon: PhosphorIconsBold.bank,
        body: Center(child: Text('تعذّر تحميل الخزائن البنكية: $e')),
      ),
    );
  }

  // ── الرأس: منتقي الخزنة · شريطُ الفترة · رصيدُ الكشف · جلسةٌ جديدة ─────

  Widget _buildHeader(
    BuildContext context,
    List<SafeData> safes,
    int excluded,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PicPosReportFilterBar(
          selectedRange: _period,
          onRangeChanged: (start, end) => setState(() {
            _period = DateTimeRange(start: start, end: end);
          }),
          trailing: [
            _safePickerButton(context, safes),
            _statementBalanceField(context),
            _newSessionButton(context),
          ],
        ),
        // خزنةٌ بنكيّةٌ أو أكثرُ بلا حسابٍ مرتبطٍ تُقصى من المنتقي أعلاه —
        // وهذا السطرُ يشرح لماذا لا يبدو عدد الخزائن كاملاً.
        if (excluded > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 8, 26, 0),
            child: Text(
              'خزنةٌ بنكيّةٌ أو أكثرُ بلا حسابٍ مرتبطٍ — لا يمكن مطابقتُها',
              style: TextStyle(fontSize: 12, color: context.picposMuted),
            ),
          ),
      ],
    );
  }

  Widget _safePickerButton(BuildContext context, List<SafeData> safes) {
    final matches = safes.where((s) => s.id == _safeId);
    final label = matches.isEmpty ? 'اختر خزنة بنكية' : matches.first.name;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: safes.isEmpty ? null : () => _pickSafe(context, safes),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: context.picposField,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: context.picposHairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsBold.bank,
                  size: 15, color: context.picposBrandInk),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: context.picposText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickSafe(BuildContext context, List<SafeData> safes) async {
    final picked = await showPicPosOptionPicker<int?>(
      context: context,
      title: 'اختيار الخزنة البنكية',
      options: [
        for (final s in safes)
          PicPosOption<int?>(value: s.id, label: s.name, sub: s.bankName),
      ],
      selected: _safeId,
    );
    if (picked == null) return;
    final safe = safes.where((s) => s.id == picked);
    if (safe.isEmpty) return;
    setState(() {
      _safeId = safe.first.id;
      _accountId = safe.first.linkedAccountId;
      // خزنةٌ جديدةٌ ⇒ حسابٌ آخر، والجلسةُ المفتوحةُ كانت على حساب الخزنة
      // السابقة فلا تصلح لهذه.
      _sessionId = null;
    });
  }

  Widget _statementBalanceField(BuildContext context) {
    return SizedBox(
      width: 170,
      height: 40,
      child: TextField(
        controller: _statementBalanceController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: context.picposText,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'رصيد كشف البنك',
          hintStyle: TextStyle(fontSize: 11.5, color: context.picposMuted),
          filled: true,
          fillColor: context.picposField,
          contentPadding: const EdgeInsets.symmetric(horizontal: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide(color: context.picposHairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide(color: context.picposHairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide(color: context.picposBrandInk),
          ),
        ),
      ),
    );
  }

  Widget _newSessionButton(BuildContext context) {
    final canCreate = _safeId != null && _accountId != null && !_creatingSession;
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: canCreate ? _createSession : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        icon: _creatingSession
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : const Icon(PhosphorIconsBold.plusCircle, size: 16),
        label: const Text('جلسة جديدة'),
      ),
    );
  }

  Future<void> _createSession() async {
    final accountId = _accountId;
    if (accountId == null) return;
    final balance =
        double.tryParse(_statementBalanceController.text.trim()) ?? 0;

    setState(() => _creatingSession = true);
    try {
      final repo = ref.read(accountingRepositoryProvider);
      final id = await repo.createReconciliation(
        bankAccountId: accountId,
        periodStart: _period.start,
        periodEnd: _period.end,
        statementBalance: balance,
      );
      if (!mounted) return;
      setState(() => _sessionId = id);
    } finally {
      if (mounted) setState(() => _creatingSession = false);
    }
  }

  // ── المتن: مؤشّراتُ الجلسة، أو حالةٌ فارغةٌ بلا جلسةٍ مفتوحة ──────────

  Widget _buildBody() {
    final sessionId = _sessionId;
    if (sessionId == null) {
      return const PicPosEmptyState(
        icon: PhosphorIconsBold.bank,
        title: 'اختر خزنةً وفترةً ثمّ أنشئ جلسة',
      );
    }
    return _buildReport(sessionId);
  }

  Widget _buildReport(int sessionId) {
    final repo = ref.read(accountingRepositoryProvider);
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('bank_reconciliation_report_$sessionId'),
      future: repo.getReconciliationReport(sessionId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('تعذّر حسابُ تقرير المطابقة: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final bookBalance = (data['bookBalance'] as num?)?.toDouble() ?? 0;
        final statementBalance =
            (data['statementBalance'] as num?)?.toDouble() ?? 0;
        final difference = (data['difference'] as num?)?.toDouble() ?? 0;
        final matched = data['matchedCount'] as int? ?? 0;
        final unmatched = data['unmatchedCount'] as int? ?? 0;

        return PicPosHubKpiRow(items: [
          PicPosHubKpi(
            icon: PhosphorIconsBold.bookOpen,
            label: 'رصيد الدفتر',
            value: _money.format(bookBalance),
            tint: AppColors.primary,
          ),
          PicPosHubKpi(
            icon: PhosphorIconsBold.bank,
            label: 'رصيد الكشف',
            value: _money.format(statementBalance),
            tint: AppColors.info,
          ),
          PicPosHubKpi(
            icon: PhosphorIconsBold.scales,
            label: 'الفرق',
            value: _money.format(difference),
            tint: difference == 0 ? AppColors.success : AppColors.error,
          ),
          PicPosHubKpi(
            icon: PhosphorIconsBold.checkSquareOffset,
            label: 'مطابَق / غير مطابَق',
            value: '$matched / $unmatched',
            tint: unmatched == 0 ? AppColors.success : AppColors.warning,
          ),
        ]);
      },
    );
  }
}
