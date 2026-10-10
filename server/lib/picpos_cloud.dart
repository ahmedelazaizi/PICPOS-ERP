/// PicPos cloud API (Phase I). See docs/mobile/ARCHITECTURE-I.md.
library;

import 'dart:io';

import 'src/db/database.dart';
import 'src/http/app.dart';
import 'src/security.dart';
import 'src/service/admin_service.dart';
import 'src/service/auth_service.dart';
import 'src/service/rate_limiter.dart';
import 'src/service/sync_service.dart';
import 'src/whatsapp/whatsapp.dart';

// Shared rules (tax, pricing, sale math, integrity, barcode): one package
// used by the server and the mobile app (packages/picpos_rules).
export 'package:picpos_rules/picpos_rules.dart';
export 'src/db/database.dart';
export 'src/http/app.dart';
export 'src/seed.dart';
export 'src/security.dart';
export 'src/service/admin_service.dart';
export 'src/service/auth_service.dart';
export 'src/service/desktop_service.dart';
export 'src/service/errors.dart';
export 'src/service/field_expenses.dart' show kMaxExpensePhotoBytes, kOverCustodyPolicies;
export 'src/service/field_geo.dart' show kGeoStatuses;
export 'src/service/rate_limiter.dart';
export 'src/service/sync_service.dart';
export 'src/whatsapp/whatsapp.dart';

/// Wires the services from environment variables.
class CloudConfig {
  CloudConfig(this.env);
  final Map<String, String> env;

  String get dbHost => env['DB_HOST'] ?? 'localhost';
  int get dbPort => int.tryParse(env['DB_PORT'] ?? '') ?? 5432;
  String get dbName => env['DB_NAME'] ?? 'picpos_cloud';
  String get dbUser => env['DB_USER'] ?? 'picpos';
  String get dbPassword => env['DB_PASSWORD'] ?? 'picpos';
  bool get dbSsl => env['DB_SSL'] == 'true';
  int get port => int.tryParse(env['PORT'] ?? '') ?? 8080;
  String get tokenSecret {
    final s = env['TOKEN_SECRET'];
    if (s == null || s.length < 32) {
      stderr.writeln('[config] TOKEN_SECRET missing/short — using a random one (sessions reset on restart)');
      return randomToken();
    }
    return s;
  }

  String get adminKey => env['ADMIN_KEY'] ?? '';

  /// Minimum `ADMIN_KEY` length outside the explicit test escape hatch (S-5).
  static const minAdminKeyLength = 24;

  /// Test stacks only: `ALLOW_WEAK_ADMIN_KEY=1` accepts short admin keys.
  bool get allowWeakAdminKey => env['ALLOW_WEAK_ADMIN_KEY'] == '1';

  /// Startup error for an unacceptable `ADMIN_KEY`, or null when fine. An empty
  /// key is allowed (it disables the `/admin/*` routes).
  String? get adminKeyProblem {
    final k = adminKey;
    if (k.isEmpty || allowWeakAdminKey || k.length >= minAdminKeyLength) return null;
    return 'ADMIN_KEY is too short (${k.length} chars): at least $minAdminKeyLength are required. '
        'Generate one with e.g. `openssl rand -hex 32`, leave ADMIN_KEY empty to disable /admin/*, '
        'or set ALLOW_WEAK_ADMIN_KEY=1 on a throw-away TEST stack only.';
  }

  bool get seedDemo => env['SEED_DEMO'] == 'true';
}

class CloudServices {
  CloudServices._(this.db, this.app, this.outbox);
  final CloudDatabase db;
  final CloudApp app;
  final WhatsAppOutbox outbox;

  static Future<CloudServices> create({
    required CloudDatabase db,
    required String tokenSecret,
    required String adminKey,
    WhatsAppProvider? provider,
    int pullOverlapMs = 2000,
    RateLimiter? loginLimiter,
    RateLimiter? pushLimiter,
    RateLimiter? adminLoginLimiter,
    RateLimiter? adminKeyLimiter,
  }) async {
    await db.migrate();
    final outbox = WhatsAppOutbox(db, provider ?? MockWhatsAppProvider());
    final app = CloudApp(
      db: db,
      auth: AuthService(db, SessionTokens(tokenSecret), loginLimiter: loginLimiter),
      sync: SyncService(db, pullOverlapMs: pullOverlapMs),
      outbox: outbox,
      adminKey: adminKey,
      pushLimiter: pushLimiter,
      adminKeyLimiter: adminKeyLimiter,
      // Distinct HMAC key: rep and admin session tokens are not interchangeable.
      admin: AdminService(db, SessionTokens('$tokenSecret|manage'), loginLimiter: adminLoginLimiter),
    );
    return CloudServices._(db, app, outbox);
  }
}
