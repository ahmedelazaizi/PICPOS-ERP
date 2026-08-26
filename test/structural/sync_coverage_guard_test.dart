// حارسُ تغطية المزامنة — أيُّ جدولٍ لا يصل الخادمَ ولا المرآة؟
//
// ═══ فئةُ العطب ═══
//
// جردٌ 2026-08-26: **٩١ جدولاً من ١٥٩** (٥٧٪) لا تذكره أيُّ استراتيجيّةِ
// مزامنةٍ ولا مسارُ الخادم. ولم يكن ذلك قراراً موثَّقاً — لا سجلَّ «محلّيٌّ
// عمداً» ولا حارسَ تغطية. أي أنّ الفجوةَ نمت صامتةً مع كلّ جدولٍ جديد.
//
// وأخطرُ ما فيها ليس العدد بل **التفاوت**: تطبيقُ ورقةِ تحميلٍ وترحيلُ إهلاكٍ
// وتسجيلُ مصروفٍ تشغيليٍّ **تقيّد قيوداً تُزامَن** (‏`journal` استراتيجيّةٌ
// قائمة) بينما المستندُ المولِّدُ يبقى محلّيّاً. فالخادمُ يرى أثراً ماليّاً بلا
// مصدرٍ يفسّره — لا يُراجَع ولا يُعكَس من جهازٍ آخر. وجهازٌ ثانٍ لا يعرف أنّ
// الورقةَ طُبِّقت فيطبّقها ثانية.
//
// ═══ تصحيحان 2026-08-27 ═══
//
// **١) الرقمُ كان ٩١ وهو ٩٤.** الكشفُ كان يقرأ نصَّ ملفّات المزامنة كلَّه
// بما فيه التعليقات، فثلاثةُ جداولٍ بدت مغطّاةً بذكرِ اسمها في تعليقٍ:
// `BillOfMaterials` و`SyncOutbox` و`WarehousePrices`. [_stripComments]
// يسدّ ذلك، وفحصٌ في «حراسةِ الحارس» يثبته على البلاغ نفسِه.
//
// **٢) واثنا عشرَ جدولاً خرجت من القائمة.** المرحلة ٢ (v166) أعطت
// مستنداتِ الأثر المحاسبيّ أعمدةَ المزامنة الخمسةَ ووصلتها بمساري
// السحب. فالباقي **٨٢ من ١٥٩** — ٩٤ ناقص ١٢.
//
// ═══ ما يفعله هذا الملفّ ═══
//
// يجمّد الـ٩١ خطَّ أساسٍ صريحاً. جدولٌ **جديدٌ** بلا مزامنةٍ يُسقط الحارسَ
// فيلزم قرارٌ: إمّا استراتيجيّةٌ وإمّا سطرٌ هنا بسببه. والقائمةُ **تتقلّص ولا
// تكبر** — الاختبارُ الثاني يفشل لجدولٍ صار مُزامَناً وبقي مكتوباً.
//
// ⚠️ وهذا حارسُ **تغطيةٍ** لا حارسُ صحّة: وجودُ اسمِ الجدول في طبقة المزامنة
// لا يثبت أنّ الحقولَ تُنقَل صحيحةً ولا أنّ تعارضَها يُحَلّ. تلك مصالحةٌ
// تُقاس باختبارات تكامل، لا بجردِ أسماء.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الجداولُ التي **لا تُزامَن اليوم** — خطُّ أساسٍ مجمَّدٌ 2026-08-26.
///
/// مرتّبةٌ بالمجال لا بالحروف، ومع كلّ مجموعةٍ حكمُها. والحكمُ ثلاثةٌ:
///   🔴 **يجب أن تُزامَن** — أثرٌ ماليٌّ أو تشغيليٌّ عابرٌ للأجهزة.
///   🟡 **قرارُ مالكٍ مؤجَّل** — ميزةٌ لم تُطرح بعد أو مؤجَّلةٌ بقرار.
///   ⚪ **محلّيٌّ بطبعه** — لا معنى لمزامنته.
const _unsyncedBaseline = <String>{
  // ═══ ✅ أثرٌ محاسبيٌّ مباشر — سُدَّت 2026-08-27 (المرحلة ٢ / v166) ═══
  //
  // كانت أحدَ عشرَ جدولاً هنا: أوراقُ التحميل والأصولُ والإهلاكُ
  // والمصروفاتُ التشغيليّةُ وأوامرُ التصنيع. صارت كلُّها تحمل أعمدةَ
  // المزامنة الخمسةَ وتُدرَج في مساري السحب، فلا سطرَ لها هنا.
  //
  // ومعها `BillOfMaterials` — ولم يكن لها سطرٌ أصلاً لأنّ الحارسَ كان
  // يقرأ التعليقاتِ فيعدّها مُزامَنةً وهي ليست كذلك. انظر [_stripComments].

  // ═══ 🔴 تشغيلٌ عابرٌ للأجهزة — مطعمٌ بجهازين لا يرى أحدُهما الآخر ═══
  'TableOrders', 'TableOrderItems', 'TableOrderPayments',
  'TableReservations', 'RestaurantTables', 'TableSections',
  'WorkOrders', 'WorkOrderItems', 'KitchenStations',
  'CategoryStationMappings',
  'Bookings', 'BookingResources', 'BookingServices', 'BookingReminders',
  'SalesRoutes', 'RouteVisits', 'SalesRepCollections', 'SalesRepTargets',
  'CycleCountPlans', 'CycleCountTasks', 'CycleCountItems',
  'StockAudits', 'StockAuditItems',
  'StockRequisitions', 'StockRequisitionItems',
  'CustomerLoyaltyPoints', 'LoyaltyPrograms', 'LoyaltyTransactions',
  'DeliveryCompanies', 'Couriers',
  'BankReconciliations', 'BankStatementLines',

  // ═══ 🔴 سجلٌّ قانونيٌّ ورقابيّ — ضياعُ الجهاز ضياعُ الإثبات ═══
  'EInvoiceSubmissions', 'EInvoiceStatusLog',
  'FieldAuditLogs', 'FailedAutoposts',
  'ApprovalWorkflows', 'ApprovalRequests', 'ApprovalSteps',
  'ApprovalDecisions', 'SodConflicts', 'SodViolations',
  'ComplianceChecks',

  // ⚠️ **`EInvoiceConfigs` استثناءٌ أمنيٌّ صريح**: يحمل `clientSecret` نصّاً.
  //    لا يُزامَن كما هو مهما تقرّر في الباقي — وأيُّ مزامنةٍ له تحتاج
  //    تشفيراً أو استبعادَ العمود.
  'EInvoiceConfigs',

  // ═══ 🟡 قرارُ مالكٍ مؤجَّل ═══
  // شؤونُ الموظّفين مؤجَّلةٌ في `lite` بقرار مالك 2026-08-10 والكودُ مسيَّجٌ
  // بـ`features.hrEnabled` — فبقاؤها محلّيّةً متّسقٌ مع ذلك، ويُراجَع يومَ
  // تُفتَح الميزة.
  'Employees', 'EmployeeAttendance', 'EmployeeContracts', 'EmployeeLeaves',
  'EmployeeTransactions', 'LeaveBalances', 'OvertimeRecords',
  'SalaryPayments', 'WorkHolidays', 'FingerprintDevices',
  'PerformanceGoals', 'PerformanceReviews',

  // مؤسّسيّاتٌ لم تُطرح بعد.
  'Budgets', 'BudgetLines', 'DeferredSchedules', 'DeferredEntries',
  'Restatements', 'RestatementLines', 'IntercompanyTransactions',
  'EntityMappings', 'ActivityProfiles', 'ExchangeRateHistory',

  // قوالبُ ووثائقُ إعداد — تُنقل يدويّاً اليوم.
  'InvoiceTemplates', 'InvoiceTemplateElements', 'InvoiceTableSettings',
  'JournalEntryTemplates', 'JournalEntryTemplateLines',
  'TaxTypes', 'TaxSubtypes',
  'CustomReports',

  // ═══ ⚪ محلّيٌّ بطبعه ═══
  // `SavedReportRuns` سجلُّ تشغيلٍ على هذا الجهاز · `ProcessedMessages` جدولُ
  // إزالةِ تكرارٍ للمزامنة نفسِها (‏مزامنتُه تُنتج دوراً) · `LabelScales`
  // و`ReceiptSettings` عتادٌ وإعدادُ طابعةٍ لكلّ جهاز · `ApiKeys` أسرارٌ محلّيّة
  // · `Notifications` إشعاراتُ جهازٍ لا رسائلُ نظام.
  'SavedReportRuns', 'ProcessedMessages', 'LabelScales', 'ReceiptSettings',
  'ApiKeys', 'Notifications',

  // `SyncOutbox` طابورُ الدفعِ نفسُه — مزامنتُه تُنتج دوراً كـ
  // `ProcessedMessages` بالضبط.
  'SyncOutbox',

  // ═══ 🔴 كشفهما نزعُ التعليقات 2026-08-27 ═══
  //
  // `WarehousePrices` سعرُ بيعٍ وتكلفةٍ لكلّ صنفٍ في كلّ مخزن. جهازٌ يبيع
  // بسعرٍ عدّله جهازٌ آخرُ ولا يراه ⇒ فرقُ إيرادٍ لا يُفسَّر. تستحقّ
  // استراتيجيّةً، وهي خارجُ نطاق المرحلة ٢ المعلَن (‏مستنداتُ الأثر
  // المحاسبيّ) فتُسجَّل هنا بحكمها بدل أن تمرّ صامتة.
  'WarehousePrices',
};

/// جداولُ نعلم يقيناً أنّها تُزامَن — **مرساةُ الحارس**.
///
/// ⚠️ بلا هذه المرساةِ يكون الحارسُ بلا معنى: لو انكسر الكشفُ (‏تغيّر مسارُ
/// `lib/services/sync/` مثلاً) لعُدَّ **كلُّ** جدولٍ غيرَ مُزامَنٍ، ولمرّ
/// الاختبارُ الأوّلُ أخضرَ ما دامت القائمةُ تشمله. فالمرساةُ تُسقطه بدل ذلك.
const _knownSynced = <String>{
  'SalesInvoices', 'Products', 'Parties', 'SafeTransactions',
  'JournalEntries', 'Users', 'Warehouses', 'Branches',
};

// ── الكشف ─────────────────────────────────────────────────────────────────

String _snake(String s) =>
    s.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
        .toLowerCase();

List<String> _allTables() {
  final out = <String>[];
  final dir = Directory('lib/data/database/tables');
  for (final f in dir.listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final src = f.readAsStringSync();
    for (final m in RegExp(r'class\s+(\w+)\s+extends\s+Table\b').allMatches(src)) {
      out.add(m.group(1)!);
    }
  }
  return out..sort();
}

/// ينزع التعليقاتِ قبلَ قياس التغطية.
///
/// ⚠️ **بلا هذا يكذب الحارسُ في الاتّجاه الخطر**: اسمُ جدولٍ يرد في تعليقٍ
/// يُعَدّ تغطيةً. وقع فعلاً — `bill_of_materials` كانت «مغطّاةً» بسطرَي
/// تعليقٍ في `sale_bom_consumption_sync_strategy.dart` يقولان صراحةً إنّ
/// مزامنتَها **لم تصل بعد**. فالحارسُ قرأ وعداً بالمزامنة وحسبه مزامنة،
/// ولم يكن لها سطرٌ في خطّ الأساس فمرّت بلا قرار.
///
/// و`://` مستثناةٌ: قطعُ السطرِ عند مسارٍ في نصٍّ حرفيٍّ يحذف كوداً بعده
/// فيُنتج «غيرَ مغطّى» كاذباً في الاتّجاه المعاكس.
String _stripComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ');
  return noBlock.split('\n').map((line) {
    var i = line.indexOf('//');
    while (i > 0 && line[i - 1] == ':') {
      i = line.indexOf('//', i + 2);
    }
    return i < 0 ? line : line.substring(0, i);
  }).join('\n');
}

String _syncSurface() {
  final buf = StringBuffer();
  for (final f in Directory('lib/services/sync').listSync(recursive: true)) {
    if (f is File && f.path.endsWith('.dart')) {
      buf.write(_stripComments(f.readAsStringSync()));
    }
  }
  for (final p in const [
    'lib/services/api/api_data_handler.dart',
    'lib/services/delta_pull_service.dart',
  ]) {
    final f = File(p);
    if (f.existsSync()) buf.write(_stripComments(f.readAsStringSync()));
  }
  return buf.toString();
}

void main() {
  final tables = _allTables();
  final surface = _syncSurface();

  bool isCovered(String t) =>
      surface.contains(t) || surface.contains(_snake(t));

  group('حراسةُ الحارس', () {
    test('الجداولُ تُقرأ فعلاً — وإلّا فالحارسُ يقيس فراغاً', () {
      expect(tables.length, greaterThan(100),
          reason: 'قُرئ ${tables.length} جدولاً فقط — مسارُ التعريفات تغيّر '
              'غالباً، والحارسُ صار يقيس لا شيء.');
    });

    test('ذكرٌ في تعليقٍ ليس تغطيةً — على البلاغ نفسِه', () {
      const commentOnly = '/// FK dependencies: sales_invoices, '
          'bill_of_materials, products.\n'
          'const x = 1;';
      expect(
        _stripComments(commentOnly).contains('bill_of_materials'),
        isFalse,
        reason: 'اسمٌ في تعليقٍ ما زال يُحسَب تغطيةً ⇒ الحارسُ يكذب في '
            'الاتّجاه الخطر: يمرّ جدولٌ غيرُ مُزامَنٍ بلا قرار.',
      );
      expect(
        _stripComments(commentOnly).contains('const x = 1;'),
        isTrue,
        reason: 'النزعُ ابتلع كوداً ⇒ سيُبلَّغ عن فجواتٍ وهميّة.',
      );
      expect(
        _stripComments("const u = 'https://x/y'; // hi").contains('https'),
        isTrue,
        reason: 'قُطع السطرُ عند `://` داخلَ نصٍّ حرفيّ ⇒ كودٌ ضائع.',
      );
    });

    test('وسطحُ المزامنة مقروءٌ — مرساةٌ موجبة', () {
      for (final t in _knownSynced) {
        expect(isCovered(t), isTrue,
            reason: 'الجدولُ «$t» يُزامَن يقيناً ولم يُكتشَف ⇒ الكشفُ '
                'مكسور، وكلُّ حكمٍ بعده باطل.');
      }
    });
  });

  test('لا جدولَ جديدٌ خارجَ المزامنة بلا قرارٍ مكتوب', () {
    final uncovered = tables.where((t) => !isCovered(t)).toSet();
    final unregistered = uncovered.difference(_unsyncedBaseline).toList()
      ..sort();

    expect(
      unregistered,
      isEmpty,
      reason: 'هذه الجداولُ لا تصل الخادمَ ولا المرآة ولا سطرَ لها في خطّ '
          'الأساس. فإمّا تُكتَب لها استراتيجيّةُ مزامنة، وإمّا يُضاف سطرُها '
          'في `_unsyncedBaseline` **بسببه** وتحت حكمِه (🔴 أو 🟡 أو ⚪).\n'
          'وجدولٌ يكتب فيه المستخدمُ ويقيّد قيداً يُزامَن ⇒ 🔴 دائماً: '
          'القيدُ يصل الخادمَ ومستندُه لا، فلا يُراجَع الأثرُ الماليّ.',
    );
  });

  test('وخطُّ الأساس يتقلّص: لا جدولَ صار مُزامَناً وبقي مكتوباً', () {
    final stale = _unsyncedBaseline.where(isCovered).toList()..sort();

    expect(
      stale,
      isEmpty,
      reason: 'هذه الجداولُ صارت تصل طبقةَ المزامنة ⇒ اشطبْ أسطرَها من '
          '`_unsyncedBaseline`. وبقاؤها يجعل القائمةَ تكذب، ويُخفي أنّ '
          'الفجوةَ تُسَدّ فعلاً.',
    );
  });

  test('وكلُّ اسمٍ في خطّ الأساس جدولٌ قائمٌ — لا سطرَ بائت', () {
    final ghosts = _unsyncedBaseline.difference(tables.toSet()).toList()
      ..sort();

    expect(ghosts, isEmpty,
        reason: 'أسماءٌ في خطّ الأساس لا تقابلها جداولُ اليوم — حُذفت أو '
            'أُعيدت تسميتُها. والسطرُ البائتُ يُنقص المدى صامتاً.');
  });
}
