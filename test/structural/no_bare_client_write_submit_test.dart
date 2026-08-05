// حارس بنيوي — ممنوع نداء عارٍ (إطلاق وننسى) لـClientWriteInterceptor من
// طبقات المُنادين.
//
// ── ليه حارس تاني جنب mirror_write_dispatch_test ────────────────────────────
// الحارس ده مكمّل مش مكرّر. `mirror_write_dispatch_test` بيدوّر بـregex على
// `unawaited(ClientWriteInterceptor.` — والصيغة العارية
// `ClientWriteInterceptor.deleteProduct(id).catchError((_) {});` بتعدّي من
// تحته وهي **نفس الدلالة وأسوأ**: `unawaited(...)` على الأقل بتعلن النية
// وبتسجّل الخطأ، والصيغة العارية بـ`.catchError((_) {})` بتبلعه بالكامل.
//
// ── العطل اللي كشف الفجوة ───────────────────────────────────────────────────
// حذف صنف من شاشة الأصناف. `products_controller.deleteProduct` كانت بتطلق
// نداء السيرفر وتنسى، وتحذف محلياً مهما حصل. و`cwi_catalog.deleteProduct:194`
// بيجدول `_scheduleProductsPull` بعد النداء على طول — فلو السيرفر رفض أو
// الشبكة فصلت، السحب ده بيرجّع الصنف **فوراً**، مش في المزامنة الجاية.
// والمستخدم شايف رسالة نجاح.
//
// ونفس فئة العطل دي كانت في التصنيفات واتصلحت في v128
// (categories_controller.dart:150) — الأصناف اتنسيت.
//
// ── العقد ───────────────────────────────────────────────────────────────────
// في `lib/presentation/` و`lib/data/`: أي نداء لـClientWriteInterceptor لازم
// يكون `await` أو `return` أو مُسنَداً لمتغيّر يُفحص. ملفات
// `lib/services/interceptor/` مستثناة — دي تنفيذ المُعترِض نفسه، بيستعمل
// الاسم كـnamespace داخل تعبيرات.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// خط أساس موثَّق — **مش نمطاً مقبولاً**، دي مسارات لسه ممكن تضيع فيها كتابة.
///
/// كل واحد فيهم بيحتاج نفس علاج v128: استنِّ النداء في وضع العميل، وأجهض
/// الكتابة المحلية لو السيرفر رفض. اتساب هنا لأن كل واحد بيغيّر تدفّق شاشة
/// مختلفة وله مخاطرته — والأهم إنه **مش** نفس العطل المُبلَّغ.
///
/// لإزالة سطر: حوّل الموضع لـawait + رفض عند الفشل، واكتب اختباراً، وشيله.
const Map<String, int> _baseline = {
  'lib/presentation/pos/widgets/pos_expense_dialog.dart': 1,
  'lib/presentation/pos/widgets/pos_previous_expenses_dialog.dart': 1,
  'lib/presentation/products/providers/categories_controller.dart': 2,
  'lib/presentation/products/providers/products_controller.dart': 1,
  'lib/presentation/screens/inventory/inventory_notifier.dart': 1,
  'lib/presentation/screens/shift_close_screen.dart': 1,
  'lib/presentation/shift_close_picpos/screens/shift_close_picpos_screen.dart': 1,
  'lib/data/services/excel_service.dart': 1,
};

void main() {
  test('مفيش نداء عارٍ جديد لـClientWriteInterceptor في presentation/ و data/',
      () {
    // نداء في موضع **جملة**: بداية سطر (بعد مسافات) بالاسم مباشرةً — يعني
    // مش مسبوقاً بـawait ولا return ولا `= `.
    final pattern = RegExp(r'^\s*ClientWriteInterceptor\s*\.');
    final perFile = <String, int>{};

    for (final root in ['lib/presentation', 'lib/data']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        final hits = entity
            .readAsLinesSync()
            .where((l) => pattern.hasMatch(l))
            .length;
        if (hits > 0) perFile[path] = hits;
      }
    }

    final offenders = <String>[];
    perFile.forEach((path, count) {
      final allowed = _baseline[path] ?? 0;
      if (count > allowed) {
        offenders.add('$path: $count نداء عارٍ (المسموح $allowed)');
      }
    });
    expect(offenders, isEmpty,
        reason: 'نداء إطلاق-وننسى جديد — استنِّ النداء في وضع العميل وأجهض '
            'الكتابة المحلية لو السيرفر رفض (زي deleteCategory)');

    // خط الأساس لازم يضيق: لو موضع اتصلح، شيله من _baseline عشان الحارس
    // يقفل عليه.
    //
    // ملف **غير موجود** مش موضعاً اتصلح — الحارس ده بينتقل بـpatch بين
    // منتجين بيتشاركوا المحرك ومش متطابقين في كل الشاشات (مثلاً
    // shift_close_picpos_screen موجودة في PicPos بس). فغياب الملف يتخطّى،
    // ووجوده بعدد أقل هو اللي بيتبلّغ.
    final stale = <String>[];
    _baseline.forEach((path, allowed) {
      if (!File(path).existsSync()) return;
      final actual = perFile[path] ?? 0;
      if (actual < allowed) {
        stale.add('$path: بقى $actual والمسجَّل $allowed');
      }
    });
    expect(stale, isEmpty,
        reason: 'مواضع اتصلحت — نزّل الرقم في _baseline');
  });
}
