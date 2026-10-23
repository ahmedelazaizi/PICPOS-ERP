// حارسُ العقد: إصدارُ حزمةِ التنصيب يطابق `pubspec.yaml`.
//
// ═══ فئةُ العطب ═══
//
// Inno Setup لا يقرأ Dart ولا `pubspec.yaml` إطلاقاً. فرقمُ الإصدار مكتوبٌ
// **يدويّاً** في `installer/setup.iss`، ولا شيءَ يربطه بالمصدر.
// (‏كان اسمُه `UralCash.iss` حتى 2026-09-02؛ أُعيدت تسميتُه لأنّ محتواه محايدٌ
//  بين العلامتَين والمنتَجُ الحيُّ هو PicPos.)
//
// 🔴 **وقع فعلاً:** رُفع `pubspec` إلى `3.1.3+248` يوم 2026-08-03 في كوميتٍ
// عنوانُه «نظافة الإصدار»، وآخرُ لمسةٍ للـ`iss` كانت 2026-07-26. فبقيت
// `3.1.2.247`، وحُزمت في 2026-08-27 نسخةٌ تحمل كودَ `3.1.3+248` وتُعلن
// نفسَها `3.1.2.247`.
//
// ═══ ولماذا هذا أكثرُ من تجميل ═══
//
//  ‏١) Inno يستعمل `AppVersion` في **كشف الترقية**. نسختان مختلفتان تحملان
//     الرقمَ نفسَه ⇒ المُنصِّبُ لا يرى الثانيةَ ترقيةً.
//  ‏٢) وهو ما يظهر في «إضافة أو إزالة البرامج». فالدعمُ الفنّيُّ يسأل
//     العميلَ عن نسخته فيُجيب برقمٍ لا يدلّ على ما يشغّله فعلاً — وتُطارَد
//     أعطابٌ في كودٍ ليس عنده.
//
// ═══ صيغةُ التحويل ═══
//
// `pubspec` يكتب `3.1.3+248`، وInno يريد أربعةَ أرقامٍ منقوطة ⇒ `3.1.3.248`.
// أي أنّ `+build` يصير الرقمَ الرابع.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `3.1.3+248` → `3.1.3.248`
String _pubspecToInnoVersion(String pubspecVersion) =>
    pubspecVersion.replaceAll('+', '.');

void main() {
  late String pubspecVersion;
  late String innoVersion;

  setUpAll(() {
    final pub = File('pubspec.yaml').readAsStringSync();
    final pm = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pub);
    pubspecVersion = pm?.group(1) ?? '';

    final iss = File('installer/setup.iss').readAsStringSync();
    final im = RegExp(r'#define\s+AppVersion\s+"([^"]+)"').firstMatch(iss);
    innoVersion = im?.group(1) ?? '';
  });

  group('مرساةُ الكشف — قبلَ أيِّ حكم', () {
    // الفحصُ الرئيسُ يقارن نصّين؛ ولو عاد كلاهما فارغاً لتساويا ومرّ أخضرَ
    // وهو لا يقيس شيئاً.
    test('رقمُ pubspec قُرئ فعلاً', () {
      expect(pubspecVersion, isNotEmpty,
          reason: 'تعذّرت قراءةُ `version:` من pubspec.yaml — تغيّر الشكلُ '
              'أو المسار، والحكمُ أدناه باطل.');
      expect(pubspecVersion, matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')),
          reason: 'شكلٌ غيرُ متوقَّع: «$pubspecVersion» — راجِع التحويل.');
    });

    test('ورقمُ Inno قُرئ فعلاً', () {
      expect(innoVersion, isNotEmpty,
          reason: 'تعذّرت قراءةُ `#define AppVersion` من setup.iss');
      expect(innoVersion, matches(RegExp(r'^\d+\.\d+\.\d+\.\d+$')),
          reason: 'Inno يريد أربعةَ أرقامٍ منقوطة: «$innoVersion»');
    });

    test('والتحويلُ يعمل — على البلاغ نفسِه', () {
      // نفسُ الرقمين اللذين افترقا فعلاً.
      expect(_pubspecToInnoVersion('3.1.3+248'), '3.1.3.248');
      expect(_pubspecToInnoVersion('3.1.2+247'), '3.1.2.247');
      // ولا يتساهل: رقمان مختلفان يبقيان مختلفَين.
      expect(_pubspecToInnoVersion('3.1.3+248'), isNot('3.1.2.247'));
    });
  });

  test('🔴 إصدارُ حزمةِ التنصيب يطابق pubspec', () {
    expect(
      innoVersion,
      _pubspecToInnoVersion(pubspecVersion),
      reason: 'حزمةُ التنصيب تُعلن «$innoVersion» والكودُ «$pubspecVersion».\n\n'
          'Inno لا يقرأ pubspec، فالرقمان يفترقان بصمت. والحزمةُ حينئذٍ '
          'تكذب على من يقرؤها: كشفُ الترقية يعتمد على `AppVersion`، '
          'و«إضافة أو إزالة البرامج» تعرضه — فنسختان مختلفتان بالرقم نفسِه '
          'لا تُرقّي إحداهما الأخرى، والدعمُ يطارد عطباً في كودٍ ليس عند '
          'العميل.\n\n'
          'حدِّث `#define AppVersion` في `installer/setup.iss` إلى '
          '«${_pubspecToInnoVersion(pubspecVersion)}» في نفس الكوميت الذي '
          'يرفع pubspec.',
    );
  });

  test('🔴 وسكربتُ مثبِّت PicPos (setup_picpos.iss) يطابق pubspec أيضاً', () {
    final iss = File('installer/setup_picpos.iss').readAsStringSync();
    final im = RegExp(r'#define\s+AppVersion\s+"([^"]+)"').firstMatch(iss);
    expect(im?.group(1), _pubspecToInnoVersion(pubspecVersion),
        reason: 'حدِّث `#define AppVersion` في `installer/setup_picpos.iss` '
            'إلى «${_pubspecToInnoVersion(pubspecVersion)}» مع رفع pubspec.');
  });
}