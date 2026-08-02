// بلاغ العميل 2026-07-30 — «في أوقات الاتصال بالـ IP مش بيتم اكتشاف الميزان
// رغم أن الميزان متصل والـ IP سليم، وكمان من على AclasSDK بحاول الربط عن
// طريق الـ IP ومش بيشوف الميزان» (موازين NVK · Rongta · TEM).
//
// ── محوران، لا محور واحد ──
//
// الخلط الذي أنتج العطل هو دمج سؤالين مختلفين في جدول واحد:
//   ① هل **الميزان** يدعم هذه الطريقة؟
//   ② هل **تنفيذنا** لها متحقَّق منه على جهاز حقيقي؟
//
// AclasSDK مثال على فشل ①: هو SDK خاص بموازين Aclas، ودالّة الكشف فيه
// ترسل استعلام UDP ببروتوكول Aclas المملوك — فميزان NVK أو TEM لن يردّ
// مهما كان الـ IP صحيحاً. ولهذا فشلت أداة AclasSDK نفسها عند العميل:
// دليل يؤكّد التشخيص لا عرَض إضافي.
//
// ومسارا TCP/Serial لـ NVK و TEM مثال على فشل ②: مكتوبان من بروتوكول
// تسلسلي عام (STX + "PLUSTART" + ETX) بلا أي التقاط من جهاز — نفس نمط
// التخمين الذي جعل رونجتا وحده يعمل، لأنه وحده كُتب من ملف تصدير حقيقي.
//
// ── تصحيح 2026-07-30 (لقطات برنامج mscale الرسمي) ──
//
// كان مسجّلاً في المشروع أن TEM «serial only». اللقطات تُثبت العكس:
// قائمة Communication → Mode تعرض ethernet و serial، وشاشة
// Communication → Ethernet تُظهر اتصالاً على IP:**4001** — لا 9100 ولا
// 8000 كما كان مسجّلاً لـ TEM و NVK.

import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/services/label_scale_service.dart';

void main() {
  group('AclasSDK — يكتشف موازين Aclas وحدها', () {
    test('NVK و TEM لا يُكتشفان عبره مهما كان الـ IP صحيحاً', () {
      for (final b in [LabelScaleBrand.nvkTma, LabelScaleBrand.tem]) {
        final a = adviseBrandConnection(b, LabelScaleConnection.aclasSDK);
        expect(a.level, ScaleAdviceLevel.unsupported,
            reason: '${b.name} ليس ميزان Aclas');
        // الرسالة تُسمّي السبب بدل أن تُعيد المستخدم لفحص الـ IP — والـ IP
        // سليم أصلاً، وهذا بيت القصيد في البلاغ.
        expect(a.message, contains('Aclas'));
      }
    });

    test('Aclas و Rongta وحدهما بلا اعتراض على AclasSDK', () {
      // Rongta مسموح لأن بعض إصداراته Aclas-OEM — وهو مصدر التقطّع بين
      // ميزان وآخر من نفس الماركة.
      for (final b in [LabelScaleBrand.aclas, LabelScaleBrand.rongta]) {
        expect(
          adviseBrandConnection(b, LabelScaleConnection.aclasSDK).level,
          ScaleAdviceLevel.ok,
        );
      }
    });

    test('باقي البراندات كلها unsupported على AclasSDK', () {
      const others = [
        LabelScaleBrand.cas,
        LabelScaleBrand.digi,
        LabelScaleBrand.mettlerToledo,
        LabelScaleBrand.dibal,
      ];
      for (final b in others) {
        expect(
          adviseBrandConnection(b, LabelScaleConnection.aclasSDK).level,
          ScaleAdviceLevel.unsupported,
          reason: '${b.name} ليس ميزان Aclas',
        );
      }
    });
  });

  group('NVK و TEM — الجهاز يدعم الشبكة، وتنفيذنا غير متحقَّق منه', () {
    test('TCP يُصنَّف unverified لا unsupported ولا ok', () {
      // unsupported كان سيمنع المستخدم من طريق يدعمها جهازه فعلاً؛
      // و ok كان سيَعِد بما لم نختبره. الحقيقة بينهما.
      for (final b in [LabelScaleBrand.nvkTma, LabelScaleBrand.tem]) {
        final a = adviseBrandConnection(b, LabelScaleConnection.tcp);
        expect(a.level, ScaleAdviceLevel.unverified, reason: b.name);
        expect(a.message, isNotNull);
      }
    });

    test('التنبيه يذكر المنفذ 4001 والمسار المضمون', () {
      final a = adviseBrandConnection(
          LabelScaleBrand.nvkTma, LabelScaleConnection.tcp);
      expect(a.message, contains('4001'));
      expect(a.message, contains('mscale'));
    });

    test('تصدير الملف هو المسار المضمون — بلا أي تنبيه', () {
      for (final b in [LabelScaleBrand.nvkTma, LabelScaleBrand.tem]) {
        final a = adviseBrandConnection(b, LabelScaleConnection.file);
        expect(a.level, ScaleAdviceLevel.ok, reason: b.name);
        expect(a.message, isNull);
      }
    });
  });

  group('المنافذ الافتراضية', () {
    test('TEM و NVK على 4001 — لا 9100 ولا 8000', () {
      // الرقم كان موجوداً في المشروع أصلاً لكن معلّقاً على البراند الخطأ
      // (ضمن منافذ رونجتا). تصحيح من شاشة Communication → Ethernet.
      expect(kDefaultBrandPort[LabelScaleBrand.tem], 4001);
      expect(kDefaultBrandPort[LabelScaleBrand.nvkTma], 4001);
    });

    test('جدول الخدمة يشتقّ من نفس المصدر — لا نسخة ثانية', () {
      // كانت ثلاث نسخ من الجدول بقيم متباعدة، فتصحيح منفذ في واحدة لا
      // يصل للباقي.
      for (final b in LabelScaleBrand.values) {
        expect(LabelScaleService.defaultPorts[b], kDefaultBrandPort[b],
            reason: b.name);
      }
    });

    test('كل براند له منفذ افتراضي معرَّف', () {
      for (final b in LabelScaleBrand.values) {
        expect(kDefaultBrandPort[b], isNotNull, reason: b.name);
      }
    });
  });

  group('Dibal — تسلسلي فقط (لم يُصحَّح بدليل)', () {
    test('TCP unsupported، والتنبيه يقترح البديل', () {
      final a =
          adviseBrandConnection(LabelScaleBrand.dibal, LabelScaleConnection.tcp);
      expect(a.level, ScaleAdviceLevel.unsupported);
      expect(a.message, contains('Serial'));
    });
  });

  group('لا براند بلا مخرج', () {
    test('تصدير CSV صالح لكل البراندات', () {
      for (final b in LabelScaleBrand.values) {
        expect(
          adviseBrandConnection(b, LabelScaleConnection.file).level,
          ScaleAdviceLevel.ok,
          reason: '${b.name} يجب أن يبقى له مخرج ملف دائماً',
        );
        expect(kBrandSupportedConnections[b], isNotNull,
            reason: '${b.name} غير مذكور في خريطة التوافق');
      }
    });
  });
}
