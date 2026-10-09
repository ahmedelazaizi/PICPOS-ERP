// ═══════════════════════════════════════════════════════════════════════════
// API RATE LIMITER — Per-Endpoint Buckets (Feature 011)
// ═══════════════════════════════════════════════════════════════════════════
//
// Fixed-window rate limiter for the embedded Shelf HTTP server, with
// per-endpoint-class buckets.
//
// Each endpoint is classified into one of 5 classes; each class has its own
// per-IP quota so high-volume telemetry cannot starve critical business
// writes. Real-world incident that motivated this refactor (Feature 011):
// a beta restaurant's mirror device flooded a single global 120-req/60s
// bucket with `activity_logs/push`, and EVERY downstream write (sales,
// purchases, parties, returns, journal entries) got 429'd for the rest of
// the minute. Result: parties/invoices created on mirror never reached HQ.
//
// Classes & default budgets (60-second window for all):
//   • critical (300 req/60s)     — sales, purchases, parties, journals, etc.
//   • telemetry (600 req/60s)    — activity-logs (high-volume, low-priority)
//   • read (600 req/60s)         — GET endpoints (idempotent, cacheable)
//   • otherWrite (300 req/60s)   — admin/config (product, user, order CRUD)
//   • defaultClass (120 req/60s) — unmapped endpoints (safe fallback)
//
// Backward-compatible: existing `configure(limit, window)` calls now apply
// the same limit to ALL classes (preserves the 8 existing tests in
// test/unit/api_rate_limiter_test.dart). Use `configureClass(...)` to
// override individual classes.
//
// Wiring (in network_service.dart):
//   .addMiddleware(ApiRateLimiter.createMiddleware())

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';

/// Endpoint classification for rate limiting.
///
/// Classify by INTENT (what the path is for in production), not by HTTP
/// verb. A path that is mostly POST/PUT writes goes into [critical] /
/// [otherWrite] even though incidental GETs share the same bucket — the
/// goal is to protect the WRITE budget, not optimise reads.
enum RateLimitClass {
  /// Sales, purchases, parties, journals, safes ops, shifts, returns,
  /// commercial papers, inventory adjustments. MUST always succeed under
  /// load — losing one of these means an invoice never reaches HQ.
  critical,

  /// Activity logs and similar high-volume audit/telemetry. Lossy by
  /// design — local copy is the source of truth, central mirror is best-
  /// effort. Larger budget so a noisy client doesn't immediately 429,
  /// but still bounded.
  telemetry,

  /// GET endpoints: products, categories, settings, sync/pull, etc.
  /// Idempotent and cacheable; clients re-poll on UI refresh, so the
  /// budget is generous.
  read,

  /// Admin / config writes: user CRUD, product CRUD, order CRUD,
  /// price-list, printers, etc. Lower frequency than [critical] but
  /// still important.
  otherWrite,

  /// Unmapped endpoints (safe fallback). Every NEW endpoint that hasn't
  /// been classified lands here — the conservative budget prevents
  /// silent degradation while a developer notices the warning log.
  defaultClass,
}

/// Per-IP × per-class request bucket.
class _Bucket {
  int count;
  DateTime windowStart;

  _Bucket() : count = 0, windowStart = DateTime.now();
}

/// Fixed-window rate-limiter middleware for the embedded Shelf HTTP server.
class ApiRateLimiter {
  ApiRateLimiter._();

  /// Default per-class limits. Tunable via [configureClass].
  ///
  /// Mutable map — `configure(limit:)` overwrites every entry to the same
  /// value (backward compat with the v1 single-bucket tests), and
  /// `configureClass(cls, limit)` updates a single class.
  static final Map<RateLimitClass, int> _classLimits = {
    RateLimitClass.critical: 300,
    RateLimitClass.telemetry: 600,
    RateLimitClass.read: 600,
    RateLimitClass.otherWrite: 300,
    RateLimitClass.defaultClass: 120,
  };

  /// Window duration applied to every class.
  static Duration _window = const Duration(seconds: 60);

  /// Paths that bypass rate limiting entirely (existing contract).
  static const _exemptPrefixes = ['/api/health', '/cfd', '/menu', '/ws'];

  /// Per-IP × per-class buckets.
  /// Outer key: client IP. Inner key: endpoint class.
  static final Map<String, Map<RateLimitClass, _Bucket>> _buckets = {};

  /// Tracks unmapped paths we have already warned about, so we only log
  /// the WARNING once per app session per path. Without this guard the
  /// warning would spam debug output and itself become a perf issue.
  static final Set<String> _unmappedPathsLogged = <String>{};

  // ─── Endpoint classification ──────────────────────────────────────────

  /// Path-prefix → class rules. Sorted longest-first for deterministic
  /// matching: `/api/safes/transaction` MUST match before `/api/safes`.
  ///
  /// Keys are LITERAL prefixes (no regex). Match is `path.startsWith(key)`.
  /// To override or add at runtime use [registerEndpoint].
  static final List<MapEntry<String, RateLimitClass>> _classRules = [
    // ── Critical writes (longer prefixes first) ────────────────────────
    const MapEntry('/api/safes/transaction', RateLimitClass.critical),
    const MapEntry('/api/safes/transfer', RateLimitClass.critical),
    const MapEntry('/api/safes/close', RateLimitClass.critical),
    const MapEntry('/api/shifts/open', RateLimitClass.critical),
    const MapEntry('/api/shifts/close', RateLimitClass.critical),
    const MapEntry('/api/inventory/adjust', RateLimitClass.critical),
    const MapEntry('/api/inventory/transfer', RateLimitClass.critical),
    const MapEntry('/api/purchases/return', RateLimitClass.critical),
    const MapEntry('/api/sales/return', RateLimitClass.critical),
    const MapEntry('/api/sales/held', RateLimitClass.critical),
    const MapEntry('/api/pos-terminals/register', RateLimitClass.critical),
    const MapEntry('/api/commercial-papers', RateLimitClass.critical),
    const MapEntry('/api/safe-transactions', RateLimitClass.critical),
    const MapEntry('/api/sales', RateLimitClass.critical),
    const MapEntry('/api/purchases', RateLimitClass.critical),
    const MapEntry('/api/parties', RateLimitClass.critical),
    const MapEntry('/api/journals', RateLimitClass.critical),
    const MapEntry('/api/expenses', RateLimitClass.critical),
    const MapEntry('/api/receipts', RateLimitClass.critical),
    const MapEntry('/api/vouchers', RateLimitClass.critical),

    // ── Telemetry ──────────────────────────────────────────────────────
    const MapEntry('/api/activity-logs', RateLimitClass.telemetry),

    // ── Reads (sync + lookups) ─────────────────────────────────────────
    const MapEntry('/api/sync', RateLimitClass.read),
    const MapEntry('/api/products', RateLimitClass.read),
    const MapEntry('/api/product-units', RateLimitClass.read),
    const MapEntry('/api/product-barcodes', RateLimitClass.read),
    const MapEntry('/api/categories', RateLimitClass.read),
    const MapEntry('/api/units', RateLimitClass.read),
    const MapEntry('/api/users', RateLimitClass.read),
    const MapEntry('/api/roles', RateLimitClass.read),
    const MapEntry('/api/permissions', RateLimitClass.read),
    const MapEntry('/api/branches', RateLimitClass.read),
    const MapEntry('/api/regions', RateLimitClass.read),
    const MapEntry('/api/warehouses', RateLimitClass.read),
    const MapEntry('/api/safes', RateLimitClass.read),
    const MapEntry('/api/shifts', RateLimitClass.read),
    const MapEntry('/api/accounts', RateLimitClass.read),
    const MapEntry('/api/cost_centers', RateLimitClass.read),
    const MapEntry('/api/settings', RateLimitClass.read),
    const MapEntry('/api/inventory-balances', RateLimitClass.read),
    const MapEntry('/api/payments', RateLimitClass.read),
    const MapEntry('/api/documents-sequences', RateLimitClass.read),
    const MapEntry('/api/fiscal-years', RateLimitClass.read),
    const MapEntry('/api/account-mappings', RateLimitClass.read),
    const MapEntry('/api/quotations', RateLimitClass.read),
    const MapEntry('/api/sales-orders', RateLimitClass.read),
    const MapEntry('/api/purchase-orders', RateLimitClass.read),
    const MapEntry('/api/price-lists', RateLimitClass.read),
    const MapEntry('/api/printers', RateLimitClass.read),
    const MapEntry('/api/party-groups', RateLimitClass.read),
    const MapEntry('/api/auth/verify-admin', RateLimitClass.read),
    // Spec 151 (P1-8): session issuance is a credential endpoint — throttle it
    // (same budget as verify-admin) to blunt password/card brute-force.
    const MapEntry('/api/auth/session', RateLimitClass.read),
    // الويب (م3-4/م3-5): دخولٌ بالاعتماد + تذكرة + قناة قراءة. ⚠️ /webdb
    // **لا** يبدأ بـ/ws فلا يشمله إعفاءُ _exemptPrefixes — يُصنَّف صراحةً
    // (طلبُ ترقيةٍ واحدٌ لكلّ اتصال؛ الاتصالُ نفسه لا يُحتسب بعد ذلك).
    const MapEntry('/api/web/session', RateLimitClass.read),
    const MapEntry('/api/web/ws-ticket', RateLimitClass.read),
    const MapEntry('/webdb', RateLimitClass.read),
    const MapEntry('/api/backup', RateLimitClass.otherWrite),
    // حسابُ الطاولة على هاتف الزبون (2026-09-12) — **مصنَّفٌ صراحةً على
    // الفئة الافتراضيّة (١٢٠/دقيقة) لا على `read` (٦٠٠)**.
    //
    // ⚠️ وهو المسارُ الوحيدُ **غيرُ المصادَق** الذي يُصنَّف هنا: `/menu`
    // و`/cfd` معفيّان من المحدِّد أصلاً لأنهما شاشتا عرضٍ لا تقرآن بياناتِ
    // زبونٍ بعينه. وهذا يقرأ حساباً، فتخمينُ التوقيعات عليه مسحٌ لا تصفّح —
    // والمحدِّدُ هو ما يُبطئ المسح. وتركُه بلا قاعدةٍ كان يُسقطه على نفس
    // الفئة لكن مع تحذيرِ «مسارٌ غيرُ مصنَّف» في كلّ جلسة، فيبدو سهواً.
    const MapEntry('/api/table-bill', RateLimitClass.defaultClass),
  ];

  /// Configure the rate limiter (backward compat — v1 single-bucket tests).
  ///
  /// Sets the SAME limit for ALL classes and the shared window. Use
  /// [configureClass] for per-class tuning.
  ///
  /// [limit]  — maximum requests per [window] per IP per class.
  /// [window] — time window before each class's counter resets.
  static void configure({int limit = 120, Duration window = const Duration(seconds: 60)}) {
    _window = window;
    for (final cls in RateLimitClass.values) {
      _classLimits[cls] = limit;
    }
  }

  /// Override the per-IP limit for a single endpoint class.
  ///
  /// Use after [configure] when production needs differentiated budgets.
  /// Tests can use this to verify per-class isolation without disturbing
  /// the other classes.
  static void configureClass(RateLimitClass cls, int limit) {
    _classLimits[cls] = limit;
  }

  /// Reset all buckets (useful for testing).
  static void reset() {
    _buckets.clear();
    _unmappedPathsLogged.clear();
  }

  /// Number of distinct IPs currently tracked.
  static int get trackedIps => _buckets.length;

  /// Returns true if [ip] is currently rate-limited.
  ///
  /// Without [cls], reports "limited on ANY class" — preserves the
  /// pre-Feature-011 contract that callers used to ask "is this IP
  /// limited?" without caring which endpoint. With [cls], checks only
  /// that class.
  static bool isLimited(String ip, {RateLimitClass? cls}) {
    final classMap = _buckets[ip];
    if (classMap == null) return false;
    final now = DateTime.now();

    bool isClassLimited(RateLimitClass c) {
      final bucket = classMap[c];
      if (bucket == null) return false;
      if (now.difference(bucket.windowStart) >= _window) return false;
      return bucket.count > (_classLimits[c] ?? 120);
    }

    if (cls != null) return isClassLimited(cls);
    for (final c in RateLimitClass.values) {
      if (isClassLimited(c)) return true;
    }
    return false;
  }

  /// Visible for testing — read the current limit for [cls].
  @visibleForTesting
  static int limitFor(RateLimitClass cls) => _classLimits[cls] ?? 120;

  /// Visible for testing — classify a path the same way the middleware does.
  @visibleForTesting
  static RateLimitClass classifyPath(String path) => _classify(path);

  // ─── Internal helpers ─────────────────────────────────────────────────

  static String _clientIp(Request request) {
    final xff = request.headers['x-forwarded-for'];
    if (xff != null && xff.isNotEmpty) {
      return xff.split(',').first.trim();
    }
    final realIp = request.headers['x-real-ip'];
    if (realIp != null && realIp.isNotEmpty) return realIp.trim();
    return request.headers['host']?.split(':').first ?? 'unknown';
  }

  /// Classify [path] using the longest-prefix rule. Logs a one-shot
  /// WARNING for any path that misses the rules so unmapped routes are
  /// visible in dev/staging without spamming production logs.
  static RateLimitClass _classify(String path) {
    for (final rule in _classRules) {
      if (path == rule.key || path.startsWith('${rule.key}/') ||
          path.startsWith('${rule.key}?')) {
        return rule.value;
      }
    }
    if (_unmappedPathsLogged.add(path)) {
      debugPrint('[RateLimit] WARNING: endpoint "$path" not in classification '
          'map — using defaultClass (${_classLimits[RateLimitClass.defaultClass]} '
          'req/${_window.inSeconds}s). Add it to api_rate_limiter.dart '
          '_classRules with the appropriate class.');
    }
    return RateLimitClass.defaultClass;
  }

  /// Check + increment the bucket for ([ip], [cls]).
  ///
  /// Returns true if allowed, false if the IP exceeded its budget for
  /// this class. The window resets independently per class.
  static bool _checkAndIncrement(String ip, RateLimitClass cls) {
    final now = DateTime.now();
    final classMap = _buckets.putIfAbsent(ip, () => <RateLimitClass, _Bucket>{});
    final bucket = classMap.putIfAbsent(cls, _Bucket.new);

    if (now.difference(bucket.windowStart) >= _window) {
      bucket.count = 0;
      bucket.windowStart = now;
    }

    bucket.count++;
    return bucket.count <= (_classLimits[cls] ?? 120);
  }

  /// Create the shelf [Middleware].
  static Middleware createMiddleware() {
    return (Handler innerHandler) {
      return (Request request) {
        final path = '/${request.url.path}';

        for (final prefix in _exemptPrefixes) {
          if (path.startsWith(prefix) || path == prefix) {
            return innerHandler(request);
          }
        }

        final ip = _clientIp(request);
        final cls = _classify(path);
        final allowed = _checkAndIncrement(ip, cls);

        if (!allowed) {
          final retryAfter = _window.inSeconds;
          final limit = _classLimits[cls] ?? 120;
          debugPrint('[RateLimit] 429 for $ip — class=${cls.name} exceeded '
              '$limit req/${_window.inSeconds}s on path=$path');
          return Response(
            429,
            body: '{"error":"Too many requests",'
                '"retryAfterSeconds":$retryAfter,'
                '"class":"${cls.name}"}',
            headers: {
              'content-type': 'application/json',
              'retry-after': '$retryAfter',
              'x-ratelimit-limit': '$limit',
              'x-ratelimit-class': cls.name,
              'x-ratelimit-window': '$retryAfter',
            },
          );
        }

        return innerHandler(request);
      };
    };
  }
}
