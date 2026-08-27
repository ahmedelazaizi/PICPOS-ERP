// حارسُ العقد: خطوةٌ قديمةٌ تُعيد بناءَ جدولٍ مُزامَنٍ تُصرِّح أعمدةَ المزامنة.
//
// ═══ فئةُ العطب ═══
//
// `m.alterTable` **تبني تعريفَ اليوم** وتنسخ البيانات بـ
// `INSERT INTO new SELECT <أعمدةِ اليوم> FROM old`. فعمودٌ أُضيف إلى تعريف
// الجدول **بعد** تلك الخطوة يُطلَب من جدولٍ قديمٍ لا يملكه ⇒
// `no such column: global_id`.
//
// و`_safeMigrate` تعدّ «no such column» خطأً عديمَ الأثر **فتبتلعه**. فتضيع
// **الخطوةُ كلُّها** — لا العمودُ الجديدُ وحدَه — وتُختَم القاعدةُ بالرقم
// التالي وكأنّ شيئاً لم يكن. و`from < N` لا يعود يفحصها أبداً.
//
// 🔴 **وقع فعلاً 2026-08-27:** إضافةُ أعمدةِ المزامنة (v167) إلى
// `TableOrders` و`Bookings` و`BookingResources` و`TableOrderPayments` كسرت
// **ستَّ** خطواتٍ أقدم (v156 · v157 · v158 · v161×2 · v162). والمكشوفُ منها
// باختبارٍ **اثنتان فقط** (`bookings_v161_upgrade_test.dart`)؛ وثلاثُ خطوات
// `table_orders` لم يكن لها اختبارُ ترقيةٍ أصلاً — كانت ستسقط على قواعد
// المستخدمين بلا أن يحمرَّ شيء.
//
// ═══ ولماذا الشرطُ مقيَّدٌ بالإصدار ═══
//
// `newColumns` تعني «لا تقرأ هذا العمودَ من القديم — اكتب الافتراض». فهي
// **صحيحةٌ** لخطوةٍ أقدمَ من v167 (العمودُ لم يكن موجوداً بعد)، و**مُتلِفةٌ**
// لخطوةٍ أحدثَ منها: القاعدةُ تكون قد نالت العمودَ وقيمتَه في v167، فتصريحُه
// يمسح المعرّفاتِ العالميّةَ القائمةَ ويستبدلها بـ NULL.
//
// والترتيبُ هو ما يجعل ذلك آمناً: الخطواتُ تُنفَّذ تصاعديّاً، فأيُّ خطوةٍ
// بعد v167 تجري على قاعدةٍ مرّت بـ v167 حتماً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الإصدارُ الذي أضاف أعمدةَ المزامنة للفئة التشغيليّة.
const _kSyncColumnsVersion = 167;

/// أعمدةُ المزامنة كما تُكتَب في Dart.
const _syncColumns = ['globalId', 'lastModifiedAt', 'originClientId', 'rowVersion'];

/// جداولُ الفئة التشغيليّة التي نالت الأعمدةَ في v167 — بأسماء الـgetter.
///
/// `deletedAt` **ليس** في [_syncColumns] عمداً: ثلاثةُ جداولِ حجوزاتٍ وُلدت
/// به، فاشتراطُه كان سيُنتج بلاغاً كاذباً عليها — واشتراطُه على غيرها
/// يُنتج نفسَ الخطأ في الاتّجاه المقابل. فالفحصُ على الأربعةِ المؤكَّدة.
const _v167Tables = <String>{
  'employees',
  'tableSections', 'restaurantTables', 'tableOrders', 'tableOrderItems',
  'tableReservations', 'tableOrderPayments',
  'kitchenStations', 'categoryStationMappings',
  'workOrders', 'workOrderItems',
  'bookingResources', 'bookingServices', 'bookings', 'bookingReminders',
  'salesRoutes', 'routeVisits', 'salesRepTargets', 'salesRepCollections',
};

/// نداءُ `alterTable` واحدٌ مستخرَجٌ من مصدر الهجرات.
typedef _Call = ({String table, int version, String body, int line});

List<_Call> _alterTableCalls() {
  final out = <_Call>[];
  final dir = Directory('lib/data/database/migrations');
  for (final f in dir.listSync()) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final src = f.readAsStringSync();
    final versionRe = RegExp(r'if\s*\(\s*from\s*<\s*(\d+)\s*\)');
    final callRe = RegExp(r'alterTable\(\s*TableMigration\(\s*(\w+)');

    for (final m in callRe.allMatches(src)) {
      // آخرُ `if (from < N)` قبلَ النداء هو الخطوةُ التي يقع فيها.
      var version = -1;
      for (final v in versionRe.allMatches(src)) {
        if (v.start > m.start) break;
        version = int.parse(v.group(1)!);
      }

      // جسمُ النداء بعدِّ الأقواس من `TableMigration(`.
      final open = src.indexOf('(', src.indexOf('TableMigration', m.start));
      var depth = 1;
      var i = open + 1;
      while (i < src.length && depth > 0) {
        if (src[i] == '(') depth++;
        if (src[i] == ')') depth--;
        i++;
      }
      out.add((
        table: m.group(1)!,
        version: version,
        body: src.substring(open + 1, i - 1),
        line: '\n'.allMatches(src.substring(0, m.start)).length + 1,
      ));
    }
  }
  return out;
}

void main() {
  final calls = _alterTableCalls();

  group('مرساةُ الكشف — قبلَ أيِّ حكم', () {
    test('وُجدت نداءاتُ إعادةِ بناءٍ أصلاً', () {
      // بلا هذه المرساةِ يمرّ الفحصُ أخضرَ لو تغيّر شكلُ النداء أو مسارُ
      // الهجرات — «لا نداءَ مخالف» على قائمةٍ فارغة.
      expect(calls, isNotEmpty,
          reason: 'لم يُعثَر على `alterTable(TableMigration(` — تغيّر الشكلُ '
              'أو المسار، والحارسُ صار يقيس فراغاً.');
    });

    test('ويُنسَب كلُّ نداءٍ إلى إصدارِه', () {
      expect(calls.every((c) => c.version > 0), isTrue,
          reason: 'نداءٌ خارجَ أيِّ `if (from < N)` — إمّا تغيّر الشكلُ أو '
              'ثمّة هجرةٌ غيرُ مشروطةٍ بإصدار.');
    });

    test('ويُقرأ جسمُ النداء كاملاً — قوسٌ داخليٌّ لا يقطعه', () {
      // `TableMigration(x, newColumns: [a.b, c.d])` فيه أقواسٌ ضمنيّة.
      // مرساةٌ على نداءٍ نعلم أنّ له `newColumns`.
      final withCols = calls.where((c) => c.body.contains('newColumns'));
      expect(withCols, isNotEmpty,
          reason: 'لا نداءَ فيه `newColumns` ⇒ الاستخراجُ يقطع الجسمَ باكراً');
    });

    test('وقائمةُ جداول v167 ليست فارغة', () {
      expect(_v167Tables, isNotEmpty);
    });
  });

  test('🔴 كلُّ إعادةِ بناءٍ أقدمَ من v167 تُصرِّح أعمدةَ المزامنة', () {
    final offenders = <String>[];

    for (final c in calls) {
      if (!_v167Tables.contains(c.table)) continue;
      if (c.version > _kSyncColumnsVersion) continue; // نالتها القاعدةُ سلفاً

      final missing = _syncColumns
          .where((col) => !c.body.contains('${c.table}.$col'))
          .toList();
      if (missing.isNotEmpty) {
        offenders.add(
            'v${c.version} → ${c.table} (سطر ${c.line}) ينقصه: ${missing.join('، ')}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'خطواتُ هجرةٍ تُعيد بناءَ جدولٍ مُزامَنٍ بلا تصريحِ أعمدته:\n'
          '  ${offenders.join('\n  ')}\n\n'
          '`alterTable` تنسخ بـ`SELECT <أعمدةِ اليوم> FROM old`، فقاعدةٌ '
          'أقدمُ من v167 لا تملك العمودَ فترمي `no such column` — '
          'و`_safeMigrate` تبتلعها فتضيع **الخطوةُ كلُّها** وتُختَم القاعدةُ '
          'بالرقم التالي. أضِف الأعمدةَ في `newColumns`.',
    );
  });

  test('🔴 ولا خطوةَ أحدثَ من v167 تُصرِّحها — فتمسح المعرّفاتِ القائمة', () {
    // الاتّجاهُ المعاكس، وهو أخطر: `newColumns` تكتب الافتراضَ فوقَ القيمة.
    // فخطوةٌ بعد v167 تُصرِّح `globalId` تمسح المعرّفاتِ العالميّةَ كلَّها —
    // وكلُّ صفٍّ يصير مجهولَ الهويّة على الخادم فيتضاعف عند سحب الدلتا.
    final offenders = <String>[];
    for (final c in calls) {
      if (!_v167Tables.contains(c.table)) continue;
      if (c.version <= _kSyncColumnsVersion) continue;
      final declared =
          _syncColumns.where((col) => c.body.contains('${c.table}.$col'));
      if (declared.isNotEmpty) {
        offenders.add('v${c.version} → ${c.table} (سطر ${c.line}) '
            'يُصرِّح: ${declared.join('، ')}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'تصريحٌ بعد v167 يمسح القيمَ القائمة:\n  '
            '${offenders.join('\n  ')}');
  });

  test('والستُّ المعروفةُ مغطّاةٌ — على البلاغ نفسِه', () {
    // فحصٌ بالأسماء لا بالعدّ: لو أُعيدت تسميةُ خطوةٍ أو حُذفت، يجب أن
    // يُلاحَظ بدل أن يتقلّص المدى صامتاً.
    final covered = calls
        .where((c) => _v167Tables.contains(c.table))
        .where((c) => c.version <= _kSyncColumnsVersion)
        .map((c) => '${c.version}:${c.table}')
        .toSet();

    expect(
      covered,
      containsAll(<String>{
        '156:tableOrders',
        '157:tableOrders',
        '158:tableOrderPayments',
        '161:bookings',
        '161:bookingResources',
        '162:bookingResources',
      }),
      reason: 'اختفت خطوةٌ كانت مرصودةً — إمّا حُذفت أو تغيّر إصدارُها. '
          'راجِع بدل أن تُحدّث القائمةَ آليّاً.',
    );
  });
}
