// ═══════════════════════════════════════════════════════════════════════════
// متطلبات العميل 2026-07-25 · م7 · البند 3 (الفجوة المتبقية) — نسخة المرتجع
// المحلية في وضع العميل لا تحمل رابطاً بالفاتورة الأصلية.
// ═══════════════════════════════════════════════════════════════════════════
//
// م0 أصلح الجانب الخادمي (كان يكتب معرّف العميل في نص الربط). تبقّى الطرف
// الآخر: في وضع العميل/المرآة يُكتب صف مرتجع محلي **بلا `notes`** إطلاقاً،
// و`getReturnedAmountsForInvoices` تربط عبر ذلك النص — فالجهاز يُنقص قيمة
// المرتجع محلياً حتى يأتي السحب التفاضلي بنسخة الخادم.
//
// الأثر: بعد المرتجع مباشرةً يعرض الجهاز «متبقياً» أكبر من الحقيقي حتى
// المزامنة التالية.
//
// ملاحظة على النطاق: الإصلاح الجذري (عمود ربط حقيقي بدل تحليل نصّي) يتطلّب
// تغيير سكيمة + إعادة توليد + تعديل استراتيجيات المزامنة. هذا الإصلاح يغلق
// الفجوة **بلا أي تغيير سكيمة**، ويبقى العمود توصيةً لاحقة.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int warehouseId;
  late int userId;
  late int customerId;

  setUp(() async {
    db = AppDatabase.forTesting();
    warehouseId = await db.into(db.warehouses).insert(
        WarehousesCompanion.insert(
            name: 'مخزن م7', globalId: const Value('gid-wh-m7')));
    userId = await db.into(db.users).insert(UsersCompanion.insert(
          username: 'm7_user',
          passwordHash: 'x',
          displayName: 'M7',
          roleId: const Value(1),
        ));
    customerId = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'عميل م7',
          isCustomer: const Value(true),
          globalId: const Value('gid-cust-m7'),
        ));
  });

  tearDown(() async => db.close());

  test('صف المرتجع المحلي يحمل رابط الفاتورة الأصلية فيُخصم من المتبقي',
      () async {
    final originalId = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'INV-M7',
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: DateTime(2026, 7, 10),
            customerId: Value(customerId),
            total: const Value(1000),
            paid: const Value(400),
          ),
        );

    // نفس ما يكتبه مسار العميل في التخزين المحلي.
    await db.insertSalesInvoiceWithoutStock(
      invoice: SalesInvoicesCompanion.insert(
        invoiceNumber: 'SRET-abcd1234',
        warehouseId: warehouseId,
        userId: userId,
        invoiceDate: DateTime(2026, 7, 11),
        customerId: Value(customerId),
        subtotal: const Value(300),
        total: const Value(300),
        paid: const Value(0),
        saleType: const Value('return'),
        status: const Value('completed'),
        globalId: const Value('gid-sret-m7'),
        notes: Value(localReturnLinkNote(originalId)),
      ),
      items: const [],
    );

    final returned = await db.getReturnedAmountsForInvoices([originalId]);
    expect(returned[originalId], closeTo(300, 0.001),
        reason: 'الجهاز يربط مرتجعه المحلي فوراً — لا ينتظر المزامنة');

    final inv = await (db.select(db.salesInvoices)
          ..where((s) => s.id.equals(originalId)))
        .getSingle();
    expect(inv.total - inv.paid - (returned[originalId] ?? 0), closeTo(300, 0.001),
        reason: 'المتبقي = 1000 − 400 − 300');
  });

  test('صيغة الرابط مطابقة تماماً لما يقرأه الاستعلام', () {
    expect(localReturnLinkNote(42), 'Return for invoice #42');
    expect(localReturnLinkNote(42, originalGlobalId: 'abc'),
        'Return for invoice #42|gid:abc');
  });

  test('الرابط بالمعرّف العالمي يصمد أمام اختلاف المعرّفات بين الجهاز والخادم',
      () async {
    // بعد السحب التفاضلي يستبدل صفُّ الخادم صفَّ العميل، فيحمل **معرّف
    // الخادم**. بلا المعرّف العالمي يُقرأ ذلك الرقم محلياً كمعرّف محلي
    // ⇒ يُخصم المرتجع من فاتورة خاطئة أو من لا شيء.
    final localOriginalId = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'INV-GID',
            warehouseId: warehouseId,
            userId: userId,
            invoiceDate: DateTime(2026, 7, 10),
            customerId: Value(customerId),
            total: const Value(1000),
            paid: const Value(400),
            globalId: const Value('gid-orig-m7b'),
          ),
        );

    // صف مرتجع كما ينزل من الخادم: رقم خادم لا يخصّ هذا الجهاز إطلاقاً.
    await db.insertSalesInvoiceWithoutStock(
      invoice: SalesInvoicesCompanion.insert(
        invoiceNumber: 'SRET-server',
        warehouseId: warehouseId,
        userId: userId,
        invoiceDate: DateTime(2026, 7, 11),
        total: const Value(300),
        paid: const Value(0),
        saleType: const Value('return'),
        globalId: const Value('gid-sret-m7b'),
        notes: Value(localReturnLinkNote(98765,
            originalGlobalId: 'gid-orig-m7b')),
      ),
      items: const [],
    );

    final returned = await db.getReturnedAmountsForInvoices([localOriginalId]);
    expect(returned[localOriginalId], closeTo(300, 0.001),
        reason: 'المعرّف العالمي يعيد الإسناد للفاتورة الصحيحة محلياً');
  });
}
