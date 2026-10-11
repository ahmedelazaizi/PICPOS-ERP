// ApiDataHandler - attachment upload / delete / download endpoints.
part of '../api_data_handler.dart';

/// Attachment endpoints of [ApiDataHandler].
extension ApiDataAttachmentsRoutes on ApiDataHandler {
  /// خريطةُ الهُويّة العالميّة إلى الرقم المحلّيّ على **هذا** الخادم.
  ///
  /// واسمُ الجدول من [kAttachmentEntityByType] لا من نصٍّ يصل في الطلب —
  /// فلا يبلغ حقنُ SQL هذا الاستعلامَ بحالٍ.
  Future<int?> _resolveAttachmentOwnerId(
    AttachmentEntity entity,
    String entityGlobalId,
  ) async {
    final row = await db
        .customSelect(
          'SELECT id FROM "${entity.tableName}" WHERE global_id = ? LIMIT 1',
          variables: [Variable.withString(entityGlobalId)],
        )
        .getSingleOrNull();
    return row?.data['id'] as int?;
  }

  /// رفعُ مرفقٍ واردٍ من عميل.
  Future<Response> postAttachment(Request request) async {
    try {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;

      final entity = attachmentEntityFor(data['entityType'] as String?);
      if (entity == null) {
        return jsonResponse({
          'success': false,
          'error': 'نوعُ مستندٍ غيرُ مدعومٍ للمرفقات: ${data['entityType']}',
        }, statusCode: 400);
      }

      // والصلاحيةُ صلاحيةُ **المستند** لا صلاحيةٌ عامّةٌ للمرفقات: من يملك
      // تعديلَ الفاتورة يُرفق بها، ولا يُرفق بقيد يوميّةٍ لا يملكه.
      final perm = await ApiUserCtx.requirePermission(
          request, db, entity.attachPermission);
      if (perm != null) return perm;

      final globalId = data['globalId'] as String?;
      final entityGlobalId = data['entityGlobalId'] as String?;
      if (globalId == null ||
          globalId.isEmpty ||
          entityGlobalId == null ||
          entityGlobalId.isEmpty) {
        return jsonResponse({
          'success': false,
          'error': 'globalId أو entityGlobalId مفقود',
        }, statusCode: 400);
      }

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postAttachment',
        tables: const {'attachments'},
        body: () async {
          // إعادةُ الإرسال بعد انقطاعٍ ليست رفعاً ثانياً.
          final existing = await db.attachmentByGlobalId(globalId);
          if (existing != null) {
            return jsonResponse({
              'success': true,
              'id': existing.id,
              'duplicate': true,
            });
          }

          final ownerId =
              await _resolveAttachmentOwnerId(entity, entityGlobalId);
          if (ownerId == null) {
            // 409 لا 400: الطلبُ سليمٌ والمستندُ لم يصل الخادمَ بعد،
            // والطابورُ يعيد المحاولة. وابتلاعُه صامتاً يُضيّع الورقةَ
            // نهائيّاً والمستخدمُ يظنُّ أنّه أرفقها.
            return jsonResponse({
              'success': false,
              'error': 'المستندُ لم يصل الخادمَ بعد',
              'retry': true,
            }, statusCode: 409);
          }

          final b64 = data['bytesBase64'] as String?;
          if (b64 == null || b64.isEmpty) {
            return jsonResponse(
                {'success': false, 'error': 'bytesBase64 مفقود'},
                statusCode: 400);
          }
          final Uint8List bytes;
          try {
            bytes = base64Decode(b64);
          } catch (_) {
            return jsonResponse(
                {'success': false, 'error': 'bytesBase64 غيرُ صالح'},
                statusCode: 400);
          }

          final fileName = (data['fileName'] as String?) ?? '';
          final mimeType = (data['mimeType'] as String?) ?? '';

          final live = await db.countAttachments(
            entityType: entity.type,
            entityId: ownerId,
            entityGlobalId: entityGlobalId,
          );
          final bad = validateAttachment(
            entityType: entity.type,
            fileName: fileName,
            mimeType: mimeType,
            byteSize: bytes.length,
            existingCount: live,
          );
          if (bad != null) {
            return jsonResponse({'success': false, 'error': bad},
                statusCode: 400);
          }

          // ⚠️ **والبصمةُ تُحسَب هنا لا تُؤخَذ كما وصلت**: بصمةٌ يرسلها
          // العميلُ ولا تُتحقَّق تجعل العمودَ حِلْيةً — وهو العمودُ الذي
          // يكشف غداً أنّ البايتاتِ وصلت ناقصةً.
          final actualSha = crypto.sha256.convert(bytes).toString();
          final claimedSha = (data['sha256'] as String?) ?? actualSha;
          final mismatch = validateAttachmentBytes(
            expectedSize: (data['byteSize'] as num?)?.toInt() ?? bytes.length,
            expectedSha: claimedSha,
            actualSize: bytes.length,
            actualSha: actualSha,
          );
          if (mismatch != null) {
            return jsonResponse({'success': false, 'error': mismatch},
                statusCode: 400);
          }

          final row = await db.insertAttachment(
            globalId: globalId,
            entityType: entity.type,
            entityId: ownerId,
            entityGlobalId: entityGlobalId,
            fileName: fileName,
            mimeType: mimeType,
            byteSize: bytes.length,
            shaHex: actualSha,
            docType: (data['docType'] as String?) ?? 'other',
            attachedByUserId: ApiUserCtx.userIdOf(request),
            notes: data['notes'] as String?,
            bytes: bytes,
          );

          return jsonResponse({'success': true, 'id': row.id});
        },
      );
    } catch (e, st) {
      debugPrint('[API] postAttachment failed: $e\n$st');
      return ApiErrors.failJson(e, st);
    }
  }

  /// حذفُ مرفقٍ واردٌ من عميل — ناعمٌ للوصف ومحوٌ للبايتات.
  Future<Response> postAttachmentDelete(Request request) async {
    try {
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final globalId = data['globalId'] as String?;
      if (globalId == null || globalId.isEmpty) {
        return jsonResponse({'success': false, 'error': 'globalId مفقود'},
            statusCode: 400);
      }

      final row = await db.attachmentByGlobalId(globalId);
      if (row == null) {
        // حذفُ ما لا وجودَ له **نجاحٌ لا خطأ**: الطابورُ يعيد المحاولةَ
        // بعد نجاحٍ لم يصل جوابُه، وردُّ 404 يجعلها تُعاد إلى الأبد.
        return jsonResponse({'success': true, 'missing': true});
      }

      final entity = attachmentEntityFor(row.entityType);
      final perm = await ApiUserCtx.requirePermission(request, db,
          entity?.attachPermission ?? PermissionCodes.accountingManage);
      if (perm != null) return perm;

      return await ApiHandlerBase.withBroadcast<Response>(
        endpointLabel: 'postAttachmentDelete',
        tables: const {'attachments'},
        body: () async {
          final hit = await db.softDeleteAttachment(globalId);
          return jsonResponse({'success': true, 'deleted': hit});
        },
      );
    } catch (e, st) {
      debugPrint('[API] postAttachmentDelete failed: $e\n$st');
      return ApiErrors.failJson(e, st);
    }
  }

  /// جلبُ بايتاتِ مرفقٍ — **كسولٌ بالتعريف**.
  ///
  /// ولا تركب هذه البايتاتُ سحبَ الدلتا أبداً: تُطلَب حين يفتح أحدٌ
  /// المرفقَ، ويخبّئها جهازُه فلا يطلبها ثانيةً.
  Future<Response> getAttachmentBytes(Request request, String globalId) async {
    try {
      final row = await db.attachmentByGlobalId(globalId);
      if (row == null || row.deletedAt != null) {
        return jsonResponse({'success': false, 'error': 'مرفقٌ غيرُ موجود'},
            statusCode: 404);
      }

      final entity = attachmentEntityFor(row.entityType);
      final perm = await ApiUserCtx.requirePermission(
          request, db, entity?.viewPermission ?? PermissionCodes.accountingView);
      if (perm != null) return perm;

      final bytes = await db.attachmentBytes(globalId);
      if (bytes == null) {
        // على الخادم هذه **حالةٌ شاذّةٌ لا طبيعيّة**: هو مصدرُ البايتات.
        return jsonResponse(
            {'success': false, 'error': 'بايتاتُ المرفق مفقودةٌ على الخادم'},
            statusCode: 410);
      }

      return jsonResponse({
        'success': true,
        'globalId': globalId,
        'fileName': row.fileName,
        'mimeType': row.mimeType,
        'byteSize': row.byteSize,
        'sha256': row.shaHex,
        'bytesBase64': base64Encode(bytes),
      });
    } catch (e, st) {
      debugPrint('[API] getAttachmentBytes failed: $e\n$st');
      return ApiErrors.failJson(e, st);
    }
  }
}
