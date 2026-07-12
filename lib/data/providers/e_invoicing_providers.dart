import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/e_invoicing/eta_service.dart';
import '../../services/e_invoicing/jofotara_service.dart';
import '../../services/e_invoicing/e_invoice_service_wrapper.dart';
import '../../services/e_invoicing/e_invoice_auto_submitter.dart';
import 'providers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// E-INVOICING PROVIDERS — مزودات الفوترة الإلكترونية
// ═══════════════════════════════════════════════════════════════════════════

/// E-Invoice Service Wrapper (singleton)
final eInvoiceServiceProvider = Provider<EInvoiceServiceWrapper>((ref) {
  final wrapper = EInvoiceServiceWrapper();
  ref.onDispose(() => wrapper.dispose());
  return wrapper;
});

/// Auto-submitter for automatic e-invoice submission after sales
final eInvoiceAutoSubmitterProvider = Provider<EInvoiceAutoSubmitter>((ref) {
  final repo = ref.watch(eInvoiceRepositoryProvider);
  final wrapper = ref.watch(eInvoiceServiceProvider);
  return EInvoiceAutoSubmitter(repo: repo, wrapper: wrapper);
});

/// Stream that watches all e-invoice submissions
final eInvoiceSubmissionsProvider =
    StreamProvider.autoDispose<List<EInvoiceSubmissionData>>((ref) {
      final repo = ref.watch(eInvoiceRepositoryProvider);
      return repo.watchSubmissions();
    });

/// Submission statistics for dashboard
final eInvoiceStatsProvider = FutureProvider.autoDispose
    .family<Map<String, int>, String?>((ref, platform) {
      final repo = ref.watch(eInvoiceRepositoryProvider);
      return repo.getSubmissionStats(platform: platform);
    });

/// Active e-invoice configuration
final eInvoiceConfigProvider = FutureProvider.autoDispose
    .family<EInvoiceConfigData?, String>((ref, platform) {
      final repo = ref.watch(eInvoiceRepositoryProvider);
      return repo.getActiveEInvoiceConfig(platform);
    });

/// Detect which platform is currently enabled (if any)
final activeEInvoicePlatformProvider = FutureProvider.autoDispose<String?>((ref) async {
  final repo = ref.watch(eInvoiceRepositoryProvider);
  final eta = await repo.getActiveEInvoiceConfig('eta');
  if (eta != null && eta.isEnabled) return 'eta';
  final jofotara = await repo.getActiveEInvoiceConfig('jofotara');
  if (jofotara != null && jofotara.isEnabled) return 'jofotara';
  return null;
});

/// Pending (unsent) submissions count
final pendingSubmissionsCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final repo = ref.watch(eInvoiceRepositoryProvider);
  final pending = await repo.getPendingSubmissions();
  return pending.length;
});

/// Initialize the e-invoice service from saved config
Future<void> initializeEInvoiceService(WidgetRef ref, String platform) async {
  final repo = ref.read(eInvoiceRepositoryProvider);
  final config = await repo.getActiveEInvoiceConfig(platform);

  if (config == null) return;

  final wrapper = ref.read(eInvoiceServiceProvider);

  if (platform == 'eta') {
    wrapper.configure(
      platform: EInvoicePlatform.eta,
      etaConfig: EtaConfig(
        clientId: config.clientId,
        clientSecret: config.clientSecret,
        registrationNumber: config.registrationNumber,
        activityCode: config.activityCode,
        isProduction: config.isProduction,
      ),
    );
  } else if (platform == 'jofotara') {
    wrapper.configure(
      platform: EInvoicePlatform.jofotara,
      jofotaraConfig: JofotaraConfig(
        clientId: config.clientId,
        clientSecret: config.clientSecret,
        registrationNumber: config.registrationNumber,
        isProduction: config.isProduction,
      ),
    );
  }
}
