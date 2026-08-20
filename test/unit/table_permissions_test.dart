import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/domain/models/table_actions.dart';
import 'package:ural_erp/domain/models/table_status.dart';
import 'package:ural_erp/presentation/screens/tables_screen.dart';

void main() {
  // الأفعالُ الثلاثةُ الموصولةُ حديثاً (الإلغاء، تغييرُ الحالة، طباعةُ
  // الفاتورة) تُنادى من قائمةٍ مبنيّةٍ من دالّةٍ خالصة، فحراستُها تعيش عند
  // التنفيذ لا عند الرسم — نفسُ نمط `canPrintPosWorkOrder` المجاور.
  group('hasTableActionPermission', () {
    test('مرفوض من غير الكود', () {
      expect(
          hasTableActionPermission(const [], PermissionCodes.tablesCancel),
          isFalse);
    });

    test('مسموح مع الكود', () {
      expect(
          hasTableActionPermission(
              [PermissionCodes.tablesCancel], PermissionCodes.tablesCancel),
          isTrue);
    });

    test('كودٌ آخرُ لا يفتح البابَ', () {
      expect(
          hasTableActionPermission(
              [PermissionCodes.tablesView], PermissionCodes.tablesCancel),
          isFalse);
    });

    test('مديرُ النظام يمرّ بلا الكود صراحة', () {
      expect(
          hasTableActionPermission(
              const ['system_admin'], PermissionCodes.tablesPrintBill),
          isTrue);
      expect(
          hasTableActionPermission(
              const ['*'], PermissionCodes.tablesManage),
          isTrue);
    });
  });

  // ── نقرةُ الطاولة تفتح طلباً: بوّابةٌ لا نافذةٌ خلفيّة ────────────────────
  //
  // في شاشة PicPos تفتح النقرةُ نافذةَ الطلب، وطاولةٌ بلا طلبٍ نشطٍ تعني
  // «افتح طاولة». وكانت تصل إلى `_confirmOpenTable` **بلا فحصٍ إطلاقاً**
  // بينما زرُّ «فتح طاولة» المجاور محروسٌ — فمن لا يملك `tables_manage` يرى
  // الزرَّ معطَّلاً ويفتح الطلبَ بالنقر. و`blockOnTapOpen` هي البوّابةُ التي
  // يمرّ بها المسارُ الآن، فهي المُختبَرةُ هنا لا تهيئتُها.
  group('blockOnTapOpen — بوّابةُ فتحِ الطاولة بالنقر', () {
    const holder = [PermissionCodes.tablesManage];

    test('بلا صلاحيّةٍ لا يُفتَح طلبٌ ولو كانت الحالةُ تسمح', () {
      expect(blockOnTapOpen(TableStatus.available, const []),
          TableTapBlock.permission);
      expect(blockOnTapOpen(TableStatus.reserved, const []),
          TableTapBlock.permission);
    });

    test('كودٌ آخرُ لا يفتح البابَ', () {
      expect(
          blockOnTapOpen(
              TableStatus.available, const [PermissionCodes.tablesView]),
          TableTapBlock.permission);
    });

    test('حالةٌ لا تقبل الفتحَ تُمنَع ولو كانت الصلاحيّةُ حاضرة', () {
      // ⚪ خارج الخدمة و🟠 مدفوعةٌ ليس في قائمتيهما `open`. والمنعُ يُنسَب
      // إلى الحالة لا إلى الصلاحيّة، فلا تُعرَض رسالةُ رفضٍ كاذبة.
      expect(blockOnTapOpen(TableStatus.outOfService, holder),
          TableTapBlock.status);
      expect(blockOnTapOpen(TableStatus.paid, holder), TableTapBlock.status);
    });

    test('حالةٌ مجهولةٌ تُمنَع — الارتدادُ سجلٌّ فقط', () {
      expect(blockOnTapOpen('cleaning', holder), TableTapBlock.status);
    });

    test('الحالةُ تسمح والصلاحيّةُ حاضرةٌ ⇒ يُفتَح', () {
      expect(blockOnTapOpen(TableStatus.available, holder), isNull);
      expect(blockOnTapOpen(TableStatus.reserved, holder), isNull);
    });

    test('مديرُ النظام يمرّ بلا الكود صراحة', () {
      expect(blockOnTapOpen(TableStatus.available, const ['system_admin']),
          isNull);
      expect(blockOnTapOpen(TableStatus.available, const ['*']), isNull);
    });

    test('البوّابةُ من محرّك الشريط نفسِه لا من شرطٍ موازٍ', () {
      // لو بدّل أحدٌ `actionsForStatus` أو `permissionForAction` لاحقاً،
      // تتبعه البوّابةُ تلقائياً — وهذا التوكيدُ يكشف انفصالَهما لو نُسخ
      // الشرطُ يوماً.
      for (final status in TableStatus.all) {
        final allowedByEngine =
            actionsForStatus(status).contains(TableAction.open);
        expect(blockOnTapOpen(status, holder) == null, allowedByEngine,
            reason: 'البوّابةُ خالفت actionsForStatus في الحالة $status');
      }
      expect(permissionForAction(TableAction.open),
          PermissionCodes.tablesManage);
    });
  });

  test('صلاحيةُ خصم الطاولة مسجَّلةٌ في تصنيف الطاولات', () {
    final entry = PermissionCodes.masterList
        .firstWhere((p) => p['code'] == PermissionCodes.tablesDiscount);
    expect(entry['category'], 'tables');
    expect(entry['name'], isNotEmpty);
  });

  test('طباعةُ فاتورة الطاولة لم تعد محجوزة', () {
    expect(
        PermissionCodes.nonToggleable
            .containsKey(PermissionCodes.tablesPrintBill),
        isFalse);
  });
}
