// حارس بنيوي — كل شاشة تقرير مالي لازم تحلّ حصر الفروع الآمر.
//
// ── ليه بنيوي مش سلوكي ──────────────────────────────────────────────────────
// فئة العطل هي «شاشة تقرير **جديدة** نسيت تمرّر الحصر». الاختبار السلوكي
// بيغطّي الشاشات اللي حد فتكر يكتبلها اختبار؛ ده بيوقع لحظة ما أي حد يضيف
// ملفاً في `lib/presentation/screens/reports/` من غير ما يحلّ النطاق.
//
// ── الخلفية ─────────────────────────────────────────────────────────────────
// تقرير المصروفات كان ٩١١ سطر بلا **ولا ذكر واحد** لـ`branchScopeProvider`.
// وبدل الحصر كان بيبذر `_selectedBranchId` من `activeBranchIdProvider` —
// اللي بيرجّع `null` لمستخدم بلا تخصيص فرع، وهو **نفس** المستخدم اللي
// `branchScopeProvider` بيدّيه `{}` («ما يشوفش حاجة»). فانقلب fail-closed
// لـfail-open: المستخدم ده كان بيقرا إجمالي مصروفات الشركة كلها بفئاتها
// وطرق دفعها وملاحظاتها.
//
// وجود `branchScopeProvider` في الملف مش إثبات إن الحصر **مُنفَّذ** — هو شرط
// لازم مش كافٍ. الإنفاذ الفعلي بيتحرس سلوكياً (شوف
// test/unit/expenses_report_branch_scope_test.dart و
// test/unit/treasury_report_branch_scope_d01_test.dart). الحارس ده بيمسك
// النسيان الكامل، وهو فئة العطل اللي وقعت فعلاً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// شاشات تقارير خارج مجلد `reports/` بتقرا بيانات مالية عبر الفروع.
const _extraReportScreens = <String>[
  'lib/presentation/screens/report_builder_screen.dart',
  'lib/presentation/screens/party_statement_screen.dart',
  'lib/presentation/screens/stock_movements_screen.dart',
];

/// مش شاشة — زرار تصدير مشترك بين ١٣ شاشة، بيحرس صلاحية `reports_export`
/// ومش بيبني استعلاماً.
const _notAScreen = <String>{
  'lib/presentation/screens/reports/report_export_guard.dart',
};

/// تقارير **لا يصحّ** حصرها بفرع — محروسة بصلاحية بدلاً من ذلك.
///
/// `vat_reconciliation` بيقارن طرفين: إجماليات الضريبة من الفواتير (فيها
/// branch_id) مقابل **أرصدة حسابات GL** (‏2121 و1141 — على مستوى الشركة
/// بطبيعتها). حصر طرف وترك الآخر بيخلّي التقرير يعرض فرقاً دايماً،
/// و«التسوية» — كل وظيفته — تفقد معناها. فالفلتر هنا كسر لا إصلاح.
///
/// البديل الصحيح: الوصول نفسه يتحرس. من يملك `reports_taxes` يراه كاملاً،
/// ومن لا يملكها لا يراه. الفحص التاني تحت بيثبت إن الحراسة **موجودة فعلاً**
/// عشان شيلها ما يعدّيش صامتاً.
/// شاشات بتحصر عبر **المزوّد** لا في ملفها (‏PIR P1-01: الشاشة ما بتلمسش
/// الـDB). القيمة اسم المزوّد، والفحص تحت بيثبت إن `report_providers.dart`
/// بيحلّ `branchScopeProvider` جوّه فعلاً.
///
/// ليه في المزوّد: `ArAgingParams` عبارة عن record، و`Set<int>` في Dart
/// بيتقارن **بالهوية لا بالمحتوى** — فحطّ النطاق في مفتاح `family` كان
/// هيبطّل الكاش ويعيد الاستعلام مع كل rebuild.
const _scopedViaProvider = <String, String>{
  'lib/presentation/screens/reports/ar_aging_report_screen.dart':
      'arAgingReportProvider',
};

const _permissionGatedNotBranchScoped = <String, String>{
  'lib/presentation/screens/reports/vat_reconciliation_screen.dart':
      'PermissionCodes.reportsTaxes',
};

/// خط أساس موثَّق — **مش نمطاً مقبولاً**، دي تسريبات مقيسة لسه مفتوحة.
///
/// كل واحدة فيهم بتعرض قيم مالية عبر الفروع لمستخدم محصور:
///   • ar_aging_report_screen    — أرصدة كل العملاء والموردين على مستوى الشركة
///   • vat_reconciliation_screen — إجماليات ضريبة المخرجات/المدخلات + أرصدة GL
///   • report_builder_screen     — تقارير مخصّصة على كل الجداول بلا أي حصر
///
/// اتشال: party_statement_screen — بقى بيحلّ branchScopeProvider ويمرّره لـ
/// watchAllPartiesForBranches. الإثبات في party_statement_branch_scope_test.
///
/// اتشال: stock_movements_screen — بقى بيحلّ userAccessibleWarehousesProvider
/// ويمرّر معرّفات المخازن للاستعلام، والاستعلام بقى عنده سقف صفوف.
/// الإثبات في stock_movements_scope_test (‏[] بتفشل مقفولة).
///
/// لإزالة سطر: حُلّ `branchScopeProvider` في الشاشة، مرّر `allowedBranchIds`
/// للاستعلام، اكتب اختباراً سلوكياً يثبت إن `{}` بتفشل مقفولة، وشيل السطر.
const _baseline = <String>{
  'lib/presentation/screens/report_builder_screen.dart',
};

void main() {
  test('كل شاشة تقرير بتحلّ branchScopeProvider (عدا خط الأساس الموثَّق)', () {
    final files = <String>[
      ...Directory('lib/presentation/screens/reports')
          .listSync()
          .whereType<File>()
          .map((f) => f.path.replaceAll(r'\', '/'))
          .where((p) => p.endsWith('.dart')),
      ..._extraReportScreens,
    ]..sort();

    final offenders = <String>[];
    for (final path in files) {
      if (_notAScreen.contains(path)) continue;
      // تقارير لا يصحّ حصرها بفرع — محروسة بصلاحية، والفحص التاني تحت بيثبت
      // إن الحراسة موجودة فعلاً.
      if (_permissionGatedNotBranchScoped.containsKey(path)) continue;
      // بتحصر عبر المزوّد — الفحص التاني تحت بيثبت إن المزوّد بيحلّ النطاق.
      if (_scopedViaProvider.containsKey(path)) continue;
      final file = File(path);
      if (!file.existsSync()) {
        fail('مسار في قائمة الحارس مش موجود — حدّث القائمة: $path');
      }
      // حصر المخازن مقبول زي حصر الفروع بالظبط: شاشات زي حركة المخزون
      // استعلامها **لكل مخزن** لا لكل فرع، و`userAccessibleWarehousesProvider`
      // بيشتق من نفس المصدر (‏getWarehouseScopeForUser) وبيفشل مقفولاً على
      // العميل/المرآة. إجبارها على branchScopeProvider كان هيخلّي الحصر
      // الصحيح يتقرا «تسريباً».
      final src = file.readAsStringSync();
      final resolvesScope = src.contains('branchScopeProvider') ||
          src.contains('userAccessibleWarehousesProvider');
      if (!resolvesScope) {
        offenders.add(path);
      }
    }

    final unexpected = offenders.where((p) => !_baseline.contains(p)).toList();
    expect(unexpected, isEmpty,
        reason: 'شاشة تقرير جديدة بلا حصر فروع — مرّر allowedBranchIds '
            'للاستعلام زي expenses_report_screen.dart');

    // خط الأساس لازم يضيق مع الوقت: لو اتصلحت شاشة، شيلها من `_baseline`
    // عشان ما ترجعش تتسرّب تاني من غير ما حد ياخد باله.
    final fixed = _baseline.where((p) => !offenders.contains(p)).toList();
    expect(fixed, isEmpty,
        reason: 'الشاشات دي بقت بتحلّ النطاق — شيلها من _baseline عشان '
            'الحارس يقفل عليها');
  });

  // ── ليه فحص تاني ────────────────────────────────────────────────────────
  // الفحص فوق بيسأل «الملف بيذكر branchScopeProvider؟» وبس. طفرةٌ أثبتت
  // ضعفه: إرجاع party_statement لـ`watchAllParties()` غير المحصورة **عدّى**،
  // لأن سطر حلّ النطاق فضل موجود فوقها بلا استعمال. فالحارس بيمسك النسيان
  // الكامل — مش الارتداد.
  //
  // القراءات دي ليها نظير محصور بنفس الاسم + ForBranches، فاستعمال النسخة
  // العارية في شاشة تقرير خطأ دايماً حتى لو النطاق متحلول في مكان تاني من
  // نفس الملف.
  // الإعفاء من الحصر بالفرع مشروط بوجود بديل. من غير الفحص ده، شيل
  // `PermissionGuard` من الشاشة بيخلّيها تقرير على مستوى الشركة **مفتوحاً
  // للكل** — وخط الأساس فوق مش هيلاحظ لأنها معفاة أصلاً.
  // الإعفاء مشروط بوجود البديل. من غير الفحص ده، شيل حلّ النطاق من المزوّد
  // بيرجّع التسريب و**خط الأساس مش هيلاحظ** لأن الشاشة معفاة أصلاً.
  test('الشاشات المعفاة بتحصر عبر مزوّد بيحلّ النطاق فعلاً', () {
    const providersFile = 'lib/data/providers/report_providers.dart';
    final src = File(providersFile).readAsStringSync();
    final missing = <String>[];

    _scopedViaProvider.forEach((screen, providerName) {
      if (!File(screen).existsSync()) {
        fail('مسار في قائمة الإعفاء مش موجود — حدّث القائمة: $screen');
      }
      if (!File(screen).readAsStringSync().contains(providerName)) {
        missing.add('$screen → مش بينده $providerName');
        return;
      }
      // المزوّد لازم يكون موجوداً في الملف **و**الملف بيحلّ النطاق.
      // فحص على مستوى الملف — كافٍ لأن الملف ده مزوّدات التقارير وحدها.
      if (!src.contains(providerName) ||
          !src.contains('branchScopeProvider')) {
        missing.add('$providersFile → $providerName بلا branchScopeProvider');
      }
    });

    expect(missing, isEmpty,
        reason: 'شاشة معفاة من الفحص الأول لأن مزوّدها بيحصر — لو المزوّد '
            'بطّل يحصر، التسريب رجع بلا أي حارس');
  });

  test('التقارير المعفاة من الحصر محروسة بصلاحية فعلاً', () {
    final missing = <String>[];
    _permissionGatedNotBranchScoped.forEach((path, permission) {
      final file = File(path);
      if (!file.existsSync()) {
        fail('مسار في قائمة الإعفاء مش موجود — حدّث القائمة: $path');
      }
      final src = file.readAsStringSync();
      if (!src.contains('PermissionGuard') || !src.contains(permission)) {
        missing.add('$path → ناقصه PermissionGuard($permission)');
      }
    });
    expect(missing, isEmpty,
        reason: 'تقرير معفى من حصر الفروع لازم يكون محروساً بصلاحية — وإلا '
            'بقى مكشوفاً للكل بلا أي طبقة');
  });

  test('مفيش شاشة تقرير بتنده قراءةً غير محصورة ليها نظير محصور', () {
    const unscopedReaders = <String>[
      'watchAllParties()',
      'watchCustomers()',
      'watchSuppliers()',
    ];

    final files = <String>[
      ...Directory('lib/presentation/screens/reports')
          .listSync()
          .whereType<File>()
          .map((f) => f.path.replaceAll(r'\', '/'))
          .where((p) => p.endsWith('.dart')),
      ..._extraReportScreens,
    ]..sort();

    final offenders = <String>[];
    for (final path in files) {
      if (_notAScreen.contains(path)) continue;
      final file = File(path);
      if (!file.existsSync()) continue;
      // التعليقات تُستبعَد: أول نسخة من الفحص ده اتعثّرت في تعليقٍ بيشرح
      // العطل القديم ويذكر اسم الدالة العارية. حارس بيفشل على شرح العطل
      // بيعلّم الناس تشيل الشرح.
      final src = file
          .readAsLinesSync()
          .map((l) {
            final i = l.indexOf('//');
            return i >= 0 ? l.substring(0, i) : l;
          })
          .join('\n');
      for (final reader in unscopedReaders) {
        if (src.contains(reader)) {
          offenders.add('$path → $reader');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'استعمل النسخة المحصورة (‏…ForBranches(allowedBranchIds)) — '
            'العارية بتعرض أطراف كل الفروع بأسمائها وأرصدتها');
  });
}
