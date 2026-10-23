// حارس ثابت: مسار الويب (lib/main_web_entry.dart) لا يصل بالاستيراد إلى شاشات
// POS/مطبخ/طاولات/ميزان/إقفال وردية/اختبار طباعة.
//
// يتتبّع import/export/part تعدّياً من نقطة دخول الويب، ويتّبع فرع الويب في
// الاستيراد الشرطي (`dart.library.html`/`js_interop` صحيحة، `io`/`ffi` خاطئة).
//
// «المحظور» = ملفات `lib/presentation/**` داخل مجلد يبدأ بـ pos/kitchen/
// tables_picpos/scale_plu_picpos/shift_close_picpos/print_test_picpos، أو
// ملفٌ في presentation باسم يبدأ بها. طبقة البيانات (جداول/DAOs المطبخ مثلاً)
// مشتركة ولا تُحظر: هي مخطّط القاعدة نفسه.
//
// ── خطّ الأساس: صفر (م3-9) ─────────────────────────────────────────────────
// كان فيه ثلاثةُ ملفاتٍ محظورةٍ تصلها السلسلةُ عبر تشابكٍ في طبقات أخرى؛ قُطعت:
//   * cart_controller / checkout_controller: `network_service` يستورد `api_handler`
//     (← cfd_service ← cart_controller) باستيرادٍ شرطي: على الويب `api_handler_web_stub.dart`.
//   * modifier_selection_dialog: `SelectedModifier`/`OptionQuantityLevel` انتقلا إلى
//     `domain/entities/selected_modifier.dart` (والحوار يعيد تصديرهما).
// الاختبار يفشل إن وُصل أيُّ ملفٍّ محظور. وإن احتاج دَيْنٌ جديدٌ أن يُسجَّل
// فأضفه إلى [_knownLeaks] مع سببه — والاختبار الثالث يُجبر على حذفه حين يزول.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _entry = 'lib/main_web_entry.dart';

const _knownLeaks = <String>{};

final _forbiddenName = RegExp(
  r'^(pos|kitchen|tables_picpos|scale_plu_picpos|shift_close_picpos|print_test_picpos)',
);

bool _isForbidden(String path) {
  if (!path.startsWith('lib/presentation/')) return false;
  final segments = path.substring('lib/presentation/'.length).split('/');
  return segments.any((s) => _forbiddenName.hasMatch(s));
}

final _directive = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]((?:\s+if\s*\([^)]*\)\s*['"][^'"]+['"])*)''',
  multiLine: true,
);
final _condition = RegExp(
  r'''if\s*\(\s*([\w.]+)\s*(?:==\s*['"][^'"]*['"])?\s*\)\s*['"]([^'"]+)['"]''',
);
const _webTrue = {
  'dart.library.html',
  'dart.library.js_interop',
  'dart.library.js_interop_unsafe',
  'dart.library.js_util',
};

String? _resolve(String from, String target) {
  if (target.startsWith('dart:')) return null;
  if (target.startsWith('package:picpos_erp/')) {
    return 'lib/${target.substring('package:picpos_erp/'.length)}';
  }
  if (target.startsWith('package:')) return null;
  return Uri.parse(from).resolve(target).path;
}

/// كل ملفات lib المُوصَلة من [_entry] → أول والدٍ وصل إليها.
Map<String, String?> _reach() {
  final parent = <String, String?>{_entry: null};
  final queue = <String>[_entry];
  while (queue.isNotEmpty) {
    final file = queue.removeAt(0);
    final f = File(file);
    if (!f.existsSync()) continue;
    final src = f.readAsStringSync();
    for (final m in _directive.allMatches(src)) {
      var target = m.group(1)!;
      for (final c in _condition.allMatches(m.group(2) ?? '')) {
        if (_webTrue.contains(c.group(1))) {
          target = c.group(2)!;
          break;
        }
      }
      final r = _resolve(file, target);
      if (r != null && !parent.containsKey(r)) {
        parent[r] = file;
        queue.add(r);
      }
    }
  }
  return parent;
}

String _chain(Map<String, String?> parent, String file) {
  final out = <String>[];
  for (String? x = file; x != null; x = parent[x]) {
    out.add(x.replaceFirst('lib/', ''));
  }
  return out.take(8).join('\n    <- ');
}

void main() {
  late Map<String, String?> parent;
  setUpAll(() => parent = _reach());

  test('الحارس يتتبّع فعلاً (نقطة الدخول ولوحة التحكم ضمن الإغلاق)', () {
    expect(parent.length, greaterThan(100));
    expect(
      parent.keys,
      contains('lib/presentation/dashboard_picpos/screens/dashboard_picpos_screen.dart'),
    );
    expect(parent.keys, contains('lib/web/web_session.dart'));
    // م3-8: غلاف التنقّل وسجلّ الشاشات المترجَمة ضمن الإغلاق (وإلا صار الحارس
    // أعمى عمّا تستورده شاشات الويب).
    expect(parent.keys, contains('lib/web/web_shell.dart'));
    expect(parent.keys, contains('lib/web/web_screen_registry.dart'));
    // م3-9: الشاشات الخمس المفصولة عن POS ضمن الإغلاق (وبلا تسريب محظور أدناه).
    for (final f in [
      'lib/web/web_settings_screen.dart',
      'lib/presentation/users_picpos/screens/users_management_picpos_screen.dart',
      'lib/presentation/settings_picpos/screens/branches_picpos_screen.dart',
      'lib/presentation/sales_returns_picpos/screens/sales_return_records_picpos_screen.dart',
      'lib/presentation/purchase_returns_picpos/screens/purchase_return_records_picpos_screen.dart',
    ]) {
      expect(parent.keys, contains(f), reason: f);
    }
    expect(
      parent.keys,
      contains(
          'lib/presentation/accounting_picpos/journal_entries_picpos_screen.dart'),
    );
  });

  test('مسار الويب لا يصل إلى شاشات POS/مطبخ/طاولات/ميزان/وردية/طباعة', () {
    final reached = parent.keys.where(_isForbidden).toSet();
    final fresh = reached.difference(_knownLeaks);
    expect(
      fresh,
      isEmpty,
      reason: 'مسار الويب وصل ملفاتٍ محظورة جديدة:\n'
          '${fresh.map((f) => '  $f\n    <- ${_chain(parent, f)}').join('\n')}',
    );
  });

  test('خطّ الأساس لا يحتفظ بما لم يعد مُوصَلاً (قلّصه)', () {
    final stale = _knownLeaks.where((f) => !parent.containsKey(f));
    expect(stale, isEmpty,
        reason: 'ملفاتٌ في _knownLeaks لم تعد مُوصَلة — احذفها من القائمة: $stale');
  });
}
