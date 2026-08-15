// ═══════════════════════════════════════════════════════════════════════════
// استعلامُ التسعير — البحثُ بالاسم يعرض قائمةً تُختار، لا أوّلَ مطابقةٍ صامتة
// ═══════════════════════════════════════════════════════════════════════════
//
// بلاغُ المالك: «عند تسعير الأصناف لا تظهر لي لستة خاصة بالبحث النصّي لاختيار
// الذي أريد الاستعلام عنه».
//
// والجذرُ سطرٌ واحدٌ مقيس: `getProducts(query: query, limit: 1)` — فالبحثُ
// بالاسم كان يجلب **واحداً** ويعرضه بلا أن يعلم المستخدمُ أن هناك غيرَه.
// فمن يبحث «لبن» ولديه خمسةُ أصناف لبنٍ يرى واحداً بلا اختيار، ولا شيءَ في
// الشاشة يقول إن ثمّةَ أربعةً أخرى.
//
// ── وما يجب ألّا ينكسر ─────────────────────────────────────────────────────
// مسارُ الباركود/الكود يبقى **مطابقةً واحدةً مباشرة**: هذا مسحٌ سريعٌ بقارئ،
// وإقحامُ قائمةٍ بينه وبين النتيجة يبطّئ الاستعمالَ الأساسيَّ للحوار.
//
// ولا قاعدةَ بياناتٍ هنا: المستودعُ مزيَّفٌ بـ`noSuchMethod` (الواجهةُ فيها ٦٤
// دالّةً ولا يلزم منها إلا ثلاث). فلا `AppDatabase` ولا مؤقّتاتُ drift تنتظر
// الإغلاقَ — وهو سببُ تعليق اختبارات الودجت المعروف في هذا المستودع.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/domain/entities/product_entity.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/presentation/pos/widgets/product_pricing_inquiry.dart';

ProductEntity _product({
  required int id,
  required String code,
  required String name,
  String? barcode,
  double salePrice = 10,
}) =>
    ProductEntity(
      id: id,
      code: code,
      name: name,
      barcode: barcode,
      salePrice: salePrice,
      costPrice: 5,
      currentStock: 3,
      minStock: 0,
    );

/// مستودعٌ مزيَّفٌ لا يجيب إلا الدوالَّ الثلاثَ التي يستعملها الحوار.
class _FakeProductRepo implements IProductRepository {
  _FakeProductRepo({
    this.byBarcode,
    this.byCode,
    this.byName = const [],
  });

  final ProductEntity? byBarcode;
  final ProductEntity? byCode;
  final List<ProductEntity> byName;

  /// آخرُ `limit` طُلب — الشاهدُ على أن البحثَ لم يعد مقيَّداً بواحد.
  int? lastLimit;

  @override
  Future<ProductEntity?> getProductByBarcode(String barcode) async => byBarcode;

  @override
  Future<ProductEntity?> getProductByCode(String code) async => byCode;

  @override
  Future<List<ProductEntity>> getProducts({
    int limit = 20,
    int offset = 0,
    String? query,
    int? categoryId,
  }) async {
    lastLimit = limit;
    return byName;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} غيرُ مستعملٍ في الحوار');
}

Future<void> _openDialog(WidgetTester tester, _FakeProductRepo repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [productRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        home: Scaffold(body: ProductPricingInquiry()),
      ),
    ),
  );
  await tester.tap(find.text('تسعير الأصناف (إستعلام)'));
  await tester.pumpAndSettle();
}

Future<void> _searchFor(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).last, query);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('البحثُ بالاسم يعرض كلَّ المطابقات لا أوّلَها', (tester) async {
    final repo = _FakeProductRepo(byName: [
      _product(id: 1, code: 'M1', name: 'لبن كامل الدسم', barcode: 'BC-001'),
      _product(id: 2, code: 'M2', name: 'لبن خالي الدسم', barcode: 'BC-002'),
      _product(id: 3, code: 'M3', name: 'لبن بالشوكولاتة', barcode: 'BC-003'),
    ]);

    await _openDialog(tester, repo);
    await _searchFor(tester, 'لبن');

    expect(find.text('لبن كامل الدسم'), findsOneWidget);
    expect(find.text('لبن خالي الدسم'), findsOneWidget);
    expect(find.text('لبن بالشوكولاتة'), findsOneWidget);
  });

  testWidgets('حدُّ البحث لم يعد واحداً', (tester) async {
    final repo = _FakeProductRepo(byName: [
      _product(id: 1, code: 'M1', name: 'لبن كامل الدسم'),
      _product(id: 2, code: 'M2', name: 'لبن خالي الدسم'),
    ]);

    await _openDialog(tester, repo);
    await _searchFor(tester, 'لبن');

    // ⚠️ الشاهدُ على الجذر نفسِه: `limit: 1` كان يجعل القائمةَ مستحيلةً مهما
    // تغيّر العرض.
    expect(repo.lastLimit, greaterThan(1));
  });

  testWidgets('اختيارُ صنفٍ من القائمة يعرض تفاصيلَه وحدَه', (tester) async {
    final repo = _FakeProductRepo(byName: [
      _product(id: 1, code: 'M1', name: 'لبن كامل الدسم', barcode: 'BC-001'),
      _product(id: 2, code: 'M2', name: 'لبن خالي الدسم', barcode: 'BC-002'),
    ]);

    await _openDialog(tester, repo);
    await _searchFor(tester, 'لبن');
    await tester.tap(find.text('لبن خالي الدسم'));
    await tester.pumpAndSettle();

    // لوحُ التفاصيل وحدَه هو الذي يرسم شريحةَ الباركود.
    expect(find.text('BC-002'), findsOneWidget);
    // والمرشّحُ الآخرُ انصرف — وإلا لبقيت القائمةُ فوق التفاصيل.
    expect(find.text('لبن كامل الدسم'), findsNothing);
  });

  testWidgets('الباركودُ يبقى مطابقةً مباشرةً بلا قائمة', (tester) async {
    final repo = _FakeProductRepo(
      byBarcode: _product(
        id: 9,
        code: 'S9',
        name: 'سكر',
        barcode: '6221031492',
      ),
      // لو التُمس مسارُ الاسم لظهر هذان، وهو بعينه الانكسارُ المخشيّ.
      byName: [
        _product(id: 1, code: 'M1', name: 'لبن كامل الدسم'),
        _product(id: 2, code: 'M2', name: 'لبن خالي الدسم'),
      ],
    );

    await _openDialog(tester, repo);
    await _searchFor(tester, '6221031492');

    // ⚠️ الشاهدُ على **الاسم** لا الباركود: حقلُ البحث نفسُه يحمل الباركودَ
    // المكتوب، فـ`find.text` يجده مرّتين ويسقط الشاهدُ بلا عطبٍ في الإنتاج.
    expect(find.text('سكر'), findsOneWidget);
    expect(find.text('لبن كامل الدسم'), findsNothing);
  });

  testWidgets('كودُ الصنف يبقى مطابقةً مباشرةً بلا قائمة', (tester) async {
    final repo = _FakeProductRepo(
      byCode: _product(id: 7, code: 'A7', name: 'أرز', barcode: 'BC-A7'),
      byName: [
        _product(id: 1, code: 'M1', name: 'لبن كامل الدسم'),
        _product(id: 2, code: 'M2', name: 'لبن خالي الدسم'),
      ],
    );

    await _openDialog(tester, repo);
    await _searchFor(tester, 'A7');

    expect(find.text('أرز'), findsOneWidget);
    expect(find.text('لبن كامل الدسم'), findsNothing);
  });

  testWidgets('مطابقةُ اسمٍ واحدةٌ تُعرض تفاصيلَها مباشرة', (tester) async {
    final repo = _FakeProductRepo(byName: [
      _product(id: 1, code: 'M1', name: 'لبن كامل الدسم', barcode: 'BC-001'),
    ]);

    await _openDialog(tester, repo);
    await _searchFor(tester, 'لبن كامل');

    // اختيارٌ من عنصرٍ واحدٍ ليس اختياراً — والقائمةُ هنا خطوةٌ زائدة.
    expect(find.text('BC-001'), findsOneWidget);
  });
}
