// Long-form notes moved out of api_handler.dart so that file stays under the CI
// size gate (WH-029). Comments only - no code.
part of '../api_handler.dart';

// ── _adminSelfHealRan ─────────────────────────────────────────────────────
// Spec 029 / US3 Bug A — admin self-heal flag.
// Production observed admin (id=1) absent from the `/api/users`
// response despite the source containing `u.id.equals(1)`. Root cause
// could be: row physically deleted, row renamed to `__dup_1_admin`,
// or `drift_postgres` empty-IN-list semantics on PostgreSQL. The
// defensive fix runs ONCE per process: at the first `_getUsers` call,
// if the bootstrap admin is missing or corrupted, restore it BEFORE
// executing the query. See contracts/bug-a-admin-self-heal.md.

// ── roadcastChange ───────────────────────────────────────────────────────
// Public: Broadcast a data_changed event to connected WebSocket clients.
// Call this from server-side screens when entities are modified directly
// (e.g. branches, cost centers, accounts created via the server UI).
// 
// Delegates to [ApiHandlerBase.broadcast] instead of re-implementing the
// fan-out. The duplicate loop this replaces had two defects: it never
// pushed to `_localChangeController`, so the SERVER's own open screens did
// not refresh after an admin edit (only remote clients did); and it ignored
// `WsSubscriberInfo.branchId` entirely, so it could not scope a broadcast
// even when the caller knew the branch. Every current caller passes global
// master data (accounts, branches, cost centers, role_permissions), which
// correctly reaches everyone with [branchId] left null.

// ── 	ransactionalPullTablesForTest ────────────────────────────────────────
// Spec 151 P1-8b — exposed so a guard test can assert this stays IDENTICAL
// to `DeltaPullService.branchScopedPullTables`. If the two drift apart, one
// side silently reopens either the tokenless transactional leak (server
// serves a table the client thinks is denied) or the watermark poison
// (client seeds a watermark the server denies).
