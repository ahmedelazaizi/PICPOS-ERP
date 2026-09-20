part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ATTACHMENTS DAO — المرفقات (v176، §٨)
// ═══════════════════════════════════════════════════════════════════════════
//
// ═══ 🔴 الوصفُ والبايتاتُ لا يُكتبان معاً بالضرورة ═══
//
// على **الخادم** يصلان معاً في `POST /api/attachments`، فالجدولان يُملآن في
// معاملةٍ واحدة.
//
// وعلى **العميل** يصل الوصفُ وحدَه بالمزامنة الدوريّة — البايتاتُ لا تركب
// السحبَ عمداً. فصفٌّ في `attachments` بلا صفٍّ في `attachment_blobs` هي
// **الحالةُ الطبيعيّةُ لا عطب**: مرفقٌ يعرفه الجهازُ ولم يجلبه بعد.
//
// ولذلك [attachmentBytes] تعيد `null` بلا استثناء، و[hasAttachmentBytes]
// تفرّق «ليس عندي» عن «لا وجودَ له».

extension AttachmentsDao on AppDatabase {
  // ───────────────────────────────────────────────────────────────────────
  // قراءةُ الوصف
  // ───────────────────────────────────────────────────────────────────────

  /// شرطُ «مرفقاتُ هذا المستند» — **الهُويّةُ العالميّةُ أوّلاً**.
  ///
  /// 🔴 **والرقمُ المحلّيُّ لا يُقبَل لصفٍّ يحمل هُويّةً.**
  ///
  /// صفُّ المرفق يعود من الخادم حاملاً `entity_id` **كما هو على
  /// الخادم** لا كما هو هنا: مستندٌ أُنشئ على هذا الجهاز يحمل
  /// رقماً فوق المليار (أرضيّةُ `IdNamespaceService`)، والخادمُ
  /// يعطيه رقماً صغيراً — **وذاك الرقمُ الصغيرُ قد يكون مستنداً
  /// آخرَ تماماً على هذا الجهاز**. فشرطٌ يقبل تطابُقَ الرقم
  /// ولو اختلفت الهُويّة يعرض **ورقةً على مستندٍ لا تخصُّه**.
  ///
  /// ⚠️ ولماذا الاثنان لا واحد؟ لأنّ المستندَ المُنشَأَ للتوِّ على هذا
  /// الجهاز قد لا يكون قد نال هُويّتَه العالميّةَ بعد في كلّ مسار، والصفَّ
  /// الآتيَ من الخادم يحمل هُويّةً ولا يحمل رقمَنا المحلّيّ. فالبحثُ
  /// بالاثنين معاً هو وحدَه الذي يرى المرفقَ في الحالتَين.
  Expression<bool> _attachmentScope(
    $AttachmentsTable a, {
    required String entityType,
    required int? entityId,
    required String? entityGlobalId,
  }) {
    Expression<bool> match;
    if (entityGlobalId != null && entityGlobalId.isNotEmpty) {
      match = a.entityGlobalId.equals(entityGlobalId);
      // والرقمُ المحلّيُّ **لصفٍّ بلا هُويّةٍ وحدَه**.
      if (entityId != null) {
        match = match |
            (a.entityGlobalId.isNull() & a.entityId.equals(entityId));
      }
    } else if (entityId != null) {
      match = a.entityId.equals(entityId);
    } else {
      // لا هُويّةَ ولا رقم — لا مرفقاتٍ، ولا يجوز أن يعني ذلك «كلَّها».
      match = const Constant(false);
    }
    return a.entityType.equals(entityType) & match;
  }

  /// مرفقاتُ مستندٍ — **الحيّةُ وحدَها**، أحدثُها أوّلاً.
  Stream<List<AttachmentData>> watchAttachments({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
  }) {
    return (select(attachments)
          ..where((a) => _attachmentScope(a,
              entityType: entityType,
              entityId: entityId,
              entityGlobalId: entityGlobalId))
          ..where((a) => a.deletedAt.isNull())
          ..orderBy([
            (a) => OrderingTerm.desc(a.attachedAt),
            // ⚠️ والرقمُ فاصِلاً: ملفّان يُرفَعان في نفس المِلّي
            //    يترتّبان عشوائيّاً بلاه — ودقّةُ الساعة على
            //    ويندوز قريبةٌ من ٥١ مِلّي لا واحد.
            (a) => OrderingTerm.desc(a.id),
          ]))
        .watch();
  }

  Future<List<AttachmentData>> getAttachments({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
  }) {
    return (select(attachments)
          ..where((a) => _attachmentScope(a,
              entityType: entityType,
              entityId: entityId,
              entityGlobalId: entityGlobalId))
          ..where((a) => a.deletedAt.isNull())
          ..orderBy([
            (a) => OrderingTerm.desc(a.attachedAt),
            // ⚠️ والرقمُ فاصِلاً: ملفّان يُرفَعان في نفس المِلّي
            //    يترتّبان عشوائيّاً بلاه — ودقّةُ الساعة على
            //    ويندوز قريبةٌ من ٥١ مِلّي لا واحد.
            (a) => OrderingTerm.desc(a.id),
          ]))
        .get();
  }

  /// عددُ المرفقات **الحيّة** — هو الذي يُقاس عليه سقفُ العشرة.
  ///
  /// ⚠️ والمحذوفةُ لا تُعَدّ: الحذفُ ناعمٌ، فعدُّها كان يُقفل المستندَ بعد
  /// عشرِ عمليّاتِ رفعٍ وحذفٍ وإن لم تبقَ ورقةٌ واحدة.
  Future<int> countAttachments({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
  }) async {
    final rows = await getAttachments(
      entityType: entityType,
      entityId: entityId,
      entityGlobalId: entityGlobalId,
    );
    return rows.length;
  }

  /// هُويّةُ **المستند** العالميّةُ من رقمِه المحلّيّ.
  ///
  /// 🔴 **وبها تستغني الشاشاتُ التسعُ عن حملِها**: لا `InvoiceEntity` ولا
  /// أكثرُ ما تمرّره الشاشاتُ يحمل `global_id`، وإضافتُه إلى تسعةٍ من
  /// الكيانات ومُحوِّلاتِها تغييرٌ واسعٌ لأجل حقلٍ واحد — وقراءةٌ واحدةٌ
  /// بمفتاحٍ أساسيٍّ تغني عنه.
  ///
  /// ⚠️ و[tableName] يأتي من `kAttachmentEntityByType` لا من نصٍّ يصل في
  /// طلب، فلا يبلغ حقنُ SQL هذا الاستعلامَ بحال.
  Future<String?> attachmentOwnerGlobalId({
    required String tableName,
    required int id,
  }) async {
    final row = await customSelect(
      'SELECT global_id FROM "$tableName" WHERE id = ? LIMIT 1',
      variables: [Variable.withInt(id)],
    ).getSingleOrNull();
    final gid = row?.data['global_id'];
    return gid is String && gid.isNotEmpty ? gid : null;
  }

  Future<AttachmentData?> attachmentByGlobalId(String globalId) {
    return (select(attachments)
          ..where((a) => a.globalId.equals(globalId))
          ..limit(1))
        .getSingleOrNull();
  }

  /// صفٌّ حيٌّ بنفس البصمة على **نفس المستند** — به يُمنَع رفعُ الملفّ
  /// مرّتَين بالنقر المزدوج.
  Future<AttachmentData?> attachmentBySha({
    required String entityType,
    required String shaHex,
    int? entityId,
    String? entityGlobalId,
  }) {
    return (select(attachments)
          ..where((a) => _attachmentScope(a,
              entityType: entityType,
              entityId: entityId,
              entityGlobalId: entityGlobalId))
          ..where((a) => a.shaHex.equals(shaHex) & a.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  // ───────────────────────────────────────────────────────────────────────
  // قراءةُ البايتات
  // ───────────────────────────────────────────────────────────────────────

  /// بايتاتُ مرفقٍ إن كانت عند هذا الجهاز — و`null` **حالةٌ طبيعيّة**.
  Future<Uint8List?> attachmentBytes(String attachmentGlobalId) async {
    final row = await (select(attachmentBlobs)
          ..where((b) => b.attachmentGlobalId.equals(attachmentGlobalId))
          ..limit(1))
        .getSingleOrNull();
    return row?.bytes;
  }

  Future<bool> hasAttachmentBytes(String attachmentGlobalId) async {
    final row = await (selectOnly(attachmentBlobs)
          ..addColumns([attachmentBlobs.id])
          ..where(attachmentBlobs.attachmentGlobalId.equals(attachmentGlobalId))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  // ───────────────────────────────────────────────────────────────────────
  // كتابة
  // ───────────────────────────────────────────────────────────────────────

  /// إرفاقُ ملفٍّ — الوصفُ والبايتاتُ في **معاملةٍ واحدة**.
  ///
  /// 🔴 ولماذا معاملةٌ واحدة؟ لأنّ الشقَّين بلا رابطٍ مرجعيٍّ في المخطَّط
  /// (البايتاتُ تشير بهُويّةٍ نصّيّةٍ لا بمفتاحٍ أجنبيّ — عمداً، فالوصفُ
  /// يُزامَن والبايتاتُ لا). فبلا معاملةٍ يُنتج انقطاعٌ في المنتصف **وصفاً
  /// لمرفقٍ لا بايتاتِ له على الجهاز الذي رفعه** — وهو لا يقدر على جلبها
  /// من الخادم لأنّه هو مصدرُها.
  ///
  /// و[globalId] يُمرَّر من فوق ليكون واحداً على الجهازَين — وهو عينُ درس
  /// المرحلة الثامنة: الهُويّةُ تُختَم **قبل** الكتابتَين لا بينهما.
  Future<AttachmentData> insertAttachment({
    required String globalId,
    required String entityType,
    int? entityId,
    String? entityGlobalId,
    required String fileName,
    required String mimeType,
    required int byteSize,
    required String shaHex,
    required String docType,
    int? attachedByUserId,
    String? notes,
    required Uint8List bytes,
  }) async {
    final now = DateTime.now();
    return transaction(() async {
      final row = await into(attachments).insertReturning(
        AttachmentsCompanion.insert(
          entityType: entityType,
          entityId: Value(entityId),
          entityGlobalId: Value(entityGlobalId),
          fileName: fileName,
          mimeType: mimeType,
          byteSize: byteSize,
          shaHex: shaHex,
          docType: Value(docType),
          attachedByUserId: Value(attachedByUserId),
          attachedAt: Value(now),
          notes: Value(notes),
          globalId: Value(globalId),
          lastModifiedAt: Value(now),
        ),
      );
      await into(attachmentBlobs).insert(
        AttachmentBlobsCompanion.insert(
          attachmentGlobalId: globalId,
          bytes: bytes,
          cachedAt: Value(now),
        ),
        mode: InsertMode.insertOrReplace,
      );
      return row;
    });
  }

  /// خزنُ بايتاتٍ جُلبت من الخادم — **خبيئةٌ لا كتابةُ مستند**.
  ///
  /// ولذلك لا تلمس `attachments` ولا `lastModifiedAt`: الخبيئةُ ليست
  /// تعديلاً يُزامَن، ولو ختمتها لعاد الصفُّ إلى الخادم بلا سببٍ في كلّ
  /// مرّةٍ يفتح فيها أحدٌ مرفقاً.
  Future<void> cacheAttachmentBytes({
    required String attachmentGlobalId,
    required Uint8List bytes,
  }) async {
    await into(attachmentBlobs).insert(
      AttachmentBlobsCompanion.insert(
        attachmentGlobalId: attachmentGlobalId,
        bytes: bytes,
        cachedAt: Value(DateTime.now()),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  /// حذفُ مرفق — **ناعمٌ للوصف، ومحوٌ تامٌّ للبايتات** (قرارُ المالك §٨٫٤).
  ///
  /// 🔴 ولماذا لا يُحذَف الصفُّ؟ لأنّ المستندَ المحاسبيَّ **لا يفقد أثرَ أنّ
  /// ورقةً كانت معه**: مراجعٌ يسأل غداً «أين البيانُ الجمركيُّ؟» يستحقّ
  /// جواباً بأنّه حُذف ومتى ومَن، لا صمتاً.
  ///
  /// ⚠️ وحذفٌ ناعمٌ بلا محوِ البايتات كان يُبقي الملفَّ في القاعدة وفي كلّ
  /// نسخةٍ احتياطيّةٍ إلى الأبد — «حذفٌ» لا يحذف.
  Future<bool> softDeleteAttachment(String globalId) async {
    final now = DateTime.now();
    return transaction(() async {
      final hit = await (update(attachments)
            ..where((a) => a.globalId.equals(globalId) & a.deletedAt.isNull()))
          .write(AttachmentsCompanion(
        deletedAt: Value(now),
        lastModifiedAt: Value(now),
      ));
      await (delete(attachmentBlobs)
            ..where((b) => b.attachmentGlobalId.equals(globalId)))
          .go();
      return hit > 0;
    });
  }

  /// بايتاتٌ بقيت لوصفٍ محذوفٍ أو غائب — تُمحى.
  ///
  /// ⚠️ **ولها موضعٌ واقعيٌّ لا نظريّ**: الحذفُ يقع على جهازٍ ويصل غيرَه
  /// **وصفاً وحدَه** (‏`deleted_at` عبر المزامنة). فالجهازُ الآخرُ يرى
  /// المرفقَ محذوفاً ويبقى ملفُّه في قاعدته — إلى أن تمرَّ هذه.
  Future<int> purgeOrphanAttachmentBlobs() async {
    return customUpdate(
      'DELETE FROM attachment_blobs WHERE attachment_global_id NOT IN ('
      'SELECT global_id FROM attachments '
      'WHERE global_id IS NOT NULL AND deleted_at IS NULL)',
      updates: {attachmentBlobs},
      updateKind: UpdateKind.delete,
    );
  }
}
