// طبقةُ المستودع لمكتبة النماذج — كلُّ ما تحتاجه الشاشةُ يمرّ من هنا.
//
// ── لماذا مستودعٌ لا نداءٌ مباشر ──────────────────────────────────────────
// حارسُ `presentation_db_import_guard` يمنع أيَّ ملفِّ عرضٍ **جديد** من
// استيراد `data/database`. فالمكتبةُ لا تملك أن تنادي الـDAO، وكلُّ قدرةٍ
// تحتاجها لا بدّ أن تُكشَف في `IInvoiceTemplatesRepository` أوّلاً.
//
// وهذا يقيس السلوكَ الذي تعتمد عليه أزرارُ المكتبة في `BUTTON-CONTRACT.md`:
// النسخُ · التفعيلُ وما يُلغيه · الفكُّ · والحذفُ المحروس.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/invoice_templates_repository_impl.dart';
import 'package:ural_erp/domain/repositories/invoice_templates_repository.dart';

const _assetDir = 'assets/invoice_templates';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late IInvoiceTemplatesRepository repo;

  setUp(() {
    db = AppDatabase.forTesting();
    repo = InvoiceTemplatesRepositoryImpl(db);
  });
  tearDown(() => db.close());

  group('النسخ', () {
    test('النسخةُ تحمل كلَّ عناصر الأصل ولا تنقص واحداً', () async {
      final srcId = await _import(repo, 'a4_sales_tax_invoice.json');
      final srcEls = await repo.getTemplateElements(srcId);

      final copyId = await repo.duplicateTemplate(srcId);
      final copyEls = await repo.getTemplateElements(copyId);

      expect(copyId, isNot(srcId));
      // العددُ لا «> صفر»: نسخٌ يدويٌّ يُنسى تحديثُه يخرج ناقصاً بصمت.
      expect(copyEls.length, srcEls.length,
          reason: 'النسخةُ نقصت عناصرَ — والفرقُ لا يُرى إلّا بمقارنة ورقتين');

      // والمحتوى لا العدد فحسب.
      expect(
        copyEls.map((e) => '${e.elementType}|${e.content}').toSet(),
        srcEls.map((e) => '${e.elementType}|${e.content}').toSet(),
        reason: 'العددُ تطابق والمحتوى اختلف — نسخةٌ شكليّة',
      );
    });

    test('النسخةُ لا ترث رابطاتِ الأصل', () async {
      // وإلّا خطفت النسخةُ مستنداتِ أصلها لحظةَ إنشائها، وطُبع مستندٌ بقالبٍ
      // لم يختره أحد.
      final srcId = await _import(repo, 'a4_sales_tax_invoice.json');
      await repo.activateBinding(
          templateId: srcId, documentType: 'sales_invoice');

      final copyId = await repo.duplicateTemplate(srcId);

      expect(await repo.getBindingsForTemplate(copyId), isEmpty,
          reason: 'النسخةُ ورثت رابطةً فخطفت مستندَ الأصل');
      expect(await repo.getBindingsForTemplate(srcId), hasLength(1),
          reason: 'النسخُ سرق رابطةَ الأصل بدل أن يتركها');
    });

    test('اسمُ النسخة يُميَّز', () async {
      final srcId = await _import(repo, 'a4_sales_tax_invoice.json');
      final src = (await repo.getAllTemplates()).firstWhere((t) => t.id == srcId);
      final copyId = await repo.duplicateTemplate(srcId);
      final copy = (await repo.getAllTemplates()).firstWhere((t) => t.id == copyId);

      expect(copy.name, isNot(src.name),
          reason: 'نسختان بنفس الاسم في المكتبة لا يُفرَّق بينهما');
      expect(copy.name, contains(src.name));
    });
  });

  group('الرابطات', () {
    test('التفعيلُ يُرجع ما ألغاه — لا يُلغي صامتاً', () async {
      // الإلغاءُ الصامتُ يجعل المستخدمَ يظنّ قالبين مفعَّلَين.
      final a = await _import(repo, 'a4_sales_tax_invoice.json');
      final b = await _import(repo, 'a4_commercial.json');

      final first =
          await repo.activateBinding(templateId: a, documentType: 'sales_invoice');
      expect(first, isEmpty, reason: 'لا شيءَ كان مفعَّلاً ليُلغى');

      final second =
          await repo.activateBinding(templateId: b, documentType: 'sales_invoice');
      expect(second, hasLength(1),
          reason: 'أُلغيت رابطةُ الأوّل ولم تُذكر — إلغاءٌ صامت');
      expect(second.first.templateId, a,
          reason: 'أُلغيت رابطةٌ أخرى غيرُ المتعارضة');
    });

    test('الفكُّ يُرجع عددَ ما حُذف، وصفراً لمفتاحٍ غير مربوط', () async {
      final a = await _import(repo, 'a4_sales_tax_invoice.json');
      await repo.activateBinding(templateId: a, documentType: 'sales_invoice');

      expect(await repo.deactivateBinding(documentType: 'sales_invoice'), 1);
      expect(await repo.deactivateBinding(documentType: 'sales_invoice'), 0,
          reason: 'فكٌّ ثانٍ حذف شيئاً — أو أبلغ عن حذفٍ لم يقع');
    });

    test('`getAllBindings` ترى ما كُتب', () async {
      final a = await _import(repo, 'a4_sales_tax_invoice.json');
      expect(await repo.getAllBindings(), isEmpty);
      await repo.activateBinding(templateId: a, documentType: 'sales_invoice');
      expect(await repo.getAllBindings(), hasLength(1));
    });
  });

  group('الحذفُ المحروس', () {
    test('قالبٌ مربوطٌ يُرفض حذفُه — ويقول بكم رابطة', () async {
      // بدونه تُطبع مستنداتٌ بلا قالبٍ بعد أسابيعَ بلا سببٍ ظاهر.
      final a = await _import(repo, 'a4_sales_tax_invoice.json');
      await repo.activateBinding(templateId: a, documentType: 'sales_invoice');

      expect(
        () => repo.deleteTemplateGuarded(a),
        throwsA(isA<TemplateBoundException>()),
        reason: 'حُذف قالبٌ مربوط',
      );
      expect((await repo.getAllTemplates()).any((t) => t.id == a), isTrue,
          reason: 'الرفضُ رُمي والقالبُ حُذف — أسوأُ الحالتين');
    });

    test('قالبٌ حرٌّ يُحذف', () async {
      final a = await _import(repo, 'a4_sales_tax_invoice.json');
      await repo.deleteTemplateGuarded(a);
      expect((await repo.getAllTemplates()).any((t) => t.id == a), isFalse);
    });

    test('وبعد الفكِّ يُحذف', () async {
      final a = await _import(repo, 'a4_sales_tax_invoice.json');
      await repo.activateBinding(templateId: a, documentType: 'sales_invoice');
      await repo.deactivateBinding(documentType: 'sales_invoice');
      await repo.deleteTemplateGuarded(a);
      expect((await repo.getAllTemplates()).any((t) => t.id == a), isFalse,
          reason: 'الرابطةُ فُكّت والحارسُ ما زال يرفض');
    });
  });

  test('إعداداتُ الجدول تُقرأ من المستودع', () async {
    final a = await _import(repo, 'a4_sales_tax_invoice.json');
    // قد تكون `null` لقالبٍ بلا إعدادات — والمقيسُ أنّ النداءَ يعمل ولا يرمي.
    await repo.getTableSettings(a);
  });
}

Future<int> _import(IInvoiceTemplatesRepository repo, String file) async =>
    repo.importTemplateFromJson(await File('$_assetDir/$file').readAsString());
