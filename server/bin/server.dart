import 'dart:async';
import 'dart:io';

import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final cfg = CloudConfig(Platform.environment);
  final adminKeyProblem = cfg.adminKeyProblem;
  if (adminKeyProblem != null) {
    stderr.writeln('[config] FATAL: $adminKeyProblem');
    exit(78);
  }
  final tlsProblem = cfg.tlsProblem;
  if (tlsProblem != null) {
    stderr.writeln('[config] FATAL: $tlsProblem');
    exit(78);
  }
  if (cfg.allowWeakAdminKey) {
    stderr.writeln('[config] WARNING: ALLOW_WEAK_ADMIN_KEY=1 — weak admin keys accepted (TEST ONLY)');
  }
  CloudDatabase? db;
  // Postgres may still be starting inside docker compose: retry for ~60 s.
  for (var i = 0; i < 30; i++) {
    try {
      db = await CloudDatabase.open(
        host: cfg.dbHost,
        port: cfg.dbPort,
        database: cfg.dbName,
        username: cfg.dbUser,
        password: cfg.dbPassword,
        ssl: cfg.dbSsl,
      );
      await db.query('SELECT 1');
      break;
    } catch (e) {
      stderr.writeln('[startup] waiting for database: $e');
      await db?.close();
      db = null;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
  if (db == null) {
    stderr.writeln('[startup] database unreachable, exiting');
    exit(1);
  }

  final services = await CloudServices.create(
    db: db,
    tokenSecret: cfg.tokenSecret,
    adminKey: cfg.adminKey,
    provider: providerFromEnv(cfg.env),
  );
  if (cfg.seedDemo) {
    await seedDemo(db);
    stdout.writeln('[startup] demo data ensured (SEED_DEMO=true)');
  }

  // Single WhatsApp outbox worker (I-1).
  Timer.periodic(const Duration(seconds: 10), (_) async {
    try {
      await services.outbox.processDue();
    } catch (e) {
      stderr.writeln('[whatsapp] worker error: $e');
    }
  });

  final server = await io.serve(
    services.app.handler,
    cfg.bindAddress,
    cfg.port,
    securityContext: cfg.tlsEnabled ? cfg.buildSecurityContext() : null,
  );
  if (cfg.plainHttpExposed) {
    stderr.writeln('[security] WARNING: plain HTTP on ${cfg.bindAddress.address}:${server.port}. '
        'Tokens and business data are NOT encrypted in transit. For production set TLS_CERT_FILE/TLS_KEY_FILE '
        'or bind BIND_ADDRESS=127.0.0.1 behind a TLS reverse proxy (docs/ops/CLOUD-SERVER-DEPLOY.md).');
  }
  stdout.writeln('[startup] picpos_cloud listening on ${cfg.tlsEnabled ? 'https' : 'http'}://'
      '${cfg.bindAddress.address}:${server.port} (whatsapp=${services.outbox.provider.name})');
}
