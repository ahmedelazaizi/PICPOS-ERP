// ApiHandler - health, settings, roles, heartbeat, sequences, fiscal years and periods (GET).
part of '../api_handler.dart';

/// health, settings, roles, heartbeat, sequences, fiscal years and periods (GET) (see [ApiHandler]).
extension ApiHandlerSystemGets on ApiHandler {
  // ═══════════════════════════════════════════════════════════════
  // Health & Status
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _healthCheck(Request request) async {
    final ns = NetworkService.instance;
    return _json({
      'status': 'ok',
      'version': AppConstants.appVersion,
      'serverTime': DateTime.now().toIso8601String(),
      'uptime': ns.serverStartTime != null
          ? DateTime.now().difference(ns.serverStartTime!).inSeconds
          : 0,
      'connectedClients': ns.connectedClientCount,
      // يُعلَن دائماً — ليس سرّاً، والعميلُ يحتاجه ليعرف بأيِّ مخطَّطٍ
      // يخاطب الخادمَ في نداءاته التالية. وبدونه كان العميلُ يبني
      // `http://` صلباً فيعمى عن خادمٍ يعمل بـTLS.
      'tls': ns.isServerUsingTls,
      'sessionKeyId': ?ApiAuthMiddleware.sessionKeyId, // ليس سرّاً
      // A-SEC-1: only hand the bearer token to callers during an operator-opened
      // device-pairing window — never in steady state.
      if (ApiAuthMiddleware.isPairingOpen)
        'apiToken': ApiAuthMiddleware.activeToken,
      // بصمةُ شهادةِ الخادم — تُسلَّم في **نفس** نافذة الاقتران التي
      // يُسلَّم فيها التوكن، فيثبّتها العميلُ ويرفض بعدها أيَّ شهادةٍ
      // أخرى. وهذا ما يحوّل TLS من تشفيرٍ بلا هويّةٍ إلى منعٍ فعليٍّ
      // للرجل في المنتصف على الشبكة المحلّيّة.
      if (ApiAuthMiddleware.isPairingOpen && ns.isServerUsingTls)
        'certFingerprint': ns.serverCertFingerprint,
    });
  }


  // ═══════════════════════════════════════════════════════════════
  // Settings (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getSettings(Request request) async {
    try {
      final settings = await _db.select(_db.settings).get();
      final settingsMap = <String, String>{};
      for (final s in settings) {
        if (s.value == null) continue;
        // 🔴 كان هذا المسارُ يُفرغ جدولَ الإعدادات **كاملاً** — بلا بوّابةِ
        // صلاحيّةٍ ولا ترشيح. ومن بين صفوفه `admin_password_hash` و
        // `admin_password_salt`: كلمةُ مرور المدير التي تحرس تجاوزَ
        // الصلاحيّات كلَّه. فأيُّ حاملٍ لتوكن LAN المشترك كان يقرؤها ثمّ
        // يكسرها دون اتّصال — والهاشُ سلسلةُ SHA‑256 مكرَّرةٌ لا KDF حقيقيّ
        // (‏الملحُ يدخل في الدورة الأولى وحدَها)، فالكسرُ رخيص.
        if (isServerSecretSettingKey(s.key)) continue;
        settingsMap[s.key] = s.value!;
      }

      return _json({'settings': settingsMap});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch settings');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Roles & Permissions (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getRoles(Request request) async {
    try {
      final roles = await _db.select(_db.roles).get();
      final jsonList = roles
          .map(
            (r) => <String, dynamic>{
              'id': r.id,
              'name': r.name,
              'description': r.description,
              'isSystemRole': r.isSystemRole,
              'createdAt': r.createdAt.toIso8601String(),
            },
          )
          .toList();
      return _json({'roles': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch roles');
    }
  }

  Future<Response> _getPermissions(Request request) async {
    try {
      final perms = await _db.select(_db.permissions).get();
      final jsonList = perms
          .map(
            (p) => <String, dynamic>{
              'id': p.id,
              'code': p.code,
              'name': p.name,
              'category': p.category,
            },
          )
          .toList();
      return _json({'permissions': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch permissions');
    }
  }

  Future<Response> _getRolePermissions(Request request) async {
    try {
      // CRITICAL: Include the permission CODE and role NAME alongside the IDs.
      //
      // The numeric IDs in `permissions` and `roles` tables are auto-increment
      // and CAN DIVERGE between server and client (the seeding order, ON
      // CONFLICT DO NOTHING races, and Phase-additions of new permission codes
      // all leave the two databases with the SAME codes but DIFFERENT IDs).
      //
      // The previous response shipped only IDs, so the client's
      // RolePermissionSyncStrategy filtered each row by
      //     existingPermIds.contains(serverPermId)
      // and dropped every mapping whose server id had no local twin — silently
      // stripping critical permissions like pos_save from the cashier's role
      // even though the server clearly had them. The user's exact symptom:
      // "I added pos_save on the server, the SQL query confirms it, but the
      // override dialog still fires on the cashier's POS".
      //
      // Codes are universal (the same code identifies the same permission on
      // every node), so shipping them lets the client re-resolve to its own
      // local id without depending on id alignment.
      final perms = await _db.select(_db.permissions).get();
      final codeById = <int, String>{
        for (final p in perms) p.id: p.code,
      };
      final roles = await _db.select(_db.roles).get();
      final roleNameById = <int, String>{
        for (final r in roles) r.id: r.name,
      };

      final rp = await _db.select(_db.rolePermissions).get();
      final jsonList = rp
          .map(
            (r) => <String, dynamic>{
              'roleId': r.roleId,
              'permissionId': r.permissionId,
              // New fields — clients on the latest build prefer these.
              if (codeById[r.permissionId] != null)
                'permissionCode': codeById[r.permissionId],
              if (roleNameById[r.roleId] != null)
                'roleName': roleNameById[r.roleId],
            },
          )
          .toList();
      return _json({'role_permissions': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch role_permissions');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Heartbeat
  // ═══════════════════════════════════════════════════════════════

  // EXEMPT-PER-USER: device-level keepalive; per-user gating makes no
  // semantic sense — the heartbeat is sent by the device, not a user.
  // (Spec 077 Batch 5 allow-list — see §6 of endpoint-permission-map.md)
  Future<Response> _heartbeat(Request request) async {
    try {
      final body = await request.readAsString();
      final data = json.decode(body) as Map<String, dynamic>;
      final clientId = data['clientId'] as String? ?? 'unknown';

      NetworkService.instance.registerClient(clientId);

      return _json({
        'status': 'ok',
        'serverTime': DateTime.now().toIso8601String(),
        'clientId': clientId,
      });
    } catch (e) {
      return ApiErrors.fail(e, 'Heartbeat failed');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Document Sequences (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getDocumentSequences(Request request) async {
    try {
      final seqs = await _db.select(_db.documentSequences).get();
      final jsonList = seqs
          .map((d) => <String, dynamic>{
                'prefix': d.prefix,
                'nextValue': d.nextValue,
              })
          .toList();

      return _json(
          {'document_sequences': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch document sequences');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Fiscal Years (GET)
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getFiscalYears(Request request) async {
    try {
      final years = await _db.select(_db.fiscalYears).get();
      final jsonList = years
          .map((f) => <String, dynamic>{
                'id': f.id,
                'name': f.name,
                'startDate': f.startDate.millisecondsSinceEpoch ~/ 1000,
                'endDate': f.endDate.millisecondsSinceEpoch ~/ 1000,
                'isClosed': f.isClosed,
                'isCurrent': f.isCurrent,
              })
          .toList();

      return _json({'fiscal_years': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch fiscal years');
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // Accounting Periods
  // ═══════════════════════════════════════════════════════════════

  Future<Response> _getAccountingPeriods(Request request) async {
    try {
      final rows = await _db.select(_db.accountingPeriods).get();
      final jsonList = rows.map((p) => <String, dynamic>{
        'id': p.id,
        'fiscalYearId': p.fiscalYearId,
        'name': p.name,
        'month': p.month,
        'year': p.year,
        'startDate': p.startDate.toIso8601String(),
        'endDate': p.endDate.toIso8601String(),
        'isClosed': p.isClosed,
        'closedAt': p.closedAt?.toIso8601String(),
        'closedBy': p.closedBy,
        'notes': p.notes,
        'createdAt': p.createdAt.toIso8601String(),
        'globalId': p.globalId,
      }).toList();
      return _json({'accounting_periods': jsonList, 'count': jsonList.length});
    } catch (e) {
      return ApiErrors.fail(e, 'Failed to fetch accounting periods');
    }
  }

}
