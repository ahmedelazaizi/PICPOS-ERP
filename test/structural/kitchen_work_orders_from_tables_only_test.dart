// حارسٌ بنيويّ — أوامرُ التحضير تُولَد من الطاولات وحدَها.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// `SalesTransactionOrchestrator` كان ينادي `generateKitchenWorkOrder` على
// **كلِّ فاتورة مبيعاتٍ تُنشَأ، بلا أيِّ شرط** — و`saleType` متاحٌ في الدالّة
// نفسِها ومستعملٌ في سطرٍ مجاور، لكنّ نداءَ المطبخ لا يقرأه.
//
// فترتّب عليه ثلاثةُ آثار:
//   ١. **المرتجعُ يذهب إلى المطبخ.** فاتورةٌ بـ`saleType == 'return'` تولّد
//      أمرَ تحضيرٍ كأيِّ بيعة — أصنافٌ مرتجَعةٌ تُطلَب من الطبّاخ ليُحضّرها.
//   ٢. **صنفُ الطاولة يُطلَب مرّتين.** مسارُ الطاولة يُنشئ الأمرَ لحظةَ الطلب
//      في `table_pos_operations.dart`، ثم يولّده المنسّقُ ثانيةً عند التحصيل
//      لأن التحصيلَ يُنشئ فاتورةَ مبيعات.
//   ٣. البيعُ السريعُ من الكاشير يولّده كذلك.
//
// وقرارُ المالك (2026-08-18): **الطاولاتُ وحدَها تُحضَّر.** فالنداءُ أُزيل من
// مسار المبيعات، ومعه `KitchenService.generateKitchenWorkOrder` نفسُها — لم
// يبقَ لها مستدعٍ، وتركُها يعني نسخةً ثانيةً من توجيه المحطّات تُصان.
//
// حارسٌ بنيويٌّ لا سلوكيّ: مسارُ الطاولة يعيش في ودجت، وشاشاتُ هذا المستودع
// لا تُركَّب في اختبارات الويدجت (‏`db.close()` ينتظر مؤقّت drift في المنطقة
// الوهميّة)، فلا سبيلَ لقياس هذا سلوكيّاً من طرفٍ إلى طرف.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _orchestratorPath = 'lib/data/repositories/sales_transaction_orchestrator.dart';
const _kitchenServicePath = 'lib/services/kitchen_service.dart';
const _tablePath = 'lib/presentation/pos/screens/table_pos_operations.dart';

/// سطرُ نداءٍ فعليّ لا ذكرٌ في تعليق.
bool _isCall(String line, String name) {
  final t = line.trimLeft();
  if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) {
    return false;
  }
  return line.contains('$name(');
}

Iterable<String> _callLines(File f, String name) =>
    f.readAsLinesSync().where((l) => _isCall(l, name));

void main() {
  final orchestrator = File(_orchestratorPath);
  final kitchenService = File(_kitchenServicePath);
  final table = File(_tablePath);

  test('الملفّاتُ الثلاثةُ موجودةٌ — وإلّا فالحارسُ يحرس عدماً', () {
    expect(orchestrator.existsSync(), isTrue, reason: _orchestratorPath);
    expect(kitchenService.existsSync(), isTrue, reason: _kitchenServicePath);
    expect(table.existsSync(), isTrue, reason: _tablePath);
  });

  test('مسارُ المبيعات لا يولّد أمرَ تحضير', () {
    expect(
      _callLines(orchestrator, 'generateKitchenWorkOrder'),
      isEmpty,
      reason: 'فاتورةُ المبيعات تولّد أمرَ تحضيرٍ مرّةً أخرى: المرتجعُ يذهب '
          'إلى المطبخ، وصنفُ الطاولة يُطلَب مرّتين. الطاولاتُ وحدَها تُحضَّر.',
    );
  });

  test('مسارُ المبيعات لا يُنشئ أمرَ تحضيرٍ بنداءٍ مباشرٍ كذلك', () {
    // إغلاقُ البابِ الخلفيّ: لو أُزيلت الخدمةُ الوسيطةُ ونُودي الـDAO رأساً
    // لَعاد العطبُ نفسُه بوجهٍ آخر.
    expect(
      _callLines(orchestrator, 'createWorkOrder'),
      isEmpty,
      reason: 'مسارُ المبيعات ينشئ أمرَ تحضيرٍ مباشرةً',
    );
  });

  test('`generateKitchenWorkOrder` أُزيلت — لا نسخةَ ثانيةً لتوجيه المحطّات',
      () {
    // مُدرِكٌ للتعليقات عمداً: ملحوظةٌ تشرح **لماذا** أُزيلت مطلوبةٌ ومفيدة،
    // والممنوعُ أن يعود التعريفُ أو نداؤه — لا أن يُذكَر الاسمُ في سطرِ شرح.
    expect(
      kitchenService
          .readAsLinesSync()
          .where((l) => _isCall(l, 'generateKitchenWorkOrder')),
      isEmpty,
      reason: 'الدالّةُ بلا مستدعٍ، وتركُها يُبقي نسخةً ثانيةً من منطق '
          'التصنيف→المحطة تُصان بجوار نسخة مسار الطاولات',
    );
  });

  test('مسارُ الطاولة ما زال يولّد أمرَ التحضير — المصدرُ الوحيدُ الباقي', () {
    expect(
      _callLines(table, 'createWorkOrder'),
      isNotEmpty,
      reason: 'لو سقط هذا النداءُ لَما وصل المطبخَ شيءٌ إطلاقاً',
    );
  });
}
