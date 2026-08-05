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

/// إعفاءات موثَّقة — الإطلاق-وننسى هنا **صحيح**، مش فجوة.
///
/// الفرق الفاصل: العطل بيحصل لما السيرفر يفشل بصمت والكتابة المحلية تتم، وبعدين
/// **سحب مجدوَل** يدهس الحالة المحلية بحالة السيرفر القديمة. المواضع اللي تحت
/// عندها آلية تقارب بتمنع ده، وكل واحدة اتفحصت على حدة:
///
///   • pos_expense_dialog — المحلي والسيرفر بيتشاركوا نفس `globalId`، فالسيرفر
///     بيعمل dedupe على الإدراج والمُصالِح بيدمج الصفّين. إصلاح ميداني مقصود
///     («المصروفات مش بتظهر للكاشير») والتراجع عنه بيرجّع العطل.
///   • inventory_notifier — Spec 135 BUG-A: `adjustmentEventGid` واحد بيتمرّر
///     للطرفين عشان قيدَي اليومية يتقاربوا على globalId حتمي بدل تصادم 23505.
///   • excel_service — استيراد جماعي محروس بـ`hasOpeningStockMovement`
///     (إعادة الاستيراد idempotent)، والاستناء لكل صف بيخنق الاستيراد.
///   • pos_previous_expenses_dialog — قرار موثَّق: الربط على القيمة المرجَّعة
///     كان بيسيب الصف محلياً لأن المُعترِض بيرجّع true لـ«نجح» و«اتحجز» معاً.
///
/// ⚠️ صيغة `unawaited(` مستثناة أصلاً في الماسح فوق — دي مسؤولية
/// mirror_write_dispatch_test وليها خط أساسها هناك.
///
/// لإضافة سطر هنا لازم تكتب ليه الإطلاق-وننسى صحيح في الموضع ده. ولو مفيش
/// آلية تقارب، الصح هو علاج v128: استنِّ في وضع العميل وأجهض الكتابة المحلية.
const Map<String, int> _baseline = {
  'lib/presentation/pos/widgets/pos_expense_dialog.dart': 1,
  'lib/presentation/pos/widgets/pos_previous_expenses_dialog.dart': 1,
  'lib/presentation/screens/inventory/inventory_notifier.dart': 1,
  'lib/data/services/excel_service.dart': 1,
};

void main() {
  test('مفيش نداء عارٍ جديد لـClientWriteInterceptor في presentation/ و data/',
      () {
    // نداء في موضع **جملة**: بداية سطر (بعد مسافات) بالاسم مباشرةً — يعني
    // مش مسبوقاً بـawait ولا return ولا `= `.
    final pattern = RegExp(r'^\s*ClientWriteInterceptor\s*\.');
    // صيغة `unawaited(` على السطر اللي قبله مستثناة — دي مسؤولية
    // mirror_write_dispatch_test، وهو بيقرا الملف كله فالـ`\s*` عنده بيعدّي
    // السطر ويمسكها. من غير الاستثناء ده الحارسان بيعدّوا نفس الموضع مرتين
    // وخط الأساس هنا بيوحي بفئة عطل مستقلة مش موجودة.
    final unawaitedOpen = RegExp(r'unawaited\(\s*$');
    final perFile = <String, int>{};

    for (final root in ['lib/presentation', 'lib/data']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        final lines = entity.readAsLinesSync();
        var hits = 0;
        for (var i = 0; i < lines.length; i++) {
          if (!pattern.hasMatch(lines[i])) continue;
          final prev = i > 0 ? lines[i - 1] : '';
          if (unawaitedOpen.hasMatch(prev)) continue;
          hits++;
        }
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
