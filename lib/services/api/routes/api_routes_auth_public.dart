// ApiHandler - auth/web/sync, display, table-bill, static and catch-all route registration.
part of '../api_handler.dart';

/// auth/web/sync, display, table-bill, static and catch-all route registration (see [ApiHandler.buildRouter]).
/// Registration order inside and across these methods is security-relevant.
extension ApiHandlerAuthPublicRoutes on ApiHandler {
  void _registerAuthSyncRoutes(Router router) {
    // Mirror-mode admin verification (Feature 006 / MM.C). Used by the
    // setup wizard to verify the operator's HQ admin identity before
    // entering NetworkMode.mirror, so MirrorState.adminUserId is stamped
    // into every subsequent write payload for audit attribution.
    router.post('/api/auth/verify-admin', _auth.verifyAdmin);
    // Spec 151 (P1-8): issue a signed per-user session token after a credential
    // check — replaces the forgeable X-User-Id header as the identity source.
    router.post('/api/auth/session', _auth.issueSession);
    // P1 (plan 2026-10-24): a user sets his OWN password (proves the current one).
    router.post('/api/auth/change-password', _passwordChange.changePassword);
    // P5: a second user's credential -> a signed four-eyes approval proof.
    router.post('/api/approvals/grant', _approvals.grant);
    // M2: the branch-manager console's working context (branches in scope).
    router.get('/api/mirror/context', MirrorConsole.context);
    // الويب (م3-4/م3-5): دخول بالاعتماد → رمز جلسة 12 ساعة؛ تذكرة لمرة واحدة؛
    // ثم قناة drift للقراءة. ⚠️ /webdb لا يبدأ بـ/ws (انظر الإعفاءات).
    router.post('/api/web/session', _webSession.login);
    router.post('/api/web/ws-ticket', _webSession.issueTicket);
    router.post('/api/web/logout', _webSession.logout);
    router.get('/webdb', _webRead.handle);
    // Heartbeat
    router.post('/api/sync/heartbeat', _heartbeat);
    // Delta pull — generic watermark-based sync endpoint (P3.1)
    router.get('/api/sync/pull', _getSyncPull);
    // Authoritative server clock — clients use this to seed watermarks
    // instead of their local DateTime.now(), eliminating the risk that a
    // client clock running ahead of the server causes rows modified in the
    // gap to be skipped by the first delta pull.
    router.get('/api/sync/time', (Request r) => _json({
          'serverTime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        }));
  }

  void _registerPublicRoutes(Router router) {
    // CFD Endpoints
    router.get('/cfd', _display.getCfdDisplay);
    router.get('/api/cfd/stream', _display.cfdStream);

    // Digital Menu Endpoints
    router.get('/menu', _display.getMenuDisplay);
    router.get('/api/menu', _display.getMenuData);

    // حسابُ الطاولة على هاتف الزبون — البندُ الأوّل من فيتشرات المالك
    // 2026-09-12. ثلاثةُ مساراتٍ **بلا مصادقة** (الزبونُ ليس جهازاً مقترناً)
    // وكلُّها محكومةٌ بـ[kTableBillQrEnabledKey] المطفأ افتراضاً، وبالتوقيع.
    router.get('/t/<token>', _getTableBillPage);
    router.get('/api/table-bill/<token>', _getTableBill);
    router.post('/api/table-bill/<token>/request', _requestTableBill);
    router.post('/api/table-bill/<token>/add', _addGuestOrderRequest);

    // طابورُ طلبات الضيوف — **مصادَقٌ** بخلاف الثلاثة فوقه: هذه يقرؤها
    // النادلُ من جهازٍ مقترنٍ، لا الضيفُ من هاتفه.
    router.get('/api/table-requests', _listGuestOrderRequests);
    router.post('/api/table-requests/<id>/approve', _approveGuestOrderRequest);
    router.post('/api/table-requests/<id>/reject', _rejectGuestOrderRequest);

    // م3-9: ملفات الويب الثابتة (index.html fallback) — قبل الـcatch-all.
    WebStaticHandler.mount(router, _webStaticDir, _notFound);


    // Catch-all for undefined routes
    router.all('/<ignored|.*>', _notFound);
  }
}
