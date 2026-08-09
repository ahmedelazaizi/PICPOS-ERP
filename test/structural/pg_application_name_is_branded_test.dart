// ═══════════════════════════════════════════════════════════════════════════
// اسمُ التطبيق المُرسَل إلى PostgreSQL لا بد أن يتبع العلامة.
// ═══════════════════════════════════════════════════════════════════════════
//
// `applicationName` يظهر في `pg_stat_activity` على الخادم. وكان مثبَّتاً نصّاً
// `'URAL-ERP'` في المنتجَين معاً — رغم أن قواعدهما عُزلت لكلّ منتج — فتظهر
// اتصالاتُهما بالاسم نفسه ولا يُفرَّق بينهما عند تشخيصِ قفلٍ أو استعلامٍ ثقيل
// على خادمٍ مشترك.
//
// وهو فحصٌ بنيويّ لا سلوكيّ عن قصد: [Brand] كلُّها `const` تُحسم وقت الترجمة،
// فاختبارٌ يقرأ القيمة يفحص **علامةَ البناء الحالية وحدها** ويمرّ أخضرَ على
// المنتج الآخر وهو مكسور. والمصدرُ هو ما يُنقَل بين المنتجَين بالرقع.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('لا اسمَ منتجٍ مثبَّتٌ نصّاً في applicationName', () {
    final src = File('lib/data/database/connection_io.dart').readAsStringSync();

    final lines = src.split('\n');
    final offenders = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.contains('applicationName:')) continue;
      if (!line.contains(r'${Brand.')) {
        offenders.add('${i + 1}: ${line.trim()}');
      }
    }

    expect(offenders, isEmpty,
        reason: 'اسمُ التطبيق لا يشتقّ من `Brand` — فالمنتجان يظهران بالاسم '
            'نفسه في `pg_stat_activity`:\n${offenders.join('\n')}');
  });
}
