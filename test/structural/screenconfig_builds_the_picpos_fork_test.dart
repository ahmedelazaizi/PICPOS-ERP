// `ScreenConfig` يبني **فوركَ PicPos** حيث يوجد — لا الشاشةَ المشتركةَ بجواره.
//
// ═══ 🔴 لماذا هذا الحارسُ موجود ═══
//
// شاشةٌ يُعاد تصميمُها في `*_picpos/` ثمّ **لا يُوصَل فرعُ العلامة في
// `ScreenConfig`** تبقى غيرَ مرئيّةٍ لمن يدخل من الباب المعتاد: المدخلُ
// الجانبيُّ يفتح القديمةَ، والجديدةُ تُفتَح من موضعٍ آخرَ وحدَه. فكلُّ ما
// أُعيد تصميمُه لا يراه أحد.
//
// ⚠️ **وقع فعلاً ثلاثَ مرّاتٍ في هذا المستودع**:
//   • «قيود اليومية» (32) — كُشف وأُصلح، وتعليقُه ما زال في
//     `app_main_screen.dart` يصف العطبَ بنصّه.
//   • «دفتر الأستاذ» (36) · «مراكز التكلفة» (33) · «ربط الحسابات» (31)
//     — كُشفت 2026-09-20 وكلُّ الحرّاس خضراء. وسترُها أنّ حاويةَ
//     «الحسابات» كانت تفتح الفوركَ من تبويباتها فتتجاوز `ScreenConfig`
//     كلَّه. فرفعُ الطيّ وحدَه كان **يُعيد الشاشاتِ القديمةَ إلى
//     الواجهة بلا أن يسقط اختبارٌ واحد**.
//
// فالعطبُ لا يُكشَف بتشغيلٍ ولا باختبارِ ودجت: الشاشتان تعملان، والفرقُ
// شكلٌ لا استثناء.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_source.dart';

const _configFile = 'lib/app_main_screen.dart';

/// نصٌّ بلا أسطر التعليق — فذكرُ صنفٍ في شرحٍ ليس بناءً له.
String _code(String raw) => [
  for (final line in raw.split('\n'))
    if (!line.trimLeft().startsWith('//')) line,
].join('\n');

/// أصنافُ فوركِ PicPos المعرَّفةُ فعلاً في شجرة العرض.
Set<String> _picposForks() {
  final re = RegExp(r'class ([A-Za-z0-9_]+Pic[Pp]os[A-Za-z0-9_]*Screen)\b');
  final out = <String>{};
  for (final f in Directory('lib/presentation').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    for (final m in re.allMatches(f.readAsStringSync())) {
      out.add(m.group(1)!);
    }
  }
  return out;
}

/// جذعُ اسمِ شاشةٍ مشتركة: `XScreen` ← `X`، و`XSettingsScreen` ← `X`.
///
/// ⚠️ **ولاحقةُ `Settings` تُسقَط عمداً**: بعضُ الشاشات
/// المشتركة تحملها وفوركُها لا — `AccountMappingSettingsScreen`
/// مقابل `AccountMappingPicPosScreen`. ومطابقةُ الجذع حرفيّاً
/// **أفلتت عطباً قائماً فعلاً** في أوّل صياغةٍ لهذا الحارس.
String stemOfSharedScreen(String className) {
  var stem = className.endsWith('Screen')
      ? className.substring(0, className.length - 'Screen'.length)
      : className;
  if (stem.endsWith('Settings')) {
    stem = stem.substring(0, stem.length - 'Settings'.length);
  }
  return stem;
}

/// كتلةُ كلِّ `ScreenConfig` من `appScreen:` إلى `label:` — وهو **جسمُ
/// البنّاء** بالضبط.
///
/// ⚠️ والمرساةُ `label:` لا القوسُ المغلق: البنّاءُ يحمل أقواساً متداخلةً
/// (‏`SecurityScreenGate` و`Brand.isPicPos ? … : …`)، وعدُّها يدويّاً
/// يخطئ على أوّل نصٍّ حرفيٍّ فيه قوس.
List<({String screen, String body})> _configs(String code) {
  final out = <({String screen, String body})>[];
  final re = RegExp(r'appScreen: AppScreen\.([A-Za-z0-9_]+),');
  for (final m in re.allMatches(code)) {
    final start = m.end;
    final labelAt = code.indexOf('label:', start);
    if (labelAt == -1) continue;
    out.add((screen: m.group(1)!, body: code.substring(start, labelAt)));
  }
  return out;
}

void main() {
  late String code;
  late Set<String> forks;
  late List<({String screen, String body})> configs;

  setUpAll(() {
    code = _code(readLibrarySource(_configFile));
    forks = _picposForks();
    configs = _configs(code);
  });

  group('حراسةُ الحارس', () {
    test('الملفُّ قُرئ والكتلُ استُخرجت', () {
      expect(code.length, greaterThan(10000));
      expect(
        configs.length,
        greaterThan(40),
        reason:
            'استُخرج ${configs.length} إعداداً فقط ⇒ الكاشفُ مكسور، '
            'وكلُّ حكمٍ بعده باطل.',
      );
    });

    test('وأصنافُ الفورك قُرئت من الشجرة', () {
      expect(forks.length, greaterThan(40));
      expect(forks, contains('GeneralLedgerPicPosScreen'));
      expect(forks, contains('CostCentersPicPosScreen'));
      expect(forks, contains('AccountMappingPicPosScreen'));
    });

    test('🔴 ومرساةٌ موجبة — إعدادٌ مفروكٌ يُكتشَف مفروكاً', () {
      // `chartOfAccounts` مفروكٌ وموصولٌ يقيناً. لو سقط هذا فالكاشفُ
      // يقرأ كتلاً خاطئة، وغيابُ البلاغات بعده صمتٌ لا براءة.
      final coa = configs.where((c) => c.screen == 'chartOfAccounts');
      expect(coa, hasLength(1));
      expect(coa.single.body, contains('Brand.isPicPos'));
      expect(coa.single.body, contains('ChartOfAccountsPicPosScreen'));
    });

    test('🔴 والجذعُ يُسقِط `Settings` — على البلاغ نفسِه', () {
      // الحالةُ التي أفلتت فعلاً.
      expect(
        stemOfSharedScreen('AccountMappingSettingsScreen'),
        'AccountMapping',
      );
      expect(stemOfSharedScreen('GeneralLedgerScreen'), 'GeneralLedger');
    });

    test('ونزعُ التعليقات لا يبتلع كوداً — على البلاغ نفسِه', () {
      const sample =
          '  // Brand.isPicPos مذكورٌ شرحاً\n'
          '  builder: (_) => const XScreen(),';
      final stripped = _code(sample);
      expect(stripped.contains('Brand.isPicPos'), isFalse);
      expect(stripped.contains('XScreen'), isTrue);
    });
  });

  test(
    '🔴 كلُّ إعدادٍ يبني شاشةً مشتركةً لها فوركُ PicPos يحمل فرعَ العلامة',
    () {
      final offenders = <String>[];

      for (final c in configs) {
        // اسمُ الصنف المشترك المبنيّ في هذه الكتلة.
        final shared = RegExp(r'\b([A-Z][A-Za-z0-9_]*Screen)\b')
            .allMatches(c.body)
            .map((m) => m.group(1)!)
            .where((n) => !n.contains('PicPos') && !n.contains('Picpos'))
            .toSet();

        for (final s in shared) {
          // هل لهذا المشترك فوركٌ بنفس الجذع؟
          final stem = stemOfSharedScreen(s);
          final twin = forks.firstWhere(
            (f) => f == '${stem}PicPosScreen' || f == '${stem}PicposScreen',
            orElse: () => '',
          );
          if (twin.isEmpty) continue;
          if (c.body.contains('Brand.isPicPos')) continue;
          offenders.add('AppScreen.${c.screen} → يبني $s والفوركُ $twin موجود');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'مدخلٌ جانبيٌّ يفتح الشاشةَ **القديمة** بينما فوركُ PicPos '
            'مبنيٌّ ويُفتَح من موضعٍ آخرَ وحدَه — فكلُّ ما أُعيد تصميمُه '
            'لا يراه من يدخل من الباب المعتاد:\n'
            '  ${offenders.join('\n  ')}',
      );
    },
  );
}
