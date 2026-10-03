// حارسُ العقد: عضويّةُ القوائم لا تُغني عن الأعمدة — ولا العكس.
//
// ═══ فئةُ العطب ═══
//
// إدراجُ جدولٍ في `pullTables` **لا يمنحه** أعمدةَ المزامنة. والطرفان
// يفشلان صامتَين حين يفترقان:
//
//  ‏١) 🔴 **عضويّةٌ بلا أعمدة.** `_upsertRow` يبني
//     `INSERT OR REPLACE INTO t (global_id, …)` من مفاتيحِ ردِّ الخادم، ثمّ
//     **يبتلع** خطأَ العمود المفقود بـ`debugPrint` ويمضي
//     (`delta_pull_service.dart` — كتلةُ `catch` حول الإدراج). فالسحبُ
//     يبدو عاملاً، ولا صفَّ يصل، ولا اختبارَ يحمرّ.
//
//     وقع فعلاً في هذه المرحلةِ نفسِها: `employees` أُدرجت في **ستِّ**
//     قوائمَ وهي بلا `global_id` — والفحوصُ كلُّها خضراء. لم يكشفها إلّا
//     مسحٌ صريحٌ لتعريفات الجداول، وهو ما يفعله هذا الملفّ.
//
//  ‏٢) 🔴 **وأعمدةٌ بلا أرضيّةِ ترقيم.** جدولٌ في `pullTables` وغائبٌ عن
//     `IdNamespaceService.namespacedTables` يبدأ ترقيمَه المحلّيَّ من ١،
//     فيصطدم صفُّ العميل بصفِّ الخادم على نفس الرقم. الحارسُ العامُّ في
//     `_upsertRow` يعالجه بإعادةِ ترقيمٍ **بعد** وقوع التصادم، والأرضيّةُ
//     تمنعه أصلاً. والعقدُ المكتوبُ في وثيقةِ القائمة صريح: «اتّحادُ
//     `pullTables` مع حفنةِ جداولَ محلّيّة» — فالانحرافُ عنه خللٌ لا خيار.
//
//     وهذا أيضاً وقع: ثلاثةَ عشرَ جدولاً (‏اثنا عشرَ من المرحلة ٢ ومعها
//     `activity_logs`) دخلت `pullTables` ولم تدخل الأرضيّة.
//
// ═══ ما لا يفعله ═══
//
// حارسُ **بنيةٍ** لا حارسُ صحّة: وجودُ العمود لا يثبت أنّ قيمتَه تُسَكّ ولا
// أنّ التعارضَ يُحَلّ. تلك مصالحةٌ تُقاس باختبارات تكامل.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/delta_pull_service.dart';
import 'package:ural_erp/services/id_namespace_service.dart';

/// الأعمدةُ الخمسةُ التي يقوم عليها مسارُ الدلتا.
const _syncColumns = <String>[
  'globalId',
  'lastModifiedAt',
  'deletedAt',
  'originClientId',
  'rowVersion',
];

/// استثناءاتٌ **بحكمٍ مكتوب** — لا قائمةُ إسكاتٍ تكبر بالصمت.
///
/// (‏وسطرُ `activity_logs` أُسقط 2026-08-31: خرج الجدولُ من المزامنة
/// بقرارِ مالك، واستثناءُ أعمدةٍ لجدولٍ لا يُزامَن اسمٌ بائتٌ يوهم بعقدٍ قائم.)
/// فـ`deleted_at` بلا معنًى فيه (‏حذفُ سطرِ تدقيقٍ هو العطبُ لا الميزة)،
/// و`row_version` رقمٌ لا يرتفع أبداً. وله `global_id` و`last_modified_at`
/// وهما ما يحتاجه سحبُ الدلتا فعلاً.
const _columnExceptions = <String, Set<String>>{
};

/// جداولُ **SQL خامٍّ** — تعريفُها DDL لا صنفُ drift، ودليلُها اختبارٌ على
/// قاعدةٍ حيّة.
///
/// ═══ لماذا استثناءٌ أصلاً ═══
///
/// غرضُ هذا الحارس: **أثبِت أنّ الأعمدةَ موجودةٌ في التعريف**، لأنّ عموداً
/// مفقوداً يُبتلَع في `catch` فيبدو السحبُ عاملاً ولا يصل صفّ. ودليلُه في
/// الحالة العامّة **جسمُ صنف drift**.
///
/// وجداولُ الإضافات والخيارات (‏أُنشئت بـSQL خامٍّ في هجرة v70) لا صنفَ لها،
/// فلا يجد المسحُ لها جسماً ويقول «لا صنفَ يقابله» — وهو صحيحٌ حرفيّاً
/// ومضلِّلٌ معنًى: الأعمدةُ موجودةٌ فعلاً، يضعها
/// `AppDatabase._ensureModifierSyncColumns`.
///
/// ⚠️ **والدليلُ هنا أقوى من مطابقة النصّ**: الملفُّ المذكورُ يفتح قاعدةً
///    حقيقيّةً ويقرأ الأعمدةَ بعد `ensureModifierTables()`. فمطابقةُ نصٍّ
///    على DDL تُثبت أنّ السطرَ مكتوب؛ وهذا يُثبت أنّ العمودَ **وُجد**.
///
/// ⚠️ **وليست قائمةَ إسكات**: الحارسُ أدناه يشترط وجودَ ملفِّ الدليل وأن
///    يذكر الجدولَ باسمه. فحذفُ الاختبار يُسقط البناءَ بدل أن يُسكته.
///
/// 🟡 **وهذا توسيعٌ لعقد الحارس** (2026-09-21): كان يقبل أصنافَ drift
///    وحدَها. والبديلُ تحويلُ الثلاثة إلى أصنافٍ — عقدٌ كاملٌ لكنّه يحتاج
///    `build_runner` و**يُعيد تعريفاً ثانياً** بجوار `ensureModifierTables`،
///    وهو عينُ ما عطّل الميزةَ بالكامل على PostgreSQL مرّةً (‏٦‑٢، مكتوبٌ
///    في `database.dart`). فإن رُئي التحويلُ أولى، يُحذَف هذا السطرُ ويُعاد
///    البناءُ — والحارسُ يُعيد البلاغَ من نفسه.
const _rawSqlProvenAtRuntime = <String, String>{
  'modifier_groups': 'test/unit/modifiers_sync_contract_test.dart',
  'modifier_items': 'test/unit/modifiers_sync_contract_test.dart',
  'product_modifier_groups': 'test/unit/modifiers_sync_contract_test.dart',
  'butchery_templates': 'test/unit/manufacturing_phase17_test.dart',
  'butchery_template_lines': 'test/unit/manufacturing_phase17_test.dart',
  'butchery_orders': 'test/unit/manufacturing_phase17_test.dart',
  'butchery_order_lines': 'test/unit/manufacturing_phase17_test.dart',
  // v184 — دفاترُ السندات (المرحلة هـ / E3).
  'voucher_books':
      'test/unit/voucher_books_and_coa_vouchers_phase_e_test.dart',
  'voucher_book_leaves_cancelled':
      'test/unit/voucher_books_and_coa_vouchers_phase_e_test.dart',
  // v185 — نموذجُ التوزيع (المرحلة و).
  'distribution_areas': 'test/unit/distribution_model_phase_f_test.dart',
  'route_customers': 'test/unit/distribution_model_phase_f_test.dart',
  'route_rep_history': 'test/unit/distribution_model_phase_f_test.dart',
  'rep_resources': 'test/unit/distribution_model_phase_f_test.dart',
  // v189 — مسوّداتُ المرتجعات (J2).
  'return_drafts': 'test/integration/return_drafts_lifecycle_j2_test.dart',
  // v191 — ملفُّ الموظف (J4).
  'hr_departments': 'test/integration/hr_employee_file_j4_test.dart',
  'hr_job_titles': 'test/integration/hr_employee_file_j4_test.dart',
  'employee_allowances': 'test/integration/hr_employee_file_j4_test.dart',
  'employee_documents': 'test/integration/hr_employee_file_j4_test.dart',
  'employee_history': 'test/integration/hr_employee_file_j4_test.dart',
  // v192 — الورديّاتُ والحضورُ والإجازات (J4 الجزء ٢).
  'hr_shifts': 'test/integration/hr_attendance_leave_j4_test.dart',
  'hr_shift_assignments': 'test/integration/hr_attendance_leave_j4_test.dart',
  'hr_public_holidays': 'test/integration/hr_attendance_leave_j4_test.dart',
  'hr_leave_types': 'test/integration/hr_attendance_leave_j4_test.dart',
  'hr_leave_requests': 'test/integration/hr_attendance_leave_j4_test.dart',
  'hr_leave_entitlements': 'test/integration/hr_attendance_leave_j4_test.dart',
  'hr_attendance_days': 'test/integration/hr_attendance_leave_j4_test.dart',
  // v193 — الرواتبُ والسلفُ والعمولات (J4 الجزء ٣).
  'hr_payroll_settings': 'test/integration/hr_payroll_j4_test.dart',
  'hr_salary_components': 'test/integration/hr_payroll_j4_test.dart',
  'hr_commission_plans': 'test/integration/hr_payroll_j4_test.dart',
  'hr_employee_advances': 'test/integration/hr_payroll_j4_test.dart',
  'hr_advance_repayments': 'test/integration/hr_payroll_j4_test.dart',
  'hr_payroll_adjustments': 'test/integration/hr_payroll_j4_test.dart',
  'hr_payroll_runs': 'test/integration/hr_payroll_j4_test.dart',
  'hr_payroll_lines': 'test/integration/hr_payroll_j4_test.dart',
  'hr_payroll_items': 'test/integration/hr_payroll_j4_test.dart',
};

/// جداولُ ليست في `pullTables` وتُرقَّم مع ذلك — الطرفُ الآخرُ من العقد.
///
/// وثيقةُ [IdNamespaceService.namespacedTables] تذكر «حفنةً من جداولَ
/// محلّيّةِ الترقيم تصل الخادمَ عبر إعادةِ تشغيل الطابور» — و**مقيسٌ
/// 2026-08-27 أنّها لا أحد**: `shifts` و`held_orders` وأخواتُها كلُّها
/// في `pullTables` فعلاً، فالمجموعتان متطابقتان تماماً (٧٢ = ٧٢).
///
/// وتُترَك فارغةً عمداً لا محذوفةً: إضافةُ جدولٍ محلّيِّ الترقيم مستقبلاً
/// قرارٌ يُكتَب هنا بحكمه، لا انحرافٌ يمرّ صامتاً.
const _namespacedButNotPulled = <String>{
  // قرارُ مالك 2026-08-31 — أُخرجا من المزامنة ويبقى ترقيمُهما محلّيّاً:
  //   • `printers` إعدادٌ **جهازيّ** (`port` = COM3) لا يُدهَس بإعداد الخادم.
  //   • `activity_logs` سجلٌّ إلحاقيٌّ بلا سقفٍ زمنيّ؛ المراجعةُ المركزيّةُ
  //     من جهاز الخادم، وكلُّ جهازٍ يرى ما سُجّل عليه.
  // ويبقى الترقيمُ المحلّيُّ لهما: الصفوفُ تُنشَأ محلّيّاً وتحتاج مدًى لا
  // يصطدم بمدى الخادم لو أُعيدت المزامنةُ يوماً.
  'printers',
  'activity_logs',
};

// ── الكشف ─────────────────────────────────────────────────────────────────

/// اسمُ الجدول في SQL كما يشتقّه drift. ⚠️ الصيغةُ القديمةُ
/// `([a-z0-9])([A-Z])` كانت تُخرج `EInvoiceStatusLog` ⇒ `einvoice_status_log`
/// فيُبلَّغ «لا صنفَ يقابله» عن جدولٍ قائم (مقيس 2026-09-02).
String _snake(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    final isUpper = c.toUpperCase() == c && c.toLowerCase() != c;
    if (isUpper && i > 0) {
      final prevUpper = s[i - 1].toUpperCase() == s[i - 1] &&
          s[i - 1].toLowerCase() != s[i - 1];
      final nextLower = i + 1 < s.length && s[i + 1].toLowerCase() == s[i + 1];
      if (!prevUpper || nextLower) b.write('_');
    }
    b.write(c.toLowerCase());
  }
  return b.toString();
}

/// جسمُ كلِّ صنفِ جدولٍ في المشروع، مفهرساً باسمه في SQL.
///
/// المطابقةُ بعدِّ الأقواس لا بتعبيرٍ نمطيّ: جسمُ الجدول يحوي `{` و`}`
/// داخلَ `customConstraints` و`primaryKey`، وتعبيرٌ كسولٌ يقطع عند أوّلها
/// فيُبلّغ عن أعمدةٍ مفقودةٍ وهي موجودة.
Map<String, ({String cls, String body})> _tableBodies() {
  final out = <String, ({String cls, String body})>{};
  final dir = Directory('lib/data/database/tables');
  for (final f in dir.listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final src = f.readAsStringSync();
    for (final m in RegExp(r'class\s+(\w+)\s+extends\s+Table\s*\{').allMatches(src)) {
      var depth = 1;
      var i = m.end;
      while (i < src.length && depth > 0) {
        if (src[i] == '{') {
          depth++;
        } else if (src[i] == '}') {
          depth--;
        }
        i++;
      }
      final body = src.substring(m.end, i - 1);
      final override =
          RegExp(r"String\s+get\s+tableName\s*=>\s*'([^']+)'").firstMatch(body);
      out[override?.group(1) ?? _snake(m.group(1)!)] =
          (cls: m.group(1)!, body: body);
    }
  }
  return out;
}

bool _hasColumn(String body, String column) =>
    RegExp('get\\s+$column\\s*=>').hasMatch(body);

void main() {
  final bodies = _tableBodies();

  group('مرساةُ الكشف — قبلَ أيِّ حكم', () {
    // ⚠️ الفحوصُ أدناه تقيس **غيابَ** شيء، وغيابٌ يمرّ أخضرَ حين ينكسر
    // الكشفُ نفسُه. فلو عاد `_tableBodies` فارغاً لصار «لا جدولَ ناقصاً»
    // صحيحاً شكلاً وكاذباً معنًى.
    test('المسحُ وجد جداولَ أصلاً', () {
      expect(bodies.length, greaterThan(100),
          reason: 'مسحُ `lib/data/database/tables` عاد شبهَ فارغ — كلُّ حكمٍ '
              'بعده باطل. غالباً تغيّر المسارُ أو شكلُ التعريف.');
    });

    test('واشتقاقُ اسم SQL يطابق drift — على البلاغ نفسِه', () {
      expect(_snake('EInvoiceStatusLog'), 'e_invoice_status_log');
      expect(_snake('EInvoiceSubmissions'), 'e_invoice_submissions');
      expect(_snake('BookingReminders'), 'booking_reminders');
      expect(bodies.containsKey('e_invoice_status_log'), isTrue,
          reason: 'الجدولُ يُسحَب ولا يجده المسحُ ⇒ «لا صنفَ يقابله» كاذب');
    });

    test('ويقرأ جسمَ الجدول كاملاً — لا يقطعه عند أوّل قوس', () {
      // `BookingReminders` تحمل `customConstraints` (‏فيها `{` و`}`) **قبلَ**
      // أعمدةِ المزامنة. تعبيرٌ كسولٌ يقطع عندها فيقول «ينقصها global_id».
      final br = bodies['booking_reminders'];
      expect(br, isNotNull);
      expect(br!.body.contains('customConstraints'), isTrue,
          reason: 'تغيّر الجدولُ — اختر مرساةً أخرى ذاتَ قوسٍ داخليّ');
      expect(_hasColumn(br.body, 'globalId'), isTrue,
          reason: 'الكشفُ يقطع جسمَ الجدول عند قوسٍ داخليّ ⇒ كلُّ بلاغٍ '
              'أدناه مشكوكٌ فيه.');
    });

    test('ويرى العمودَ الموجودَ ويفتقد الغائبَ — على نصٍّ مضبوط', () {
      // اختبارُ الحارس على **البلاغ نفسِه**: هذا شكلُ `Employees` قبلَ
      // v167 بالضبط — عضويّةُ قوائمَ بلا عمود.
      const before = 'IntColumn get id => integer().autoIncrement()();\n'
          'RealColumn get salary => real()();';
      expect(_hasColumn(before, 'salary'), isTrue);
      expect(_hasColumn(before, 'globalId'), isFalse,
          reason: 'الكشفُ يرى عموداً غيرَ موجود ⇒ لن يمسك فجوةً أبداً.');
    });
  });

  test('🔴 واستثناءُ SQL الخامّ يحمل دليلَه — لا إسكاتَ صامت', () {
    // الاستثناءُ أعلاه يُسقط الجدولَ من الفحص، فلا بدّ أن يبقى دليلُه
    // قائماً ويذكر الجدولَ باسمه. وإلّا صار سطراً يُخرس الحارسَ إلى الأبد.
    expect(_rawSqlProvenAtRuntime, isNotEmpty,
        reason: 'لا استثناءَ ⇒ الفحصُ تحته لا يقيس شيئاً');
    _rawSqlProvenAtRuntime.forEach((table, path) {
      final f = File(path);
      expect(f.existsSync(), isTrue,
          reason: '🔴 دليلُ `$table` غائب: $path — استثناءٌ بلا دليلٍ '
              'إسكاتٌ صامت');
      expect(f.readAsStringSync(), contains(table),
          reason: '🔴 ملفُّ الدليل لا يذكر `$table` — الدليلُ لا يخصّه');
      // ويجب أن يكون مُدرَجاً في السحب فعلاً، وإلّا فهو سطرٌ بائت.
      expect(DeltaPullService.pullTables, contains(table),
          reason: 'استثناءٌ لجدولٍ لا يُسحَب — اسمٌ بائتٌ يوهم بعقدٍ قائم');
    });
  });

  test('🔴 كلُّ جدولٍ يُسحَب يحمل أعمدةَ المزامنة في تعريفه', () {
    final gaps = <String>[];
    for (final table in DeltaPullService.pullTables) {
      final entry = bodies[table];
      if (entry == null) {
        final proof = _rawSqlProvenAtRuntime[table];
        if (proof != null) continue; // دليلُه اختبارٌ حيٌّ — راجع الوثيقةَ أعلاه
        gaps.add('$table — لا صنفَ يقابله');
        continue;
      }
      final allowed = _columnExceptions[table] ?? const <String>{};
      final missing = _syncColumns
          .where((c) => !allowed.contains(c) && !_hasColumn(entry.body, c))
          .toList();
      if (missing.isNotEmpty) {
        gaps.add('$table (${entry.cls}) — ينقصه ${missing.join('، ')}');
      }
    }

    expect(
      gaps,
      isEmpty,
      reason: 'جداولُ في `pullTables` بلا أعمدةِ مزامنةٍ في تعريفها:\n'
          '  ${gaps.join('\n  ')}\n\n'
          '`_upsertRow` يبني الإدراجَ من مفاتيحِ ردِّ الخادم و**يبتلع** خطأَ '
          'العمود المفقود بـ`debugPrint`. فالسحبُ يبدو عاملاً، ولا صفَّ '
          'يصل، ولا اختبارَ يحمرّ. أضِف الأعمدةَ وهجرةً ترفع رقمَ المخطَّط '
          '— أو انزع الجدولَ من القائمة.',
    );
  });

  test('🔴 وكلُّ جدولٍ يُسحَب له أرضيّةُ ترقيمٍ محلّيّة', () {
    final missing = DeltaPullService.pullTables
        .where((t) => !IdNamespaceService.namespacedTables.contains(t))
        .toList()
      ..sort();

    expect(
      missing,
      isEmpty,
      reason: 'جداولُ في `pullTables` وغائبةٌ عن `namespacedTables`: '
          '${missing.join('، ')}\n\n'
          'ترقيمُها المحلّيُّ يبدأ من ١ فيصطدم صفُّ العميل بصفِّ الخادم على '
          'نفس الرقم. الحارسُ العامُّ يعالجه بإعادةِ ترقيمٍ **بعد** التصادم، '
          'والأرضيّةُ تمنعه ابتداءً.',
    );
  });

  test('ولا اسمَ بائتٍ في أرضيّة الترقيم', () {
    // الاتّجاهُ المعاكس: اسمٌ في الأرضيّة لا يقابله جدولٌ يُسحَب ولا استثناءٌ
    // معلَن ⇒ إمّا حُذف أو أُعيدت تسميتُه، والأرضيّةُ تحمي جدولاً لا وجودَ له.
    final ghosts = IdNamespaceService.namespacedTables
        .where((t) => !DeltaPullService.pullTables.contains(t))
        .where((t) => !_namespacedButNotPulled.contains(t))
        .toList()
      ..sort();

    expect(ghosts, isEmpty,
        reason: 'أسماءٌ في `namespacedTables` بلا مقابلٍ في `pullTables` ولا '
            'حكمٍ في `_namespacedButNotPulled`: ${ghosts.join('، ')}');
  });

  test('واستثناءاتُ الأعمدة تصف جداولَ قائمةً — لا أسماءَ بائتة', () {
    for (final t in _columnExceptions.keys) {
      expect(DeltaPullService.pullTables, contains(t),
          reason: 'استثناءٌ لجدولٍ لا يُسحَب — أزِله بدل أن يُخفي فجوةً لاحقاً');
    }
  });
}
