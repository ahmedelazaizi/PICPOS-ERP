// ignore_for_file: avoid_dynamic_calls
import 'dart:io' show File, FileMode, Platform;
import 'package:path_provider/path_provider.dart';

import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async' show unawaited;
import 'services/printing/pdf_compute_helper.dart';
import 'services/app_version_service.dart';
import 'services/client_write_interceptor.dart';
import 'services/id_namespace_service.dart';
import 'services/offline_sync_worker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ural_erp/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/app_config.dart';
import 'core/i18n/locale_provider.dart';
import 'core/i18n/tr.dart';
import 'core/auth/admin_password_heal.dart';
import 'core/config/brand.dart';
import 'core/config/business_profile_provider.dart';
import 'core/config/feature_key.dart';
import 'core/config/industry_tables_policy.dart';
import 'core/tax/tax_rate_policy.dart';
import 'core/theme/app_theme.dart';
import 'core/config/supabase_config.dart';
import 'data/providers/providers.dart';
import 'data/repositories/settings_repository_cached.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/setup_wizard_screen.dart';
import 'presentation/touch_keyboard/providers/touch_mode_provider.dart';
import 'presentation/widgets/admin_elevation_banner.dart';
import 'presentation/widgets/connection_health_wrapper.dart';
import 'presentation/widgets/touch_keyboard/touch_keyboard_controller.dart';
import 'presentation/widgets/touch_keyboard/touch_keyboard_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'services/admin_password_service.dart';
import 'services/audit_log.dart';
import 'services/developer_auth_service.dart';
import 'services/device_identity_service.dart';
import 'services/pos_terminal_registration_service.dart';
import 'core/logging/diagnostic_logger.dart';
import 'services/security_service.dart';
import 'services/sync/sync_worker.dart';

// Conditional import for desktop-only features
import 'main_desktop.dart' if (dart.library.html) 'main_web.dart' as platform;
import 'data/database/pg_config.dart';
import 'data/database/connection.dart' show openPostgresConnection, testPostgresConnection;
import 'services/invoice_integrity_service.dart';
import 'data/database/extensions/branch_dedup_extension.dart';
import 'data/database/extensions/return_memo_dedup_extension.dart';
import 'data/database/extensions/fiscal_year_dedup_extension.dart';
import 'data/database/extensions/sales_cogs_backfill_extension.dart';
import 'data/database/extensions/negative_sales_default_backfill_extension.dart';
import 'services/network_service.dart';
import 'services/deployment/reconcile_result.dart';
import 'services/sync/client_first_sync_service.dart';
import 'services/sync/mirror_divergence_handler.dart';
import 'services/sync_service.dart';
import 'presentation/screens/fatal_setup_error_screen.dart';
import 'core/widgets/app_error_boundary.dart'
    show installGlobalErrorWidgetBuilder;
import 'app_main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await I18nCatalog.load();
  // All Cairo weights are bundled; never depend on network access at POS startup.
  GoogleFonts.config.allowRuntimeFetching = false;

  // حارس الهوية — أول حاجة تتنفّذ.
  //
  // `String.fromEnvironment` بترجع أي سلسلة من غير تحقق، فغلطة كتابة زي
  // `--dart-define=APP_BRAND=picops` كانت هتبني بنجاح وتشتغل بهوية UralCash
  // كاملة — بناء يبان سليم وهو مخلوط. الرمي هنا بيحوّل الغلطة الصامتة دي
  // لفشل صريح عند أول تشغيل، قبل ما توصل للعميل.
  Brand.assertKnownBrand();

  // Replace Flutter's default error box with a readable Arabic card that
  // swaps in for ONLY the widget that failed, leaving the rest of the screen
  // usable. Previously a build exception anywhere left the raw framework error
  // box on screen with no way to recover short of restarting the app — the
  // "شاشة فيها مشكلة" reports. `FlutterError.onError` below still logs the
  // full stack; this governs what the operator sees.
  installGlobalErrorWidgetBuilder();

  // Capture Flutter framework errors (widget build failures, layout exceptions)
  // that are otherwise silently dropped in release builds.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details); // keeps debug overlay in debug mode
    // P5 (Issue #3): Truncating to 300 chars hid the actual failing frame
    // — the user reported a RangeError that pointed at line 1084 (a safe
    // `Colors.orange.shade800` call) but the real frame was further down
    // the stack. Log the FULL stack and add widget/library context so we
    // can pinpoint the source on the next reproduction.
    final stack = details.stack?.toString() ?? '<no stack>';
    final library = details.library ?? '<no library>';
    final context = details.context?.toDescription() ?? '<no context>';
    final summary = StringBuffer()
      ..writeln('library=$library')
      ..writeln('context=$context')
      ..writeln('exception=${details.exception}')
      ..writeln('---STACK---')
      ..writeln(stack.length > 4000 ? stack.substring(0, 4000) : stack);
    unawaited(
      DiagnosticLogger.log('FLUTTER_ERROR', summary.toString())
          .catchError((_) {}),
    );
  };

  // Field-report 2026-05-14 (Feature 054 v134): standalone build process-
  // exited ~90s after a successful A4 print. FlutterError.onError only
  // catches framework-level errors; platform-channel exceptions (e.g.
  // the Windows `printing` package's native dialog teardown) bypass it
  // entirely and crash the whole process. PlatformDispatcher.onError is
  // the Dart 3.1+ hook that intercepts every otherwise-uncaught async
  // error in the root zone — including the ones that come back across
  // platform channels. Return true to mark them handled so the process
  // doesn't die.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    final summary = StringBuffer()
      ..writeln('source=PlatformDispatcher.onError')
      ..writeln('error=$error')
      ..writeln('---STACK---')
      ..writeln(stack.toString().length > 4000
          ? stack.toString().substring(0, 4000)
          : stack.toString());
    unawaited(
      DiagnosticLogger.log('PLATFORM_ERROR', summary.toString())
          .catchError((_) {}),
    );
    return true; // handled — keep the process alive
  };

  await AppVersionService.initialize(); // ISS-CODE-02: read real version from pubspec
  ClientWriteInterceptor.setup();

  // Initialize Supabase for web platform.
  // On web we REQUIRE configuration — fail fast instead of silently running
  // against an unconfigured backend. See docs/SUPABASE_RLS_CHECKLIST.md.
  if (kIsWeb) {
    SupabaseConfig.assertConfigured();
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
  }

  // Initialize platform-specific features (window manager for desktop)
  await platform.initPlatform();

  // Pre-load database mode from settings (before creating providers)
  AppDatabase? pgDb;
  if (!kIsWeb) {
    // ─── CLI escape hatches (checked BEFORE any DB open attempt) ──────
    //
    // `--use-sqlite`        → force next boot onto local SQLite even if
    //                          the saved deployment mode is postgres.
    //                          Unblocks operators whose PG install is
    //                          broken (e.g. half-provisioned schema,
    //                          42P10/42601 seeder failures on PG 17).
    //                          Login recovers to admin/admin on SQLite
    //                          and they can re-link PG from Settings.
    //
    // `--use-postgres`      → clear the "use sqlite" override (admin
    //                          explicitly wants PG again).
    try {
      final args = Platform.executableArguments;
      if (args.contains('--use-sqlite')) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('pg_provisioned_ok', false);
        debugPrint('[STARTUP] 🔧 --use-sqlite flag observed — next boot uses SQLite');
      }
      if (args.contains('--use-postgres')) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('pg_provisioned_ok', true);
        debugPrint('[STARTUP] 🔧 --use-postgres flag observed — next boot attempts PG');
      }
    } catch (_) {}

    // Restore offline fallback state from previous session
    await PostgresConfig.loadOfflineFallbackState();
    final dbMode = await PostgresConfig.loadMode();

    // Client mode: ALWAYS use local SQLite for fast reads.
    // Data syncs via HTTP from the server automatically.
    final isClient = NetworkService.instance.isClient;

    // ─── PG gate: never connect to PG before admin has EXPLICITLY ────
    //     provisioned it successfully from inside the app.
    //
    // The `pg_provisioned_ok` SharedPreferences flag is set to TRUE by
    // the "Link to PostgreSQL" flow AFTER a successful test + schema
    // provisioning. Without this gate, a half-provisioned or corrupt PG
    // instance (common on fresh PG 17 installs before the Drift seeder
    // fix lands) left operators permanently locked out of the login
    // screen — the app couldn't find the admin row, the seeder couldn't
    // fix it, and there was no path back to SQLite.
    //
    // The flow is now strictly:
    //   1. Fresh install  → SQLite → login admin/admin → in-app setup.
    //   2. Admin picks "server" → in-app Link-to-PG flow → provision →
    //      sets `pg_provisioned_ok=true`.
    //   3. Next restart  → app reads the flag and connects to PG.
    //   4. If PG fails for any reason, `--use-sqlite` (or wiping the
    //      flag) returns the operator to the working SQLite session.
    final prefs = await SharedPreferences.getInstance();
    final pgProvisioned = prefs.getBool('pg_provisioned_ok') ?? false;

    if (dbMode == DatabaseMode.postgres && pgProvisioned && !isClient) {
      // Server mode: connect directly to PostgreSQL
      final pgConfig = await PostgresConfig.load();
      // Test connectivity first (3s timeout) to avoid crashing offline
      final error = await testPostgresConnection(pgConfig);
      if (error == null) {
        // Server reachable — use PostgreSQL
        pgDb = AppDatabase.withExecutor(
          openPostgresConnection(pgConfig),
          isPostgres: true,
        );
        await PostgresConfig.setOfflineFallback(false);
        debugPrint('[STARTUP] ✅ PostgreSQL connected: ${pgConfig.displayString}');
      } else {
        // Server unreachable — fall back to local SQLite
        debugPrint('[STARTUP] ⚠️ PostgreSQL unreachable: $error — using local SQLite');
        await PostgresConfig.setOfflineFallback(true);
      }
    } else if (dbMode == DatabaseMode.postgres && !pgProvisioned && !isClient) {
      debugPrint('[STARTUP] 📂 PG mode saved but not yet provisioned — using local SQLite. '
          'Admin can link PG from Settings → Network Mode after login.');
    } else if (isClient) {
      // Client mode doesn't use PostgreSQL — clear any stale offline fallback flag
      // that may persist from a previous mode switch
      if (PostgresConfig.isOfflineFallback) {
        await PostgresConfig.setOfflineFallback(false);
        debugPrint('[STARTUP] 📱 Client mode — cleared stale PostgreSQL offline fallback flag');
      }
      debugPrint('[STARTUP] 📱 Client mode — using local SQLite + HTTP sync');
    }

    // ── Start HTTP API server DIRECTLY in main() for reliable startup ──
    // This ensures the API is available before the widget tree is mounted.
    // CRITICAL: keep ONE AppDatabase instance for the entire process —
    // cache, API server and Riverpod provider all share it. Multiple
    // instances on the same SQLite file caused subtle write-lock
    // contention that manifested as "app starts but UI never appears"
    // after a `business_profile` SQL change.
  }

  // ─── Phase C1: hydrate runtime config before runApp ────────────────
  //
  // Order matters: settings cache MUST be warm before we build the
  // Riverpod ProviderScope, otherwise the profile / feature notifiers
  // pay async DB hits during their first build (race-prone).
  AppDatabase? sharedDb;
  SettingsRepositoryCached? cachedSettings;
  if (!kIsWeb) {
    // Single shared instance — pgDb when available (server mode), else a
    // fresh `AppDatabase()`. We pass this same instance to every
    // downstream component so SQLite never sees parallel handles on the
    // same file from this process.
    try {
      sharedDb = pgDb ?? AppDatabase();
      await InvoiceIntegrityService.initialize(
        storage: const FlutterSecureStorage(),
      );
    } on DatabaseKeyUnavailableException catch (error) {
      runApp(FatalSetupErrorApp(
        result: ReconcileInconsistent(
          reasonAr: error.toString(),
          reasonCode: ReconcileReasonCode.dbReadError,
          dbMode: NetworkMode.standalone,
          details: [error.toString()],
        ),
      ));
      return;
    }

    // تسجيلُ طباعة التقارير — يُضبَط مرّةً هنا لأنّ `PdfComputeHelper` في
    // طبقةِ خدماتٍ لا تعرف قاعدةً ولا مستخدماً. والخطّافُ فارغٌ بالبناء،
    // فبلا هذا السطر لا يُسجَّل شيءٌ ولا يتغيّر سلوكُ الطباعة إطلاقاً.
    //
    // ⚠️ والفواتيرُ **ليست هنا**: `PrintingServiceImpl` يسجّلها بمعرِّفها
    // ومبلغها، وتسجيلُها هنا أيضاً يكتب سطرَين لطباعةٍ واحدة. ولذلك
    // `documentLabel` غيرُ ممرَّرٍ في مساري الفاتورتين.
    final auditDb = sharedDb;
    PdfComputeHelper.onPrinted = (label) => auditDb.logActivity(
          userId: ActorSnapshot.userId,
          userName: ActorSnapshot.userName,
          action: 'print_report',
          entityType: 'report',
          description: 'طباعةُ $label',
        );

    // Spec 089 — reconcile network_mode between SharedPreferences (legacy)
    // and the DB settings table (canonical). Repairs the split-brain
    // bug where wiping Documents leaves SharedPreferences intact, so the
    // next boot reads a stale `network_mode = client` from prefs even
    // though the DB has been wiped. Must run BEFORE any code branches
    // on `isClient`/`isMirror`/`isServer` below (HTTP API gate, admin
    // self-heal gate, ensureClientFloor, etc.).
    // Spec 125 FR-012/FR-013: reconcileWithDb now returns ReconcileResult
    // sealed. On Inconsistent → boot the FatalSetupErrorApp full-screen
    // blocker instead of letting the system silently downgrade. No
    // silent-fallback under any condition (per Spec 125 BUG 4 fix).
    final dbForReconcile = sharedDb; // local non-null capture for closures
    try {
      final reconcileResult =
          await NetworkService.instance.reconcileWithDb(dbForReconcile);
      if (reconcileResult is ReconcileInconsistent) {
        debugPrint('[STARTUP] ❌ Reconcile inconsistent: '
            '${reconcileResult.reasonCode}');
        // Hand control to the minimal Fatal app — we do NOT continue boot.
        // The user must repair via Dev Tools or reset the wizard.
        runApp(FatalSetupErrorApp(
          result: reconcileResult,
          onEnterDevTools: () {
            // T041: detailed Dev Tools entry from Fatal screen requires
            // the full app + auth provider stack to be alive. Logging
            // here is sufficient for support diagnostics; the user can
            // close + reopen, then navigate to Dev Tools through the
            // normal app entry that follows a "reset wizard" tap.
            debugPrint('[FATAL-SCREEN] user chose: enter developer tools');
          },
          onResetWizard: () {
            // T042: reset = clear setup_completed + setup_in_progress so
            // the wizard runs from scratch on next launch. We don't wipe
            // the DB here (preserves any salvageable data); the wizard's
            // own client/mirror branches will wipe seeded master data
            // via ClientFirstSyncService if/when the user picks those.
            debugPrint('[FATAL-SCREEN] user chose: reset wizard');
            unawaited(() async {
              try {
                await dbForReconcile.setSetting('setup_completed', '');
                await dbForReconcile.setSetting('setup_in_progress', '');
                debugPrint('[FATAL-SCREEN] setup flags cleared — '
                    'restart app to re-run wizard');
              } catch (e) {
                debugPrint('[FATAL-SCREEN] reset failed: $e');
              }
            }());
          },
        ));
        return; // Stop main() — Fatal app owns the UI now.
      }
      // Spec 131 (A5 upgrade trigger) — silent one-shot re-sync on the
      // first boot of a build that includes the mirror-cache-integrity
      // fix. `reconcileWithDb` sets `forceFirstSync=true` when a mirror
      // device hasn't yet applied the fix; here we run the wipe+pull
      // BEFORE the regular UI launches so the user never sees the bug.
      // On success, `performFirstSync` itself sets the
      // `mirror_cache_integrity_v1_applied` flag, so this branch never
      // fires twice. On failure we surface the existing Fatal screen for
      // mirror-first-sync-incomplete; the user re-runs the wizard.
      if (reconcileResult is ReconcileOk && reconcileResult.forceFirstSync) {
        debugPrint('[STARTUP] 🔁 Spec 131 upgrade trigger: '
            'forcing mirror first-sync before UI launch');
        try {
          final firstSyncService =
              ClientFirstSyncService.mirror(db: dbForReconcile);
          // Same resolve-or-build pattern used by deployment_mode_committer
          // _firstSync(): prefer the hosted singleton if it exists, else
          // construct one inline from the saved server URL.
          final SyncService syncService;
          final hosted = SyncService.instance;
          if (hosted != null) {
            syncService = hosted;
          } else {
            final serverUrl = NetworkService.instance.buildServerUrl();
            syncService = SyncService(serverUrl: serverUrl, localDb: dbForReconcile);
          }
          await firstSyncService.performFirstSync(syncService: syncService);
          debugPrint('[STARTUP] ✓ Spec 131 upgrade re-sync complete');
        } catch (e, st) {
          debugPrint('[STARTUP] ❌ Spec 131 upgrade re-sync failed: $e\n$st');
          // Flip the existing flag so the next reconcile pass returns
          // mirrorFirstSyncIncomplete — user sees the existing Fatal
          // screen and re-runs the wizard.
          try {
            await dbForReconcile.setSetting('mirror_first_sync_completed', 'false');
          } catch (_) {}
          runApp(FatalSetupErrorApp(
            result: ReconcileInconsistent(
              reasonAr: 'تعذّر إكمال إعادة المزامنة التلقائية للمرآة بعد '
                  'الترقية: $e. يرجى إعادة اعداد البدء.',
              reasonCode: ReconcileReasonCode.mirrorFirstSyncIncomplete,
              dbMode: NetworkMode.mirror,
            ),
            onEnterDevTools: () {},
            onResetWizard: () {
              unawaited(() async {
                try {
                  await dbForReconcile.setSetting('setup_completed', '');
                  await dbForReconcile.setSetting('setup_in_progress', '');
                } catch (_) {}
              }());
            },
          ));
          return;
        }
      }
      // ReconcileOk → continue boot normally.

      // Spec 131 (FR-006) — install the Fatal-screen runner so the
      // sales-transaction orchestrator (and any other site) can surface
      // a mirror-cache-divergence Fatal screen mid-session. The runner
      // replaces the active UI via runApp(FatalSetupErrorApp(...)); the
      // re-pair button re-runs performFirstSync and restarts the app.
      MirrorDivergenceHandler.installRunner((inconsistent) async {
        debugPrint('[STARTUP] 🚨 mirror-cache-divergence Fatal surfacing: '
            '${inconsistent.reasonCode}');
        runApp(FatalSetupErrorApp(
          result: inconsistent,
          onMirrorRepair: () async {
            debugPrint('[FATAL-SCREEN] user chose: re-pair mirror');
            try {
              await dbForReconcile
                  .setSetting('client_first_sync_completed', 'false');
              // Best-effort POS cart invalidation. The exact provider name
              // is identified in T030; for now, clearing client_first_sync_completed
              // forces a fresh first-sync on the next boot which produces
              // a clean state regardless of in-memory cart.
              final firstSyncService =
                  ClientFirstSyncService.mirror(db: dbForReconcile);
              final SyncService syncService;
              final hosted = SyncService.instance;
              if (hosted != null) {
                syncService = hosted;
              } else {
                final serverUrl = NetworkService.instance.buildServerUrl();
                syncService =
                    SyncService(serverUrl: serverUrl, localDb: dbForReconcile);
              }
              await firstSyncService.performFirstSync(syncService: syncService);
              debugPrint('[FATAL-SCREEN] ✓ re-pair complete — '
                  'user should restart the app');
            } catch (err) {
              debugPrint('[FATAL-SCREEN] re-pair failed: $err');
            }
          },
          onEnterDevTools: () {},
          onResetWizard: () {
            unawaited(() async {
              try {
                await dbForReconcile.setSetting('setup_completed', '');
                await dbForReconcile.setSetting('setup_in_progress', '');
              } catch (_) {}
            }());
          },
        ));
      });
    } on PgSchemaParityException catch (e) {
      // Spec 130 — PG schema parity self-heal failed unrecoverably.
      // Per Clarification Q2: Block-all. Refuse any reads/writes and
      // hand control to the Fatal screen with the new retry button.
      // Re-opening the DB (which re-runs runBeforeOpen → Phase 2d) is
      // sufficient to retry — no app restart needed.
      debugPrint('[STARTUP] ❌ PG schema parity FATAL: ${e.reasonAr}');
      runApp(FatalSetupErrorApp(
        result: ReconcileInconsistent(
          kind: ReconcileFatalKind.pgSchemaParity,
          reasonCode: ReconcileReasonCode.pgSchemaParity,
          reasonAr: e.reasonAr,
          details: [...e.details, ...e.failedEntities.map((f) => 'entity: $f')],
          dbMode: NetworkService.instance.mode,
        ),
        onRetrySelfHeal: () {
          debugPrint('[FATAL-SCREEN] user chose: retry PG self-heal');
          // The simplest in-process retry: trigger another DB read which
          // re-fires beforeOpen → Phase 2d. If the operator just granted
          // CREATE/ALTER perms, the pass will succeed and the app can
          // continue — but the user still needs to fully close + reopen
          // to escape this minimal Fatal app. We mark the setting so the
          // next boot is clean.
          unawaited(() async {
            try {
              await dbForReconcile.customSelect('SELECT 1').get();
              debugPrint('[FATAL-SCREEN] retry probe succeeded — '
                  'restart app to resume normal boot');
            } catch (err) {
              debugPrint('[FATAL-SCREEN] retry still failing: $err');
            }
          }());
        },
        onEnterDevTools: () {
          debugPrint('[FATAL-SCREEN] user chose: enter developer tools');
        },
        onResetWizard: () {
          debugPrint('[FATAL-SCREEN] user chose: reset wizard');
          unawaited(() async {
            try {
              await dbForReconcile.setSetting('setup_completed', '');
              await dbForReconcile.setSetting('setup_in_progress', '');
            } catch (err) {
              debugPrint('[FATAL-SCREEN] reset failed: $err');
            }
          }());
        },
      ));
      return; // Stop main() — Fatal app owns the UI now.
    } catch (e) {
      if (e is DatabaseKeyUnavailableException) {
        debugPrint('[STARTUP] ❌ database encryption key unavailable: $e');
        runApp(FatalSetupErrorApp(
          result: ReconcileInconsistent(
            reasonAr: e.toString(),
            reasonCode: ReconcileReasonCode.dbReadError,
            dbMode: NetworkService.instance.mode,
            details: [e.toString()],
          ),
        ));
        return;
      }
      // A PostgreSQL privilege failure must NOT fall through to the
      // continue-anyway branch below.
      //
      // Measured 2026-08-03: when the DB user lacks DDL rights on `public`,
      // the open fails with a raw `ServerException 42501` thrown from inside
      // drift's own migration machinery — *before* `beforeOpen` runs at all
      // (proven with a positive control: the admin connection produced 151
      // startup log entries, the restricted one produced zero). So Phase 2d's
      // parity pass never executes and can never raise the
      // `PgSchemaParityException` the clause above is waiting for, despite its
      // doc comment promising exactly that for "DDL permission denied".
      //
      // The old behaviour was the worst of both: the raw driver error landed
      // here, got logged as "continuing", and the app carried on against a
      // database it could not use — no Fatal screen, no Arabic reason, and a
      // confusing downstream failure instead. Route it to the same Fatal
      // screen the parity path uses; the retry button is exactly right here,
      // because the operator's fix (granting rights) needs no restart.
      if (isPostgresInsufficientPrivilege(e)) {
        debugPrint('[STARTUP] ❌ PG insufficient privilege: $e');
        runApp(FatalSetupErrorApp(
          result: ReconcileInconsistent(
            kind: ReconcileFatalKind.pgSchemaParity,
            reasonCode: ReconcileReasonCode.pgSchemaParity,
            reasonAr:
                'فشل فتح قاعدة البيانات. مستخدم PostgreSQL لا يملك صلاحيات '
                'كافية على مخطط public (إنشاء/تعديل الجداول). امنح المستخدم '
                'الصلاحيات المطلوبة ثم اضغط إعادة المحاولة.',
            details: ['insufficient_privilege (42501): $e'],
            dbMode: NetworkService.instance.mode,
          ),
          onRetrySelfHeal: () {
            debugPrint('[FATAL-SCREEN] retry after privilege grant');
            unawaited(() async {
              try {
                await dbForReconcile.customSelect('SELECT 1').get();
                debugPrint('[FATAL-SCREEN] retry probe succeeded — '
                    'restart app to resume normal boot');
              } catch (err) {
                debugPrint('[FATAL-SCREEN] retry still failing: $err');
              }
            }());
          },
          onEnterDevTools: () {
            debugPrint('[FATAL-SCREEN] user chose: enter developer tools');
          },
        ));
        return; // Stop main() — Fatal app owns the UI now.
      }
      debugPrint('[STARTUP] ⚠️ reconcileWithDb failed (continuing): $e');
    }

    // Start HTTP API now that we have a guaranteed-shared db handle.
    // Skip for both client and mirror modes — both *consume* an HQ server
    // and have no reason to host their own API. Without this skip, a
    // mirror laptop would bind port 8080 and accept connections it has
    // no business serving.
    final ns = NetworkService.instance;
    if (!ns.isClient && !ns.isMirror) {
      debugPrint('[STARTUP] 🚀 Starting HTTP API server...');
      try {
        await platform.autoStartNetworkServer(sharedDb);
      } catch (e) {
        debugPrint('[STARTUP] ❌ HTTP API server failed: $e');
      }
    }

    // Data-integrity backfill for every mode: materialise any missing
    // `inventory_balances` rows for products that only have `current_stock`
    // set. Older Excel imports populated current_stock but never created the
    // balance row, so any later sale failed with
    // "الصنف غير متوفر نهائياً فى المستودع". Idempotent — runs every start.
    try {
      final fixed = await sharedDb.backfillMissingInventoryBalances();
      if (fixed > 0) {
        debugPrint('[STARTUP] ✅ Backfilled $fixed missing inventory_balances row(s)');
      }
    } catch (e) {
      debugPrint('[STARTUP] ⚠️ backfillMissingInventoryBalances failed: $e');
    }

    // Feature 012 / Issue M-DUP-BRANCH — one-shot consolidation of
    // duplicate `branches` rows that piled up on mirror devices before
    // Feature 011's server-side `postBranch` dedup landed. Idempotent:
    // a clean local DB exits the dry-run in O(1) (single GROUP BY scan).
    // Runs for every mode because the same legacy state can exist on a
    // standalone-then-promoted-to-mirror laptop.
    try {
      final removed = await sharedDb.mergeDuplicateBranches();
      if (removed > 0) {
        debugPrint('[STARTUP] ✅ Merged $removed duplicate branch row(s)');
      }
    } catch (e) {
      debugPrint('[STARTUP] ⚠️ mergeDuplicateBranches failed: $e');
    }

    // Feature 012 / Issue M-DUP-PRET — collapse duplicate
    // purchase/sales return memo rows (`category = '*_return_balance'`)
    // that piled up before the (refType, refId, partyId) dedup landed
    // in SafeTransactionSyncStrategy. Idempotent: clean DB exits in O(1).
    try {
      final removed = await sharedDb.mergeDuplicateReturnMemos();
      if (removed > 0) {
        debugPrint('[STARTUP] ✅ Merged $removed duplicate return-memo row(s)');
      }
    } catch (e) {
      debugPrint('[STARTUP] ⚠️ mergeDuplicateReturnMemos failed: $e');
    }

    // Feature 014 / Issue 2 — collapse duplicate fiscal-year rows that
    // piled up on mirror / client devices. Same idempotent pattern as
    // the branch / return-memo passes above.
    try {
      final removed = await sharedDb.mergeDuplicateFiscalYears();
      if (removed > 0) {
        debugPrint('[STARTUP] ✅ Merged $removed duplicate fiscal-year row(s)');
      }
    } catch (e) {
      debugPrint('[STARTUP] ⚠️ mergeDuplicateFiscalYears failed: $e');
    }

    // Feature 016 — backfill `sales_invoice_items.cost_price` for the
    // legacy rows that mirror devices wrote with cost_price=0 BEFORE the
    // mirror's local-create path started stamping the local product WAC.
    // Without this, historical analytics on mirror still show
    // تكلفة البضاعة المباعة = 0 → inflated صافي ربح. Idempotent: clean
    // DB exits in O(1).
    try {
      // C-PERF-3: one-shot — skips the full JOIN scan once the DB is clean.
      final updated = await sharedDb.backfillSalesItemCostPriceOnce();
      if (updated > 0) {
        debugPrint('[STARTUP] ✅ Backfilled cost_price on $updated sales-item row(s)');
      }
    } catch (e) {
      debugPrint('[STARTUP] ⚠️ backfillSalesItemCostPriceOnce failed: $e');
    }

    // Feature 018 / Issue 10 — one-shot backfill of `enable_negative_sales`.
    // Existing installs (with sales history) get 'true' to preserve the legacy
    // hardcoded `'allow_negative'` behavior; fresh installs get 'false' so
    // they're safe by default. Idempotent: skipped if the setting already
    // exists.
    try {
      final chosen = await sharedDb.ensureNegativeSalesDefault();
      if (chosen != null) {
        debugPrint('[STARTUP] ✅ enable_negative_sales=$chosen (one-shot default)');
      }
    } catch (e) {
      debugPrint('[STARTUP] ⚠️ ensureNegativeSalesDefault failed: $e');
    }

    // 1. CLI / env recovery flag for the developer password.
    // ISS-SEC-02: disabled in release builds — developer tools must not be
    // reachable via environment variables in production.
    if (!kReleaseMode) {
      final cache = SettingsRepositoryCached(sharedDb);
      await cache.preload(const [
        'developer_password_salt',
        'developer_password_hash',
      ]);
      try {
        final args = Platform.executableArguments;
        final env = Platform.environment;
        await DeveloperAuthService.maybeHandleRecoverySignal(
          args: args,
          env: env,
          service: DeveloperAuthService(cache),
        );
      } catch (e) {
        debugPrint('[STARTUP] dev-pwd recovery check failed: $e');
      }
    }

    // 1b. CLI / env recovery flag for the *admin* user password.
    //
    // Recovery scenarios:
    //   * Fresh PostgreSQL server install where the seed reported success
    //     but the admin user ended up with a broken salt/hash (rare — seen
    //     when the provisioning transaction half-committed on a
    //     connection hiccup).
    //   * Operator forgot the admin password or someone changed it.
    //
    // Recognised signals:
    //   * CLI arg   `--reset-admin-password`
    //   * Env var   `URAL_RESET_ADMIN_PASSWORD=1`
    //
    // Behaviour: deletes any row where `username='admin'` and inserts a
    // fresh one with `username=admin`, `password=admin`, role = "مدير
    // النظام" (or 1 if the role is missing). On next launch the
    // built-in password-integrity self-heal (database_startup.dart step
    // 4) confirms verification works.
    try {
      final args = Platform.executableArguments;
      final env = Platform.environment;
      final fromCli = args.contains('--reset-admin-password');
      final fromEnv = env['URAL_RESET_ADMIN_PASSWORD'] == '1';
      // `--purge-users` is the nuclear option: wipe EVERY user row so the
      // next boot's self-heal + seeder run from scratch and create a
      // pristine admin/admin account. Use when `--reset-admin-password`
      // alone doesn't recover login (e.g. the users table has a
      // duplicate/corrupted admin row that the reset helper misses).
      final purgeUsers = args.contains('--purge-users') ||
          env['URAL_PURGE_USERS'] == '1';

      if (purgeUsers) {
        // Use print (stdout) so the message is visible in PowerShell on
        // a release build — debugPrint is a no-op in release mode.
        debugPrint('[STARTUP] 🔑 --purge-users flag observed — deleting ALL user rows');
        try {
          await sharedDb.customStatement('DELETE FROM users');
          debugPrint('[STARTUP] ✅ all users deleted — next startup will re-seed admin/admin');
        } catch (e) {
          debugPrint('[STARTUP] ❌ --purge-users failed: $e');
        }
      }

      if (fromCli || fromEnv) {
        debugPrint('[STARTUP] 🔑 --reset-admin-password flag observed — resetting admin/admin');
        try {
          await _resetAdminPasswordToDefault(sharedDb);
          // Immediate verification: re-read the row and confirm the hash
          // verifies against "admin" so a silent write failure is caught
          // and reported instead of leaving the user locked out.
          final rows = await sharedDb.customSelect(
            "SELECT password_hash, password_salt FROM users WHERE username = 'admin' LIMIT 1",
          ).get();
          if (rows.isEmpty) {
            debugPrint('[STARTUP] ⚠️ reset ran but no admin row found afterwards!');
          } else {
            final hash = rows.first.data['password_hash']?.toString() ?? '';
            final salt = rows.first.data['password_salt']?.toString() ?? '';
            final ok = salt.isNotEmpty &&
                SecurityService.verifyPassword('admin', salt, hash);
            debugPrint(ok
                ? '[STARTUP] ✅ admin password reset verified — login with: admin'
                : '[STARTUP] ❌ admin password reset WRITTEN but verify FAILED '
                    '(salt.len=${salt.length}, hash.len=${hash.length}). '
                    // اسم الملف التنفيذي حسب العلامة — دي تعليمة المستخدم
                    // بينفّذها فعلاً وهو مقدرش يدخل النظام، فاسم ملف مش
                    // موجود عنده يخلّيها بلا قيمة.
                    'Try: .\\${Brand.name}.exe --purge-users  then restart.');
          }
        } catch (e) {
          debugPrint('[STARTUP] ❌ admin-reset SQL failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[STARTUP] admin-pwd recovery failed: $e');
    }

    // 1b2. Setup-wizard recovery flag.
    //
    // Recognised signals:
    //   * CLI arg `--reset-setup-wizard`
    //   * Env var `URAL_RESET_SETUP_WIZARD=1`
    //
    // Why this exists: an install can land in a stuck state where no
    // developer password is set (e.g. wizard never completed cleanly, or
    // dev password was cleared but never re-set).
    //
    // The narrow case — "no dev password, need into Developer Tools" — is
    // now handled at the gate itself: when nothing is configured it offers
    // a set-password form instead of a disabled field, which is what
    // `DeveloperAuthService` documented all along. This flag remains for
    // the broader case: re-running the whole wizard (profile, mode,
    // branches, provisioning), which cannot be triggered from anywhere
    // else once setup is marked complete.
    //
    // It clears `setup_completed`,
    // `setup_in_progress`, AND the developer password keys. On the next
    // boot's wizard-gate (lib/main.dart line ~907), `setup_completed`
    // will be empty so the wizard runs from scratch, including the dev
    // password step. User data (sales, customers, products) is
    // preserved — only the setup flags are cleared.
    try {
      final args = Platform.executableArguments;
      final env = Platform.environment;
      final fromCli = args.contains('--reset-setup-wizard');
      final fromEnv = env['URAL_RESET_SETUP_WIZARD'] == '1';
      if (fromCli || fromEnv) {
        debugPrint('[STARTUP] 🔑 --reset-setup-wizard observed — clearing setup flags + dev password');
        await sharedDb.customStatement(
          "DELETE FROM settings WHERE \"key\" IN "
          "('setup_completed', 'setup_in_progress', "
          "'developer_password_salt', 'developer_password_hash')",
        );
        debugPrint('[STARTUP] ✅ setup flags cleared — wizard will run on this boot');
      }
    } catch (e) {
      debugPrint('[STARTUP] --reset-setup-wizard failed: $e');
    }

    // 1c. UNCONDITIONAL admin-login self-heal (runs on EVERY boot).
    //
    // Root-cause fix for "login fails on first run against a fresh
    // PostgreSQL database, operator must run --reset-admin-password".
    //
    // Why this lives in main.dart (not just beforeOpen):
    //   * beforeOpen runs deep inside Drift's opening pipeline and any
    //     early exception in a prior phase silently skips its own heal.
    //   * This block is the *last line of defence* — independent of the
    //     schema phases, integrity checks, and seeder. Raw SQL only.
    //   * It always writes a diagnostic log (to TWO locations) so we
    //     know with certainty whether this code path ran at all.
    //
    // Behaviour:
    //   1. Log boot to <exe>\${Brand.dbPrefix}_startup_log.txt AND
    //      <Documents>\${Brand.dbPrefix}_startup_log.txt — proves the code
    //      executed and the build is fresh.
    //   2. Raw-SQL SELECT admin row.
    //   3. If row is missing → call _resetAdminPasswordToDefault (which
    //      inserts it). If row is present, verify 'admin' password.
    //   4. If verify fails AND settings.admin_password_customized != 'true'
    //      (user never changed it via UI) → reset via raw SQL.
    //   5. Log every step. Never throw — swallow all errors so the app
    //      still comes up.
    //
    // Client mode: SKIP boot heal entirely. The admin credentials on a
    // client are SYNCED from the server (UserSyncStrategy / DeltaPullService),
    // and the server admin's password is almost always customised away from
    // 'admin'. With heal enabled, every boot would:
    //   1. See admin/admin verify=false (correct! — server password is custom)
    //   2. Reset locally to PBKDF2('admin')
    //   3. The next sync overwrites the local row with the server password
    //   4. The next boot sees admin/admin fails again → reset → loop
    // The user observed this loop in ${Brand.dbPrefix}_startup_log.txt
    // (defaultVerifies(admin/admin)=false → reset → next session same).
    if (!NetworkService.instance.isClient) {
      await _bootTimeAdminHeal(sharedDb);
    } else {
      debugPrint('[BootHeal] Skipped — client mode (admin credentials are '
          'server-authoritative, synced via UserSyncStrategy)');
    }

    // 2. Warm the settings cache with every key the runtime-profile
    //    layer reads. Each FeatureKey is enumerated so the override
    //    map is fully populated before Riverpod inspects it.
    final preloadKeys = <String>[
      'setup_completed',
      'setup_in_progress',
      'business_profile',
      'deployment_mode',
      'developer_password_salt',
      'developer_password_hash',
      'admin_password',
      'admin_password_salt',
      'admin_password_hash',
      'feature_schema_version',
      'runtime_config_hash',
      'config_recovery_attempted',
      // Feature 031 — Touch Mode toggle. Pre-warmed so the global focus
      // listener can read it synchronously on every focus event without
      // an async hop. Default (missing row) is read as 'false'.
      'touchMode',
      // Product tax ladder. Pre-warmed and pushed into TaxRatePolicy right
      // below so every write path (product form, Excel importer, server API)
      // validates against this install's ladder. It was configurable on paper
      // only: nothing in the codebase ever read the key, so a deployment that
      // set a custom ladder still had 14% rejected everywhere.
      TaxRatePolicy.settingKey,
      // «نوع النشاط التجاري» — يحكم رايةَ الطاولات في PicPos عبر
      // `withIndustryTablesOverride`. والقراءةُ هناك **متزامنة**
      // (`SettingsRepositoryCached.get`)، وهي ترجع `null` عند إخفاق الكاش
      // بنفس ما ترجعه عند غياب المفتاح. فبلا هذا السطر يُقرأ `null` دائماً
      // ⇒ اختيارُ «مطعم (طاولات وصالات)» لا يُظهر شيئاً، بلا خطأٍ ولا أثر.
      industryModeSettingKey,
      ...FeatureKey.values.map((k) => k.settingKey),
    ];
    cachedSettings = SettingsRepositoryCached(sharedDb);
    await cachedSettings.preload(preloadKeys);
    TaxRatePolicy.configureFromSetting(
        cachedSettings.get(TaxRatePolicy.settingKey));

    // 2b. Feature 009 (T012e) — warm up the device identity (UUIDv7 in
    //     secure storage, mirrored into app_settings.device_id). The
    //     value is a hard prerequisite for POS terminal registration
    //     (T012f) and shift-binding (T012h). Failure must not block app
    //     boot — DeviceIdentityService falls back to an in-memory id
    //     and logs a warning if secure storage is unavailable.
    try {
      await DeviceIdentityService.instance.warmup(cachedSettings);
    } catch (e) {
      debugPrint('[STARTUP] DeviceIdentityService warmup failed: $e');
    }
    // 2c. Feature 009 (T012f) — wire and trigger first POS terminal
    //     registration attempt. Idempotent + fire-and-forget; the
    //     online-reconnect hook (T012g, OfflineSyncWorker) retries
    //     on every WebSocket reconnect. Standalone installs short-
    //     circuit at the network-mode check inside the service.
    try {
      PosTerminalRegistrationService.instance.initialize(sharedDb);
      // ignore: discarded_futures
      PosTerminalRegistrationService.instance.registerIfNeeded();
    } catch (e) {
      debugPrint('[STARTUP] PosTerminalRegistrationService init failed: $e');
    }

    // 3. Wire the global AuditLog sink so the providers + services can
    //    record events from the very first boot frame.
    AuditLog.configure(ActivityLogger(sharedDb));

    // 3b. Migrate plaintext admin_password → hashed (ISS-002).
    try {
      await AdminPasswordService(cachedSettings).migrateIfNeeded();
    } catch (e) {
      debugPrint('[STARTUP] admin_password migration failed: $e');
    }

    // 4. CRITICAL (client-mode sync fix): initialize the write interceptor
    //    and offline outbox BEFORE the widget tree mounts. These two state
    //    holders used to live inside `autoSyncIfClient()` which was gated
    //    behind `setup_completed == 'true'` inside a post-frame callback.
    //    On a client machine whose setup flag was missing or blanked by
    //    any `ConfigService.resetWizard()` call, `ClientWriteInterceptor.
    //    _db` stayed null and `_tryOrQueue` silently dropped every write
    //    (server never saw it, and the outbox was empty so the "sync now"
    //    button had nothing to drain). Moving initialization here makes
    //    it unconditional — the interceptor and outbox are wired to the
    //    shared DB regardless of client/server/standalone mode, and any
    //    client write immediately lands either on the server or in the
    //    outbox (never on the floor).
    ClientWriteInterceptor.initialize(sharedDb);
    OfflineSyncWorker.instance.initialize(sharedDb);

    // 4b. CRITICAL (client-mode id-collision fix): lift the auto-increment
    //     sequence into the client-reserved range (>= 1B) BEFORE any
    //     local write or DeltaPull runs. Without this, a fresh client DB
    //     would hand out `id = 1, 2, 3…` for offline-created rows which
    //     collide with the server's own low ids the first time DeltaPull
    //     fetches master data — `INSERT OR REPLACE` then overwrites the
    //     user's local row with the unrelated server row, corrupting the
    //     just-typed customer/supplier. See services/id_namespace_service.dart.
    // Spec 136 ISS-22 — the id-namespace floor must run for BOTH client AND
    // mirror. NetworkService.isClient is FALSE on mirror (R9), so the old
    // isClient-only gate skipped the floor on mirror → offline rows got low ids
    // that collide with server ids → DeltaPull's INSERT OR REPLACE clobbered
    // the offline invoice (it vanished from the device, causing a shift
    // variance). Gate the floor on client||mirror; keep the inventory reconcile
    // client-only (a mirror must not push master inventory).
    if (NetworkService.instance.isClient || NetworkService.instance.isMirror) {
      try {
        await IdNamespaceService.instance.ensureClientFloor(sharedDb);
      } catch (e) {
        debugPrint('[STARTUP] ⚠️ ensureClientFloor failed (continuing): $e');
      }
    }

    if (NetworkService.instance.isClient) {
      // Reconcile local inventory_balances → server. Heals the gap where an
      // Excel import's opening-stock adjustStock call reached the server
      // with the wrong productId (sequence drift before UUID resolution
      // landed) and left the server without an `inventory_balances` row for
      // the product — later sales then fail with "غير متوفر نهائياً فى
      // المستودع". Idempotent: the server-side handler skips any
      // (product, warehouse) that already has an opening_stock movement.
      // Fire-and-forget — never blocks startup.
      unawaited(
        ClientWriteInterceptor.reconcileOpeningStocks().then((pushed) {
          if (pushed > 0) {
            debugPrint('[STARTUP] ✅ Reconciled $pushed inventory balance(s) to server');
          }
        }).catchError((e) {
          debugPrint('[STARTUP] ⚠️ reconcileOpeningStocks failed: $e');
        }),
      );
    }

    debugPrint('[STARTUP] ✅ ClientWriteInterceptor + OfflineSyncWorker initialized (mode=${NetworkService.instance.mode})');
  }

  runApp(ProviderScope(
    overrides: [
      // Use the shared instance for the provider too — eliminates
      // multi-instance lock contention with the cache + API server.
      if (sharedDb != null) databaseProvider.overrideWithValue(sharedDb),
      if (cachedSettings != null)
        settingsRepositoryCachedProvider.overrideWithValue(cachedSettings),
    ],
    child: const FeaturesBridge(child: CashierMarketApp()),
  ));
}

/// Boot-time admin-login self-heal — LAST LINE OF DEFENCE.
///
/// Runs on every boot from `main()` after `sharedDb` is open, whether the
/// DB is fresh, migrated, PG, or SQLite. Writes a diagnostic log to two
/// locations so the operator can always confirm this code path ran.
///
/// Uses pure raw SQL (no Drift companions) so it sidesteps the
/// `drift_postgres` companion-value quirk that caused
/// `UsersCompanion(...).copyWith(passwordSalt: Value(x))` to silently
/// write an empty salt on first install.
///
/// Never throws — always swallows errors so app startup continues.
Future<void> _bootTimeAdminHeal(AppDatabase db) async {
  final lines = <String>[
    '',
    '════════════════════════════════════════════════════════',
    '[BootHeal] ${DateTime.now().toIso8601String()}',
    '════════════════════════════════════════════════════════',
  ];

  Future<void> flush() async {
    final body = '${lines.join('\n')}\n';
    // Location A: next to UralCash.exe (always writable — co-located).
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final f = File('$exeDir${Platform.pathSeparator}${Brand.dbPrefix}_startup_log.txt');
      await f.writeAsString(body, mode: FileMode.append);
    } catch (e) {
      debugPrint('[BootHeal] exe-dir log write failed: $e');
    }
    // Location B: Documents folder.
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}${Platform.pathSeparator}${Brand.dbPrefix}_startup_log.txt');
      await f.writeAsString(body, mode: FileMode.append);
    } catch (e) {
      debugPrint('[BootHeal] Documents log write failed: $e');
    }
    // Location C: TEMP as a final fallback — Windows always allows writes here.
    try {
      final tmp = Platform.environment['TEMP'] ?? Platform.environment['TMP'];
      if (tmp != null && tmp.isNotEmpty) {
        final f = File('$tmp${Platform.pathSeparator}${Brand.dbPrefix}_startup_log.txt');
        await f.writeAsString(body, mode: FileMode.append);
      }
    } catch (e) {
      debugPrint('[BootHeal] TEMP log write failed: $e');
    }
  }

  try {
    // Step 1: read the admin row (duplicate-safe via ORDER BY + LIMIT).
    dynamic rows;
    try {
      rows = await db.customSelect(
        "SELECT id, password_hash, password_salt FROM users "
        "WHERE username = 'admin' ORDER BY id LIMIT 1",
      ).get();
    } catch (e) {
      lines.add('❌ SELECT admin row failed: $e');
      await flush();
      return;
    }

    // Step 2: check the sentinel.
    bool customized = false;
    try {
      final s = await db.customSelect(
        "SELECT value FROM settings WHERE key = 'admin_password_customized' LIMIT 1",
      ).get();
      customized = s.isNotEmpty && s.first.data['value']?.toString() == 'true';
    } catch (e) {
      lines.add('⚠ sentinel read failed (assuming not customized): $e');
    }
    lines.add('admin_password_customized=$customized');

    if (rows.isEmpty) {
      lines.add('admin row MISSING — inserting via raw SQL');
      try {
        await _resetAdminPasswordToDefault(db);
        lines.add('✅ admin inserted (admin/admin)');
      } catch (e) {
        lines.add('❌ admin insert failed: $e');
      }
      await flush();
      return;
    }

    final salt = rows.first.data['password_salt']?.toString() ?? '';
    final hash = rows.first.data['password_hash']?.toString() ?? '';
    // Use the Argon2-aware verifier. The legacy verifyPassword(...) only
    // recognises PBKDF2-SHA256 hashes, so after the first successful login
    // (which transparently rehashes to Argon2id and sets passwordSalt='')
    // every subsequent boot would see salt.len=0, decide the row is broken,
    // and reset back to PBKDF2 — only for the next login to rehash to
    // Argon2 again. The salt-wipe loop the user observed in
    // ${Brand.dbPrefix}_startup_log.txt was this exact ping-pong.
    final verifyResult = await SecurityService.verifyPasswordFull(
        'admin', salt, hash);
    final verifiesDefault = verifyResult.verified;

    lines.add('salt.len=${salt.length} hash.len=${hash.length}');
    lines.add('verifies("admin")=$verifiesDefault');

    if (verifiesDefault) {
      lines.add('✅ admin/admin works — no action');
      await flush();
      return;
    }

    if (customized) {
      lines.add('ℹ admin_password_customized=true — preserving custom password');
      await flush();
      return;
    }

    if (!adminPasswordNeedsHeal(salt: salt, hash: hash)) {
      lines.add('ℹ valid non-default password preserved');
      await flush();
      return;
    }

    // Step 3: structurally broken + no sentinel → heal via raw SQL.
    lines.add('⚠ admin password hash is structurally broken — resetting…');
    try {
      await _resetAdminPasswordToDefault(db);
    } catch (e) {
      lines.add('❌ _resetAdminPasswordToDefault threw: $e');
      await flush();
      return;
    }

    // Step 4: read-back verify.
    try {
      final rb = await db.customSelect(
        "SELECT password_hash, password_salt FROM users "
        "WHERE username = 'admin' ORDER BY id LIMIT 1",
      ).get();
      if (rb.isEmpty) {
        lines.add('❌ read-back returned no row');
      } else {
        final s2 = rb.first.data['password_salt']?.toString() ?? '';
        final h2 = rb.first.data['password_hash']?.toString() ?? '';
        // Argon2-aware verify (see verifiesDefault block above for why).
        final rbResult = await SecurityService.verifyPasswordFull(
            'admin', s2, h2);
        final ok = rbResult.verified;
        lines.add('read-back: salt.len=${s2.length} hash.len=${h2.length} '
            'verify=$ok');
        if (ok) {
          lines.add('✅ admin reset OK — login with admin/admin');
        } else {
          lines.add('❌ CRITICAL: reset written but verify still fails — '
              'report this log');
        }
      }
    } catch (e) {
      lines.add('❌ read-back verify failed: $e');
    }
  } catch (e, st) {
    lines.add('❌ _bootTimeAdminHeal uncaught: $e');
    lines.add(st.toString());
  } finally {
    await flush();
  }
}

/// S-04 decision: the known 'admin' password is only ever (re)created with
/// force_password_change=true, so it must be rotated at first login.
///
/// Reset the admin user to a known-good state (username='admin',
/// password='admin'). Used by the `--reset-admin-password` /
/// `URAL_RESET_ADMIN_PASSWORD=1` startup recovery path.
///
/// Works on both SQLite and PostgreSQL targets because it uses raw SQL
/// via [AppDatabase.customStatement]/`customSelect` plus the cross-
/// dialect [sqlBool] helper for the boolean column.
Future<void> _resetAdminPasswordToDefault(AppDatabase db) async {
  final salt = SecurityService.generateSalt();
  final hash = await SecurityService.hashPasswordArgon2('admin');

  final boolTrue = db.sqlBool(true);
  final boolFalse = db.sqlBool(false);

  // Ensure the admin role exists before inserting the user — otherwise
  // the users.role_id FK fails on PG with 23503 on fresh installs where
  // the seeder never ran or the roles table got truncated. `role_id` is
  // nullable, so we fall back to NULL if role creation also fails.
  int? roleId;
  try {
    final rows = await db.customSelect(
      "SELECT id FROM roles WHERE name = 'مدير النظام' LIMIT 1",
    ).get();
    if (rows.isNotEmpty) {
      roleId = rows.first.data['id'] as int;
    } else {
      // Insert the admin role and re-read its id. Cross-dialect: no
      // RETURNING clause (drift's `customStatement` on SQLite doesn't
      // surface it); SELECT after INSERT works on both backends.
      try {
        await db.customStatement(
          "INSERT INTO roles (name, description, is_system_role) "
          "VALUES ('مدير النظام', 'مدير النظام الرئيسي', $boolTrue)",
        );
        final after = await db.customSelect(
          "SELECT id FROM roles WHERE name = 'مدير النظام' LIMIT 1",
        ).get();
        if (after.isNotEmpty) roleId = after.first.data['id'] as int;
      } catch (_) {
        // FK insertion failed — leave roleId null, admin still gets created.
      }
    }
  } catch (_) {}

  // Check if an admin user already exists.
  final existing = await db.customSelect(
    "SELECT id FROM users WHERE username = 'admin' LIMIT 1",
  ).get();

  if (existing.isEmpty) {
    // Fresh insert. Columns match the `users` schema in both SQLite and
    // PostgreSQL since Drift normalises types. When roleId is null we
    // omit the column so the nullable FK doesn't get a bad value.
    if (roleId == null) {
      await db.customStatement(
        "INSERT INTO users (username, password_hash, password_salt, display_name, "
        "is_active, is_locked, force_password_change) "
        "VALUES ('admin', ?, ?, 'مدير النظام', $boolTrue, $boolFalse, $boolTrue)",
        [hash, salt],
      );
    } else {
      await db.customStatement(
        "INSERT INTO users (username, password_hash, password_salt, display_name, "
        "role_id, is_active, is_locked, force_password_change) "
        "VALUES ('admin', ?, ?, 'مدير النظام', ?, $boolTrue, $boolFalse, $boolTrue)",
        [hash, salt, roleId],
      );
    }
  } else {
    // Update in place — also un-lock and re-activate in case the account
    // was locked after too many failed logins.
    if (roleId == null) {
      await db.customStatement(
        "UPDATE users SET password_hash = ?, password_salt = ?, "
        "is_active = $boolTrue, is_locked = $boolFalse, "
        "force_password_change = $boolTrue "
        "WHERE username = 'admin'",
        [hash, salt],
      );
    } else {
      await db.customStatement(
        "UPDATE users SET password_hash = ?, password_salt = ?, "
        "is_active = $boolTrue, is_locked = $boolFalse, role_id = ?, "
        "force_password_change = $boolTrue "
        "WHERE username = 'admin'",
        [hash, salt, roleId],
      );
    }
  }

  // Clear the "admin password has been customized" sentinel — the operator
  // has explicitly asked to go back to admin/admin, so the startup
  // self-heal can once again treat a broken hash as worth repairing.
  try {
    await db.customStatement(
      "DELETE FROM settings WHERE key = 'admin_password_customized'",
    );
  } catch (_) {}
}


class CashierMarketApp extends ConsumerStatefulWidget {
  const CashierMarketApp({super.key});

  @override
  ConsumerState<CashierMarketApp> createState() => _CashierMarketAppState();
}

class _CashierMarketAppState extends ConsumerState<CashierMarketApp> {
  bool _initDone = false;

  @override
  void initState() {
    super.initState();
    // PIR-007 FIX: Moved from build() to initState() — one-shot initialization
    // without side-effects on every rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initDone) {
        _initDone = true;
        ref.read(themeModeProvider.notifier).init();
        ref.read(systemCurrencyProvider.notifier).init();
        // Spec 032 v3 — instantiate the sync worker once. The previous
        // `ref.watch(syncWorkerProvider)` in build() forced the entire
        // MaterialApp tree to rebuild on every sync tick (the worker
        // listens to a Drift stream that re-emits whenever sync_outbox
        // changes — i.e., several times per second under active sync).
        // The worker is a non-autoDispose NotifierProvider; one `read`
        // here is enough to start its build() and keep it alive.
        ref.read(syncWorkerProvider);
        final db = ref.read(databaseProvider);

        // CRITICAL FIX: Do NOT auto-sync until setup wizard has completed.
        // Without this guard, a fresh install with stale SharedPreferences
        // (e.g. network_mode=client from a previous DB) would pull server
        // data BEFORE the user even reaches the setup wizard.
        _startSyncIfReady(db);
      }
    });
  }

  Future<void> _startSyncIfReady(AppDatabase db) async {
    final setupDone = await db.getSettingValue('setup_completed');
    if (setupDone != 'true') {
      debugPrint('[STARTUP] ⏸️ Setup not completed — skipping auto-sync');
      return;
    }
    platform.autoSyncIfClient(db);
    platform.startOfflineReconnectionTimer();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    // Watch currency so entire tree rebuilds when currency changes
    ref.watch(systemCurrencyProvider);

    // Spec 032 v3 — REMOVED `ref.watch(syncWorkerProvider)`. The watch
    // forced a full MaterialApp rebuild on every sync_outbox change
    // (which fires multiple times per second on an active POS). The
    // worker is now started lazily in initState via `ref.read`; it
    // doesn't need a build-phase subscription because it isn't
    // autoDispose.

    final authState = ref.watch(authProvider);
    final isAuthenticated = authState.isAuthenticated;
    final locale = ref.watch(userLocaleProvider);

    return MaterialApp(
      key: ValueKey('app_auth_$isAuthenticated'),
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: const [Locale('ar', 'EG'), Locale('en', 'US')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => ConnectionHealthWrapper(
        child: _TouchKeyboardWrapper(
          // Feature 004 (US3) — top-of-screen banner appears across every
          // screen when an elevated System Admin loses the server
          // connection. Hides itself when canMutate is true.
          // Feature 031 — Stack lets the on-screen touch keyboard float
          // above all routes / dialogs without per-screen wiring; the
          // _TouchKeyboardViewInsets adapter feeds the keyboard's height
          // into MediaQuery.viewInsets so existing scroll-into-view code
          // on every form keeps the focused field above the keyboard
          // (FR-010 + FR-018 — see research D6).
          child: Stack(
            children: [
              _TouchKeyboardViewInsets(
                child: Column(
                  children: [
                    const AdminElevationBanner(),
                    Expanded(child: child ?? const SizedBox()),
                  ],
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: TouchKeyboardOverlay(),
              ),
            ],
          ),
        ),
      ),
      home: isAuthenticated
          ? const _SetupGate()
          : const LoginScreen(),
    );
  }
}

/// Feature 031 — global FocusManager listener that drives the in-app
/// on-screen touch keyboard.
///
/// Architecture:
///   • Listener attaches once per app lifetime, in `MaterialApp.builder`,
///     so coverage is global without touching any individual screen
///     (spec FR-018).
///   • Early-returns when `touchModeProvider` is `false`. On the desktop
///     default install (touchMode off), this listener is observably a
///     no-op — same behaviour as the prior release (Constitution
///     Principle I, spec SC-007).
///   • The pre-Feature-031 implementation invoked Windows TabTip via
///     `platform.showTouchKeyboard()`. That path is retired here in
///     favour of an in-app overlay because the user explicitly chose
///     pure-Flutter / Web-compatible delivery (research D5).
///   • US1 (T011) replaces the `// TODO(US1)` block below with a
///     dispatch into the TouchKeyboardController.
class _TouchKeyboardWrapper extends ConsumerStatefulWidget {
  final Widget child;
  const _TouchKeyboardWrapper({required this.child});

  @override
  ConsumerState<_TouchKeyboardWrapper> createState() =>
      _TouchKeyboardWrapperState();
}

class _TouchKeyboardWrapperState extends ConsumerState<_TouchKeyboardWrapper> {
  // Feature 031 bugfix v3 — track the focused field by its
  // TextEditingController, not by EditableText widget identity. When a
  // TextField's parent rebuilds (which happens often — every state
  // change, every Riverpod tick, every keystroke that goes through the
  // input pipeline), Flutter constructs a NEW EditableText widget
  // instance even though the underlying state is unchanged. Comparing
  // by widget identity made the wrapper think it was a brand-new field
  // on every rebuild and trigger show() — which reset the layout to
  // the keyboardType-default, undoing the operator's manual switch to
  // numeric (the user reported "123 reverts to alpha"). The
  // TextEditingController is stable across rebuilds (it's typically
  // held in State).
  TextEditingController? _lastFocusedController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.addListener(_onFocusChange);
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    // Constitution Principle I — the very first check. When touch mode is
    // off, this listener MUST do nothing so installs on conventional
    // desktops (touchMode = false) experience zero behavioural change.
    if (!ref.read(touchModeProvider)) return;

    final controller = ref.read(touchKeyboardControllerProvider.notifier);
    final focusedNode = FocusManager.instance.primaryFocus;

    // Null primary focus → genuinely lost focus → hide.
    if (focusedNode == null) {
      if (_lastFocusedController != null) {
        _lastFocusedController = null;
        controller.hide();
      }
      return;
    }

    // Resolve the focus owner to its EditableText ancestor (if any).
    final ctx = focusedNode.context;
    EditableText? currentField;
    if (ctx != null) {
      currentField = ctx.findAncestorWidgetOfExactType<EditableText>();
    }

    // Focus moved to a non-text widget (e.g., a button, a tile, OR one of
    // the touch keyboard's own InkWell keys). Do NOT hide — the operator
    // is interacting with something that isn't a text field but the text
    // field they were typing into is still the keyboard's intended
    // target. Hiding here would race with cycleAlphaLayout / pressKey
    // and dismiss the keyboard on every key press.
    if (currentField == null) return;

    // Read-only / disabled fields don't get the keyboard (FR-021).
    if (currentField.readOnly) {
      if (_lastFocusedController != null) {
        _lastFocusedController = null;
        controller.hide();
      }
      return;
    }

    // Same controller as before → same logical field, even if the
    // EditableText widget instance was recreated by a parent rebuild.
    // Skipping re-dispatch here is critical: show() resets the layout
    // to the keyboardType-default (e.g., back to alpha for a text
    // field), undoing any manual switch the operator made via the 123
    // / EN / أ ب ج keys.
    if (identical(currentField.controller, _lastFocusedController)) return;

    _lastFocusedController = currentField.controller;
    controller.onFocusChanged(currentField);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Feature 031 — propagates the on-screen keyboard's height into
/// `MediaQuery.viewInsets.bottom`, which is the same channel the
/// framework uses for the OS soft keyboard. Existing scroll-aware
/// code (`Scrollable.ensureVisible`, `EditableText`'s built-in
/// caret-into-view) reacts to this without per-screen wiring
/// (research D6, spec FR-010 + FR-018).
class _TouchKeyboardViewInsets extends ConsumerWidget {
  final Widget child;
  const _TouchKeyboardViewInsets({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(
      touchKeyboardControllerProvider.select((s) => s.isVisible),
    );
    final mq = MediaQuery.of(context);
    final keyboardHeight = visible ? touchKeyboardHeightFor(mq.size.height) : 0.0;
    return MediaQuery(
      data: mq.copyWith(
        viewInsets: mq.viewInsets.copyWith(bottom: keyboardHeight),
      ),
      child: child,
    );
  }
}


// =======================================================================
// SETUP GATE — checks if first-run wizard is needed
// =======================================================================

/// One-time gate: shows Setup Wizard on first run, MainScreen after.
class _SetupGate extends ConsumerWidget {
  const _SetupGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return FutureBuilder<String?>(
      future: db.getSettingValue('setup_completed'),
      builder: (context, snapshot) {
        // While checking, show branded splash screen
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: const Color(0xFF1A1A2E),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // App icon/logo area
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F3460),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.point_of_sale_rounded,
                      size: 56,
                      color: Color(0xFF16C79A),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    AppConfig.appName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(0xFF16C79A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'جاري التحميل...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        // If setup_completed is 'true', go to main screen
        if (snapshot.data == 'true') {
          return const MainScreen();
        }
        // Otherwise, show the setup wizard
        return const SetupWizardScreen();
      },
    );
  }
}


/// True when [e] is PostgreSQL's `42501 insufficient_privilege`.
///
/// Matched on the SQLSTATE code and the server's message text rather than a
/// typed check, because the startup path sees this error in more than one
/// shape: raw `ServerException` from package:postgres when it escapes drift's
/// migration machinery, and drift-wrapped forms elsewhere. A typed catch would
/// silently miss whichever shape it wasn't written for.
///
/// Deliberately narrow: it must not classify ordinary runtime failures as a
/// fatal setup error. `42501` is emitted by PostgreSQL only for privilege
/// denial.
bool isPostgresInsufficientPrivilege(Object e) {
  final s = e.toString();
  return s.contains('42501') || s.contains('permission denied for schema');
}

// =======================================================================
// MAIN SCREEN & NAVIGATION -- See app_main_screen.dart
// =======================================================================