// حارسٌ بنيويّ — ربطُ الخزائن بحساباتها موصولٌ بالإقلاع، ومصدرُ الأب واحد.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// نفسُ فئة `startup_repairs_wired_test` المجاور: دالّةُ إصلاحٍ **موجودةٌ
// ومختبَرةٌ وصحيحة**، ولا شيءَ يناديها.
//
// `linkUnlinkedSafesToSubAccounts` تمنح كلَّ خزنةٍ بلا `linkedAccountId`
// حسابَها الفرعيَّ تحت أب الخزائن. وبدونها تسقط الخزنةُ بحسب **نوعها** على
// حسابٍ مشترك (`kSafeTypeAccountCode`: cash→1111)، فدرجُ الكاشير والصندوقُ
// المركزيُّ رقمٌ واحدٌ في الأستاذ لا ينفصل.
//
// والوصلُ بالإقلاع **ضرورةٌ لا تحسين**: `createSafeWithLinkedAccount` تربط
// ما يُنشئه المستخدم، لكنّ الخزائنَ **المبذورة** (‏صندوق الكاشير · الحساب
// البنكي · كليك · الصندوق الرئيسي) تُدرَج في `database_seeder.dart` بإدراجٍ
// عارٍ — فكلُّ تنصيبٍ جديدٍ يولد بالعطب، ولا زرَّ يصلحه.
//
// حارسٌ بنيويٌّ لا سلوكيّ: صحّةُ الإصلاح مقيسةٌ في
// `test/integration/safe_sub_accounts_backfill_test.dart`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _startupPath = 'lib/data/database/database_startup.dart';
const _treasuryPath = 'lib/data/database/daos/treasury_dao.dart';

/// سطرُ نداءٍ فعليّ لا ذكرٌ في تعليق.
bool _isCall(String line, String name) {
  final t = line.trimLeft();
  if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) {
    return false;
  }
  return line.contains('$name(');
}

void main() {
  final startup = File(_startupPath);
  final treasury = File(_treasuryPath);

  test('الإقلاعُ ينادي `linkUnlinkedSafesToSubAccounts`', () {
    expect(startup.existsSync(), isTrue, reason: 'مسارُ ملفّ الإقلاع تغيّر');

    final called = startup
        .readAsLinesSync()
        .any((l) => _isCall(l, 'linkUnlinkedSafesToSubAccounts'));

    expect(
      called,
      isTrue,
      reason: 'الخزائنُ المبذورةُ تُدرَج بلا ربط، فبلا وصلٍ بالإقلاع يولد '
          'كلُّ تنصيبٍ جديدٍ وكلُّ خزائنه النقدية على حسابٍ واحد — '
          'ولا رسالةَ خطأٍ واحدة تدلّ على السبب.',
    );
  });

  test('مسارا الإنشاء والإصلاح يشتركان في `_resolveSafesParentAccount`', () {
    // لو افترق النصّان لأمكن أن يُنشئ أحدُهما تحت `1110` والآخرُ تحت `111`
    // في نفس التنصيب، فتتشتّت حساباتُ الخزائن على أبوين ولا يجمعها تقرير.
    // والفرعان المتشابهان يفترقان بأوّل تعديلٍ على أحدهما.
    expect(treasury.existsSync(), isTrue, reason: 'مسارُ DAO الخزينة تغيّر');
    final lines = treasury.readAsLinesSync();

    final callSites =
        lines.where((l) => _isCall(l, '_resolveSafesParentAccount')).length;
    expect(
      callSites,
      greaterThanOrEqualTo(2),
      reason: 'يناديه مسارُ الإنشاء (`createSafeWithLinkedAccount`) ومسارُ '
          'الإصلاح (`linkUnlinkedSafesToSubAccounts`) كلاهما.',
    );

    // وقائمةُ أكواد الأب مكتوبةٌ في **موضعٍ واحد**: نسخةٌ ثانيةٌ منها بجوار
    // الدالّة المشتركة تعني أن مساراً عاد يقرّر الأبَ لنفسه.
    final codeListSites = lines
        .where((l) => !l.trimLeft().startsWith('//'))
        .where((l) => l.contains("'1110'") && l.contains("'111'"))
        .length;
    expect(
      codeListSites,
      1,
      reason: 'قائمةُ ["1110", "111"] داخل `_resolveSafesParentAccount` '
          'وحدَها. تكرارُها يعيد فئةَ العطب: أبوان مختلفان في تنصيبٍ واحد.',
    );
  });

  test('ضابط: الإصلاحُ المجاور (قيودُ الفواتير) لسه موصولاً', () {
    // لو انفكّ هذا أيضاً فالمشكلةُ أوسعُ من بندٍ واحد، والحارسُ فوق وحدَه
    // كان سيمرّ صامتاً على تجهيزةٍ فقدت الاثنين.
    final called = startup
        .readAsLinesSync()
        .any((l) => _isCall(l, 'repairAllMissingInvoiceJEs'));
    expect(called, isTrue);
  });
}
