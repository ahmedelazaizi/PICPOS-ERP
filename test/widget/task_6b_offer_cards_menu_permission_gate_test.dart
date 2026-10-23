// Task 6b — فيكس المراجعة: التحقق من "السلك" في قائمة كارت العرض
// (`offers_edit`/`offers_delete`/`toggle`).
//
// المراجعة رصدت إن `test/unit/task_6b_offer_cards_edit_delete_permission_test.dart`
// كان بيفحص `canEditOffer`/`canDeleteOffer` لوحدهم بس — لو حد شال شرط
// `if (!canEditOffer(perms)) return;` من جوه `onSelected` وسايب الدالة زي ما
// هي، الاختبارات القديمة كانت هتفضل خضرا (نفس شكل باج f8d3fa9: الفحص
// موجود، بس السلك اللي بينده عليه مش مضمون).
//
// عشان الفحص ده يتثبت فعلاً، القائمة كلها (`PopupMenuButton` + منطق
// `onSelected`) اتنقلت لودجت top-level مستقل (`OfferCardActionsMenu` في
// `offer_cards.dart`) بياخد الـcallbacks (`onEdit`/`onDelete`/`onToggle`/
// `onPrintBarcode`) كبارامترات بسيطة. هنا بنبني الودجت ده لوحده (من غير
// شاشة `OffersScreen` ولا قاعدة بيانات)، نفتح الميني فعلياً، نختار عنصر،
// ونتأكد إن الـcallback الحقيقي اتنفذ أو لأ حسب الصلاحية.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/screens/offers_screen.dart';

void main() {
  Future<void> pumpMenu(
    WidgetTester tester,
    List<String> perms, {
    bool offerIsActive = true,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
    required VoidCallback onToggle,
    required VoidCallback onPrintBarcode,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => perms),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: OfferCardActionsMenu(
                offerIsActive: offerIsActive,
                onEdit: onEdit,
                onDelete: onDelete,
                onToggle: onToggle,
                onPrintBarcode: onPrintBarcode,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// بتفتح الميني (تاب على أيقونة الثلاث نقط)، تختار عنصر بالنص، وترجّع.
  /// `settleAfterToast` بيبقى `true` لما الاختيار متوقع يطلع تنبيه رفض —
  /// عشان نصرّف الـTimer (`Future.delayed`) اللي جوه `AppToast` قبل ما
  /// الاختبار يخلص (وإلا هيفشل بـ"A Timer is still pending").
  Future<void> openMenuAndSelect(
    WidgetTester tester,
    String itemText, {
    bool settleAfterToast = false,
  }) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(itemText));
    await tester.pumpAndSettle();
    if (settleAfterToast) {
      // مدة عرض التنبيه (2500ms) + وقت الـreverse animation (300ms).
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  group('OfferCardActionsMenu — offers_edit («تعديل»)', () {
    testWidgets('بدون offers_edit: onEdit ما بيتنفّذش وبيظهر تنبيه رفض',
        (tester) async {
      var edited = false;
      await pumpMenu(
        tester,
        const [],
        onEdit: () => edited = true,
        onDelete: () {},
        onToggle: () {},
        onPrintBarcode: () {},
      );

      await openMenuAndSelect(tester, 'تعديل', settleAfterToast: true);

      expect(edited, isFalse);
    });

    testWidgets('مع offers_edit: onEdit بيتنفّذ فعلاً', (tester) async {
      var edited = false;
      await pumpMenu(
        tester,
        [PermissionCodes.offersEdit],
        onEdit: () => edited = true,
        onDelete: () {},
        onToggle: () {},
        onPrintBarcode: () {},
      );

      await openMenuAndSelect(tester, 'تعديل');

      expect(edited, isTrue);
    });
  });

  group('OfferCardActionsMenu — offers_delete («حذف»)', () {
    testWidgets('بدون offers_delete: onDelete ما بيتنفّذش وبيظهر تنبيه رفض',
        (tester) async {
      var deleted = false;
      await pumpMenu(
        tester,
        const [],
        onEdit: () {},
        onDelete: () => deleted = true,
        onToggle: () {},
        onPrintBarcode: () {},
      );

      await openMenuAndSelect(tester, 'حذف', settleAfterToast: true);

      expect(deleted, isFalse);
    });

    testWidgets('مع offers_delete: onDelete بيتنفّذ فعلاً', (tester) async {
      var deleted = false;
      await pumpMenu(
        tester,
        [PermissionCodes.offersDelete],
        onEdit: () {},
        onDelete: () => deleted = true,
        onToggle: () {},
        onPrintBarcode: () {},
      );

      await openMenuAndSelect(tester, 'حذف');

      expect(deleted, isTrue);
    });

    testWidgets('offers_edit وحده ما يكفيش لحذف — عبر الودجت الحقيقي',
        (tester) async {
      // إثبات إضافي إن الودجت بيستخدم canDeleteOffer الحقيقي (كود مستقل عن
      // canEditOffer) مش شرط واحد بيغطّي الاتنين — مستخدم عنده offers_edit
      // بس المفروض يتمنع من الحذف.
      var deleted = false;
      await pumpMenu(
        tester,
        [PermissionCodes.offersEdit],
        onEdit: () {},
        onDelete: () => deleted = true,
        onToggle: () {},
        onPrintBarcode: () {},
      );

      await openMenuAndSelect(tester, 'حذف', settleAfterToast: true);

      expect(deleted, isFalse);
    });
  });

  group('OfferCardActionsMenu — تفعيل/إيقاف («toggle») بيتحمي بـoffers_edit',
      () {
    testWidgets('بدون offers_edit: onToggle ما بيتنفّذش', (tester) async {
      var toggled = false;
      await pumpMenu(
        tester,
        const [],
        onEdit: () {},
        onDelete: () {},
        onToggle: () => toggled = true,
        onPrintBarcode: () {},
      );

      await openMenuAndSelect(tester, 'إيقاف', settleAfterToast: true);

      expect(toggled, isFalse);
    });

    testWidgets('مع offers_edit: onToggle بيتنفّذ فعلاً', (tester) async {
      var toggled = false;
      await pumpMenu(
        tester,
        [PermissionCodes.offersEdit],
        onEdit: () {},
        onDelete: () {},
        onToggle: () => toggled = true,
        onPrintBarcode: () {},
      );

      await openMenuAndSelect(tester, 'إيقاف');

      expect(toggled, isTrue);
    });
  });

  group('OfferCardActionsMenu — «طباعة باركود» مش محمي (قرار موثّق)', () {
    testWidgets('بيتنفّذ دايماً بغض النظر عن الصلاحيات — مفيش كود مخصص',
        (tester) async {
      var printed = false;
      await pumpMenu(
        tester,
        const [],
        onEdit: () {},
        onDelete: () {},
        onToggle: () {},
        onPrintBarcode: () => printed = true,
      );

      await openMenuAndSelect(tester, 'طباعة باركود');

      expect(printed, isTrue);
    });
  });
}
