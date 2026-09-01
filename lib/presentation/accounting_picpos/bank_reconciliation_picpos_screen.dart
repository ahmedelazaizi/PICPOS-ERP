// ignore_for_file: avoid_dynamic_calls
//
// ⚠️ **مقصودٌ لا مهمَل**: `excelServiceProvider` من نوع `Provider<dynamic>`
// (يخدم سطحَي ويب وDesktop بنوعَي إرجاعٍ مختلفَين)، والنمطُ نفسُه مستعمَلٌ
// أصلاً في `financial_statements_picpos_screen.dart` — انظر تعليقَ
// `_downloadTemplate` أدناه.

// شاشةُ «المطابقة البنكية» بهويّة PicPos — المهمّةُ ٤ (الرأسُ والجلسةُ
// والمؤشّرات) والمهمّةُ ٥ (الاستيرادُ والمطابقةُ الآليّة) معاً. القائمتان
// المتجاورتان (٦) مهمّةٌ لاحقةٌ — لا يبنيهما هذا الملفّ.
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
import '../../core/utils/uuid_v7.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/providers.dart' show excelServiceProvider;
import '../../data/providers/repository_providers.dart';
import '../../domain/repositories/treasury_repository.dart' show SafeData;
import '../picpos_shell/picpos_empty_state.dart';
import '../picpos_shell/picpos_hub_kpi.dart';
import '../picpos_shell/picpos_option_picker.dart';
import '../picpos_shell/picpos_report_bar.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import '../picpos_shell/picpos_surface.dart';
import '../picpos_shell/picpos_toolbar.dart';

final _money = NumberFormat('#,##0.00', 'en');

/// يحوّل رقماً إلى أرقامٍ عربيّة — «طوبق ٣ سطراً» لا «طوبق 3 سطراً» (نفسُ
/// نمط `_ar` في `analytics_picpos_screen.dart` و`_arabicDigits` في
/// `excel_service.dart`).
String _arabicDigits(Object n) =>
    '$n'.replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)]);

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

  // ⚠️ **مراجعة 2026-09-01، مأخذ ٣**: بلا هذا العلم، نقرتان متتاليتان على
  // «استيراد كشف» تفتحان مسارَين بدفعتَين مختلفتَين فتُدرَج الأسطرُ مرّتَين
  // بلا فحصِ تكرارٍ في المحرّك. نفسُ نمط `_creatingSession` أعلاه — علمٌ
  // واحدٌ يعطّل الأزرارَ الثلاثةَ معاً أثناء أيٍّ منها.
  bool _actionBusy = false;

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
        toolbar: _buildActionsBar(),
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

  // ── الشريطُ الثلاثيّ: تنزيلُ القالب · استيرادُ كشفٍ · مطابقةٌ آليّة ─────
  //
  // ⚠️ **الكتابةُ في الشاشة لا في `ExcelService`**: `pickAndParseBankStatement`
  // تحلّل ولا تكتب (المهمّةُ ٣، الكوميت 31d5aa3c — قرارٌ موثّق): `ExcelService`
  // يأخذ مستوداتٍ لا قاعدة، وحقنُ `IAccountingRepository` فيه لأجل دالّةٍ
  // واحدةٍ كان سيوسّع اعتمادَه على كلّ مُنشئيه. فتكتب هذه الشاشةُ بالمستودع
  // الذي بيدها أصلاً (‏`accountingRepositoryProvider`).
  //
  // ⚠️ **الثلاثةُ معطَّلةٌ حين `_accountId == null`** — لا خزنةَ لا حسابَ
  // مرتبطاً بها بعدُ، فلا جدوى من نداء أيٍّ منها.

  Widget _buildActionsBar() {
    final enabled = _accountId != null && !_actionBusy;
    return PicPosToolbar(
      children: [
        OutlinedButton.icon(
          onPressed: enabled ? _downloadTemplate : null,
          icon: const Icon(PhosphorIconsBold.download, size: 15),
          label: const Text('تنزيل القالب'),
        ),
        OutlinedButton.icon(
          onPressed: enabled ? _importStatement : null,
          icon: const Icon(PhosphorIconsBold.uploadSimple, size: 15),
          label: const Text('استيراد كشف'),
        ),
        FilledButton.icon(
          onPressed: enabled ? _autoMatch : null,
          icon: const Icon(PhosphorIconsBold.arrowsLeftRight, size: 15),
          label: const Text('مطابقة آلية'),
        ),
      ],
    );
  }

  /// [ExcelService.exportBankStatementTemplate] تُمسك كلَّ أخطائها داخليّاً
  /// وتعيد `null` عند التعذّر — لا استثناءَ يفلت هنا، لكنّ `_actionBusy`
  /// لا يزال يحتاج `finally` كي يُعاد ولو أُعيد مبكّراً.
  Future<void> _downloadTemplate() async {
    setState(() => _actionBusy = true);
    try {
      final service = ref.read(excelServiceProvider);
      final path = await service.exportBankStatementTemplate();
      if (!mounted) return;
      if (path == null) {
        AppToast.show(context, 'تعذّر إنشاءُ قالب الكشف',
            type: ToastType.error);
        return;
      }
      AppToast.show(context, 'حُفظ القالبُ في: $path', type: ToastType.success);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  /// يختار المستخدمُ ملفَّ كشفٍ ويُحلَّل (`pickAndParseBankStatement`)، ثمّ
  /// تكتب هذه الدالّةُ الأسطرَ الصالحةَ بالمستودع.
  ///
  /// ⚠️ **`null` ليست خطأً**: إلغاءُ المستخدم لاختيار ملفّ — لا شيءَ يُعرَض.
  ///
  /// ⚠️ **الرمْيُ مقصودٌ على ملفٍّ تالف**: `pickAndParseBankStatement` ترمي
  /// عمداً، و«تعذّرت العمليّة» العامّةُ كانت ستُخفي السببَ الذي يحتاجه
  /// المحاسبُ ليصلح الملفّ — فنصُّ الاستثناء يُعرَض كما هو.
  Future<void> _importStatement() async {
    final accountId = _accountId;
    if (accountId == null) return;
    setState(() => _actionBusy = true);
    try {
      final service = ref.read(excelServiceProvider);
      final summary = await service.pickAndParseBankStatement();
      if (summary == null) return; // إلغاءُ المستخدم — ليس خطأً
      if (!mounted) return;

      final List<Map<String, dynamic>> lines = summary.lines;
      final List<String> errors = summary.errors;

      // «لا صفَّ صالحاً» حالةٌ صريحةٌ — والأسبابُ (إن وُجدت) تصل كما هي،
      // لا تُبتلَع في رسالةٍ عامّة.
      if (lines.isEmpty) {
        final reason = errors.isEmpty
            ? 'لا صفَّ صالحاً في الملف'
            : 'لا صفَّ صالحاً في الملف: ${errors.join('؛ ')}';
        AppToast.show(context, reason, type: ToastType.error);
        return;
      }

      final repo = ref.read(accountingRepositoryProvider);
      final n = await repo.importBankStatementLines(
        bankAccountId: accountId,
        lines: lines,
        batchId: UuidV7.generate(),
      );
      if (!mounted) return;

      // ⚠️ **مراجعة 2026-09-01، مأخذ ٤**: سطورٌ رُفضت مع أخرى أُدرجت ليست
      // نجاحاً كاملاً — `warning` لا `success` حين توجد أسبابُ رفض.
      final hasErrors = errors.isNotEmpty;
      var message = 'استُورد ${_arabicDigits(n)} سطراً';
      if (hasErrors) {
        message += '، ورُفض ${_arabicDigits(errors.length)}: '
            '${errors.join('؛ ')}';
      }
      AppToast.show(context, message,
          type: hasErrors ? ToastType.warning : ToastType.success);

      final sessionId = _sessionId;
      if (sessionId != null) {
        ref.invalidate(_reconciliationReportProvider(sessionId));
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'تعذّر استيرادُ الكشف: $e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _autoMatch() async {
    final accountId = _accountId;
    if (accountId == null) return;
    setState(() => _actionBusy = true);
    try {
      final repo = ref.read(accountingRepositoryProvider);
      final n = await repo.autoMatchStatementLines(accountId);
      if (!mounted) return;
      AppToast.show(context, 'طوبق ${_arabicDigits(n)} سطراً',
          type: ToastType.success);

      final sessionId = _sessionId;
      if (sessionId != null) {
        ref.invalidate(_reconciliationReportProvider(sessionId));
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'تعذّرت المطابقةُ الآليّة: $e',
          type: ToastType.error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
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
