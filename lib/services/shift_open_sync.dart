// Opens a shift and tells the main about it (plan 2026-10-24, M3 / MIR-009).
//
// Branch/standalone device: the shift is written locally first (the cashier must
// be able to work while the main is down) and the server call is fire-and-forget
// (queued in the outbox when the main is unreachable).
//
// Branch-manager console (mirror): there is NO outbox, so a local-first write
// followed by a lost submit would leave a shift only this console believes in.
// The main is asked FIRST; if it refuses or is unreachable nothing is written and
// the caller sees a [MirrorOfflineException]. The accepted shift comes back by
// the pull that follows every successful console write.
import '../domain/repositories/treasury_repository.dart';
import 'client_write_interceptor.dart';
import 'write_router.dart';

Future<void> openShiftAndSync(
  ITreasuryRepository repo,
  int userId,
  double opening, {
  int? branchId,
  String tag = 'ShiftGuard',
}) async {
  if (WriteRouter.isMirrorActive) {
    await ClientWriteInterceptor.openShift(userId, opening, branchId: branchId);
    return;
  }
  await repo.openShift(userId, opening, branchId: branchId);
  try {
    final active = await repo.getCurrentOpenShift(userId);
    await ClientWriteInterceptor.dispatchWrite(
      () => ClientWriteInterceptor.openShift(
        userId,
        opening,
        localShiftId: active?.id,
        branchId: branchId,
        globalId: active?.globalId,
      ),
      tag: tag,
    );
  } catch (_) {
    // Non-fatal - the local open already succeeded.
  }
}
