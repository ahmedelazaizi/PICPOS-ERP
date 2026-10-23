// SEC-009 (audit 2026-10-23): a brute-force lockout must survive a restart.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/login_lockout_store.dart';
import 'package:picpos_erp/services/login_rate_limiter.dart';

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase.forTesting();
    LoginRateLimiter.reset();
    LoginLockoutStore.detachForTesting();
  });
  tearDown(() async {
    LoginLockoutStore.detachForTesting();
    LoginRateLimiter.reset();
    await db.close();
  });

  test('5 failures, "restart", still locked', () async {
    await LoginLockoutStore.ensureAttached(db);
    for (var i = 0; i < LoginRateLimiter.maxAttempts; i++) {
      LoginRateLimiter.recordFailure('Bob');
    }
    expect(LoginRateLimiter.getLockoutRemaining('bob'), isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // "Restart": in-memory state is gone, the store is re-attached.
    LoginRateLimiter.reset();
    LoginLockoutStore.detachForTesting();
    expect(LoginRateLimiter.getLockoutRemaining('bob'), isNull);
    await LoginLockoutStore.ensureAttached(db);

    expect(LoginRateLimiter.getLockoutRemaining('bob'), isNotNull,
        reason: 'lockout must be restored from the settings table');
    expect(LoginRateLimiter.getLockoutRemaining('alice'), isNull);
  });
}
