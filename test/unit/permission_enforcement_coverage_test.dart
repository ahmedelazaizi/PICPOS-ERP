// test/unit/permission_enforcement_coverage_test.dart
//
// كل كود صلاحية إما ليه نقطة إنفاذ في `lib/`، أو مذكور صراحة في
// `PermissionEnforcementRegistry.knownUnenforced` (لسه محتاج إنفاذ)، أو في
// `PermissionCodes.nonToggleable` (مستحيل يتحلّ بإنفاذ — Task 5).
//
// من غير الحارس ده، كود جديد يتضاف لـ`masterList` ويظهر للمدير في شاشة
// الصلاحيات وهو مالوش مستقبل — وما حدش يكتشف غير من الميدان.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/core/permissions/permission_enforcement_registry.dart';

/// الملفات اللي بتعرّف الصلاحية مش اللي بتفحصها — وجود الكود فيها مش إنفاذ.
const _definitionFiles = [
  'lib/core/permissions/permission_codes.dart',
  'lib/core/permissions/role_grant_matrix.dart',
  'lib/core/permissions/permission_enforcement_registry.dart',
  'lib/presentation/screens/role_management/data/permission_categories.dart',
  // جدول قراءة قناة الويب: يربط الجدول بالصلاحية التي تكفي لقراءته، وهذا
  // ليس إنفاذًا لزرّ أو إجراء في شاشة، فلا يُحتسب الكود منفَّذًا بوروده فيه.
  'lib/core/permissions/web_table_policy.dart',
  // مجموعاتُ «فتح الشاشة»: تسرد أكوادَ أفعالِ كلِّ شاشةٍ لتحديد من يراها —
  // هذا تعريفٌ لا إنفاذٌ لزرّ، وإلّا صار كلُّ كودٍ مذكورٍ هناك «منفَّذاً» وسقط
  // معنى الحارس (P2، 2026-10-18).
  'lib/core/permissions/screen_access_resolver.dart',
];

bool _isDefinitionFile(String path) {
  final p = path.replaceAll(r'\', '/');
  return _definitionFiles.any(p.endsWith) ||
      p.contains('lib/data/database/database_seeder');
}

/// خريطة «كود الصلاحية ← اسم الثابت» المستخرجة من `permission_codes.dart`.
///
/// ── ليه دي لازمة ─────────────────────────────────────────────────────────
/// نقاط الإنفاذ بتستدعي الصلاحية بشكلين: النص الخام `'pos_save'`، أو الثابت
/// `PermissionCodes.posSave`. والشكل التاني هو الغالب — حتى مدخلات
/// `masterList` نفسها مكتوبة بالثوابت. فالبحث عن النص الخام وحده بيقول عن
/// ٨٥ كود منفَّذ فعلاً إنهم ميتين، وده بيخلي الحارس بلا قيمة.
Map<String, String> _constantNameByCode() {
  final src =
      File('lib/core/permissions/permission_codes.dart').readAsStringSync();
  final re = RegExp(r"static const String (\w+) = '([a-z0-9_]+)';");
  return {for (final m in re.allMatches(src)) m.group(2)!: m.group(1)!};
}

/// كل الأكواد المشار إليها في الكود، مستخرجة بمسحة واحدة.
///
/// ── ليه Set مش بحث لكل كود ────────────────────────────────────────────────
/// الفحص القديم كان بيعدّي على ٢٢ ميجا من المصادر مرة لكل كود — يعني مئات
/// المسحات الكاملة. المسحة الواحدة اللي بتطلّع كل المراجع وتحطها في `Set`
/// بتخلي الفحص لكل كود عملية بحث واحدة.
({Set<String> literals, Set<String> constNames}) _referencedIn(String sources) {
  final literals = RegExp(r"""['"]([a-z0-9_]+)['"]""")
      .allMatches(sources)
      .map((m) => m.group(1)!)
      .toSet();
  // `\s*` حوالين النقطة: `PermissionGuard` جوه شجرة ودجت عميقة بيوصل لعمود
  // ٧٠+ فـ`dart format` بيلف السطر بين اسم الكلاس والنقطة. من غيرها الحارس
  // بيقول عن كود محروس فعلاً إنه ثغرة — وهو أسوأ نوع كذب لأنه بيدفع اللي
  // بيقرا التقرير إنه يسجّله في `knownUnenforced` فيتخبّى للأبد.
  final constNames = RegExp(r'PermissionCodes\s*\.\s*(\w+)')
      .allMatches(sources)
      .map((m) => m.group(1)!)
      .toSet();
  return (literals: literals, constNames: constNames);
}

bool _isEnforced(
  ({Set<String> literals, Set<String> constNames}) refs,
  String code,
  String? constName,
) {
  if (refs.literals.contains(code)) return true;
  if (constName == null) return false;
  return refs.constNames.contains(constName);
}

void main() {
  // مسح شجرة lib/ واستخراج خريطة الثوابت مرة واحدة بس — القراءتين شغل ثابت
  // ومحدَّد النتيجة، وتكراره لكل test() كان بيضاعف وقت التشغيل من غير أي
  // فايدة (الاختباران مستقلّين برضه، بيقروا نفس القيمة الجاهزة بس).
  late final ({Set<String> literals, Set<String> constNames}) refs;
  late final Map<String, String> constByCode;

  setUpAll(() {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !_isDefinitionFile(f.path))
        .map((f) => f.readAsStringSync())
        .join('\n');
    refs = _referencedIn(sources);
    constByCode = _constantNameByCode();
  });

  // ── ليه الاختبار ده موجود ───────────────────────────────────────────────
  // اتبلّغ من نقل الباتش في UralCash: الـregex كان `PermissionCodes\.(\w+)`
  // فما بيمسكش المرجع الملفوف على سطرين. وده بيحصل فعلاً — `PermissionGuard`
  // جوه شجرة ودجت عميقة بيوصل لعمود ٧٠+ فـ`dart format` بيلف السطر بين اسم
  // الكلاس والنقطة:
  //
  //     permission: PermissionCodes
  //         .purchasesPrint,
  //
  // النتيجة إن الحارس بيقول عن كود **محروس فعلاً** إنه ثغرة، والمتوقَّع من
  // اللي بيقرا التقرير إنه يسجّله في `knownUnenforced` (فيتخبّى للأبد) أو
  // يضيف إنفاذ مكرَّر. حارس بيكدب في الاتجاه ده أسوأ من غيابه.
  //
  // عندنا الحالة الوحيدة (`purchase_invoices_screen.dart:733`) متلقّطة
  // بالصدفة لأن فورك PicPos فيه نفس المرجع على سطر واحد — يعني الثغرة كامنة
  // مش ظاهرة. أول ما الفورك يتلف أو يتشال بتبان.
  test('استخراج المراجع بيمسك الشكل الملفوف على سطرين', () {
    final wrapped = _referencedIn('''
      PermissionGuard(
        permission: PermissionCodes
            .purchasesPrint,
        allowManagerOverride: true,
      )
    ''');
    expect(wrapped.constNames, contains('purchasesPrint'));
  });

  test('الشكل العادي على سطر واحد لسه بيتمسك', () {
    final inline =
        _referencedIn('permission: PermissionCodes.posSave,');
    expect(inline.constNames, contains('posSave'));
  });

  test('مفيش كود صلاحية بلا إنفاذ ومش مسجّل', () {
    final unenforced = <String>[];
    for (final entry in PermissionCodes.masterList) {
      final code = entry['code']!;
      if (!_isEnforced(refs, code, constByCode[code])) {
        unenforced.add(code);
      }
    }

    // كود بلا إنفاذ متعذّر (نص) لو مسجّل في أي من المجموعتين: knownUnenforced
    // (لسه هيتنفّذ) أو nonToggleable (مستحيل يتنفّذ — Task 5). لو الاتنين
    // مش شايفينه، يبقى ضاع من التتبّع خالص.
    final unregistered = unenforced
        .where(
          (c) =>
              !PermissionEnforcementRegistry.knownUnenforced.contains(c) &&
              !PermissionCodes.nonToggleable.containsKey(c),
        )
        .toList()
      ..sort();

    expect(unregistered, isEmpty,
        reason: 'أكواد بلا إنفاذ ومش مسجّلة — إما نفّذها أو سجّلها بسبب:\n'
            '${unregistered.join('\n')}');
  });

  test('السجل ما فيهوش كود بقى منفَّذ (يتقلّص ما يكبرش)', () {
    final staleEntries = PermissionEnforcementRegistry.knownUnenforced
        .where((c) => _isEnforced(refs, c, constByCode[c]))
        .toList()
      ..sort();

    expect(staleEntries, isEmpty,
        reason: 'الأكواد دي بقت منفَّذة — شيلها من knownUnenforced:\n'
            '${staleEntries.join('\n')}');
  });
}
