// حارسٌ بنيويٌّ ضدّ ألوانِ الأسطحِ الفاتحةِ المثبَّتةِ في الشاشاتِ العشر.
//
// ═══ العقدُ المكسور ═══
//
// `AppColors.card` و`.surface` و`.border` و`.background` ثوابتُ **الوضع
// الفاتح وحدَه**. ولها نظائرُ داكنةٌ (`cardDark` · `borderDark` …) يربطها
// `AppTheme` بـ`ThemeData`، لكنّ أيَّ ودجتٍ تكتب الثابتَ الفاتحَ مباشرةً
// تبقى بيضاءَ في الوضع الغامق. وهذا سببُ أنّ الغامقَ «لا يتعمّم»: الشريطُ
// الجانبيُّ يتبع الثيمَ والمحتوى لا يتبعه.
//
// بلاغُ المالك 2026-08-24 بعد نشرِ `93467145`: عشرُ شاشاتٍ ما زالت فاتحة.
//
// ═══ لماذا هذه الثوابتُ الأربعةُ وحدَها ═══
//
// لأنها **أسطحٌ لا مقدّمات**: لا يصحُّ أن يكون أيٌّ منها لونَ نصٍّ أو
// أيقونة، فكلُّ موضعٍ لها مخالفةٌ بلا استثناء. ولهذا يخلو هذا الحارسُ من
// الإيجابيّات الكاذبة.
//
// وعمداً **لا يفحص `Colors.white`**: أبيضُ نصٍّ أو أيقونةٍ على سطحٍ ملوَّنٍ
// صحيحٌ ويجب أن يبقى. وقد قِيس في `treasury_metrics_panel_picpos.dart` أنّ
// أبيضَه كلَّه مقدّمةٌ على تدرُّجٍ داكن — فأيُّ حارسٍ سطريٍّ يفحص الأبيضَ
// يقع عليه كاذباً. الأبيضُ يُراجَع بالعين وبحارسِ لمعانٍ يقيس السطحَ نفسَه.
//
// ═══ الإصلاح ═══
//
// المُلحقُ `picpos_shell/picpos_surface.dart`: `context.picposCard` ·
// `picposField` · `picposHairline` · `picposText` · `picposMuted`.
// والوضعُ الفاتحُ يبقى **مطابقاً بايتاً ببايت** (القيمُ الفاتحةُ هي هي)،
// فالإصلاحُ يفيد العلامتَين ولا يحتاج تسييجاً.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الشاشاتُ العشرُ كما عدّدها المالك — ملفّاً ومجلّداً.
const _scope = <String>[
  'lib/presentation/screens/analytics_dashboard_screen.dart',
  'lib/presentation/screens/stock_movements_screen.dart',
  'lib/presentation/screens/purchase_orders_screen.dart',
  'lib/presentation/screens/fiscal_year_screen.dart',
  'lib/presentation/screens/sales_orders_screen.dart',
  'lib/presentation/screens/hr_screen.dart',
  'lib/presentation/screens/hr',
  'lib/presentation/screens/operational_expenses_screen.dart',
  'lib/presentation/screens/inventory/stock_requisitions_screen.dart',
  'lib/presentation/screens/inventory/stock_requisition_create_screen.dart',
  'lib/presentation/treasury_picpos',
  'lib/presentation/pos_picpos',
];

/// ثوابتُ الأسطحِ الفاتحةِ وحدَها — بلا نظائرِها الداكنة.
///
/// `\b` بعدَ الاسمِ يمنع مطابقةَ `cardDark` و`borderDark` و`backgroundDark`:
/// تلك صحيحةٌ ومقصودةٌ حيث تقع.
final _lightSurface = RegExp(
  r'AppColors\.(?:card|surface|border|background)\b',
);

/// ألوانُ أسطحٍ فاتحةٍ مكتوبةٌ ستّةَ عشرَ رقماً — نفسُ عطبِ [_lightSurface]
/// بثوبٍ آخر، ولا يمسكها فحصُ `AppColors` لأنها لا تمرُّ به.
///
/// مقيسةٌ في الشاشات العشر 2026-08-24: `#F4F7FC` هي `--field` من التصميم،
/// و`#F8F9FA` خلفيّةُ شاشةِ المصروفات. وليست هذه قائمةَ «كلِّ فاتح»: ألوانُ
/// الدلالة (`#F59E0B` الكهرمانيّ مثلاً) فاتحةٌ أيضاً وهي صحيحةٌ حيث تقع،
/// فالقائمةُ محصورةٌ فيما يُستعمل **سطحاً**.
final _lightSurfaceHex = RegExp(
  r'Color\(0x(?:FFF4F7FC|FFF8F9FA|FFF8FAFC|FFE2E8F0)\)',
  caseSensitive: false,
);

/// ملفّاتٌ تُعرِّف الرمزَ نفسَه، فتحمل القيمةَ الفاتحةَ **داخلَ شرطِ وضعٍ**.
///
/// إضافةُ ملفٍّ هنا ليست إعفاءً: هي تعهّدٌ بأن القيمةَ الفاتحةَ فيه مقترنةٌ
/// بنظيرةٍ داكنةٍ يختار بينهما الوضعُ. راجعه بعينك قبل أن تضيفه.
const _definesBothModes = <String>{
  'lib/presentation/treasury_picpos/widgets/treasury_picpos_tokens.dart',
  // `_fieldOf` — نفسُ رمزِ `--field` بقيمته الفاتحةِ داخلَ شرطِ وضع.
  'lib/presentation/pos_picpos/widgets/picpos_payment_panel.dart',
};

Iterable<File> _dartFilesUnder(String path) sync* {
  final dir = Directory(path);
  if (dir.existsSync()) {
    for (final e in dir.listSync(recursive: true)) {
      if (e is File && e.path.endsWith('.dart')) yield e;
    }
    return;
  }
  final file = File(path);
  if (file.existsSync()) yield file;
}

void main() {
  test('لا لونَ سطحٍ فاتحٍ مثبَّتٌ في الشاشاتِ العشر', () {
    expect(Directory('lib/presentation').existsSync(), isTrue,
        reason: 'يُشغَّل من جذر المستودع');

    final offenders = <String>[];

    for (final entry in _scope) {
      final found = _dartFilesUnder(entry);
      expect(found, isNotEmpty,
          reason: 'مسارٌ في النطاق لم يُعثر عليه — انتقلت الشاشة؟ : $entry');

      for (final file in found) {
        final rel = file.path.replaceAll(r'\', '/');
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!_lightSurface.hasMatch(line)) continue;
          // التعليقاتُ التي تشرح القاعدةَ ليست مخالفةً لها.
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//')) continue;
          offenders.add('$rel:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'كلُّ موضعٍ هنا لونُ سطحٍ **للوضع الفاتح وحدَه**، فيبقى فاتحاً '
          'في الوضع الغامق ويترك بقعةً بيضاء.\n'
          'الإصلاحُ بمُلحقِ `picpos_shell/picpos_surface.dart`: '
          '`context.picposCard` للبطاقة · `picposField` للحقلِ والصفّ · '
          '`picposHairline` للحدِّ والفاصل.\n'
          'والفاتحُ يبقى مطابقاً بايتاً ببايت، فلا خطرَ على UralCash.\n'
          'المواضع (${offenders.length}):\n  ${offenders.join('\n  ')}',
    );
  });

  test('ولا لونَ سطحٍ فاتحٍ مكتوباً ستّةَ عشرَ رقماً', () {
    final offenders = <String>[];

    for (final entry in _scope) {
      for (final file in _dartFilesUnder(entry)) {
        final rel = file.path.replaceAll(r'\', '/');
        if (_definesBothModes.contains(rel)) continue;

        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!_lightSurfaceHex.hasMatch(line)) continue;
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//')) continue;
          offenders.add('$rel:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'قيمةُ سطحٍ فاتحةٌ مثبَّتةٌ بالرقم — تبقى فاتحةً في الغامق '
          'تماماً كثوابتِ `AppColors` الفاتحة.\n'
          'إن كان الرمزُ يخصُّ ملفَّه فاكتب شرطَ وضعٍ يحفظ القيمةَ الفاتحةَ '
          'كما هي؛ وإن كان عامّاً فاستعمل مُلحقَ `picpos_surface.dart`.\n'
          'المواضع (${offenders.length}):\n  ${offenders.join('\n  ')}',
    );
  });
}
