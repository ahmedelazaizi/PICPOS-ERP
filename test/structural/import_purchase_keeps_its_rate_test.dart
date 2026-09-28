// حارسُ العقد: **المشتريات الخارجيّة — تحويلٌ مرّةً واحدة، ووسمٌ لا يضيع.**
//
// ═══ ما يُحرَس هنا ولماذا ═══
//
// ‏١) 🔴 **التحويلُ يقع مرّةً واحدةً — في الشاشة.** لمسار الشراء **مساران**:
//    `createPurchaseInvoice` محلّيّاً، وحمولةُ JSON إلى الخادم ثمّ
//    `insertPurchaseInvoiceWithoutStock` للنسخة المخبوءة. فضربٌ ثانٍ في أيٍّ
//    منهما يُفرِّق رقمَ الذمّة بين الجهازَين — والقيدُ متّزنٌ على الطرفَين،
//    فلا فحصَ اتّزانٍ يمسكه.
//
// ‏٢) 🔴 **واللقطةُ تصل كلَّ مسارٍ يكتب.** صفُّ الخادم هو المعتمَد وسحبُ
//    الدلتا يستبدل صفَّ العميل به — فعملةٌ تُكتَب محلّيّاً ولا تصل الخادمَ
//    **تُمحى عند أوّل سحب**، وتُقرأ فاتورةُ الدولار محلّيّةً بلا أثر.
//
// ‏٣) 🔴 **والوسمُ داخلَ معاملة الفاتورة.** صفُّ `ImportPurchaseDetails` هو
//    الفارقُ الوحيدُ بين فاتورةِ استيرادٍ وفاتورةٍ محلّيّة، فكتابتُه بعد
//    المعاملة تترك فاتورةً بذمّةٍ ومخزونٍ وقيدٍ **بلا وسم**.
//
// ‏٤) 🔴 **وموضعُه في السحب بعد `purchase_invoices`.** `_upsertRow` **يبتلع**
//    خطأَ المفتاح الخارجيِّ بـ`debugPrint` ويمضي، فوسمٌ يسبق فاتورتَه
//    يُسقَط صامتاً.
//
// ‏٥) 🔴 **ورقمُ الطرف لا يسافر.** أرقامُ العميل والخادم تتباعد بالتصميم،
//    فرقمٌ محلّيٌّ قد يُطابِق **طرفاً آخرَ تماماً** على الخادم — فيُنسَب
//    التخليصُ إلى مورّدٍ لا علاقةَ له.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/delta_pull_service.dart';
import 'package:ural_erp/services/id_namespace_service.dart';

String _code(String path) => [
      for (final line in File(path).readAsStringSync().split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

int _count(String haystack, String needle) {
  var n = 0;
  var i = haystack.indexOf(needle);
  while (i != -1) {
    n++;
    i = haystack.indexOf(needle, i + needle.length);
  }
  return n;
}

/// ⚠️ **ولا `expect` هنا**: تُنادى عند إعلان المجموعات، و`expect` خارجَ
///    اختبارٍ يرمي `OutsideTestException` فيسقط الملفُّ كلُّه عند التحميل.
String _between(String code, String from, String to) {
  final a = code.indexOf(from);
  if (a < 0) throw StateError('العلامةُ «$from» اختفت من المصدر');
  final b = code.indexOf(to, a);
  if (b <= a) throw StateError('العلامةُ «$to» اختفت من المصدر');
  return code.substring(a, b);
}

const _purchaseDao = 'lib/data/database/daos/purchase_dao.dart';
const _importDao = 'lib/data/database/daos/import_purchases_dao.dart';
const _plan = 'lib/domain/models/import_purchase_plan.dart';
const _screen =
    'lib/presentation/import_purchases_picpos/screens/import_purchases_picpos_screen.dart';
const _repoImpl = 'lib/data/repositories/purchases_repository_impl.dart';
const _cwi = 'lib/services/interceptor/cwi_trading_purchases.dart';
const _apiHandler = 'lib/services/api/api_purchase_handler.dart';

void main() {
  final purchaseDao = _code(_purchaseDao);
  final screen = _code(_screen);
  final repoImpl = _code(_repoImpl);
  final cwi = _code(_cwi);
  final api = _code(_apiHandler);

  group('مراسٍ — الملفّاتُ تُقرأ فعلاً', () {
    test('وكلُّ مسارٍ حاضرٌ غيرَ فارغ', () {
      for (final p in const [
        _purchaseDao,
        _importDao,
        _plan,
        _screen,
        _repoImpl,
        _cwi,
        _apiHandler,
      ]) {
        expect(File(p).existsSync(), isTrue, reason: 'المسارُ $p اختفى');
        expect(_code(p).length, greaterThan(400),
            reason: '$p قُرئ شبهَ فارغٍ — الفحوصُ تحته تقيس لا شيء');
      }
    });

    test('ومرساةٌ موجبةٌ — الدالّةُ التي يُبنى عليها الحارسُ قائمة', () {
      expect(_count(purchaseDao, 'Future<int> createPurchaseInvoice('), 1);
      expect(_count(purchaseDao, 'Future<int> insertPurchaseInvoiceWithoutStock('), 1);
      expect(_code(_plan).contains('double foreignToLocal('), isTrue);
    });
  });

  group('🔴 ١ · التحويلُ مرّةً واحدةً — في الشاشة', () {
    test('والشاشةُ تحوّل فعلاً', () {
      // ⚠️ **يُعَدُّ الأثرُ لا يُنفى الاسم**: التكلفةُ والضريبةُ والخصمُ
      //    في السطر، وخصمُ الترويسة والمدفوعُ في الرأس.
      expect(_count(screen, 'foreignToLocal('), greaterThanOrEqualTo(5),
          reason: '🔴 مواضعُ التحويل نقصت — مبلغٌ يصل المحرّكَ بعملة المورّد '
              'فيُقيَّد على الذمّة بوحدةٍ ليست وحدتَه');
      // وما يُحوَّل في السطر ثلاثةٌ بالضبط: التكلفةُ والضريبةُ والخصم.
      final convert = _between(
        screen,
        'List<ImportSaveLine> convertFormItemsToLocal(',
        'List<ImportCurrencyOption> importCurrencyOptions(',
      );
      expect(_count(convert, 'foreignToLocal('), 3,
          reason: '🔴 عددُ الحقول المحوَّلة في السطر تبدّل');
    });

    test('🔴 والكمّيّةُ والنسبةُ لا تُضرَبان — ليستا مالاً', () {
      final convert = _between(
        screen,
        'List<ImportSaveLine> convertFormItemsToLocal(',
        'List<ImportCurrencyOption> importCurrencyOptions(',
      );
      // السطرُ الذي يسند الكمّيّةَ لا يمرّ بالتحويل.
      expect(convert.contains("quantity: money(it['quantity'])"), isTrue,
          reason: '🔴 الكمّيّةُ تُضرَب بالسعر — عشرُ قطعٍ تصير عُشرَ قطعة');
      expect(convert.contains("taxRate: money(it['taxRate'])"), isTrue,
          reason: '🔴 النسبةُ تُضرَب بالسعر — ١٤٪ تصير ٠٫٢٨٪');
    });

    test('🔴 والمحرّكُ لا يضرب بالسعر ثانيةً', () {
      // لمسار الشراء مساران، فضربٌ هنا يُفرِّق رقمَ الذمّة بين الجهازَين.
      for (final forbidden in const [
        '* exchangeRate',
        'exchangeRate *',
        '* rate',
        'foreignToLocal(',
      ]) {
        expect(purchaseDao.contains(forbidden), isFalse,
            reason: '🔴 «$forbidden» في `purchase_dao` — والتحويلُ وقع في '
                'الشاشة سلفاً، فهذا ضربٌ ثانٍ صامت');
      }
    });

    test('🔴 ولا قارئَ يضرب باللقطة المخزَّنة', () {
      // اللقطةُ **وصفٌ لا مُعامِل**. وقارئٌ يضرب بها يُعيد تقييمَ فاتورةٍ
      // رُحِّلت — وهو عينُ ما يمنعه تعليقُ العمود.
      final screenRate = _between(
        screen,
        'PicPosTextCell(\n                r.invoice.total',
        'PicPosTextCell(\n                r.landedApplied',
      );
      expect(screenRate.contains('*'), isFalse,
          reason: '🔴 الإجماليُّ المعروضُ يُضرَب بالسعر — وهو محلّيٌّ سلفاً');
    });
  });

  group('🔴 ٢ · اللقطةُ تصل كلَّ مسارٍ يكتب', () {
    test('المحرّكُ المحلّيُّ يخزّنها', () {
      final create = _between(
        purchaseDao,
        'Future<int> createPurchaseInvoice(',
        'Future<int> insertPurchaseInvoiceWithoutStock(',
      );
      expect(create.contains('currencyId: Value(currencyId)'), isTrue);
      expect(create.contains('exchangeRate: Value(exchangeRate)'), isTrue);
    });

    test('والنسخةُ المخبوءةُ في وضع العميل تخزّنها كذلك', () {
      // بدونها يعرض العميلُ فاتورةَ استيرادٍ بلا عملتها حتى أوّل سحب.
      final cache = purchaseDao
          .substring(purchaseDao.indexOf('Future<int> insertPurchaseInvoiceWithoutStock('));
      expect(cache.contains('currencyId: Value(currencyId)'), isTrue);
      expect(cache.contains('exchangeRate: Value(exchangeRate)'), isTrue);
    });

    test('والمستودعُ يمرّرها في الفرعَين معاً', () {
      expect(_count(repoImpl, 'currencyId: params.currencyId'), 3,
          reason: '🔴 فرعٌ من فروع الكتابة الثلاثة يُسقط العملة — '
              '(حمولةُ الخادم · النسخةُ المخبوءة · المسارُ المحلّيّ)');
      expect(_count(repoImpl, 'importDetails: params.importDetails'), 3,
          reason: '🔴 فرعٌ يُسقط الوسم — فتُقرأ الفاتورةُ محلّيّةً هناك');
    });

    test('🔴 وحمولةُ الخادم تحملها — وإلّا مُحيت عند أوّل سحب', () {
      expect(cwi.contains("'currencyId': ?currencyId"), isTrue);
      expect(cwi.contains("'exchangeRate': ?exchangeRate"), isTrue);
      expect(cwi.contains("data['importDetails'] = importDocumentToJson("),
          isTrue);
    });

    test('والخادمُ يقرأها ويكتبها', () {
      final post = _between(
        api,
        'final serverId = await db.createPurchaseInvoice(',
        'broadcast(\'purchases\');',
      );
      expect(post.contains("currencyId: parseIntNullable(data['currencyId'])"),
          isTrue);
      expect(
          post.contains(
              "exchangeRate: parseDoubleNullable(data['exchangeRate'])"),
          isTrue);
      expect(post.contains('importDetails: importDetails'), isTrue);
    });
  });

  group('🔴 ٣ · الوسمُ داخلَ معاملة الفاتورة', () {
    test('يُكتَب بعد إدراج الفاتورة وقبل سطورها — في نفس المعاملة', () {
      final create = _between(
        purchaseDao,
        'Future<int> createPurchaseInvoice(',
        'Future<int> insertPurchaseInvoiceWithoutStock(',
      );
      final tx = create.indexOf('return transaction(() async {');
      final write = create.indexOf('_writeImportPurchaseDetails(invoiceId');
      final insert = create.indexOf('into(purchaseInvoices).insert(');
      expect(tx, greaterThan(-1));
      expect(write, greaterThan(insert),
          reason: 'الوسمُ يسبق الفاتورةَ — ولا مفتاحَ خارجيَّ له بعد');
      expect(write, greaterThan(tx),
          reason: '🔴 الوسمُ خارجَ المعاملة — فسقوطُه يترك فاتورةً بذمّةٍ '
              'ومخزونٍ وقيدٍ بلا وسم، تبدو محلّيّةً إلى الأبد');
    });

    test('والنسخةُ المخبوءةُ كذلك', () {
      final cache = purchaseDao.substring(
          purchaseDao.indexOf('Future<int> insertPurchaseInvoiceWithoutStock('));
      expect(cache.contains('_writeImportPurchaseDetails(invoiceId'), isTrue);
    });

    test('🔴 وزوجُ العملة يُفحَص قبل المعاملة', () {
      // عملةٌ بلا سعرٍ تُقرأ لاحقاً على أنّها ١، ولا نسخةَ ثانيةَ من هذا
      // الفحص في أيّ مكان — فهو **الحارسُ الوحيد**.
      final head = _between(
        purchaseDao,
        'Future<int> createPurchaseInvoice(',
        'return transaction(() async {',
      );
      expect(head.contains('validateExchangeRate('), isTrue,
          reason: '🔴 الزوجُ يُفحَص داخلَ المعاملة أو لا يُفحَص');
    });

    test('🔴 وطولُ الحقول يُفحَص في موضعٍ **واحد** — عند الكتابة', () {
      // ⚠️ **نجت طفرةٌ فكشفت نسخةً لا حارساً**: كانت نسخةٌ ثانيةٌ من فحص
      //    الطول في رأس `createPurchaseInvoice`، وإسقاطُها لم يُغيّر شيئاً
      //    لأنّ الفحصَ عند الكتابة يمسك عينَ الحالة بنفس الرسالة وبنفس
      //    التراجع. فأُسقطت النسخةُ وبقي الأصل — ونسختان تنقسمان عند أوّل
      //    تعديلٍ على إحداهما.
      final importDao = _code(_importDao);
      expect(_count(importDao, 'validateImportDocument('), 2,
          reason: 'الفحصُ عند الكتابة وعند التحرير — لا أكثرَ ولا أقلّ');
      final write = importDao
          .substring(importDao.indexOf('Future<void> _writeImportPurchaseDetails('));
      final validateAt = write.indexOf('validateImportDocument(');
      final insertAt = write.indexOf('into(importPurchaseDetails)');
      expect(validateAt, greaterThan(-1),
          reason: '🔴 الوسمُ يُكتَب بلا فحصِ طول — فيرمي drift خطأً غامضاً '
              'بعد أن حُسبت الذمّة');
      expect(validateAt, lessThan(insertAt),
          reason: '🔴 الفحصُ بعد الإدراج لا قبلَه');
      expect(purchaseDao.contains('validateImportDocument('), isFalse,
          reason: 'عادت النسخةُ الثانيةُ إلى `purchase_dao` — والطفرةُ '
              'أثبتت أنّها لا تحرس شيئاً');
    });

    test('ولا بابَ ثانياً لإنشاء الوسم', () {
      final importDao = _code(_importDao);
      // `updateImportPurchaseDetails` تُحرِّر ولا تُنشئ: بابٌ ثانٍ كان
      // يحوّل فاتورةً محلّيّةً إلى خارجيّةٍ بعد أن رُحِّلت.
      final upd = _between(
        importDao,
        'Future<void> updateImportPurchaseDetails(',
        'Future<void> _writeImportPurchaseDetails(',
      );
      expect(upd.contains('into(importPurchaseDetails)'), isFalse,
          reason: '🔴 التحريرُ يُنشئ وسماً — تصنيفٌ يتبدّل من بابٍ خلفيّ');
      expect(upd.contains('throw StateError('), isTrue);
    });
  });

  group('🔴 ٤ · المزامنةُ — القوائمُ والموضع', () {
    const t = 'import_purchase_details';

    test('في قوائم السحب الخمس', () {
      expect(DeltaPullService.pullTables, contains(t));
      expect(DeltaPullService.deltaOnlyTables, contains(t));
      expect(IdNamespaceService.namespacedTables, contains(t));
      expect(AppDatabase.syncHardenedTablesForTest, contains(t));
    });

    test('🔴 وموضعُه بعد `purchase_invoices` — المفتاحُ يُبتلَع خطؤه', () {
      const tables = DeltaPullService.pullTables;
      expect(tables.indexOf(t), greaterThan(tables.indexOf('purchase_invoices')),
          reason: '🔴 الوسمُ يُسحَب قبل فاتورته — و`_upsertRow` يبتلع خطأَ '
              'المفتاح بـ`debugPrint` ويمضي، فيُسقَط الصفُّ صامتاً');
    });

    test('🔴 وهو بياناتُ عملٍ — داخلَ قائمة الفروع المحميّة', () {
      // أوراقُ صفقةٍ لا تُسلَّم لمستدعٍ بلا هويّةٍ متحقَّقة، وهو فرعٌ من
      // فاتورةٍ محميّةٍ أصلاً فالتركُ خارجاً يُسرّب ما تحميه أمُّه.
      expect(DeltaPullService.branchScopedPullTables, contains(t));
    });

    test('ولم يعد في دَين المزامنة', () {
      final baseline =
          File('test/structural/unsynced_tables_have_no_writer_test.dart')
              .readAsStringSync();
      expect(baseline.contains("  'ImportPurchaseDetails',"), isFalse,
          reason: 'الجدولُ له كاتبٌ الآن — وبقاؤه في خطّ الأساس يُسقط البناء');
    });
  });

  group('🔴 ٥ · لا بنيةَ بلا منادٍ', () {
    // نفسُ عقدِ `unsynced_tables_have_no_writer_test`: دالّةٌ تُكتَب ولا
    // تُنادى هي دَينٌ يُنسى. والثلاثُ هنا بُنيت لهذه المرحلة.
    test('تحريرُ الأوراق له منادٍ في الشاشة', () {
      expect(screen.contains('.updateDetails('), isTrue,
          reason: 'التحريرُ مبنيٌّ ولا بابَ له — بنيةٌ تُشحَن بلا مستعمل');
      expect(screen.contains('_editPapers('), isTrue);
    });

    test('🔴 والعملةُ ليست في لوح التحرير', () {
      // تبديلُ السعر بعد الترحيل يُبدّل **وصفَ** الصفِّ ولا يُبدّل مبلغاً.
      expect(screen.contains('showCurrency: false'), isTrue,
          reason: '🔴 السعرُ يُحرَّر بعد الترحيل — فيقول المستندُ سعراً لم '
              'يُحسَب به');
    });

    test('🔴 وفاتورةُ الاستيراد لا تُحرَّر من المسار المحلّيّ', () {
      final upd = _between(
        purchaseDao,
        'Future<void> updatePurchaseInvoice(',
        'Future<void> updatePurchaseInvoicePayment(',
      );
      expect(upd.contains('oldInvoice.currencyId != null'), isTrue,
          reason: '🔴 مسارٌ يستقبل مبالغَ محلّيّةً يحرّر فاتورةَ دولار — '
              'فتبقى اللقطةُ فوق أرقامٍ لم تُحوَّل، وصفٌّ يناقض نفسَه');
    });
  });

  group('🔴 ٦ · رقمُ الطرف لا يسافر', () {
    test('الحمولةُ بلا `clearingAgentPartyId`', () {
      final plan = _code(_plan);
      final toJson = _between(
        plan,
        'Map<String, dynamic> importDocumentToJson(',
        'ImportDocumentFields importDocumentFromJson(',
      );
      expect(toJson.contains('clearingAgentPartyId'), isFalse,
          reason: '🔴 رقمٌ محلّيٌّ يصل الخادمَ قد يُطابِق طرفاً آخرَ تماماً '
              '— فيُنسَب التخليصُ إلى مورّدٍ لا علاقةَ له');
    });

    test('والمعرِّفُ العالميُّ هو الذي يسافر', () {
      expect(cwi.contains("data['clearingAgentGlobalId'] ="), isTrue);
    });

    test('والخادمُ يحلُّه بـ`resolvePartyId` لا يثق برقم', () {
      final block = _between(
        api,
        'final rawImport = data[\'importDetails\'];',
        'final serverId = await db.createPurchaseInvoice(',
      );
      expect(block.contains('resolvePartyId('), isTrue);
      expect(block.contains("partyGlobalId: data['clearingAgentGlobalId']"),
          isTrue);
      expect(block.contains('clientPartyId: null'), isTrue,
          reason: '🔴 الخادمُ يقبل رقماً محلّيّاً — وهو قد يدلّ على طرفٍ آخر');
    });
  });
}
