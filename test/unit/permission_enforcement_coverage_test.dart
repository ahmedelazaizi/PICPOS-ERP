// test/unit/permission_enforcement_coverage_test.dart
//
// كل كود صلاحية إما ليه نقطة إنفاذ في `lib/`، أو مذكور صراحة في
// `PermissionEnforcementRegistry.knownUnenforced`.
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

bool _isEnforced(String sources, String code, String? constName) {
  if (sources.contains("'$code'") || sources.contains('"$code"')) return true;
  if (constName == null) return false;
  return RegExp('PermissionCodes\\.$constName\\b').hasMatch(sources);
}

void main() {
  test('مفيش كود صلاحية بلا إنفاذ ومش مسجّل', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !_isDefinitionFile(f.path))
        .map((f) => f.readAsStringSync())
        .join('\n');

    final constByCode = _constantNameByCode();
    final unenforced = <String>[];
    for (final entry in PermissionCodes.masterList) {
      final code = entry['code']!;
      if (!_isEnforced(sources, code, constByCode[code])) {
        unenforced.add(code);
      }
    }

    final unregistered = unenforced
        .where((c) => !PermissionEnforcementRegistry.knownUnenforced.contains(c))
        .toList()
      ..sort();

    expect(unregistered, isEmpty,
        reason: 'أكواد بلا إنفاذ ومش مسجّلة — إما نفّذها أو سجّلها بسبب:\n'
            '${unregistered.join('\n')}');
  });

  test('السجل ما فيهوش كود بقى منفَّذ (يتقلّص ما يكبرش)', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !_isDefinitionFile(f.path))
        .map((f) => f.readAsStringSync())
        .join('\n');

    final constByCode = _constantNameByCode();
    final staleEntries = PermissionEnforcementRegistry.knownUnenforced
        .where((c) => _isEnforced(sources, c, constByCode[c]))
        .toList()
      ..sort();

    expect(staleEntries, isEmpty,
        reason: 'الأكواد دي بقت منفَّذة — شيلها من knownUnenforced:\n'
            '${staleEntries.join('\n')}');
  });
}
