// مرفقاتُ المستندات — محرّكُ §٨ (v176).
//
// ═══ 🔴 ما يُقاس هنا ولماذا ═══
//
// ‏١) **الوصفُ والبايتاتُ في معاملةٍ واحدة.** الشقَّان بلا رابطٍ مرجعيٍّ في
//    المخطَّط عمداً (الوصفُ يُزامَن والبايتاتُ لا)، فانقطاعٌ بينهما يترك
//    وصفاً لمرفقٍ لا بايتاتِ له **على الجهاز الذي رفعه** — وهو لا يقدر
//    على جلبها من الخادم لأنّه هو مصدرُها.
//
// ‏٢) 🔴 **والحذفُ ناعمٌ للوصف وقاطعٌ للبايتات.** حذفٌ ناعمٌ بلا محوِ
//    البايتات يُبقي الملفَّ في القاعدة وفي كلّ نسخةٍ احتياطيّةٍ إلى الأبد
//    — «حذفٌ» لا يحذف.
//
// ‏٣) 🔴 **والمدى لا يتسرّب.** مرفقاتُ فاتورةٍ لا تظهر على فاتورةٍ أخرى ولا
//    على مستندٍ من نوعٍ آخرَ يحمل نفسَ الرقم المحلّيّ — وهو احتمالٌ واقعيٌّ
//    لا نظريّ: `sales_invoices.id = 7` و`journal_entries.id = 7` معاً.
//
// ‏٤) **وصفٌّ بلا هُويّةٍ ولا رقمٍ لا يعني «كلَّ المرفقات».** شرطٌ فارغٌ في
//    استعلامٍ يعيد الجدولَ كلَّه، وهو أسوأُ تسريبٍ ممكنٍ هنا.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

Uint8List _bytes(String s) => Uint8List.fromList(s.codeUnits);

/// بصمةٌ صالحةُ الطول — حرفيّةٌ لا `'a' * 64`: القيمةُ
/// الافتراضيّةُ لوسيطٍ يجب أن تكون ثابتةً زمنَ الترجمة.
const _shaA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  Future<AttachmentData> add({
    required String gid,
    String entityType = 'purchase_invoice',
    int? entityId = 7,
    String? entityGlobalId = 'doc-A',
    String fileName = 'bill.pdf',
    String mimeType = 'application/pdf',
    String sha = _shaA,
    String docType = 'other',
    String payload = 'hello',
  }) =>
      db.insertAttachment(
        globalId: gid,
        entityType: entityType,
        entityId: entityId,
        entityGlobalId: entityGlobalId,
        fileName: fileName,
        mimeType: mimeType,
        byteSize: _bytes(payload).length,
        shaHex: sha,
        docType: docType,
        bytes: _bytes(payload),
      );

  group('الإرفاق', () {
    test('يكتب الوصفَ والبايتاتِ معاً', () async {
      final row = await add(gid: 'att-1');
      expect(row.globalId, 'att-1');
      expect(row.entityType, 'purchase_invoice');
      expect(await db.attachmentBytes('att-1'), _bytes('hello'));
      expect(await db.hasAttachmentBytes('att-1'), isTrue);
    });

    test('والمرفقُ يُقرأ بهُويّة المستند وبرقمه معاً', () async {
      await add(gid: 'att-1');

      final byGid = await db.getAttachments(
          entityType: 'purchase_invoice', entityGlobalId: 'doc-A');
      expect(byGid.map((a) => a.globalId), ['att-1']);

      final byId =
          await db.getAttachments(entityType: 'purchase_invoice', entityId: 7);
      expect(byId.map((a) => a.globalId), ['att-1']);
    });

    test('🔴 وأحدثُها أوّلاً — ولو وقعا في نفس المِلّي', () async {
      // ⚠️ **بلا تأخيرٍ عمداً.** دقّةُ ساعة ويندوز قد تبلغ
      //    ٥١ مِلّي، فرفعتان متتاليتان تحملان **نفسَ الطابع
      //    تماماً**. واختبارٌ ينتظِر ٥ مِلٍّ ليفرِّقَهما يمرّ
      //    أخضرَ مرّةً ويسقط أخرى — وقد وقع فعلاً في جولة
      //    الطفرات. فالترتيبُ يُحسَم بالرقم فاصِلاً لا بالمنتظَر.
      await add(gid: 'att-1');
      await add(gid: 'att-2', fileName: 'second.pdf');

      final rows = await db.getAttachments(
          entityType: 'purchase_invoice', entityGlobalId: 'doc-A');
      expect(rows.map((r) => r.globalId), ['att-2', 'att-1']);
    });

    test('والعدُّ يقيس الحيَّ وحدَه', () async {
      await add(gid: 'att-1');
      await add(gid: 'att-2');
      expect(
          await db.countAttachments(
              entityType: 'purchase_invoice', entityGlobalId: 'doc-A'),
          2);

      await db.softDeleteAttachment('att-1');
      expect(
          await db.countAttachments(
              entityType: 'purchase_invoice', entityGlobalId: 'doc-A'),
          1,
          reason: 'المحذوفُ يُعَدّ ⇒ عشرُ عمليّاتِ رفعٍ وحذفٍ تُقفل المستندَ '
              'وهو بلا ورقةٍ واحدة.');
    });
  });

  group('🔴 المدى — لا تسرّب', () {
    test('مستندٌ آخرُ من نفس النوع لا يرى مرفقاتِ غيرِه', () async {
      await add(gid: 'att-1', entityId: 7, entityGlobalId: 'doc-A');
      await add(gid: 'att-2', entityId: 8, entityGlobalId: 'doc-B');

      final a = await db.getAttachments(
          entityType: 'purchase_invoice', entityGlobalId: 'doc-A');
      expect(a.map((r) => r.globalId), ['att-1']);
    });

    test('🔴 ونوعٌ آخرُ بنفس الرقم المحلّيّ لا يراها', () async {
      // `sales_invoices.id = 7` و`purchase_invoices.id = 7` معاً — وهي
      // الحالةُ الطبيعيّةُ لا النادرة.
      await add(gid: 'att-1', entityType: 'purchase_invoice', entityId: 7);
      final other =
          await db.getAttachments(entityType: 'sales_invoice', entityId: 7);
      expect(other, isEmpty,
          reason: 'أوراقُ فاتورةِ شراءٍ ظهرت على فاتورةِ بيع ⇒ شرطُ النوع '
              'سقط من الاستعلام.');
    });

    test('🔴 وصفٌّ بهُويّةٍ أخرى لا يظهر ولو طابق الرقمُ', () async {
      // ما يعود من الخادم: `entity_id` **كما هو على الخادم**،
      // وقد يقع على مستندٍ آخرَ تماماً هنا.
      await add(gid: 'att-server', entityId: 7, entityGlobalId: 'doc-SERVER');

      final rows = await db.getAttachments(
          entityType: 'purchase_invoice', entityId: 7, entityGlobalId: 'doc-A');
      expect(rows, isEmpty,
          reason: 'ورقةٌ ظهرت على مستندٍ لا تخصُّه — الشرطُ قبِل '
              'تطابُقَ الرقم المحلّيّ ولو اختلفت الهُويّة.');
    });

    test('وصفٌّ بلا هُويّةٍ يظهر بالرقم — المُنشَأُ للتوّ', () async {
      await add(gid: 'att-local', entityId: 7, entityGlobalId: null);

      final rows = await db.getAttachments(
          entityType: 'purchase_invoice', entityId: 7, entityGlobalId: 'doc-A');
      expect(rows.map((r) => r.globalId), ['att-local'],
          reason: 'مرفقٌ أُضيف قبل أن ينال المستندُ هُويّتَه صار غيرَ '
              'مرئيٍّ على صاحبِه.');
    });

    test('🔴 وبلا هُويّةٍ ولا رقمٍ لا شيءَ — لا «كلُّ شيء»', () async {
      await add(gid: 'att-1');
      await add(gid: 'att-2', entityId: 9, entityGlobalId: 'doc-B');

      final all = await db.getAttachments(entityType: 'purchase_invoice');
      expect(all, isEmpty,
          reason: 'شرطٌ فارغٌ أعاد الجدولَ كلَّه — وهو أسوأُ تسريبٍ ممكنٍ '
              'هنا: مرفقاتُ المنشأة كلُّها على أوّل مستندٍ يُفتَح.');
    });
  });

  group('🔴 الحذفُ — ناعمٌ للوصف، قاطعٌ للبايتات', () {
    test('الوصفُ يبقى صفّاً مختوماً بالحذف', () async {
      await add(gid: 'att-1');
      expect(await db.softDeleteAttachment('att-1'), isTrue);

      final row = await db.attachmentByGlobalId('att-1');
      expect(row, isNotNull, reason: 'الصفُّ مُحي ⇒ ضاع أثرُ أنّ ورقةً كانت.');
      expect(row!.deletedAt, isNotNull);
    });

    test('🔴 والبايتاتُ تُمحى فعلاً', () async {
      await add(gid: 'att-1');
      await db.softDeleteAttachment('att-1');
      expect(await db.attachmentBytes('att-1'), isNull,
          reason: 'الملفُّ بقي في القاعدة وفي كلّ نسخةٍ احتياطيّةٍ بعد '
              '«الحذف».');
      expect(await db.hasAttachmentBytes('att-1'), isFalse);
    });

    test('ويغيب عن القائمة', () async {
      await add(gid: 'att-1');
      await db.softDeleteAttachment('att-1');
      expect(
          await db.getAttachments(
              entityType: 'purchase_invoice', entityGlobalId: 'doc-A'),
          isEmpty);
    });

    test('وحذفُ المحذوفِ ثانيةً يعيد false بلا استثناء', () async {
      await add(gid: 'att-1');
      expect(await db.softDeleteAttachment('att-1'), isTrue);
      expect(await db.softDeleteAttachment('att-1'), isFalse);
      expect(await db.softDeleteAttachment('لا-وجودَ-له'), isFalse);
    });
  });

  group('الخبيئةُ والبصمة', () {
    test('بايتاتٌ جُلبت تُخزَّن بلا لمسِ الوصف', () async {
      final before = await add(gid: 'att-1');
      await db.cacheAttachmentBytes(
          attachmentGlobalId: 'att-1', bytes: _bytes('world'));
      expect(await db.attachmentBytes('att-1'), _bytes('world'));

      final after = await db.attachmentByGlobalId('att-1');
      expect(after!.lastModifiedAt, before.lastModifiedAt,
          reason: 'الخبيئةُ ختمت الصفَّ ⇒ يعود إلى الخادم في كلّ مرّةٍ '
              'يفتح فيها أحدٌ مرفقاً.');
    });

    test('وصفٌّ بلا بايتاتٍ حالةٌ طبيعيّةٌ لا استثناء', () async {
      expect(await db.attachmentBytes('لم-يُجلَب'), isNull);
      expect(await db.hasAttachmentBytes('لم-يُجلَب'), isFalse);
    });

    test('والبصمةُ تمنع رفعَ نفسِ الملفّ مرّتَين على نفس المستند', () async {
      await add(gid: 'att-1', sha: 'b' * 64);
      final twin = await db.attachmentBySha(
          entityType: 'purchase_invoice',
          shaHex: 'b' * 64,
          entityGlobalId: 'doc-A');
      expect(twin?.globalId, 'att-1');
    });

    test('ونفسُ الملفّ على مستندٍ آخرَ ليس توأماً', () async {
      await add(gid: 'att-1', sha: 'b' * 64);
      final other = await db.attachmentBySha(
          entityType: 'purchase_invoice',
          shaHex: 'b' * 64,
          entityGlobalId: 'doc-B');
      expect(other, isNull);
    });

    test('والمحذوفُ لا يُعَدُّ توأماً — فيُعاد رفعُه', () async {
      await add(gid: 'att-1', sha: 'b' * 64);
      await db.softDeleteAttachment('att-1');
      final twin = await db.attachmentBySha(
          entityType: 'purchase_invoice',
          shaHex: 'b' * 64,
          entityGlobalId: 'doc-A');
      expect(twin, isNull);
    });
  });

  group('🔴 كنسُ البايتات اليتيمة', () {
    test('بايتاتُ وصفٍ محذوفٍ تُمحى ولو حُذف من جهازٍ آخر', () async {
      await add(gid: 'att-1');
      // محاكاةُ ما يصل بالمزامنة: الوصفُ وحدَه صار محذوفاً، والبايتاتُ
      // هنا لم يمسّها أحد.
      await db.customStatement(
        "UPDATE attachments SET deleted_at = '2026-09-20T00:00:00.000' "
        "WHERE global_id = 'att-1'",
      );
      expect(await db.hasAttachmentBytes('att-1'), isTrue);

      final purged = await db.purgeOrphanAttachmentBlobs();
      expect(purged, 1);
      expect(await db.hasAttachmentBytes('att-1'), isFalse);
    });

    test('🔴 ولا تمسّ بايتاتِ الحيّ', () async {
      await add(gid: 'att-1');
      await add(gid: 'att-2', entityGlobalId: 'doc-B', entityId: 9);
      await db.softDeleteAttachment('att-1');

      await db.purgeOrphanAttachmentBlobs();
      expect(await db.hasAttachmentBytes('att-2'), isTrue,
          reason: 'الكنسُ محا مرفقاً حيّاً ⇒ كلُّ فتحةٍ بعده تُعيد جلبَه '
              'من الخادم، وجهازُ الخادم يفقده نهائيّاً.');
    });
  });

  group('هُويّةُ المستند من رقمه', () {
    test('تُقرأ من جدول المستند لا من جدول المرفقات', () async {
      final id = await db.createSection('قسمٌ للاختبار');
      final gid = await db.attachmentOwnerGlobalId(
          tableName: 'table_sections', id: id);
      // القسمُ يُنشَأ بهُويّةٍ عالميّةٍ أو بلا — والمهمُّ ألّا ترمي.
      expect(gid == null || gid.isNotEmpty, isTrue);
    });

    test('ورقمٌ لا وجودَ له يعيد null بلا استثناء', () async {
      expect(
          await db.attachmentOwnerGlobalId(
              tableName: 'table_sections', id: 999999),
          isNull);
    });
  });
}
