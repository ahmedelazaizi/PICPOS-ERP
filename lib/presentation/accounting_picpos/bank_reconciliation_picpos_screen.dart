import 'package:ural_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
//
// ⚠️ **مقصودٌ لا مهمَل**: `excelServiceProvider` من نوع `Provider<dynamic>`
// (يخدم سطحَي ويب وDesktop بنوعَي إرجاعٍ مختلفَين)، والنمطُ نفسُه مستعمَلٌ
// أصلاً في `financial_statements_picpos_screen.dart` — انظر تعليقَ
// `_downloadTemplate` أدناه.

// شاشةُ «المطابقة البنكية» بهويّة PicPos — المهمّةُ ٤ (الرأسُ والجلسةُ
// والمؤشّرات) والمهمّةُ ٥ (الاستيرادُ والمطابقةُ الآليّة) والمهمّةُ ٦
// (القائمتان المتجاورتان والمطابقةُ اليدويّةُ والنزعُ وإقفالُ الجلسة) معاً.
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
import '../../core/utils/financial_utils.dart';
import '../../core/utils/uuid_v7.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/providers.dart'
    show authProvider, excelServiceProvider;
import '../../data/providers/repository_providers.dart';
import '../../domain/repositories/treasury_repository.dart' show SafeData;
import '../picpos_shell/picpos_data_table.dart';
import '../picpos_shell/picpos_dialog.dart';
import '../picpos_shell/picpos_empty_state.dart';
import '../picpos_shell/picpos_hub_kpi.dart';
import '../picpos_shell/picpos_option_picker.dart';
import '../picpos_shell/picpos_report_bar.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import '../picpos_shell/picpos_surface.dart';
import '../picpos_shell/picpos_toolbar.dart';
import '../widgets/report_components.dart' show DateRangeFilter;

final _money = NumberFormat('#,##0.00', 'en');
final _dateFmt = DateFormat('yyyy-MM-dd');

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

/// الجلسةُ **المفتوحةُ** لحسابٍ وفترةٍ بعينهما — إن وُجدت.
///
/// 🔴 **بلا هذا كانت الصفوفُ تتراكم.** `createReconciliation` إدراجٌ غيرُ
/// مشروطٍ بلا فحصِ تكرار، والشاشةُ لم تكن تعرض إلّا زرَّ «جلسة جديدة» —
/// فكلُّ فتحٍ للتبويبة على نفس الخزنة والفترة كان يُنشئ صفّاً آخرَ في
/// `bank_reconciliations`. والمواصفةُ §٣‑٣ تعدّ قائمةَ الجلسات الجزءَ
/// **الحقيقيّ** من الشاشة المحذوفة، وكانت `getReconciliationSessions`
/// مُعلَنةً ومُنفَّذةً و**بلا مُنادٍ واحدٍ في `lib`**.
///
/// ⚠️ **والمطابقةُ بالتاريخ لا بلحظة**: `periodEnd` يُخزَّن بنهاية اليوم
/// (‏`23:59:59`) و`periodStart` ببدايته، والمقارنةُ بـ`==` على `DateTime`
/// تقارن الميلّي ثانية — فجلسةٌ أُنشئت بفارقِ ثانيةٍ لا تُطابَق وتُنشأ
/// نسخةٌ ثانية. فالمقارنةُ على اليوم وحدَه.
///
/// ⚠️ **ويُعيد `int?` لا صفَّ drift**: `getReconciliationSessions` تُرجع
/// `List<BankReconciliationData>`، وذكرُ ذلك النوع هنا يستلزم استيراد
/// `data/database/database.dart` — وهو **ممنوعٌ على ملفّات العرض** بحارس
/// `presentation_db_import_guard` وقائمتُه البيضاءُ مقفلة. فالحقولُ تُقرأ
/// ديناميكيّاً ولا يخرج من المزوّد إلّا المعرّف — وهو كلُّ ما يحتاجه الزرّ.
/// (نفسُ عقدِ `_sessionLocked` والقوائم الثلاث أدناه.)
final _openSessionProvider = FutureProvider.autoDispose
    .family<int?, ({int accountId, DateTime start, DateTime end})>(
        (ref, key) async {
  final sessions =
      await ref.watch(accountingRepositoryProvider).getReconciliationSessions();
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  for (final dynamic s in sessions) {
    if (s.bankAccountId == key.accountId &&
        s.status != 'completed' &&
        sameDay(s.periodStart as DateTime, key.start) &&
        sameDay(s.periodEnd as DateTime, key.end)) {
      return s.id as int;
    }
  }
  return null;
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
  // واحدٌ يعطّل الأزرارَ الثلاثةَ معاً أثناء أيٍّ منها. والمهمّةُ ٦ توسّعه
  // ليغطّي أزرارَ «طابق» و«نزع» و«إقفال الجلسة» أيضاً — نداءٌ واحدٌ في
  // كلِّ لحظة، لا تشابكَ مسارَين على نفس السطر.
  bool _actionBusy = false;

  // ── المهمّةُ ٦: اختيارُ سطرٍ من كلّ قائمة تمهيداً للمطابقة اليدويّة ─────
  //
  // ⚠️ **اختيارٌ لا تظليلَ ودجت**: `PicPosDataTable` لا تحمل مفهومَ «صفٍّ
  // مختار» (ممنوعُ تعديلها هنا). فحالةُ الاختيار تعيش في الشاشة، وتُشار
  // إليها بصريّاً بتلوين خلايا الصفّ نفسِه (`tint`/`bold`) لا بلبنةٍ جاهزة.
  int? _pickedStmtId;
  int? _pickedJeLineId;

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

  /// الشهرُ الماضي كاملاً — **بنهاية يومه الأخير لا بمنتصف ليله**.
  ///
  /// ⚠️ **مراجعةٌ 2026-09-01، مأخذ ٢**: كانت تعيد
  /// `firstOfThisMonth.subtract(Duration(days: 1))` أي `00:00:00`.
  /// و`createReconciliation` تحسب رصيدَ الدفتر بـ`e.entry_date <= ?`
  /// (‏`bank_reconciliation_dao.dart`)، وقيودُ اليوميّة تحمل وقتاً. فكلُّ قيدٍ
  /// في **اليوم الأخير من الفترة** كان يسقط من رصيد الدفتر ومن «لم تظهر في
  /// الكشف»، بينما أسطرُ الكشف لذلك اليوم (‏مسوّاةٌ إلى منتصف الليل في
  /// `_asDate`) تدخل ⇒ **فرقٌ مُختلَقٌ يُعرَض ويُصدَّق**، في المسار
  /// الافتراضيّ ما لم يلمس المستخدمُ شريطَ المدى.
  ///
  /// ⚠️ **و`DateRangeFilter.normalizeEnd` لا `DateTime(y, m, d, 23, 59, 59)`
  /// بيدٍ ثانية**: هي عقدُ Spec 065 الموثَّقُ في `report_components.dart`
  /// بوصفه «فقدانَ بياناتٍ لا يراه المشغّل»، وهي **عينُ** ما يمرّره
  /// `PicPosReportFilterBar` من فتراتِه الجاهزةِ ومن منتقي المدى المخصّص —
  /// فالبدايةُ والتحويلُ اليدويُّ يتّفقان بدل أن يفترقا في الكسور.
  static DateTimeRange _lastMonthRange() {
    final now = DateTime.now();
    final firstOfThisMonth = DateTime(now.year, now.month, 1);
    final lastMonthEnd =
        firstOfThisMonth.subtract(const Duration(days: 1));
    final lastMonthStart = DateTime(lastMonthEnd.year, lastMonthEnd.month, 1);
    return DateTimeRange(
      start: lastMonthStart,
      end: DateRangeFilter.normalizeEnd(lastMonthEnd),
    );
  }

  @override
  Widget build(BuildContext context) {
    final banksAsync = ref.watch(_bankSafesProvider);

    return banksAsync.when(
      data: (result) => PicPosScreenScaffold(
        title: tr('المطابقة البنكية'),
        icon: PhosphorIconsBold.bank,
        subHeader: _buildHeader(context, result.safes, result.excluded),
        toolbar: _buildActionsBar(),
        body: _buildBody(),
      ),
      loading: () =>  PicPosScreenScaffold(
        title: tr('المطابقة البنكية'),
        icon: PhosphorIconsBold.bank,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => PicPosScreenScaffold(
        title: tr('المطابقة البنكية'),
        icon: PhosphorIconsBold.bank,
        body: Center(child: Text(tr('تعذّر تحميل الخزائن البنكية: {e}', {'e': e}))),
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
          onRangeChanged: (start, end) {
            // ⚠️ **قبل `setState` لا داخلَه**: `clear()` تُخطر مستمعيها
            // فوراً، و`_onBalanceTextChanged` يستدعي `setState` — فنداءٌ
            // متداخل. وهذا هو موضعُ **مأخذ ٨‑ب**: رصيدُ كشفٍ يخصُّ فترةً
            // يبقى معروضاً لفترةٍ أخرى، وهو رقمٌ يدخل `difference` مباشرةً.
            _invalidateSession();
            setState(() {
              _period = DateTimeRange(start: start, end: end);
            });
          },
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
            padding: const EdgeInsetsDirectional.fromSTEB(26, 8, 26, 0),
            child: Text(
              tr('خزنةٌ بنكيّةٌ أو أكثرُ بلا حسابٍ مرتبطٍ — لا يمكن مطابقتُها'),
              style: TextStyle(fontSize: 12, color: context.picposMuted),
            ),
          ),
      ],
    );
  }

  Widget _safePickerButton(BuildContext context, List<SafeData> safes) {
    final matches = safes.where((s) => s.id == _safeId);
    final label = matches.isEmpty ? tr('اختر خزنة بنكية') : matches.first.name;

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
      title: tr('اختيار الخزنة البنكية'),
      options: [
        for (final s in safes)
          PicPosOption<int?>(value: s.id, label: s.name, sub: s.bankName),
      ],
      selected: _safeId,
    );
    if (picked == null) return;
    final safe = safes.where((s) => s.id == picked);
    if (safe.isEmpty) return;
    // خزنةٌ جديدةٌ ⇒ حسابٌ آخر، والجلسةُ المفتوحةُ كانت على حساب الخزنة
    // السابقة فلا تصلح لهذه.
    _invalidateSession();
    setState(() {
      _safeId = safe.first.id;
      _accountId = safe.first.linkedAccountId;
    });
  }

  /// تُبطِل الجلسةَ المفتوحةَ وتمسح ما يخصُّها من مُدخَلات.
  ///
  /// ⚠️ **رصيدُ الكشف يُمسَح معها** (مراجعةٌ 2026-09-01، مأخذ ٨‑ب): كان
  /// الحقلُ يبقى محمّلاً برصيد كشفِ الخزنة/الفترة السابقة، فيُنشئ المستخدمُ
  /// جلسةَ خزنةٍ أخرى برقمِ الأولى — ورقمُ رصيدِ الكشف يدخل `difference`
  /// مباشرةً بلا أيّ تحقّقٍ خلفه. ومسحُه يُعيد الزرَّ إلى التعطيل حتّى
  /// يُكتَب رقمُ هذه الخزنة، وهو الفرقُ بين «أعِد الإدخال» و«صدِّق رقماً
  /// ليس لك».
  ///
  /// ⚠️ **والاختيارُ يُمسَح كذلك**: `_pickedStmtId`/`_pickedJeLineId` معرّفا
  /// سطرَين في قوائمِ جلسةٍ بطَلت.
  void _invalidateSession() {
    _sessionId = null;
    _pickedStmtId = null;
    _pickedJeLineId = null;
    _statementBalanceController.clear();
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
          hintText: tr('رصيد كشف البنك'),
          hintStyle: TextStyle(fontSize: 11.5, color: context.picposMuted),
          // خطأُ إدخالٍ يُقال — لا يُستبدَل بصفرٍ صامت.
          errorText: invalid ? tr('قيمةٌ غيرُ صالحة') : null,
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

  /// زرٌّ واحدٌ بوجهَين: **متابعةٌ** إن كانت للحساب والفترة جلسةٌ مفتوحة،
  /// و**إنشاءٌ** إن لم تكن.
  ///
  /// ⚠️ ولا يُعرَض «جلسة جديدة» فوق جلسةٍ مفتوحة: ذلك بالضبط ما كان يراكم
  /// الصفوف. والمتابعةُ لا تشترط رصيدَ كشفٍ — الرصيدُ مخزَّنٌ في الجلسة
  /// أصلاً، واشتراطُه كان سيمنع المحاسبَ من العودة إلى عملِه.
  Widget _newSessionButton(BuildContext context) {
    final accountId = _accountId;
    final open = accountId == null
        ? null
        : ref
            .watch(_openSessionProvider((
              accountId: accountId,
              start: _period.start,
              end: _period.end,
            )))
            .value;

    if (open != null) {
      return SizedBox(
        height: 40,
        child: ElevatedButton.icon(
          onPressed: _creatingSession
              ? null
              : () => setState(() => _sessionId = open),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          icon: const Icon(PhosphorIconsBold.arrowUUpLeft, size: 16),
          label:  Text(tr('متابعة الجلسة المفتوحة')),
        ),
      );
    }

    final balance = parseStatementBalance(_statementBalanceController.text);
    final canCreate = _safeId != null &&
        accountId != null &&
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
        label:  Text(tr('جلسة جديدة')),
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
        // ⚠️ **مراجعةٌ 2026-09-01، مأخذ ٥**: `preparedBy` كان فارغاً في كلّ
        // جلسة — عمودٌ في `bank_reconciliations` لا يُملأ أبداً، فمطابقةٌ
        // مقفلةٌ بلا اسمِ مَن أعدَّها. والنمطُ منسوخٌ عن نظيره في نفس
        // الفورك: `journal_entries_picpos_screen.dart`.
        userId: ref.read(authProvider).user?.id,
      );
      if (!mounted) return;
      setState(() => _sessionId = id);
      // الجلسةُ صارت مفتوحةً — فالزرُّ يجب أن ينقلب إلى «متابعة»، وإلّا بقي
      // يعرض «جلسة جديدة» فوق جلسةٍ قائمةٍ وعاد التراكمُ من بابه.
      ref.invalidate(_openSessionProvider((
        accountId: accountId,
        start: _period.start,
        end: _period.end,
      )));
    } catch (e) {
      // ⚠️ لا يُبتلَع: كان `try { … } finally { … }` بلا `catch` يترك
      // الاستثناءَ يفلت من ردّ نداء الزرّ — خطأُ منطقةٍ غيرُ مرئيٍّ في
      // الإنتاج، والمستخدمُ يرى زرّاً ينبض ثمّ لا شيء.
      if (!mounted) return;
      AppToast.show(context, tr('تعذّر إنشاءُ جلسة المطابقة: {e}', {'e': e}),
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

  /// هل الجلسةُ المعروضةُ **مقفلة**؟ يُقرَأ من `report['reconciliation']`
  /// نفسِه لا من علمٍ محلّيّ.
  ///
  /// ⚠️ **مراجعةٌ 2026-09-01، مأخذ ٦**: بعد `completeReconciliation` كان
  /// `_sessionId` يبقى والتقريرُ معروضاً وأزرارُ «طابق» و«نزع» و«استيراد
  /// كشف» و«مطابقة آلية» فعّالةً كلَّها على جلسةٍ `status = 'completed'` —
  /// فالإقفالُ لا يقفل شيئاً. والشاشةُ لم تكن تقرأ `reconciliation` ولا
  /// `status` في أيّ موضع.
  ///
  /// ⚠️ **والقراءةُ ديناميكيّةٌ عن قصد**: `reconciliation` صفُّ drift
  /// (‏`BankReconciliationData`) والشاشةُ **ممنوعةٌ** من استيراد
  /// `data/database/database.dart` (حارسُ `presentation_db_import_guard`) —
  /// نفسُ عقدِ القوائم الثلاث أعلى `_buildReport`.
  ///
  /// و`null` ⇒ غيرُ مقفلة: تقريرٌ بلا صفِّ جلسةٍ لا يُقرأ إقفالاً.
  bool get _sessionLocked {
    final id = _sessionId;
    if (id == null) return false;
    final report = ref.watch(_reconciliationReportProvider(id)).value;
    if (report == null) return false;
    final dynamic recon = report['reconciliation'];
    if (recon == null) return false;
    return recon.status == 'completed';
  }

  Widget _buildActionsBar() {
    final enabled = _accountId != null && !_actionBusy;
    // ⚠️ **الإقفالُ يمنع الكتابةَ وحدَها**: «تنزيل القالب» لا يمسّ شيئاً —
    // ومحاسبٌ يفتح جلسةً مقفلةً ليراجعها قد يحتاج القالبَ للجلسة التالية.
    // فتعطيلُه معهما تشديدٌ بلا سبب.
    final canWrite = enabled && !_sessionLocked;
    return PicPosToolbar(
      children: [
        OutlinedButton.icon(
          onPressed: enabled ? _downloadTemplate : null,
          icon: const Icon(PhosphorIconsBold.download, size: 15),
          label:  Text(tr('تنزيل القالب')),
        ),
        OutlinedButton.icon(
          onPressed: canWrite ? _importStatement : null,
          icon: const Icon(PhosphorIconsBold.uploadSimple, size: 15),
          label:  Text(tr('استيراد كشف')),
        ),
        FilledButton.icon(
          onPressed: canWrite ? _autoMatch : null,
          icon: const Icon(PhosphorIconsBold.arrowsLeftRight, size: 15),
          label:  Text(tr('مطابقة آلية')),
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
        AppToast.show(context, tr('تعذّر إنشاءُ قالب الكشف'),
            type: ToastType.error);
        return;
      }
      AppToast.show(context, tr('حُفظ القالبُ في: {path}', {'path': path}), type: ToastType.success);
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
            ? tr('لا صفَّ صالحاً في الملف')
            : tr('لا صفَّ صالحاً في الملف: {p0}', {'p0': errors.join('؛ ')});
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
      final outOfPeriod = _allLinesOutsidePeriod(lines);
      var message = tr('استُورد {p0} سطراً', {'p0': _arabicDigits(n)});
      if (hasErrors) {
        message += tr('، ورُفض {p0}: {p1}', {'p0': _arabicDigits(errors.length), 'p1': errors.join('؛ ')});
      }
      if (outOfPeriod) {
        message += tr(' — ولا سطرَ منها يقع في الفترة المختارة، فلن تظهر في المطابقة');
      }
      AppToast.show(context, message,
          type: hasErrors || outOfPeriod
              ? ToastType.warning
              : ToastType.success);

      final sessionId = _sessionId;
      if (sessionId != null) {
        ref.invalidate(_reconciliationReportProvider(sessionId));
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, tr('تعذّر استيرادُ الكشف: {e}', {'e': e}), type: ToastType.error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  /// هل وقعت تواريخُ الأسطر المستورَدةِ **كلُّها** خارجَ الفترة المختارة؟
  ///
  /// ⚠️ **مراجعةٌ 2026-09-01، مأخذ ٧**: بعد استيرادٍ ناجحٍ لملفٍّ لا يلتقي
  /// مع الفترة، تعرض بطاقةُ «مطابَق / غير مطابَق» **صفراً على صفر** بلون
  /// النجاح — والرقمُ صحيحٌ حسابيّاً (لا سطرَ في الفترة أصلاً) لكنّه يُقرأ
  /// «طوبق كلُّ شيء». وقوائمُ التقرير كلُّها ترشِّح بـ`periodStart/periodEnd`
  /// (‏`getReconciliationReport`)، فالأسطرُ المُدرَجةُ فعلاً لا تظهر في أيّ
  /// قائمة ولا يفهم المحاسبُ لماذا.
  ///
  /// ⚠️ **و`is DateTime` شرطٌ لا صدفة**: `parseBankStatementRow` تُخرج
  /// `'date'` كـ`DateTime` دائماً — فما ليس كذلك ليس مصدراً أقيسُ عليه،
  /// و«لا أدري» تعني الصمتَ لا صيحةَ إنذارٍ كاذبة.
  bool _allLinesOutsidePeriod(List<Map<String, dynamic>> lines) {
    if (lines.isEmpty) return false;
    return lines.every((l) {
      final d = l['date'];
      if (d is! DateTime) return false;
      return d.isBefore(_period.start) || d.isAfter(_period.end);
    });
  }

  Future<void> _autoMatch() async {
    final accountId = _accountId;
    if (accountId == null) return;
    setState(() => _actionBusy = true);
    try {
      final repo = ref.read(accountingRepositoryProvider);
      final n = await repo.autoMatchStatementLines(accountId);
      if (!mounted) return;
      AppToast.show(context, tr('طوبق {p0} سطراً', {'p0': _arabicDigits(n)}),
          type: ToastType.success);

      final sessionId = _sessionId;
      if (sessionId != null) {
        ref.invalidate(_reconciliationReportProvider(sessionId));
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, tr('تعذّرت المطابقةُ الآليّة: {e}', {'e': e}),
          type: ToastType.error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  // ── المتن: مؤشّراتُ الجلسة، أو حالةٌ فارغةٌ بلا جلسةٍ مفتوحة ──────────

  Widget _buildBody() {
    final sessionId = _sessionId;
    if (sessionId == null) {
      return  PicPosEmptyState(
        icon: PhosphorIconsBold.bank,
        title: tr('اختر خزنةً وفترةً ثمّ أنشئ جلسة'),
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

        // ⚠️ **`dynamic` عمداً — العقدُ قِيس لا خُمِّن.** `unmatchedBankLines`
        // و`matchedLines` عناصرُ `BankStatementLine` (صفوفُ drift بحقولٍ
        // مسمّاة)، و`outstandingBookEntries` عناصرُ `QueryRow` تُقرأ بـ
        // `.data['...']`. والشاشةُ **ممنوعةٌ** من استيراد
        // `data/database/database.dart` (حارسُ
        // `presentation_db_import_guard_test.dart`) — فالوصولُ ديناميكيٌّ
        // (`avoid_dynamic_calls` مُلغًى أعلى الملفّ لهذا بالضبط).
        final unmatchedBankLines =
            (data['unmatchedBankLines'] as List?) ?? const [];
        final outstandingBookEntries =
            (data['outstandingBookEntries'] as List?) ?? const [];
        final matchedLines = (data['matchedLines'] as List?) ?? const [];

        // ── مأخذ ٨‑ج: الاختيارُ يُصالَح مقابلَ القوائم بعد كلّ إنعاش ───────
        //
        // ⚠️ اختَر سطراً ثمّ اضغط «مطابقة آلية»: المحرّكُ يطابقه فيختفي من
        // `unmatchedBankLines`، وكان `_pickedStmtId` يبقى عليه و«طابق» يبقى
        // فعّالاً — نقرةٌ عليه تُنادي `manualMatchStatement` على سطرٍ مطابَقٍ
        // سلفاً. فالمعرّفان يُقاسان على القائمتين الحاليّتين، وما لم يعد فيهما
        // يسقط.
        //
        // ⚠️ **كتابةٌ مباشرةٌ بلا `setState` عن قصد**: نحن داخلَ `build`،
        // والقيمُ الجديدةُ تُستعمَل في هذه العمليّة نفسِها — فـ`setState` هنا
        // إمّا محظورةٌ أو إطارٌ ضائعٌ يُرسَم فيه زرٌّ فعّالٌ على سطرٍ زائل.
        final stmtIds = {for (final dynamic l in unmatchedBankLines) l.id as int};
        final jeIds = {
          for (final dynamic r in outstandingBookEntries)
            (r.data['id'] as num).toInt()
        };
        if (_pickedStmtId != null && !stmtIds.contains(_pickedStmtId)) {
          _pickedStmtId = null;
        }
        if (_pickedJeLineId != null && !jeIds.contains(_pickedJeLineId)) {
          _pickedJeLineId = null;
        }

        final locked = _sessionLocked;
        final canMatch = _pickedStmtId != null &&
            _pickedJeLineId != null &&
            !_actionBusy &&
            !locked;

        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            PicPosHubKpiRow(items: [
              PicPosHubKpi(
                icon: PhosphorIconsBold.bookOpen,
                label: tr('رصيد الدفتر'),
                value: _money.format(bookBalance),
                tint: AppColors.primary,
              ),
              PicPosHubKpi(
                icon: PhosphorIconsBold.bank,
                label: tr('رصيد الكشف'),
                value: _money.format(statementBalance),
                tint: AppColors.info,
              ),
              PicPosHubKpi(
                icon: PhosphorIconsBold.scales,
                label: tr('الفرق'),
                value: _money.format(difference),
                tint: difference == 0 ? AppColors.success : AppColors.error,
              ),
              PicPosHubKpi(
                icon: PhosphorIconsBold.checkSquareOffset,
                label: tr('مطابَق / غير مطابَق'),
                value: '$matched / $unmatched',
                tint: unmatched == 0 ? AppColors.success : AppColors.warning,
              ),
            ]),
            if (locked) _lockedNotice(),
            const SizedBox(height: 14),
            _matchControlsBar(sessionId, difference, canMatch, locked),
            const SizedBox(height: 12),
            // ⚠️ **١١٠٠ حدُّ الانقلاب** — نفسُ نمط `analytics_picpos_screen.dart`
            // (`_trendTable`/`_seasonalityCard`): فوقَه قائمتان متجاورتان
            // بعرضٍ متساوٍ، وتحته عمودٌ. القائمتان المتجاورتان أوّلُ ما
            // ينهار ضيقاً — راجع تعليقَ `PicPosDataTable.minWidth` أدناه.
            LayoutBuilder(builder: (context, box) {
              final unmatchedTable =
                  _unmatchedBankTable(unmatchedBankLines);
              final outstandingTable =
                  _outstandingBookTable(outstandingBookEntries);
              if (box.maxWidth < 1100) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    unmatchedTable,
                    const SizedBox(height: 12),
                    outstandingTable,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: unmatchedTable),
                  const SizedBox(width: 12),
                  Expanded(child: outstandingTable),
                ],
              );
            }),
            const SizedBox(height: 12),
            _matchedTable(matchedLines, locked),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(tr('تعذّر حسابُ تقرير المطابقة: {e}', {'e': e})),
      ),
    );
  }

  // ── شريطُ «طابق» و«إقفال الجلسة» ───────────────────────────────────────

  /// سطرُ «الجلسةُ مقفلة» — الحالةُ تُقال ولا تُترَك تُستنتَج من زرٍّ رماديّ.
  ///
  /// ⚠️ **بلا أرضيّةٍ بيضاءَ صريحة**: حارسُ `picpos_light_surface_guard`
  /// يقيس الأرضيّات، والنصُّ هنا على أرضيّة الشاشة كما هي.
  Widget _lockedNotice() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(26, 12, 26, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(PhosphorIconsBold.lockSimple,
              size: 14, color: AppColors.warning),
          const SizedBox(width: 7),
          Text(
            tr('الجلسةُ مقفلة — لا استيرادَ ولا مطابقةَ ولا نزعَ بعد الإقفال'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.picposMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _matchControlsBar(
    int sessionId,
    double difference,
    bool canMatch,
    bool locked,
  ) {
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: canMatch ? _manualMatch : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
          icon: const Icon(PhosphorIconsBold.linkSimple, size: 15),
          label:  Text(tr('طابق')),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _actionBusy || locked
              ? null
              : () => _confirmComplete(sessionId, difference),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
          icon: const Icon(PhosphorIconsBold.lockSimple, size: 15),
          label:  Text(tr('إقفال الجلسة')),
        ),
      ],
    );
  }

  /// مطابقةٌ يدويّة: السطرُ المختارُ من الكشف ↔ القيدُ المختارُ من الدفتر.
  ///
  /// ⚠️ **الرمْيُ يُعرَض كما هو لا يُبتلَع في «تعذّرت العمليّة»**: المحرّكُ
  /// يرمي `StateError` تسمّي سطرَ الكشف الآخرَ حين يكون القيدُ مطابَقاً
  /// سلفاً — وهذا بالضبط ما يحتاجه المحاسبُ ليقرّر. ورسالةٌ عامّةٌ هنا
  /// تُخفيه.
  Future<void> _manualMatch() async {
    final stmtId = _pickedStmtId;
    final jeId = _pickedJeLineId;
    if (stmtId == null || jeId == null) return;

    setState(() => _actionBusy = true);
    try {
      final repo = ref.read(accountingRepositoryProvider);
      await repo.manualMatchStatement(
        statementLineId: stmtId,
        journalLineId: jeId,
      );
      if (!mounted) return;
      setState(() {
        _pickedStmtId = null;
        _pickedJeLineId = null;
      });
      final sessionId = _sessionId;
      if (sessionId != null) {
        ref.invalidate(_reconciliationReportProvider(sessionId));
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, e is StateError ? e.message : '$e',
          type: ToastType.error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _unmatch(int statementLineId) async {
    setState(() => _actionBusy = true);
    try {
      final repo = ref.read(accountingRepositoryProvider);
      await repo.unmatchStatement(statementLineId);
      if (!mounted) return;
      final sessionId = _sessionId;
      if (sessionId != null) {
        ref.invalidate(_reconciliationReportProvider(sessionId));
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, tr('تعذّر نزعُ المطابقة: {e}', {'e': e}), type: ToastType.error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  /// إقفالُ الجلسة يعمل **ولو بقي فرق** (قرارُ مالك: شيكاتٌ برسم التحصيل
  /// فرقٌ مشروع) — فلا يُمنَع الزرُّ على فرقٍ غيرِ صفريّ، لكنّ حوارَ
  /// التأكيد يعرض الفرقَ صراحةً كي يقرّر المحاسبُ بعين مفتوحة.
  ///
  /// ⚠️ **`showPicPosConfirm` لا `AlertDialog`** (مراجعةٌ 2026-09-01، مأخذ
  /// ٣): `test/structural/accounting_picpos_uses_picpos_dialog_test.dart`
  /// كان يسمّي هذا السطرَ بالضبط — حوارٌ عارٍ فوق شاشةٍ منقولةٍ إلى هويّة
  /// PicPos يكسرها في أظهرِ لحظة.
  ///
  /// ⚠️ **ولا يُضعَّف الفحصُ في النقل**: `showPicPosConfirm` تُرجع `bool`
  /// **غيرَ لاغٍ** افتراضُه الرفض — فالإغلاقُ بالمفتاح أو بالنقر خارجَ
  /// الحوار يُقرأ رفضاً كما كان `proceed != true` يقرؤه. ونصُّ الحوار يبقى
  /// حاملاً **الفرقَ صريحاً** (قرارُ مالك): إقفالٌ بلا رقمٍ قرارٌ بالظنّ.
  Future<int?> _pickAdjustmentAccount() async {
    final accounts = await ref.read(accountingRepositoryProvider).getAllAccounts();
    if (!mounted || accounts.isEmpty) return null;
    return showPicPosOptionPicker<int?>(
      context: context,
      title: tr('اختيار حساب تسوية الفرق'),
      subtitle: tr('سيُرحّل الفرق الظاهر إلى الحساب المختار.'),
      options: [
        for (final account in accounts)
          PicPosOption<int?>(
            value: account.id,
            label: account.name,
            sub: account.code,
          ),
      ],
      selected: null,
      icon: PhosphorIconsBold.scales,
    );
  }

  Future<void> _confirmComplete(int sessionId, double difference) async {
    final proceed = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.lockSimple,
      title: tr('إقفال جلسة المطابقة'),
      message: tr('الفرقُ الحاليّ: {p0}. إقفالُ الجلسة يجب تصفير الفرق أو اختيار حساب تسوية صريح قبل الإقفال.', {'p0': _money.format(difference)}),
      confirmLabel: tr('إقفال'),
    );
    if (!proceed || !mounted) return;

    int? adjustmentAccountId;
    if (difference.abs() > FinancialUtils.balanceTolerance) {
      adjustmentAccountId = await _pickAdjustmentAccount();
      if (adjustmentAccountId == null || !mounted) return;
    }

    setState(() => _actionBusy = true);
    try {
      final repo = ref.read(accountingRepositoryProvider);
      await repo.completeReconciliation(
        sessionId,
        adjustmentAccountId: adjustmentAccountId,
      );
      if (!mounted) return;
      AppToast.show(context, tr('أُقفلت جلسةُ المطابقة'), type: ToastType.success);
      ref.invalidate(_reconciliationReportProvider(sessionId));
      // ولم تعد مفتوحةً — فزرُّ «متابعة الجلسة المفتوحة» يجب أن يعود
      // «جلسة جديدة»، وإلّا عرض متابعةً لجلسةٍ مقفلةٍ أزرارُها معطَّلة.
      final accountId = _accountId;
      if (accountId != null) {
        ref.invalidate(_openSessionProvider((
          accountId: accountId,
          start: _period.start,
          end: _period.end,
        )));
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, tr('تعذّر إقفالُ الجلسة: {e}', {'e': e}), type: ToastType.error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  // ── القوائمُ الثلاث ─────────────────────────────────────────────────────

  /// سطرُ كشفٍ غيرُ مطابَق. `l.id`/`l.transactionDate`/`l.reference`/
  /// `l.description`/`l.debitAmount`/`l.creditAmount` نداءٌ ديناميكيٌّ على
  /// `BankStatementLine` (راجع تعليقَ العقد أعلى `_buildReport`).
  Widget _unmatchedBankTable(List<dynamic> lines) {
    return PicPosDataTable(
      title: tr('أسطرُ الكشف غيرُ المطابَقة'),
      subtitle: tr('اختر سطراً هنا وقيداً من الدفتر ثمّ اضغط «طابق»'),
      // ⚠️ **ليس الافتراضَ ٧٦٠**: قائمتان متجاورتان عند ١٢٨٠ تنالان نحوَ
      // ٦٢٠ لكلٍّ — والافتراضُ كان سيفتح تمريراً أفقيّاً داخل كلّ جدول
      // بلا داعٍ. ٥٦٠ تحت ذلك الحدّ فلا تمريرَ عند ١٢٨٠.
      minWidth: 560,
      columns:  [
        PicPosTableColumn(tr('التاريخ'), flex: 1.0),
        PicPosTableColumn(tr('المرجع'), flex: 1.0),
        PicPosTableColumn(tr('البيان'), flex: 1.6),
        PicPosTableColumn(tr('مدين'), flex: 1.0, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('دائن'), flex: 1.0, align: PicPosCellAlign.end),
      ],
      emptyLabel: tr('لا أسطرَ غيرَ مطابَقةٍ في الكشف'),
      rows: [for (final dynamic l in lines) _unmatchedBankRow(l)],
    );
  }

  PicPosTableRow _unmatchedBankRow(dynamic l) {
    final id = l.id as int;
    final selected = id == _pickedStmtId;
    final tint = selected ? AppColors.primary : null;
    return PicPosTableRow(
      onTap: () => setState(() => _pickedStmtId = selected ? null : id),
      cells: [
        PicPosTextCell(_dateFmt.format(l.transactionDate as DateTime),
            tint: tint, bold: selected ? true : null),
        PicPosTextCell((l.reference as String?) ?? '—',
            tint: tint, bold: selected ? true : null),
        PicPosTextCell((l.description as String?) ?? '—', tint: tint),
        PicPosTextCell(_money.format((l.debitAmount as num).toDouble()),
            tint: tint),
        PicPosTextCell(_money.format((l.creditAmount as num).toDouble()),
            tint: tint),
      ],
    );
  }

  /// قيدُ دفترٍ لم يظهر في الكشف بعد. عنصرُ `rows` هنا `QueryRow` من
  /// `customSelect` — يُقرأ بـ`.data['...']` بأسماء أعمدة SQL الخامّة، لا
  /// بحقولٍ مسمّاة (راجع تعليقَ العقد أعلى `_buildReport`).
  Widget _outstandingBookTable(List<dynamic> rows) {
    return PicPosDataTable(
      title: tr('قيودٌ في الدفتر لم تظهر في الكشف'),
      subtitle: tr('اختر قيداً هنا وسطراً من الكشف ثمّ اضغط «طابق»'),
      minWidth: 480,
      columns:  [
        PicPosTableColumn(tr('التاريخ'), flex: 1.0),
        PicPosTableColumn(tr('البيان'), flex: 2.0),
        PicPosTableColumn(tr('مدين'), flex: 1.0, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('دائن'), flex: 1.0, align: PicPosCellAlign.end),
      ],
      emptyLabel: tr('لا قيودَ معلَّقةً في الدفتر'),
      rows: [for (final dynamic r in rows) _outstandingBookRow(r)],
    );
  }

  PicPosTableRow _outstandingBookRow(dynamic r) {
    final id = (r.data['id'] as num).toInt();
    final selected = id == _pickedJeLineId;
    final tint = selected ? AppColors.primary : null;
    return PicPosTableRow(
      onTap: () => setState(() => _pickedJeLineId = selected ? null : id),
      cells: [
        PicPosTextCell(_fmtEntryDate(r.data['entry_date']),
            tint: tint, bold: selected ? true : null),
        PicPosTextCell((r.data['entry_desc'] as String?) ?? '—', tint: tint),
        PicPosTextCell(
            _money.format(((r.data['debit'] as num?) ?? 0).toDouble()),
            tint: tint),
        PicPosTextCell(
            _money.format(((r.data['credit'] as num?) ?? 0).toDouble()),
            tint: tint),
      ],
    );
  }

  /// أسطرُ الكشف المطابَقةُ سلفاً — كلٌّ منها قابلٌ للنزع ما لم تُقفَل
  /// الجلسة.
  Widget _matchedTable(List<dynamic> lines, bool locked) {
    return PicPosDataTable(
      title: tr('الأسطرُ المطابَقة'),
      columns:  [
        PicPosTableColumn(tr('التاريخ'), flex: 1.0),
        PicPosTableColumn(tr('المرجع'), flex: 1.0),
        PicPosTableColumn(tr('البيان'), flex: 1.6),
        PicPosTableColumn(tr('مدين'), flex: 1.0, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('دائن'), flex: 1.0, align: PicPosCellAlign.end),
        PicPosTableColumn(tr('إجراء'), flex: 1.0),
      ],
      emptyLabel: tr('لا أسطرَ مطابَقةً بعد'),
      rows: [for (final dynamic l in lines) _matchedRow(l, locked)],
    );
  }

  PicPosTableRow _matchedRow(dynamic l, bool locked) {
    final id = l.id as int;
    return PicPosTableRow(
      cells: [
        PicPosTextCell(_dateFmt.format(l.transactionDate as DateTime)),
        PicPosTextCell((l.reference as String?) ?? '—'),
        PicPosTextCell((l.description as String?) ?? '—'),
        PicPosTextCell(_money.format((l.debitAmount as num).toDouble())),
        PicPosTextCell(_money.format((l.creditAmount as num).toDouble())),
        PicPosButtonCell(
          tr('نزع'),
          icon: PhosphorIconsBold.linkBreak,
          tint: AppColors.error,
          onPressed: _actionBusy || locked ? null : () => _unmatch(id),
        ),
      ],
    );
  }

  /// `outstandingBookEntries.data['entry_date']` قد يعود `DateTime` أو
  /// `int` أو `String` حسب المحرّك (تعليقُ العقد أعلى `_buildReport`).
  ///
  /// ⚠️ **مراجعة — النوعُ الفعليّ `int` (ثوانٍ منذ الإبوك) لا `String`**:
  /// `lib/data/database/database.dart` توثِّق أنّ drift تخزّن أعمدةَ
  /// `DateTime` كـ`epoch seconds (BIGINT)` على SQLite وPostgreSQL معاً
  /// (‏`dateVar` تكتب `Variable<int>(dt.millisecondsSinceEpoch ~/ 1000)`)،
  /// و`entry_date` يصل من `customSelect` **خامّاً** بلا تحويل drift. وكانت
  /// النسخةُ الأولى هنا تسقط إلى `'$raw'` فتعرض `1778371200` بدل
  /// `2026-05-10` — عمودُ التاريخ عينُه الذي يقرّر به المحاسبُ أيَّ سطرٍ
  /// يطابق أيَّ سطر. والإصلاحُ نسخُ النمط العامل على نفس الاستعلام
  /// (‏`journal_entry_lines`/`journal_entries`) من
  /// `lib/data/database/daos/accounting_dao_reads.dart:658-661` بدل
  /// اختراع تحويلٍ جديد.
  String _fmtEntryDate(dynamic raw) {
    if (raw == null) return '—';
    if (raw is DateTime) return _dateFmt.format(raw);
    if (raw is int) {
      return _dateFmt.format(DateTime.fromMillisecondsSinceEpoch(raw * 1000));
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      return parsed == null ? raw : _dateFmt.format(parsed);
    }
    return '$raw';
  }
}
