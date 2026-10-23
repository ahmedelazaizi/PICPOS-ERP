// Task 6b — طبقة الإدارة: العروض (`offers_edit`, `offers_delete`).
//
// «تعديل» و«حذف» في كارت العرض بينداهم `PopupMenuButton.onSelected` لكل
// كارت — مفيش ودجت واحد يتلف بـ`PermissionGuard` (الـ`PopupMenuItem` نفسه
// بيمسك الضغطة ويقفل الميني قبل ما أي حارس جواه يشتغل، نفس وضع
// `einvoice_cancel` في Task 6a). الفحص الحقيقي جوه `onSelected` في
// `offer_cards.dart`، اتستخرج منطقه لدالتين top-level (`canEditOffer`/
// `canDeleteOffer`) عشان تتفحصوا من غير تركيب `OffersScreen` كاملة.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/presentation/screens/offers_screen.dart';

void main() {
  group('canEditOffer — offers_edit', () {
    test('من غير الصلاحية ومن غير أدمن: ممنوع', () {
      expect(canEditOffer(const []), isFalse);
      expect(canEditOffer(const ['some_other_perm']), isFalse);
    });

    test('مع offers_edit: مسموح', () {
      expect(canEditOffer([PermissionCodes.offersEdit]), isTrue);
    });

    test('أدمن (system_admin أو *) بيعدّى — الكود ده مش critical financial op',
        () {
      expect(canEditOffer(const ['system_admin']), isTrue);
      expect(canEditOffer(const ['*']), isTrue);
    });
  });

  group('canDeleteOffer — offers_delete', () {
    test('من غير الصلاحية ومن غير أدمن: ممنوع', () {
      expect(canDeleteOffer(const []), isFalse);
      expect(canDeleteOffer(const ['some_other_perm']), isFalse);
    });

    test('مع offers_delete: مسموح', () {
      expect(canDeleteOffer([PermissionCodes.offersDelete]), isTrue);
    });

    test('أدمن (system_admin أو *) بيعدّى', () {
      expect(canDeleteOffer(const ['system_admin']), isTrue);
      expect(canDeleteOffer(const ['*']), isTrue);
    });

    test('offers_edit وحده ما يكفيش لحذف — الأكواد منفصلة', () {
      expect(canDeleteOffer([PermissionCodes.offersEdit]), isFalse);
    });
  });
}
