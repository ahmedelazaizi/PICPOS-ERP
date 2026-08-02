// بلاغ العميل 2026-07-30 — «في أوقات الاتصال بالـ IP مش بيتم اكتشاف الميزان
// رغم أن الميزان متصل والـ IP سليم، وكمان من على AclasSDK بحاول الربط عن
// طريق الـ IP ومش بيشوف الميزان» (موازين NVK · Rongta · TEM).
//
// السبب الأول: قائمة «طريقة الاتصال» تعرض الطرق الخمس لكل البراندات بلا
// تفرقة، ومنها «AclasSDK — كشف تلقائي بالـ IP فقط». لكن AclasSDK هو SDK
// خاص بموازين Aclas: دالّة الكشف فيه تُرسل استعلام UDP ببروتوكول Aclas
// المملوك، فميزان لا يتكلّمه لن يردّ مهما كان الـ IP صحيحاً.
//
// ولهذا فشلت أداة AclasSDK نفسها عند العميل — وهو **دليل يؤكّد التشخيص**
// لا عرَض إضافي: الأداة تبحث عن ميزان Aclas على عنوان فيه ميزان آخر.
//
// هذا الملف يقفل على خريطة التوافق حتى لا تعود طريقة غير مدعومة تُعرَض
// كأنها صالحة، ويثبّت أن رسالة التحذير تشرح السبب بدل «تأكد من الـ IP».

import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/services/label_scale_service.dart';

void main() {
  group('AclasSDK — يكتشف موازين Aclas وحدها', () {
    test('NVK TMA لا يُكتشف عبر AclasSDK مهما كان الـ IP صحيحاً', () {
      final w = brandConnectionWarning(
          LabelScaleBrand.nvkTma, LabelScaleConnection.aclasSDK);
      expect(w, isNotNull);
      // الرسالة يجب أن تُسمّي السبب، لا أن تُعيد المستخدم لفحص الـ IP —
      // فالـ IP سليم أصلاً، وهذا بيت القصيد في البلاغ.
      expect(w, contains('Aclas'));
    });

    test('TEM لا يُكتشف عبر AclasSDK', () {
      expect(
        brandConnectionWarning(
            LabelScaleBrand.tem, LabelScaleConnection.aclasSDK),
        isNotNull,
      );
    });

    test('Aclas و Rongta وحدهما بلا تحذير على AclasSDK', () {
      // Rongta مسموح لأن بعض إصداراته Aclas-OEM — وهو مصدر التقطّع بين
      // ميزان وآخر من نفس الماركة.
      expect(
        brandConnectionWarning(
            LabelScaleBrand.aclas, LabelScaleConnection.aclasSDK),
        isNull,
      );
      expect(
        brandConnectionWarning(
            LabelScaleBrand.rongta, LabelScaleConnection.aclasSDK),
        isNull,
      );
    });

    test('كل البراندات الأخرى تُحذَّر على AclasSDK', () {
      const others = [
        LabelScaleBrand.cas,
        LabelScaleBrand.digi,
        LabelScaleBrand.mettlerToledo,
        LabelScaleBrand.dibal,
      ];
      for (final b in others) {
        expect(
          brandConnectionWarning(b, LabelScaleConnection.aclasSDK),
          isNotNull,
          reason: '${b.name} ليس ميزان Aclas',
        );
      }
    });
  });

  group('البراندات التسلسلية فقط', () {
    test('TEM و Dibal يُحذَّران على TCP/IP', () {
      // تعريفهما في LabelScaleBrand يقول «serial only» — ومع ذلك كانت
      // الشاشة تعرض لهما TCP، ولـ TEM منفذاً افتراضياً 9100، أي إعداد لا
      // يمكن أن ينجح بحال.
      expect(
        brandConnectionWarning(
            LabelScaleBrand.tem, LabelScaleConnection.tcp),
        isNotNull,
      );
      expect(
        brandConnectionWarning(
            LabelScaleBrand.dibal, LabelScaleConnection.tcp),
        isNotNull,
      );
    });

    test('التحذير يقترح الطريقة الصحيحة لا مجرد الرفض', () {
      final w = brandConnectionWarning(
          LabelScaleBrand.tem, LabelScaleConnection.tcp)!;
      expect(w, contains('Serial'));
    });

    test('Serial و CSV مقبولان لهما بلا تحذير', () {
      for (final b in [LabelScaleBrand.tem, LabelScaleBrand.dibal]) {
        expect(
          brandConnectionWarning(b, LabelScaleConnection.serial),
          isNull,
        );
        expect(
          brandConnectionWarning(b, LabelScaleConnection.file),
          isNull,
        );
      }
    });
  });

  group('NVK TMA — الشبكة مدعومة لكن ببروتوكوله الخاص', () {
    test('TCP و FTP مقبولان', () {
      expect(
        brandConnectionWarning(
            LabelScaleBrand.nvkTma, LabelScaleConnection.tcp),
        isNull,
      );
      expect(
        brandConnectionWarning(
            LabelScaleBrand.nvkTma, LabelScaleConnection.ftp),
        isNull,
      );
    });
  });

  group('تصدير CSV مخرج أخير لكل البراندات', () {
    test('لا براند بلا مسار صالح', () {
      for (final b in LabelScaleBrand.values) {
        expect(
          brandConnectionWarning(b, LabelScaleConnection.file),
          isNull,
          reason: '${b.name} يجب أن يبقى له مخرج CSV دائماً',
        );
        expect(
          kBrandSupportedConnections[b],
          isNotNull,
          reason: '${b.name} غير مذكور في خريطة التوافق',
        );
      }
    });
  });
}
