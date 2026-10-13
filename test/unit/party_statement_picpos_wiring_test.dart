// توصيلُ كشف الحساب — خمسةُ مواضعَ في مسار PicPos، وUralCash بلا مساس.
//
// ═══ لماذا حارسٌ على المصدر ═══
//
// شاشةٌ جديدةٌ لا تُفتَح من مكانٍ واحد. وجردُ التسليم قال «ثلاثةُ مواضعَ في
// `parties_picpos`»، والمقيسُ **خمسةٌ**: الموضعان الناقصان في مركز التقارير
// (`reports_picpos_screen.dart`) — مدخلا «كشف حساب العميل» و«كشف حساب
// المورد». وتوصيلُ أربعةٍ من خمسةٍ يعني مدخلاً واحداً يفتح الشاشةَ القديمة
// وهي تبدو صحيحةً تماماً لمن لا يعرف أنّ ثمّة جديدة.
//
// ═══ ولماذا المرساة ═══
//
// ⚠️ الفحصُ السالبُ وحدَه («لا `PartyStatementScreen(` في مسار PicPos») يمرّ
// أخضرَ لو تبدّل اسمُ الصنف يوماً أو حُذفت الملفّاتُ كلُّها. فالمرساةُ أنّ
// **شاشةَ UralCash ما زالت موصولةً بمواضعها هي** — وهي الفحصُ نفسُه بالنمط
// نفسِه، فإن انكسر النمطُ سقطت المرساةُ أوّلاً.
//
// وهذا أيضاً عينُ أمرِ المالك: «نسخةٌ مستقلّةٌ لا تفريع» — لا يُنقَل شيءٌ من
// UralCash ولا يُعدَّل فيها شيء.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_source.dart';

/// مواضعُ PicPos التي تفتح كشفَ الحساب — الخمسةُ المقيسةُ 2026-08-26.
const _picposEntryPoints = <String, int>{
  // زرّا الترويسة («كشف حساب عميل»/«كشف حساب مورد») + فتحُ كشفِ طرفٍ بعينه.
  'lib/presentation/parties_picpos/screens/parties_picpos_screen.dart': 3,
  // مدخلا مركز التقارير.
  'lib/presentation/reports_picpos/screens/reports_picpos_screen.dart': 2,
};

/// مواضعُ UralCash — المرساة. تبقى على شاشتها هي.
const _uralEntryPoints = <String>[
  'lib/presentation/screens/unified_parties_screen.dart',
  'lib/presentation/screens/reports_screen.dart',
  'lib/presentation/screens/customers_screen.dart',
  'lib/presentation/screens/suppliers_screen.dart',
  'lib/presentation/screens/delivery_management_screen.dart',
];

/// عددُ مرّاتِ ظهورِ [needle] في [haystack].
int _countOf(String haystack, String needle) {
  var n = 0;
  var i = haystack.indexOf(needle);
  while (i != -1) {
    n++;
    i = haystack.indexOf(needle, i + needle.length);
  }
  return n;
}

void main() {
  const picposCtor = 'PartyStatementPicposScreen(';
  const uralCtor = 'PartyStatementScreen(';

  group('توصيلُ كشف حساب PicPos', () {
    test('النمطان لا يتداخلان — وإلّا كان الفحصُ كلُّه بلا معنى', () {
      // ⚠️ `PartyStatementPicposScreen(` **لا يحتوي** `PartyStatementScreen(`
      //    لأنّ ما بعد «PartyStatement» هو «Picpos» لا «Screen». ولولا ذلك
      //    لعدَّ الفحصُ السالبُ نداءاتِ النسخة الجديدةِ مخالفات.
      expect(picposCtor.contains(uralCtor), isFalse);
      expect(uralCtor.contains(picposCtor), isFalse);
    });

    test('الخمسةُ كلُّها تفتح نسخةَ PicPos', () {
      final missing = <String>[];
      var total = 0;
      _picposEntryPoints.forEach((path, expected) {
        final f = File(path);
        if (!f.existsSync()) {
          missing.add('$path — الملفُّ غيرُ موجود');
          return;
        }
        final src = path ==
                'lib/presentation/reports_picpos/screens/reports_picpos_screen.dart'
            ? readLibrarySource(path)
            : f.readAsStringSync();
        final n = _countOf(src, picposCtor);
        total += n;
        if (n != expected) {
          missing.add('$path — مواضعُ PicPos $n والمنتظَرُ $expected');
        }
      });

      expect(
        missing,
        isEmpty,
        reason: 'توصيلُ كشف الحساب انكسر:\n${missing.join("\n")}',
      );
      expect(total, 5,
          reason: 'مواضعُ توصيل PicPos صارت $total لا ٥ — '
              'إن كان الموضعُ الجديدُ مقصوداً فحدِّثِ الجدولَ أعلاه بوعي');
    });

    test('لا موضعَ في مسار PicPos يفتح شاشةَ UralCash', () {
      final offenders = <String>[];
      for (final dir in Directory('lib/presentation').listSync()) {
        if (dir is! Directory) continue;
        if (!dir.path.replaceAll('\\', '/').contains('_picpos')) continue;
        for (final e in dir.listSync(recursive: true)) {
          if (e is! File || !e.path.endsWith('.dart')) continue;
          final src = e.readAsStringSync();
          if (_countOf(src, uralCtor) > 0) {
            offenders.add(e.path.replaceAll('\\', '/'));
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'مسارُ PicPos ما زال يفتح شاشةَ UralCash:\n'
            '${offenders.join("\n")}',
      );
    });

    test('المرساة — شاشةُ UralCash ما زالت موصولةً بمواضعها', () {
      // إن سقطت هذه فالنمطُ نفسُه انكسر، والفحصُ السالبُ أعلاه كان يمرّ
      // أخضرَ وهو لا يفحص شيئاً.
      final broken = <String>[];
      for (final path in _uralEntryPoints) {
        final f = File(path);
        if (!f.existsSync()) {
          broken.add('$path — غيرُ موجود');
          continue;
        }
        if (_countOf(f.readAsStringSync(), uralCtor) == 0) {
          broken.add('$path — لا نداءَ لـ$uralCtor');
        }
      }
      expect(
        broken,
        isEmpty,
        reason: 'المرساةُ سقطت — إمّا أنّ شاشةَ UralCash مُسَّت (وهو ممنوع)، '
            'أو أنّ نمطَ البحث لم يعد يطابق شيئاً:\n${broken.join("\n")}',
      );
    });

    test('ملفّاتُ النسخة الجديدة موجودةٌ وثلاثتُها مربوطة', () {
      const dir = 'lib/presentation/party_statement_picpos/screens';
      const shell = '$dir/party_statement_picpos_screen.dart';
      const tabs = '$dir/party_statement_tabs_picpos.dart';
      const export = '$dir/party_statement_export_picpos.dart';

      for (final p in const [shell, tabs, export]) {
        expect(File(p).existsSync(), isTrue, reason: '$p غيرُ موجود');
      }

      final shellSrc = File(shell).readAsStringSync();
      expect(shellSrc.contains("part 'party_statement_tabs_picpos.dart';"),
          isTrue);
      expect(shellSrc.contains("part 'party_statement_export_picpos.dart';"),
          isTrue);
      for (final p in const [tabs, export]) {
        expect(
          File(p).readAsStringSync().startsWith(
              "part of 'party_statement_picpos_screen.dart';"),
          isTrue,
          reason: '$p ليس جزءاً من القشرة',
        );
      }
    });
  });
}
