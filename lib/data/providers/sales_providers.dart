import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'providers.dart';
import '../../services/printing_service.dart';
import '../../domain/usecases/sales/calculate_invoice_totals_usecase.dart';
import '../../domain/usecases/sales/complete_sale_usecase.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SALES PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════



final printingServiceProvider = Provider<IPrintingService>((ref) {
  final db = ref.watch(databaseProvider);
  final salesRepository = ref.watch(salesRepositoryProvider);
  return PrintingServiceImpl(db, salesRepository);
});

// salesRepositoryProvider and returnsRepositoryProvider moved to repository_providers.dart (returnsRepositoryProvider still needs to be moved)

final calculateInvoiceTotalsUseCaseProvider =
    Provider<CalculateInvoiceTotalsUseCase>((ref) {
      return CalculateInvoiceTotalsUseCase();
    });

final completeSaleUseCaseProvider = Provider<CompleteSaleUseCase>((ref) {
  final repository = ref.watch(salesRepositoryProvider);
  final totalsUseCase = ref.watch(calculateInvoiceTotalsUseCaseProvider);
  // Day 9: pass totalsUseCase so the UseCase can validate mixed-payment totals.
  return CompleteSaleUseCase(repository, totalsUseCase);
});

/// Spec 136 ISS-25 — start time of the logged-in user's active OPEN shift
/// (null when no shift is open). Lets "today" views follow the SHIFT window
/// instead of the calendar day, so they don't reset at midnight while a shift
/// is still running.
final currentShiftStartProvider =
    FutureProvider.autoDispose<DateTime?>((ref) async {
  final userId = ref.watch(authProvider).user?.id;
  if (userId == null) return null;
  final treasuryRepo = ref.watch(treasuryRepositoryProvider);
  final shift = await treasuryRepo.getCurrentOpenShift(userId);
  return shift?.startTime;
});

final todaySalesProvider = StreamProvider.autoDispose<List<SalesInvoiceData>>((
  ref,
) async* {
  if (kIsWeb) {
    final supabase = ref.watch(supabaseDatabaseProvider);
    yield* supabase?.watchSalesInvoices() ??
        Stream<List<SalesInvoiceData>>.value([]);
    return;
  }
  final db = ref.watch(databaseProvider);
  // Spec 136 ISS-25 — follow the open shift window; fall back to the calendar
  // day when no shift is open (e.g. owner viewing the dashboard off-shift).
  final shiftStart = await ref.watch(currentShiftStartProvider.future);
  yield* shiftStart != null
      ? db.watchSalesSince(shiftStart)
      : db.watchTodaySales();
});

/// Live profit provider (Revenue - COGS - Expenses) for the current SHIFT
/// window — or the calendar day when no shift is open (Spec 136 ISS-25).
final liveProfitProvider = FutureProvider.autoDispose<double>((ref) async {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final shiftStart = await ref.watch(currentShiftStartProvider.future);
  final from = shiftStart ?? DateTime(now.year, now.month, now.day);
  final pl = await db.getIncomeStatement(from, now);
  return pl['netProfit'] as double;
});
