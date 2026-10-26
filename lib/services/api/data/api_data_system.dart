// ApiDataHandler - settings, party groups, printers, backup and activity log endpoints.
part of '../api_data_handler.dart';

/// Settings and system endpoints of [ApiDataHandler].
extension ApiDataSystemRoutes on ApiDataHandler {
  // ═══════════════════════════════════════════════════════════════
  // Settings
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postSettings(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.settingsEdit);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incoming = data.map<String, String>(
        (k, v) => MapEntry(k, v.toString()),
      );

      // ── قائمةُ منعٍ على الخادم، لا على العميل وحدَه ─────────────────────
      //
      // 🔴 كانت هذه النقطةُ تكتب **أيَّ** مفتاحٍ يرسله العميل. وهي الطرفُ
      // الثالثُ لنفس الثغرة: العميلُ يمنع الدفعَ الصاعد، والاستراتيجيّةُ
      // تمنع الكتابةَ الهابطة — والخادمُ كان مفتوحاً. فعميلٌ واحدٌ (‏أو
      // حاملُ توكن LAN) يكتب `network_mode='client'` على الخادم فيقلع
      // الخادمُ عميلاً وتعمى كلُّ الأجهزة، أو يكتب `_watermark__<table>`
      // فيفتح فجوةَ سحبٍ دائمةً صامتة.
      //
      // ولا يُرفَض الطلبُ كلُّه: حمولةٌ مشروعةٌ قد تحمل مفتاحاً واحداً
      // ممنوعاً بين عشرة صحيحة، ورفضُ الكلِّ يُسقط إعداداتٍ سليمة. فتُكتَب
      // المسموحةُ ويُبلَّغ عن المحجوبة.
      // ⚠️ **محوران، لا واحد.** `isDeviceLocalSettingKey` تمنع ما يخصُّ
      // الجهاز، و`isServerSecretSettingKey` تمنع ما يحمل سرّاً. وكلمةُ مرور
      // المدير ليست «إعداداً محلّيّاً» فلم تكن القائمةُ الأولى تغطّيها —
      // فمن يملك `settings_edit` (‏أو المستخدمُ رقم ١) كان **يستبدلها عن
      // بُعد** ويصير له تجاوزُ الصلاحيّات كلِّه. تصعيدُ امتيازٍ كامل عبر
      // نقطةِ حفظِ إعدادات.
      final blocked = <String>[];
      final allowed = <String, String>{};
      incoming.forEach((k, v) {
        if (isDeviceLocalSettingKey(k) || isServerSecretSettingKey(k)) {
          blocked.add(k);
        } else {
          allowed[k] = v;
        }
      });
      if (blocked.isNotEmpty) {
        unawaited(DiagnosticLogger.log(
          'API-SETTINGS',
          '⛔ رُفض ${blocked.length} مفتاحاً يخصُّ الجهاز: '
              '${blocked.join(", ")}',
        ));
      }

      await db.saveSettings(allowed);
      broadcast('settings');
      return jsonResponse({
        'success': true,
        'saved': allowed.length,
        if (blocked.isNotEmpty) 'blocked': blocked,
      });
    } catch (e) {
      debugPrint('[API] postSettings error: $e');
      return ApiErrors.fail(e, 'Failed to save settings');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.2: Party Groups
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postPartyGroup(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.customersEdit);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incomingGid = data['globalId'] as String?;

      if (incomingGid != null && incomingGid.isNotEmpty) {
        final existing = await (db.select(db.partyGroups)
              ..where((g) => g.globalId.equals(incomingGid))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          await (db.update(db.partyGroups)..where((g) => g.id.equals(existing.id))).write(
            PartyGroupsCompanion(
              name: Value(data['name'] as String? ?? existing.name),
              type: Value(data['type'] as String? ?? existing.type),
              description: Value(data['description'] as String? ?? existing.description),
              defaultDiscount: Value(parseDouble(data['defaultDiscount'], existing.defaultDiscount)),
              defaultPaymentTerms: Value(data['defaultPaymentTerms'] as String? ?? existing.defaultPaymentTerms),
              priceLevel: Value(data['priceLevel'] as String? ?? existing.priceLevel),
              notes: Value(data['notes'] as String? ?? existing.notes),
            ),
          );
          broadcast('party_groups');
          return jsonResponse({'success': true, 'id': existing.id, 'global_id': incomingGid});
        }
      }

      final gid = (incomingGid != null && incomingGid.isNotEmpty) ? incomingGid : UuidV7.generate();
      final id = await db.into(db.partyGroups).insert(
        PartyGroupsCompanion.insert(
          name: data['name'] as String,
          type: Value(data['type'] as String? ?? 'both'),
          description: Value(data['description'] as String?),
          defaultDiscount: Value(parseDouble(data['defaultDiscount'])),
          defaultPaymentTerms: Value(data['defaultPaymentTerms'] as String?),
          priceLevel: Value(data['priceLevel'] as String?),
          notes: Value(data['notes'] as String?),
          parentGroupId: Value(parseIntNullable(data['parentGroupId'])),
          globalId: Value(gid),
        ),
      );
      broadcast('party_groups');
      return jsonResponse({'success': true, 'id': id, 'global_id': gid});
    } catch (e) {
      debugPrint('[API] postPartyGroup error: $e');
      return ApiErrors.fail(e, 'Failed to create party group');
    }
  }

  Future<Response> putPartyGroup(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.customersEdit);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final group = await (db.select(db.partyGroups)..where((g) => g.id.equals(int.parse(id)))).getSingleOrNull();
      if (group == null) return errorResponse('Party group not found', statusCode: 404);
      await (db.update(db.partyGroups)..where((g) => g.id.equals(int.parse(id)))).write(
        PartyGroupsCompanion(
          name: data.containsKey('name') ? Value(data['name'] as String) : const Value.absent(),
          type: data.containsKey('type') ? Value(data['type'] as String) : const Value.absent(),
          description: data.containsKey('description') ? Value(data['description'] as String?) : const Value.absent(),
          defaultDiscount: data.containsKey('defaultDiscount') ? Value(parseDouble(data['defaultDiscount'])) : const Value.absent(),
          isActive: data.containsKey('isActive') ? Value(parseBool(data['isActive'], true)) : const Value.absent(),
        ),
      );
      broadcast('party_groups');
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to update party group');
    }
  }

  Future<Response> deletePartyGroup(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.customersEdit);
      if (perm != null) return perm;
      final gid = int.parse(id);
      await (db.delete(db.partyGroups)..where((g) => g.id.equals(gid))).go();
      broadcast('party_groups');
      broadcastRecordDeleted('party_groups', gid);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete party group');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // S4.2: Printers
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postPrinter(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.settingsPrinter);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final incomingGid = data['globalId'] as String?;

      if (incomingGid != null && incomingGid.isNotEmpty) {
        final existing = await (db.select(db.printers)
              ..where((p) => p.globalId.equals(incomingGid))
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          broadcast('printers');
          return jsonResponse({'success': true, 'id': existing.id, 'global_id': incomingGid});
        }
      }

      final gid = (incomingGid != null && incomingGid.isNotEmpty) ? incomingGid : UuidV7.generate();
      final id = await db.into(db.printers).insert(
        PrintersCompanion.insert(
          name: data['name'] as String,
          port: Value(data['port'] as String?),
          ipAddress: Value(data['ipAddress'] as String?),
          portNumber: Value(parseIntNullable(data['portNumber'])),
          printerType: Value(data['printerType'] as String? ?? 'thermal'),
          purpose: Value(data['purpose'] as String? ?? 'pos_receipt'),
          description: Value(data['description'] as String?),
          globalId: Value(gid),
        ),
      );
      broadcast('printers');
      return jsonResponse({'success': true, 'id': id, 'global_id': gid});
    } catch (e) {
      debugPrint('[API] postPrinter error: $e');
      return ApiErrors.fail(e, 'Failed to create printer');
    }
  }

  Future<Response> putPrinter(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.settingsPrinter);
      if (perm != null) return perm;
      final data = json.decode(await request.readAsString()) as Map<String, dynamic>;
      await (db.update(db.printers)..where((p) => p.id.equals(int.parse(id)))).write(
        PrintersCompanion(
          name: data.containsKey('name') ? Value(data['name'] as String) : const Value.absent(),
          port: data.containsKey('port') ? Value(data['port'] as String?) : const Value.absent(),
          ipAddress: data.containsKey('ipAddress') ? Value(data['ipAddress'] as String?) : const Value.absent(),
          portNumber: data.containsKey('portNumber') ? Value(parseIntNullable(data['portNumber'])) : const Value.absent(),
          printerType: data.containsKey('printerType') ? Value(data['printerType'] as String) : const Value.absent(),
          purpose: data.containsKey('purpose') ? Value(data['purpose'] as String) : const Value.absent(),
          description: data.containsKey('description') ? Value(data['description'] as String?) : const Value.absent(),
          isActive: data.containsKey('isActive') ? Value(parseBool(data['isActive'], true)) : const Value.absent(),
        ),
      );
      broadcast('printers');
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to update printer');
    }
  }

  Future<Response> deletePrinter(Request request, String id) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.settingsPrinter);
      if (perm != null) return perm;
      final pid = int.parse(id);
      await (db.delete(db.printers)..where((p) => p.id.equals(pid))).go();
      broadcast('printers');
      broadcastRecordDeleted('printers', pid);
      return jsonResponse({'success': true});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to delete printer');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Backup (client uploads its DB to the server)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> postBackup(Request request) async {
    try {
      // Spec 077 Batch 5 (Spec 060 Phase 2): per-user permission gate.
      final perm = await ApiUserCtx.requirePermission(
          request, db, PermissionCodes.settingsBackup);
      if (perm != null) return perm;
      final data =
          json.decode(await request.readAsString()) as Map<String, dynamic>;
      final clientName = data['clientName'] as String? ?? 'unknown';
      final dbBase64 = data['dbData'] as String;
      final dbBytes = base64Decode(dbBase64);

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final backupDir =
          '${DataDir.roamingAppData()}/${Brand.backupFolderName}/clients';
      final dir = Directory(backupDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      final backupPath = '$backupDir/backup_${clientName}_$timestamp.sqlite';
      await File(backupPath).writeAsBytes(dbBytes);

      debugPrint(
        '[API] Client backup saved: $backupPath (${dbBytes.length} bytes)',
      );
      return jsonResponse({'success': true, 'path': backupPath});
    } catch (e) {
      debugPrint('[API] postBackup error: $e');
      return ApiErrors.fail(e, 'Failed to save backup');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Activity Log Push — Central Audit Trail (Multi-Client Sync)
  // ═══════════════════════════════════════════════════════════════

  /// POST /api/activity-logs/push
  ///
  /// Receives a single activity log entry pushed from a client device and
  /// persists it in the server's activity_logs table.  Uses globalId for
  /// idempotency so that offline-queued entries replayed from the outbox
  /// cannot produce duplicate rows.
  // EXEMPT-PER-USER: forensic ingest, not a user-initiated action.
  // Gating would create a perm-loop (cashier denied → push deny-log
  // → log push denied). Bearer-token auth is sufficient.
  // (Spec 077 Batch 5 allow-list — see §5.27 of endpoint-permission-map.md)
  Future<Response> pushActivityLog(Request request) async {
    try {
      final body = json.decode(await request.readAsString()) as Map<String, dynamic>;

      final globalId = body['globalId'] as String?;
      if (globalId == null || globalId.isEmpty) {
        return errorResponse('Missing required field: globalId', statusCode: 400);
      }

      // Idempotency: skip silently if we already have this log entry.
      final existing = await (db.select(db.activityLogs)
            ..where((l) => l.globalId.equals(globalId))
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) {
        return jsonResponse({'success': true, 'skipped': true});
      }

      // Resolve userId: prefer exact server ID, fall back to admin.
      final clientUserId = body['userId'] as int?;
      final userName = (body['userName'] as String?) ?? '';
      final resolvedUserId = await _resolveUserIdNullable(
        clientUserId,
        fallbackUsername: userName,
      );

      final createdAtRaw = body['createdAt'] as String?;
      final createdAt = createdAtRaw != null
          ? DateTime.tryParse(createdAtRaw) ?? DateTime.now()
          : DateTime.now();
      final now = DateTime.now();

      await db.into(db.activityLogs).insert(
        ActivityLogsCompanion.insert(
          userId: Value(resolvedUserId),
          userName: userName,
          action: (body['action'] as String?) ?? '',
          entityType: (body['entityType'] as String?) ?? '',
          entityId: Value(body['entityId'] as int?),
          description: (body['description'] as String?) ?? '',
          oldValue: Value(body['oldValue'] as String?),
          newValue: Value(body['newValue'] as String?),
          amount: Value((body['amount'] as num?)?.toDouble()),
          deviceInfo: Value(body['deviceInfo'] as String?),
          createdAt: Value(createdAt),
          globalId: Value(globalId),
          originClientId: Value(body['originClientId'] as String?),
          lastModifiedAt: Value(now),
        ),
      );

      return jsonResponse({'success': true});
    } catch (e) {
      debugPrint('[API] pushActivityLog error: $e');
      return ApiErrors.fail(e, 'Failed to store activity log');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ATTACHMENTS — مرفقاتُ المستندات (v176 / §٨)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // 🔴 **ولماذا منفذٌ خاصٌّ لا ركوبُ تقديمِ المستند؟**
  //
  // لأنّ الورقةَ تُرفَق **بعد** حفظ المستند في أغلب العمر: فاتورةٌ حُفظت
  // أمس ويصل بيانُها الجمركيُّ اليوم. فلو ركب المرفقُ تقديمَ الفاتورة
  // لصار إرفاقُ ورقةٍ يعني **إعادةَ تقديم الفاتورة كلِّها** — وبها إعادةُ
  // ترحيلِ أثرِها المحاسبيّ.
  //
  // ⚠️ **والسياسةُ تُطبَّق هنا ثانيةً لا ثقةً بالعميل**: عميلٌ مُعدَّلٌ
  // يتجاوز الودجتَ والمستودعَ معاً، والخادمُ آخرُ الحرّاس.
}
