// `attachment_blobs` **خارجَ كلِّ قائمةِ سحبٍ — عمداً**.
//
// ═══ 🔴 لماذا حارسٌ بنيويٌّ لهذا بالذات ═══
//
// لأنّ الجدولَ يبدو **منسيّاً** لمن يقرأ القوائمَ بعد شهر: كلُّ جدولٍ
// آخرَ فيها، وهو وحدَه خارجها. فيأتي قارئٌ حسنُ النيّة «يسدّ الفجوة»
// فيضيفه — ولا يسقط بذلك اختبارُ سلوكٍ واحد.
//
// وما يقع حينها مقيسٌ لا متوقَّع:
//   • مُسلسِلُ `_getSyncPull` يُسقط كلَّ `List<int>` بـ`continue`، فلا
//     تصل بايتةٌ واحدة — **والصفُّ يصل بلا محتواه**.
//   • ثمّ تنتفخ حمولةُ السحب الدوريِّ بصفوفِ خبيئةٍ لا معنى لها على
//     الجهاز الآخر.
//
// فالخسارةُ صامتةٌ تماماً: مرفقاتٌ «مُزامَنةٌ» وكلُّها فارغة.
//
// ⚠️ **وحارسُ `sync_coverage_guard` لا يمسك هذا**: كشفُه مطابقةُ نصٍّ على
// سطحِ المزامنة، و`attachment_blobs` مذكورٌ في `api_data_handler` لأنّ
// منفذَ الرفع يكتبه — فيبدو «مُغطّى» وهو خارجٌ عمداً. وهذا الملفُّ هو
// السلطةُ لا ذاك.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// جسمُ قائمةٍ من إعلانها إلى مُنهيها — **بالسطور لا بمطابقةِ نصٍّ حرفيّ**:
/// التعليقاتُ العربيّةُ بين الأسطر تكسر أيَّ مرساةٍ حرفيّة.
String _listBody(String path, String decl) {
  final raw = File(path).readAsStringSync();
  final lines = raw.split('\n');
  final starts = [for (var i = 0; i < lines.length; i++) if (lines[i].contains(decl)) i];
  expect(starts.length, 1,
      reason: 'الإعلانُ «$decl» وُجد ${starts.length} مرّةً في $path — '
          'الحارسُ يقرأ غيرَ ما يظنّ.');
  final start = starts.first;
  for (var k = start + 1; k < lines.length; k++) {
    final t = lines[k].trimRight();
    if (t == '  ];' || t == '  };') {
      return lines.sublist(start, k).join('\n');
    }
  }
  fail('لم يُعثَر على مُنهي القائمة «$decl» في $path');
}

/// نصٌّ بلا أسطر التعليق — فذكرُ الاسم في شرحٍ ليس عضويّةً في القائمة.
String _noComments(String body) => [
      for (final line in body.split('\n'))
        if (!line.trimLeft().startsWith('//')) line,
    ].join('\n');

const _lists = <String, (String, String)>{
  'pullTables': (
    'lib/services/delta_pull_service.dart',
    'static const List<String> pullTables'
  ),
  'branchScopedPullTables': (
    'lib/services/delta_pull_service.dart',
    'static const Set<String> branchScopedPullTables'
  ),
  'deltaOnlyTables': (
    'lib/services/delta_pull_service.dart',
    'static const Set<String> deltaOnlyTables'
  ),
  'branchScopedMasterPullTables': (
    'lib/services/delta_pull_service.dart',
    'static const Set<String> branchScopedMasterPullTables'
  ),
  '_syncPullTables': (
    'lib/services/api/api_handler.dart',
    'static const _syncPullTables'
  ),
  '_transactionalPullTables': (
    'lib/services/api/api_handler.dart',
    'static const _transactionalPullTables'
  ),
  'namespacedTables': (
    'lib/services/id_namespace_service.dart',
    'static const List<String> namespacedTables'
  ),
  '_syncHardenedTables': (
    'lib/data/database/database.dart',
    'static const _syncHardenedTables'
  ),
};

/// القوائمُ التي **يجب** أن يكون الوصفُ فيها. و`branchScopedMasterPullTables`
/// خارجها عمداً: المرفقُ بياناتُ عملٍ لا بياناتٌ مرجعيّةٌ تُزوَّد قبل الدخول.
const _mustHaveAttachments = <String>[
  'pullTables',
  'branchScopedPullTables',
  'deltaOnlyTables',
  '_syncPullTables',
  '_transactionalPullTables',
  'namespacedTables',
  '_syncHardenedTables',
];

/// ⚠️ **قراءةٌ كسولةٌ لا `setUpAll`.** لو عميَ القارئُ داخلَ
/// `setUpAll` لسقط **الملفُّ كلُّه بصفرِ ناجحين** — وهي صورةٌ
/// لا تُفرِّق بين «الحارسُ أمسك شيئاً» و«الملفُّ لم يُحمَل».
/// فالقراءةُ هنا عند أوّل طلب، وفحصا التعريف والمصفاة
/// يبقيان خضراوَين فيتبيّن أنَّ الملفّ يعمل والقارئَ وحدَه عمي.
Map<String, String>? _cache;

Map<String, String> get bodies => _cache ??= {
      for (final e in _lists.entries)
        e.key: _noComments(_listBody(e.value.$1, e.value.$2)),
    };

void main() {

  group('حراسةُ الحارس', () {
    test('القوائمُ الثماني قُرئت غيرَ فارغة', () {
      for (final e in bodies.entries) {
        expect(e.value.length, greaterThan(40),
            reason: 'القائمةُ «${e.key}» قُرئت فارغةً ⇒ الحارسُ يقيس لا شيء.');
      }
    });

    test('وكلُّ قائمةٍ تحمل عضواً معروفاً — مرساةٌ موجبة', () {
      // بلا هذه لكان «غيابُ attachment_blobs» صحيحاً حتّى لو قرأنا
      // القائمةَ الخطأ تماماً.
      const anchors = <String, String>{
        'pullTables': "'products'",
        'branchScopedPullTables': "'sales_invoices'",
        'deltaOnlyTables': "'fixed_assets'",
        'branchScopedMasterPullTables': "'branches'",
        '_syncPullTables': "'products'",
        '_transactionalPullTables': "'sales_invoices'",
        'namespacedTables': "'users'",
        '_syncHardenedTables': "'users'",
      };
      anchors.forEach((list, member) {
        expect(bodies[list], contains(member),
            reason: 'القائمةُ «$list» بلا عضوِها المعروف $member ⇒ '
                'القارئُ يقرأ كتلةً أخرى.');
      });
    });

    test('ونزعُ التعليقات لا يبتلع كوداً — على البلاغ نفسِه', () {
      const sample = "  // 'attachment_blobs' مذكورٌ هنا شرحاً\n"
          "    'attachments',";
      final stripped = _noComments(sample);
      expect(stripped.contains("'attachment_blobs'"), isFalse);
      expect(stripped.contains("'attachments'"), isTrue);
    });
  });

  test('🔴 و`attachment_blobs` ليس في أيّ قائمةٍ من الثماني', () {
    final offenders = <String>[
      for (final e in bodies.entries)
        if (e.value.contains("'attachment_blobs'")) e.key,
    ];
    expect(offenders, isEmpty,
        reason: 'البايتاتُ دخلت مسارَ السحب في: ${offenders.join(' · ')}\n'
            '— والسلكُ يُسقط كلَّ blob بـ`continue`، فالصفُّ يصل فارغاً '
            'وحمولةُ السحب تنتفخ بلا فائدة. أخرِجه.');
  });

  test('والوصفُ `attachments` في السبعِ التي تخصّه', () {
    final missing = <String>[
      for (final name in _mustHaveAttachments)
        if (!bodies[name]!.contains("'attachments'")) name,
    ];
    expect(missing, isEmpty,
        reason: 'الوصفُ غائبٌ عن: ${missing.join(' · ')} — '
            'فمرفقٌ يُرفَع على جهازٍ لا يراه غيرُه.');
  });

  test('وهو خارجُ `branchScopedMasterPullTables` — بياناتُ عملٍ لا مرجعيّة',
      () {
    expect(bodies['branchScopedMasterPullTables'],
        isNot(contains("'attachments'")),
        reason: 'المرفقاتُ ليست بياناتٍ مرجعيّةً تُزوَّد قبل الدخول: '
            'وصفُها يحمل اسمَ ملفٍّ وملاحظةً على مستندٍ محميّ.');
  });

  test('🔴 و`AttachmentBlobs` بلا أعمدةِ مزامنةٍ — البنيةُ تقاوم الإضافة', () {
    final def = File('lib/data/database/tables/attachment_tables.dart')
        .readAsStringSync();
    final at = def.indexOf('class AttachmentBlobs');
    expect(at, greaterThan(0), reason: 'تعريفُ الجدول تبدّل مكانُه');
    final body = def.substring(at);
    for (final col in const [
      'globalId',
      'lastModifiedAt',
      'deletedAt',
      'originClientId',
      'rowVersion',
    ]) {
      expect(body.contains('get $col'), isFalse,
          reason: 'أُضيف عمودُ مزامنةٍ «$col» إلى `AttachmentBlobs` — '
              'وهو أوّلُ خطوةٍ نحو إدخالها السحبَ. البايتاتُ خبيئةٌ لا '
              'مصدرُ حقيقةٍ على العميل.');
    }
  });

  test('والسببُ ما زال قائماً — الخادمُ يُسقط الـblob على السلك', () {
    // ⚠️ لو زال هذا يوماً، فقرارُ الفصل يُعاد النظرُ فيه بقرارٍ مكتوبٍ
    //    لا بإضافةِ سطرٍ إلى قائمة.
    final api = File('lib/services/api/api_handler.dart').readAsStringSync();
    expect(api, contains('v is List<int>'),
        reason: 'مصفاةُ الـblob على السلك اختفت — أعِد قراءةَ §٨٫٢ قبل أن '
            'تُغيّر شيئاً في هذا الحارس.');
  });
}
