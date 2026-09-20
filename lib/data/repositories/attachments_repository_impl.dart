import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

import '../../core/utils/uuid_v7.dart';
import '../../domain/models/attachment_policy.dart';
import '../../domain/repositories/attachments_repository.dart';
import '../../services/client_write_interceptor.dart';
import '../../services/server_proxy.dart';
import '../database/database.dart' as db;
import '../database/sync_interceptor.dart';

/// مرفقاتُ المستندات — §٨.
///
/// ═══ 🔴 لماذا السياسةُ هنا لا في الودجت وحدَها ═══
///
/// الودجتُ يمنع الاختيار، وهذا **يمنع الكتابة**. وثالثُهما الخادمُ يمنع ما
/// يصله عبر السلك. والثلاثةُ يقرؤون [validateAttachment] نفسَها.
///
/// ═══ ⚠️ والهُويّةُ تُختَم قبل الكتابتَين ═══
///
/// لو وُلّدت داخلَ كلٍّ على حدة لحمل صفُّ العميل وصفُّ الخادم هُويّتَين
/// لمرفقٍ واحد — فيظهر **مضاعَفاً** عند أوّل سحبِ دلتا، وبايتاتُه تحت
/// هُويّةٍ لا يعرفها الطرفُ الآخر.
class AttachmentsRepositoryImpl implements IAttachmentsRepository {
  AttachmentsRepositoryImpl(this._db);

  final db.AppDatabase _db;

  @override
  Stream<List<db.AttachmentData>> watchAttachments({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
  }) =>
      _db.watchAttachments(
        entityType: entityType,
        entityId: entityId,
        entityGlobalId: entityGlobalId,
      );

  @override
  Future<List<db.AttachmentData>> getAttachments({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
  }) =>
      _db.getAttachments(
        entityType: entityType,
        entityId: entityId,
        entityGlobalId: entityGlobalId,
      );

  @override
  Future<String?> entityGlobalId({
    required String entityType,
    required int entityId,
  }) async {
    final entity = attachmentEntityFor(entityType);
    if (entity == null) return null;
    return _db.attachmentOwnerGlobalId(
      tableName: entity.tableName,
      id: entityId,
    );
  }

  @override
  Future<bool> hasLocalBytes(String globalId) =>
      _db.hasAttachmentBytes(globalId);

  @override
  Future<AttachmentResult> addAttachment({
    required String entityType,
    int? entityId,
    String? entityGlobalId,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
    AttachmentDocType docType = AttachmentDocType.other,
    int? attachedByUserId,
    String? notes,
  }) async {
    final mime = mimeType ?? attachmentMimeForFileName(fileName) ?? '';

    final existing = await _db.countAttachments(
      entityType: entityType,
      entityId: entityId,
      entityGlobalId: entityGlobalId,
    );

    final bad = validateAttachment(
      entityType: entityType,
      fileName: fileName,
      mimeType: mime,
      byteSize: bytes.length,
      existingCount: existing,
    );
    if (bad != null) return (error: bad, attachment: null);

    final shaHex = crypto.sha256.convert(bytes).toString();

    // ⚠️ نفسُ الملفِّ على نفسِ المستند مرّتَين ليس خطأَ مستخدم — نقرةٌ
    //    مزدوجةٌ أو إعادةُ محاولةٍ بعد انقطاع. فيُعاد الصفُّ القائمُ بلا
    //    كتابةٍ ثانيةٍ ولا رسالةِ خطأ.
    final twin = await _db.attachmentBySha(
      entityType: entityType,
      shaHex: shaHex,
      entityId: entityId,
      entityGlobalId: entityGlobalId,
    );
    if (twin != null) return (error: null, attachment: twin);

    final globalId = UuidV7.generate();

    if (SyncInterceptor.isClientMode) {
      // 🔴 **والإرسالُ قبل الحفظ المحلّيّ**: مرفقٌ يُحفَظ محلّيّاً ثمّ
      //    يُهمَل إرسالُه يجعل الجهازَ وحدَه يرى ورقةً لا يراها المراجعُ
      //    على أيّ جهازٍ آخر — وهو أسوأُ من رفضٍ ظاهر.
      if (entityGlobalId == null || entityGlobalId.isEmpty) {
        return (
          error: 'المستندُ لم ينل هُويّتَه العالميّةَ بعد — احفظه أوّلاً',
          attachment: null,
        );
      }
      await ClientWriteInterceptor.dispatchWrite(
        () => ClientWriteInterceptor.submitAttachment({
          'globalId': globalId,
          'entityType': entityType,
          'entityGlobalId': entityGlobalId,
          'fileName': fileName,
          'mimeType': mime,
          'byteSize': bytes.length,
          'sha256': shaHex,
          'docType': docType.code,
          'notes': notes,
          'bytesBase64': base64Encode(bytes),
        }),
        tag: 'ATTACHMENT-SYNC',
      );
    }

    final row = await _db.insertAttachment(
      globalId: globalId,
      entityType: entityType,
      entityId: entityId,
      entityGlobalId: entityGlobalId,
      fileName: fileName,
      mimeType: mime,
      byteSize: bytes.length,
      shaHex: shaHex,
      docType: docType.code,
      attachedByUserId: attachedByUserId,
      notes: notes,
      bytes: bytes,
    );
    return (error: null, attachment: row);
  }

  @override
  Future<String?> deleteAttachment(String globalId) async {
    if (SyncInterceptor.isClientMode) {
      await ClientWriteInterceptor.dispatchWrite(
        () => ClientWriteInterceptor.submitAttachmentDelete({
          'globalId': globalId,
        }),
        tag: 'ATTACHMENT-SYNC',
      );
    }
    final hit = await _db.softDeleteAttachment(globalId);
    return hit ? null : 'المرفقُ غيرُ موجودٍ أو محذوفٌ سلفاً';
  }

  @override
  Future<Uint8List?> attachmentBytes(db.AttachmentData attachment) async {
    final gid = attachment.globalId;
    if (gid == null || gid.isEmpty) return null;

    final cached = await _db.attachmentBytes(gid);
    if (cached != null) return cached;

    // لا بايتاتٍ محلّيّاً — وهي **الحالةُ الطبيعيّةُ** لمرفقٍ وصل وصفُه
    // بالمزامنة. فيُجلَب من الخادم مرّةً ويُخزَّن.
    if (!SyncInterceptor.isClientMode) return null;

    final fetched = await ServerProxy.instance.fetchAttachmentBytes(gid);
    if (fetched == null) return null;

    final actualSha = crypto.sha256.convert(fetched).toString();
    final bad = validateAttachmentBytes(
      expectedSize: attachment.byteSize,
      expectedSha: attachment.shaHex,
      actualSize: fetched.length,
      actualSha: actualSha,
    );
    if (bad != null) {
      // ⚠️ **ولا تُخزَّن**: بايتاتٌ مكسورةٌ في الخبيئة تُعرَض إلى الأبد ولا
      //    تُعاد المحاولةُ قطّ — فالكسرُ يصير دائماً بخبيئةٍ متفائلة.
      debugPrint('[Attachments] $gid: $bad');
      return null;
    }

    await _db.cacheAttachmentBytes(
      attachmentGlobalId: gid,
      bytes: fetched,
    );
    return fetched;
  }
}
