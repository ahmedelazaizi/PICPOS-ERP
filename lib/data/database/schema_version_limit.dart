// The newest `user_version` this build can open (BKP-002 / MIG-001).
//
// MUST equal `AppDatabase.schemaVersion` — `test/unit/audit_b_backup_restore_test.dart`
// fails the moment they diverge, so bumping the schema forces a bump here.
// Kept separate from `database.dart` (file-size ratchet) and dependency-free so
// `PendingRestore` can use it without importing the database library.
const int kMaxSupportedSchemaVersion = 196;
