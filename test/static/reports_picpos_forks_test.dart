// نسخُ PicPos من شاشات التقارير — عقدُ الفورك.
//
// ═══ لماذا نسخةٌ لا فرعٌ في الشاشة المشتركة ═══
//
// أمرُ المالك 2026-08-25: لا يُربَط شيءٌ من PicPos بمسار UralCash؛ وما كان
// مشتركاً ولا نُريد تعديلَه **يُنسَخ** ويُثبَّت عليه التصميمُ الجديد.
//
// وللنسخِ ثمنٌ معروف: نسختان تنحرفان. فالمحروسُ هنا **طرفا العقد** معاً:
//
//   ‏١) الأصلُ المشترك ما زال قائماً ومفتوحاً من مركز UralCash — نسخةٌ تُنشأ
//       ثمّ يُحذَف أصلُها تعني أنّ UralCash فقدت شاشةً بلا أن يشتكيَ أحد.
//   ‏٢) ومركزُ PicPos يفتح **النسخةَ** لا الأصل — وإلّا كان الفوركُ ملفّاً
//       ميّتاً والشاشةُ القديمةُ ما زالت هي التي تُرى.
//
// ⚠️ **وسببُ النسخِ نفسُه يُحرَس**: «تقادم الذمم» نُسخت لأنّ ألوانَها ثابتةٌ
//    لا تتبع الثيم (‏أرضيّةٌ `0xFFF1F5F9`، وترويسةٌ `AppColors.surface`،
//    وصفٌّ متأخّرٌ `0xFFFFEBEB`) — فلو عادت ألوانٌ ثابتةٌ إلى النسخة لضاع
//    سببُ وجودها وعادت الشاشةُ بيضاءَ فاقعةً في الوضع الغامق.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نسخةٌ واحدة: مسارُ النسخة، ومسارُ الأصل، واسما الصنفَين.
class _Fork {
  const _Fork(this.picpos, this.shared, this.picposClass, this.sharedClass);
  final String picpos;
  final String shared;
  final String picposClass;
  final String sharedClass;
}

const _forks = <_Fork>[
  _Fork(
    'lib/presentation/reports_picpos/screens/ar_aging_report_picpos_screen.dart',
    'lib/presentation/screens/reports/ar_aging_report_screen.dart',
    'ArAgingReportPicposScreen',
    'ArAgingReportScreen',
  ),
];

/// ألوانٌ ثابتةٌ مسموحةٌ في نسخ PicPos — **دلالةٌ لا سطح**.
///
/// شرائحُ أعمار الذمم (أخضر «سليم» · أصفر «متأخّر» · أحمر «خطر» · بنفسجي
/// «فوق ٩٠») تُقرأ في الوضعين، ومعناها هو اللون. أمّا الأسطحُ فتتبع الثيم.
///
/// ⚠️ بحروفٍ صغيرةٍ كلُّها، والمقارنةُ تُصغّر الطرفَ الآخرَ أيضاً: أوّلُ صيغةٍ
/// كتبتُها كبّرت النصَّ كلَّه فصارت `0x` هي `0X` ولم تطابق شيئاً — فاحمرَّ
/// الحارسُ على ألوانٍ مسموحة.
const _allowedLiteralColors = <String>{
  '0xff059669',
  '0xfff59e0b',
  '0xffef4444',
  '0xff7c3aed',
};

String _code(String p) => File(p)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  const picposHub =
      'lib/presentation/reports_picpos/screens/reports_picpos_screen.dart';
  const uralHub = 'lib/presentation/screens/reports_screen.dart';

  for (final f in _forks) {
    group(f.picposClass, () {
      test('النسخةُ موجودةٌ والأصلُ باقٍ', () {
        expect(File(f.picpos).existsSync(), isTrue);
        expect(File(f.shared).existsSync(), isTrue,
            reason: 'الأصلُ المشترك حُذف — وUralCash تفتحه.');
      });

      test('ومركزُ UralCash ما زال يفتح الأصل', () {
        expect(_code(uralHub).contains('${f.sharedClass}()'), isTrue,
            reason: 'مركزُ UralCash لم يعد يفتح ${f.sharedClass} — النسخُ '
                'لا يجوز أن يمسّ الطرفَ الآخر.');
      });

      test('ومركزُ PicPos يفتح النسخةَ لا الأصل', () {
        final hub = _code(picposHub);
        expect(hub.contains('${f.picposClass}()'), isTrue,
            reason: 'مركزُ PicPos لا يفتح النسخةَ — فالفوركُ ملفٌّ ميّت.');
        expect(RegExp(r'\b' + f.sharedClass + r'\(\)').hasMatch(hub), isFalse,
            reason: 'مركزُ PicPos ما زال يفتح ${f.sharedClass} — فالمستخدمُ '
                'يرى الشاشةَ القديمة مهما بُني في النسخة.');
      });

      test('والنسخةُ على إطار PicPos لا AppBar', () {
        final src = _code(f.picpos);
        expect(src.contains('PicPosScreenScaffold('), isTrue);
        expect(src.contains('AppBar('), isFalse,
            reason: 'النسخةُ ما زالت ترسم `AppBar` — وهو عينُ ما نُسخت منه.');
      });

      test('ومرشِّحاتُها في الشريط لا في الترويسة', () {
        expect(_code(f.picpos).contains('PicPosFilterStrip('), isTrue,
            reason: 'أمرُ المالك: المرشِّحاتُ تنزل من الترويسة إلى الشريط '
                'كما في التصميم.');
      });

      test('ولا لونَ سطحٍ ثابتٍ فيها — وهو سببُ نسخها', () {
        final offenders = RegExp(r'Color\((0x[0-9A-Fa-f]{8})\)')
            .allMatches(_code(f.picpos))
            .map((m) => m.group(1)!.toLowerCase())
            .where((c) => !_allowedLiteralColors.contains(c))
            .toSet();
        expect(offenders, isEmpty,
            reason: 'لونٌ ثابتٌ عاد إلى نسخة PicPos (${offenders.join(' · ')})'
                ' — وهو ما يجعل الشاشةَ بيضاءَ فاقعةً في الوضع الغامق، وهو '
                'سببُ النسخ أصلاً. استعمل `context.picpos*`.');
      });
    });
  }
}
