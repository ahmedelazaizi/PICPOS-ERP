// حوارسُ مخطَّط القاعة البنيويّة — قسمُ ٧.
//
// ═══ لماذا بنيويّةٌ لا اختباراتُ سلوك ═══
//
// ثلاثةٌ ممّا يُحرَس هنا **لا يُرى في تشغيل**:
//
//   • **ترتيبُ `pullTables`**: `_upsertRow` يبتلع خطأَ المفتاح الخارجيّ
//     بـ`debugPrint` ويمضي، فجدارٌ يسبق قسمَه يُسقَط صامتاً — ولا يُسقِط
//     اختباراً واحداً لأنّ كلَّ اختبارٍ يبني قسمَه قبل معالمه.
//   • **غيابُ التحويل في المحرّك**: الحمولةُ تعبر السلكَ مرّةً، فلو ضُرب
//     رقمٌ في موضعٍ ثانٍ لبقي القيدُ متّزناً والخريطةُ مختلفةً بين جهازَين.
//   • **قراءةُ خريطة النادل**: `isEditMode: true` لا يرمي ولا يُفشل شيئاً،
//     إنّما يجعل كلَّ نقرةٍ مائلةٍ سحبةً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/delta_pull_service.dart';
import 'package:ural_erp/services/id_namespace_service.dart';

/// نصُّ الملفّ بلا أسطر التعليق — فشرحُ العقد لا يُعَدُّ تنفيذاً له.
///
/// ⚠️ **وهذا ليس تزيُّداً**: تعليقاتُ هذا المستودع تكتب الرمزَ المحروسَ
///    حرفيّاً لتشرحه، فحارسٌ يقرأ نثرَه يمرّ أخضرَ على شيفرةٍ محذوفة.
String _code(String raw) => [
      for (final line in raw.split('\n'))
        if (!line.trimLeft().startsWith('//')) line,
    ].join('\n');

String _read(String path) {
  final f = File(path);
  expect(f.existsSync(), isTrue, reason: 'الملفُّ انتقل — حدِّث مسارَ الحارس: $path');
  return _code(f.readAsStringSync());
}

/// جسمُ دالّةٍ يبدأ من توقيعها إلى أوّلِ سطرٍ يُغلق عند نفس المسافة.
String _body(String src, String signature) {
  final i = src.indexOf(signature);
  expect(i, greaterThan(-1), reason: 'لم أجد `$signature` — النمطُ تبدّل');
  final open = src.indexOf('{', i);
  var depth = 0;
  for (var k = open; k < src.length; k++) {
    if (src[k] == '{') depth++;
    if (src[k] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, k + 1);
    }
  }
  fail('جسمُ `$signature` غيرُ مغلق');
}

void main() {
  late String dao;
  late String plan;
  late String repoImpl;
  late String tablesScreen;
  late String canvas;

  setUpAll(() {
    dao = _read('lib/data/database/daos/floor_plan_dao.dart');
    plan = _read('lib/domain/models/floor_plan_layout.dart');
    repoImpl = _read('lib/data/repositories/restaurant_repository_impl.dart');
    tablesScreen =
        _read('lib/presentation/tables_picpos/screens/tables_picpos_screen.dart');
    canvas = _read(
        'lib/presentation/floor_plan_picpos/widgets/floor_plan_canvas_picpos.dart');
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المزامنة
  // ═══════════════════════════════════════════════════════════════════════

  group('توصيلُ المزامنة', () {
    test('`floor_plan_items` في مسار السحب', () {
      expect(DeltaPullService.pullTables, contains('floor_plan_items'));
    });

    test('🔴 وموضعُه **بعد** `table_sections` — المفتاحُ الخارجيُّ يبتلع خطأَه',
        () {
      const tables = DeltaPullService.pullTables;
      final section = tables.indexOf('table_sections');
      final items = tables.indexOf('floor_plan_items');
      expect(section, greaterThan(-1));
      expect(items, greaterThan(-1));
      expect(items, greaterThan(section),
          reason: 'جدارٌ يسبق قسمَه يُسقَط صامتاً بـ`debugPrint`');
    });

    test('وفي `deltaOnlyTables` — لا استراتيجيّةَ له في `fullSync`', () {
      expect(DeltaPullService.deltaOnlyTables, contains('floor_plan_items'));
    });

    test('وفي مسار السحب على الخادم', () {
      // لا كاشفَ ساكناً لـ`_syncPullTables`، فيُقرأ جسمُ القائمة نفسُه:
      // ذكرٌ في تعليقٍ أو في قائمةٍ أخرى ليس إدراجاً فيها.
      final handler = _read('lib/services/api/api_handler.dart');
      final body = _body(handler, 'static const _syncPullTables =');
      expect(body.contains("'floor_plan_items'"), isTrue);
    });

    test('وفي `namespacedTables`', () {
      expect(IdNamespaceService.namespacedTables, contains('floor_plan_items'));
    });

    test('وفي مُصلِّبات PostgreSQL', () {
      expect(AppDatabase.syncHardenedTablesForTest,
          contains('floor_plan_items'));
    });

    test(
        '⚠️ و**خارجَ** قائمتَي المنع التعاملَيّتَين عمداً — خريطةُ الصالة '
        'تُطلَب قبلَ أوّلِ دخول', () {
      expect(DeltaPullService.branchScopedPullTables,
          isNot(contains('floor_plan_items')));
      expect(ApiHandler.transactionalPullTablesForTest,
          isNot(contains('floor_plan_items')));
    });

    test('ومع `table_sections` و`restaurant_tables` في القرار نفسِه', () {
      // مرساة: لو صار القسمُ أو الطاولةُ تعامليَّين يوماً، فمعالمُ القاعة
      // يجب أن تتبعهما — وإلّا سُحبت المعالمُ لمن لا يُسحَب له قسمُها.
      for (final t in ['table_sections', 'restaurant_tables']) {
        expect(DeltaPullService.branchScopedPullTables, isNot(contains(t)),
            reason: 'تبدّل قرارُ $t — راجع موضعَ `floor_plan_items` معه');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المحرّك
  // ═══════════════════════════════════════════════════════════════════════

  group('محرّكُ الحفظ', () {
    test('مرساةٌ — الدالّةُ ما زالت موجودةً باسمها', () {
      expect(dao.contains('Future<void> saveFloorPlanLayout('), isTrue);
    });

    test('🔴 الحفظُ معاملةٌ **واحدة** لا معاملتان', () {
      final body = _body(dao, 'Future<void> saveFloorPlanLayout(');
      expect('transaction('.allMatches(body).length, 1,
          reason: 'معاملتان تعنيان نصفَ ترتيبٍ يبقى حين ينقطع الثانية');
    });

    test('والتحقّقُ **يسبق** المعاملةَ فلا يبقى نصفُ حفظ', () {
      final body = _body(dao, 'Future<void> saveFloorPlanLayout(');
      final check = body.indexOf('validateFloorPlanLayout(');
      final txn = body.indexOf('transaction(');
      expect(check, greaterThan(-1));
      expect(txn, greaterThan(-1));
      expect(check, lessThan(txn));
    });

    test('🔴 وتحديثُ الطاولة مشروطٌ بقسمها', () {
      final body = _body(dao, 'Future<void> saveFloorPlanLayout(');
      expect(body.contains('r.sectionId.equals(layout.sectionId)'), isTrue,
          reason: 'بلا الشرط تُنقَل طاولةُ قسمٍ آخرَ إلى لوحةٍ لا تخصّها');
    });

    test('وحذفُ ما غاب ناعمٌ لا قاسٍ — المزامنةُ تحتاج الصفَّ لتحمل حذفَه', () {
      final body = _body(dao, 'Future<void> saveFloorPlanLayout(');
      expect(body.contains('deletedAt: Value(now)'), isTrue);
      expect(body.contains('delete(floorPlanItems)'), isFalse);
    });

    test('ولا حالةَ طاولةٍ في الحمولة ولا في الكتابة', () {
      final body = _body(dao, 'Future<void> saveFloorPlanLayout(');
      expect(body.contains('status:'), isFalse,
          reason: 'المصمّمُ يحفظ مواضعَ — حالةٌ قديمةٌ تعود تُفرغ طاولةً عليها طلب');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // السلك
  // ═══════════════════════════════════════════════════════════════════════

  group('السلك', () {
    test('مرساةٌ — الحمولةُ ما زالت تُبنى في `floorPlanLayoutToJson`', () {
      expect(plan.contains('Map<String, dynamic> floorPlanLayoutToJson('),
          isTrue);
    });

    test('🔴 ولا رقمَ صفٍّ محلّيٌّ فيها', () {
      final body = _body(plan, 'Map<String, dynamic> floorPlanLayoutToJson(');
      expect(body.contains("'id'"), isFalse,
          reason: 'رقمٌ محلّيٌّ قد يخصّ صفّاً آخرَ تماماً على الخادم');
      expect(body.contains("'globalId'"), isTrue);
    });

    test('والقسمُ يعبر بمعرِّفه العالميّ', () {
      final body = _body(plan, 'Map<String, dynamic> floorPlanLayoutToJson(');
      expect(body.contains("'sectionGlobalId'"), isTrue);
      expect(body.contains("'sectionId'"), isFalse);
    });

    test('🔴 وفحصُ الهويّة يسبق الكتابتَين معاً في وضع العميل', () {
      final body = _body(repoImpl, 'Future<void> saveFloorPlanLayout(');
      final check = body.indexOf('validateFloorPlanWireIdentity(');
      final submit = body.indexOf('submitFloorPlan(');
      final local = body.indexOf('_db.saveFloorPlanLayout(');
      expect(check, greaterThan(-1));
      expect(submit, greaterThan(-1));
      expect(local, greaterThan(-1));
      expect(check, lessThan(submit));
      expect(check, lessThan(local),
          reason: 'حفظٌ محلّيٌّ قبل فحصٍ يفشل يترك الجهازَ وحدَه يرى مخطَّطاً');
    });

    test('🔴 والتوسيمُ يسبق الكتابتَين — هويّةٌ واحدةٌ للمعلَم على الطرفَين',
        () {
      final body = _body(repoImpl, 'Future<void> saveFloorPlanLayout(');
      final stamp = body.indexOf('stampMissingGlobalIds(');
      final submit = body.indexOf('submitFloorPlan(');
      final local = body.indexOf('_db.saveFloorPlanLayout(');
      expect(stamp, greaterThan(-1));
      expect(stamp, lessThan(submit));
      expect(stamp, lessThan(local));
    });

    test('ونقطةُ النهاية مركَّبةٌ في الموجّه', () {
      final router = _read('lib/services/api/api_handler.dart');
      expect(router.contains("router.post('/api/floor-plan'"), isTrue);
    });

    test('والطابورُ يعرف كيف يعيد إرسالَها', () {
      final worker = _read('lib/services/offline_sync_worker.dart');
      expect(worker.contains("case 'floor_plan_items':"), isTrue,
          reason: 'بلا حالةٍ في الطابور يُرمى الحفظُ بعد أوّل انقطاع');
      expect(worker.contains('proxy.submitFloorPlan('), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // خريطةُ النادل
  // ═══════════════════════════════════════════════════════════════════════

  group('خريطةُ النادل للقراءة فقط', () {
    test('مرساةٌ — الشاشةُ ما زالت تُركّب `FloorPlanDesigner`', () {
      expect(tablesScreen.contains('FloorPlanDesigner('), isTrue);
    });

    test('🔴 و`isEditMode` مثبَّتٌ على `false`', () {
      expect(tablesScreen.contains('isEditMode: false'), isTrue);
      expect(tablesScreen.contains('isDesignerMode'), isFalse,
          reason: 'وضعُ التصميم خرج من شاشة التشغيل إلى شاشته');
    });

    test('وزرُّ المصمّم يفتح الشاشةَ بفهرسها لا بفهرسٍ مكتوبٍ بيد', () {
      expect(
          tablesScreen
              .contains('ScreenId.floorPlanDesigner.navigationIndex'),
          isTrue);
    });

    test('⚠️ وأكوادُ الحساب خرجت من رأس شاشة الطاولات', () {
      expect(tablesScreen.contains('TableBillQrDialog'), isFalse);
    });

    test('ودخلت الإعداداتِ بحراستها نفسِها', () {
      final row = _read(
          'lib/presentation/settings_picpos/widgets/table_bill_qr_launcher_row.dart');
      expect(row.contains('TableBillQrDialog.show('), isTrue);
      expect(row.contains('PermissionCodes.tablesManage'), isTrue);
      expect(row.contains('allowManagerOverride: true'), isTrue);

      final settings = _read(
          'lib/presentation/settings_picpos/screens/settings_picpos_screen.dart');
      expect(settings.contains('TableBillQrLauncherRow()'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // أدواتُ الترتيب
  // ═══════════════════════════════════════════════════════════════════════

  group('المحاذاةُ والتوزيع', () {
    late String screen;
    setUpAll(() {
      screen = _read('lib/presentation/floor_plan_picpos/screens/'
          'floor_plan_designer_picpos_screen.dart');
    });

    test('مرساةٌ — دالّةُ الترتيب ما زالت موجودة', () {
      expect(screen.contains('void _arrange('), isTrue);
    });

    test('🔴 وتعمل على **المحدَّد** لا على طاولات القسم كلِّها', () {
      final body = _body(screen, 'void _arrange(');
      expect('_selection'.allMatches(body).length, greaterThanOrEqualTo(3),
          reason: 'المصمّمُ القديم يرتّب القاعةَ كلَّها مهما اختير');
    });

    test('ولا تكتب في القاعدة — الترتيبُ خطوةٌ في المسودة يُتراجَع عنها', () {
      final body = _body(screen, 'void _arrange(');
      expect(body.contains('updateTablePosition'), isFalse);
      expect(body.contains('saveFloorPlanLayout'), isFalse);
      expect(body.contains('_push('), isTrue,
          reason: 'بلا `_push` لا تدخل الخطوةُ مكدّسَ التراجع');
    });

    test('وملاءمةُ الشاشة عدّادٌ لا راية', () {
      // رايةٌ تُضبَط ثمّ تُطفَأ تجعل النقرةَ الثانيةَ بلا أثر.
      expect(screen.contains('_fitToken++'), isTrue);
      expect(canvas.contains('widget.fitToken != oldWidget.fitToken'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // اللوحة
  // ═══════════════════════════════════════════════════════════════════════

  group('لوحةُ المصمّم', () {
    test('مرساةٌ — حلقةُ الشبكة ما زالت موجودة', () {
      expect(canvas.contains('x += gridSize'), isTrue);
    });

    test('🔴 وخطوةُ الشبكة محروسةٌ قبل الدوران — صفرٌ يجمّد الإطارَ بلا استثناء',
        () {
      final guard = canvas.indexOf('!(gridSize > 0)');
      final loop = canvas.indexOf('x += gridSize');
      expect(guard, greaterThan(-1),
          reason: 'حارسُ `gridSize` سقط من النسخة — الأصلُ يحرسها');
      expect(guard, lessThan(loop), reason: 'الحارسُ بعد الحلقة لا يمنعها');
    });

    test('واللوحةُ `ltr` — الإحداثيّةُ المحفوظةُ فيزيائيّةٌ لا منطقيّة', () {
      expect(canvas.contains('textDirection: TextDirection.ltr'), isTrue,
          reason: 'خلطُ الاتّجاه يقرأ القاعةَ معكوسةً على جهازٍ آخر');
    });

    test('🔴 والمقاسُ يُقرأ بـ`resolveTableSize` لا بالاشتقاق مباشرةً', () {
      expect(canvas.contains('resolveTableSize('), isTrue);
      expect(canvas.contains('capacity * 8'), isFalse,
          reason: 'نسخةٌ ثانيةٌ من الاشتقاق تنقسم عند أوّل تعديل');
    });

    test('ولا استيرادَ لـ`data/database` في ملفَّي الشاشة واللوحة', () {
      for (final p in [
        'lib/presentation/floor_plan_picpos/widgets/floor_plan_canvas_picpos.dart',
        'lib/presentation/floor_plan_picpos/screens/floor_plan_designer_picpos_screen.dart',
      ]) {
        final src = File(p).readAsStringSync();
        expect(src.contains("import '../../../data/database/"), isFalse,
            reason: '`presentation_db_import_guard` يمنعه على كلّ ملفٍّ جديد');
      }
    });
  });
}
