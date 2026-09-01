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
import '../../core/widgets/app_toast.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/repositories/treasury_repository.dart' show SafeData;
import '../picpos_shell/picpos_empty_state.dart';
import '../picpos_shell/picpos_hub_kpi.dart';
import '../picpos_shell/picpos_option_picker.dart';
import '../picpos_shell/picpos_report_bar.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import '../picpos_shell/picpos_surface.dart';

final _money = NumberFormat('#,##0.00', 'en');

/// نمطُ رصيدٍ صالح: رقمٌ عاديٌّ، أو مجموعٌ بفواصل الآلاف **في مواضعها
/// فقط** — كلُّ فاصلةٍ متبوعةٌ بثلاثة أرقامٍ بالضبط، لا فاصلةً عشريّةً
/// أوروبيّة. النقطةُ العشريّةُ اختياريّةٌ بعد ذلك، وإشارةُ سالبٍ اختياريّةٌ
/// قبله (‏كان `double.tryParse` يقبلها قبل هذا التشديد، فلا داعيَ لإسقاطها).
@visibleForTesting
final validBalancePattern = RegExp(r'^-?(\d+|\d{1,3}(,\d{3})*)(\.\d+)?$');

/// يحلّل نصَّ رصيد الكشف إلى رقمٍ صالح، أو `null` إن كان فارغاً أو معطوباً.
///
/// ⚠️ **الفاصلةُ تُقبَل في مواضع الآلاف فقط — لا فاصلةً عشريّةً أوروبيّة**
/// (مراجعةٌ 2026-09-01، مأخذ أ): كانت `replaceAll(',', '')` تجرّد أيَّ
/// فاصلةٍ بلا نظرٍ إلى موضعها، فـ`1500,50` (فاصلةٌ عشريّةٌ في تدوينٍ
/// أوروبيّ) كانت تصير `150050` — مئةَ ضعفٍ بلا خطأٍ ولا تنبيه، يدخل
/// `difference` مباشرةً ويُصدَّق. والعلاجُ صراحةُ الوحدة: [validBalancePattern]
/// يتحقّق من **موضع** كلّ فاصلةٍ قبل التجريد، لا يجرّدها أينما وقعت.
///
/// ⚠️ **وتحقّقتُ أنّ `NumberFormat.tryParse` لا يحلّ هذا** — قرأتُ مصدره
/// (`number_parser_base.dart` في حزمة `intl`): فاصلُ الآلاف يُستبدَل
/// بلا فحص موضعٍ إطلاقاً (‏`GROUP_SEP: handleSpace` تجرّده أينما وقع)،
/// فيقع في العطب نفسِه على `1500,50`. والنمطُ الصريحُ هنا هو الحلّ، لا
/// استبدالُ مزوّدٍ بآخر يحمل نفس الثغرة.
///
/// ولا قيمةَ افتراضيّةً عند الفشل: `null` يعني «أعِد كتابةَ الرقم»، لا
/// «افترض صفراً» — فصفرٌ صامتٌ هنا فرقٌ محاسبيٌّ مختلَق.
@visibleForTesting
double? parseStatementBalance(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (!validBalancePattern.hasMatch(trimmed)) return null;
  return double.tryParse(trimmed.replaceAll(',', ''));
}

/// تقريرُ جلسة مطابقةٍ بعينها — عائلةٌ على رقم الجلسة.
///
/// ⚠️ **مزوّدٌ لا نداءٌ داخل `build`**: `FutureBuilder.future` بكائنٍ يُبنى
/// من جديد كلَّ إعادة بناء يعيد الاستعلامَ مع كلّ `setState` — ومهمّتا
/// الاستيراد والمطابقة الآليّة (٥) والقائمتان المتجاورتان (٦) ستضيفان حالةً
/// وأزراراً إلى هذا الملفّ نفسِه، فكلُّ تفاعلٍ فيهما كان سيُطلق استعلامَ
/// تقريرٍ جديداً. والمزوّدُ (بمفتاح `sessionId`) يخزّن نتيجتَه بين
/// عمليّات البناء، ويُنعَش عمداً حين تحتاج تينك المهمّتان ذلك.
///
/// ⚠️ **يقرأ `accountingRepositoryProvider` لا `databaseProvider`** —
/// فاختبارُ الودجت يبقى بلا قاعدةٍ حقيقيّة.
final _reconciliationReportProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>((ref, sessionId) {
  return ref.watch(accountingRepositoryProvider).getReconciliationReport(sessionId);
});

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

    // ⚠️ **بلا اختيارٍ تلقائيّ لأيّ خزنة**: `list.first` ترتيبُ صفوفِ
    // استعلامٍ لا معنىً له عند المستخدم، وأثرُه ماليٌّ لا تجميليّ — خزنةٌ
    // عشوائيّةٌ مختارةٌ تجعل زرَّ «جلسة جديدة» قابلاً للنقر فوراً، و
    // `createReconciliation` إدراجٌ حقيقيٌّ بلا فحصِ تكرار. فتبدأ الشاشةُ
    // بلا خزنةٍ مختارة، والمستخدمُ يختار بنفسه من المنتقي.
    //
    // وإعادةُ البناء عند تبدّل نصِّ رصيد الكشف — لتفعيل/تعطيل زرِّ «جلسة
    // جديدة» ولإظهار خطأ الإدخال حيّاً بدل استبداله بصفر.
    _statementBalanceController.addListener(_onBalanceTextChanged);
  }

  void _onBalanceTextChanged() => setState(() {});

  @override
  void dispose() {
    _statementBalanceController
      ..removeListener(_onBalanceTextChanged)
      ..dispose();
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
            // فترةٌ جديدةٌ ⇒ الجلسةُ المفتوحةُ (إن وُجدت) كانت على فترةٍ
            // أخرى ومؤشّراتُها محسوبةٌ عليها — نفسُ تعليل تبديل الخزنة.
            _sessionId = null;
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
    final raw = _statementBalanceController.text;
    // خطأُ إدخالٍ يُقال فقط بعد أن يكتب المستخدمُ شيئاً — حقلٌ فارغٌ لم
    // يُلمَس بعدُ ليس «خطأً»، هو حالةُ البداية.
    final invalid = raw.trim().isNotEmpty && parseStatementBalance(raw) == null;

    return SizedBox(
      width: 170,
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
          // خطأُ إدخالٍ يُقال — لا يُستبدَل بصفرٍ صامت.
          errorText: invalid ? 'قيمةٌ غيرُ صالحة' : null,
          errorStyle: const TextStyle(fontSize: 10.5),
          filled: true,
          fillColor: context.picposField,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
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
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: AppColors.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: AppColors.error, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _newSessionButton(BuildContext context) {
    final balance = parseStatementBalance(_statementBalanceController.text);
    final canCreate = _safeId != null &&
        _accountId != null &&
        balance != null &&
        !_creatingSession;
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: canCreate ? () => _createSession(balance) : null,
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

  /// [balance] وصل مُحلَّلاً وصالحاً بالفعل — الزرُّ المُنادي معطَّلٌ ما لم
  /// يكن كذلك، فلا حاجةَ لإعادة التحليل ولا لقيمةٍ افتراضيّة هنا.
  Future<void> _createSession(double balance) async {
    final accountId = _accountId;
    if (accountId == null) return;

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
    } catch (e) {
      // ⚠️ لا يُبتلَع: كان `try { … } finally { … }` بلا `catch` يترك
      // الاستثناءَ يفلت من ردّ نداء الزرّ — خطأُ منطقةٍ غيرُ مرئيٍّ في
      // الإنتاج، والمستخدمُ يرى زرّاً ينبض ثمّ لا شيء.
      if (!mounted) return;
      AppToast.show(context, 'تعذّر إنشاءُ جلسة المطابقة: $e',
          type: ToastType.error);
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
    final reportAsync = ref.watch(_reconciliationReportProvider(sessionId));

    return reportAsync.when(
      data: (data) {
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('تعذّر حسابُ تقرير المطابقة: $e'),
      ),
    );
  }
}
