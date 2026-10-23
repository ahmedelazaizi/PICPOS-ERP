// ═══════════════════════════════════════════════════════════════════════════
// §٢ — اللوحةُ تطيع وجهةَ التخطيط، ولا يظهر حقلا بحثٍ اثنان أبداً
// ═══════════════════════════════════════════════════════════════════════════
//
// `pos_layout_policy_test` يقيس **القرار** (أيُّ وجهةٍ لأيّ علامة). وهذا
// الملفُّ يقيس **الطاعة**: أن اللوحةَ ترسم ما قرّرته الوجهة.
//
// والخطرُ المحدَّد: حقلُ البحث يعيش أصلاً داخلَ `ProductGrid`. فرفعُه إلى صفّ
// الباركود بلا إطفاء الداخليّ يعطي **حقلَين يكتبان في نفس الحالة** — يظهران
// معاً ويتسابقان على `setSearchQuery`. ولذلك يُقاس الطرفان: وجودُ المرفوع،
// و`showInlineSearch` المُمرَّرة للشبكة.
//
// والوجهةُ تُمرَّر معاملاً صريحاً فيجري القياسُ تحت النكهة الافتراضية
// `uralcash` — وهي التي تشتغل عليها البوابةُ كلُّها.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/config/pos_layout_policy.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/data/providers/repository_providers.dart';
import 'package:picpos_erp/data/database/database.dart' show ProductBarcode;
import 'package:picpos_erp/data/providers/settings_providers.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/presentation/pos/widgets/pos_product_search_field.dart';
import 'package:picpos_erp/presentation/pos/widgets/pos_product_selection_panel.dart';
import 'package:picpos_erp/presentation/pos/widgets/product_grid.dart';

class _EmptyProductRepo implements IProductRepository {
  @override
  Future<List<ProductBarcode>> getAllProductBarcodes() async => const [];

  @override
  Future<List<ProductEntity>> getProducts({
    int limit = 20,
    int offset = 0,
    String? query,
    int? categoryId,
  }) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '${invocation.memberName} خارجَ ما تحتاجه اللوحةُ في هذا الاختبار',
      );
}

Future<void> _pumpPanel(WidgetTester tester, PosLayoutPolicy layout) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // الحارسُ يفشل **مغلقاً** بلا قيمة، فبدون هذه المنحة لا يُرسم شيءٌ
        // أصلاً ويمرّ الاختبارُ أخضرَ على فراغ.
        currentUserPermissionsProvider
            .overrideWith((ref) async => const ['pos_search', 'pos_add_product']),
        showBarcodeInPOSProvider.overrideWith((ref) async => true),
        showSearchInPOSProvider.overrideWith((ref) async => true),
        productRepositoryProvider.overrideWithValue(_EmptyProductRepo()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PosProductSelectionPanel(
            barcodeController: TextEditingController(),
            barcodeFocus: FocusNode(),
            onSearchBarcode: (_) {},
            onProductTap: (_) {},
            layout: layout,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('وجهةُ PicPos ترفع الحقلَ وتُطفئ الداخليّ', (tester) async {
    await _pumpPanel(tester, PosLayoutPolicy.picpos);

    expect(find.byType(PosProductSearchField), findsOneWidget);

    final grid = tester.widget<ProductGrid>(find.byType(ProductGrid));
    expect(
      grid.showInlineSearch,
      isFalse,
      reason: 'الحقلُ الداخليُّ لم يُطفأ — حقلا بحثٍ على نفس الحالة',
    );
  });

  testWidgets('والوجهةُ الافتراضيةُ تُبقي كلَّ شيءٍ كما كان', (tester) async {
    await _pumpPanel(tester, PosLayoutPolicy.stacked);

    expect(
      find.byType(PosProductSearchField),
      findsNothing,
      reason: 'الحقلُ المرفوعُ ظهر في تخطيطٍ لا يطلبه — تسرُّبٌ لفورك آخر',
    );

    final grid = tester.widget<ProductGrid>(find.byType(ProductGrid));
    expect(grid.showInlineSearch, isTrue);
  });
}
