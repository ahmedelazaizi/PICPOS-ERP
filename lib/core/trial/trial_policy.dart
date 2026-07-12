/// Configurable trial policy for the application.
///
/// Defines the limits and restrictions for trial/demo versions.
/// The policy can be configured at build time or embedded in license keys.
library;

/// Trial restriction mode
enum TrialMode {
  /// Full version — no restrictions
  full,

  /// Time-limited trial (e.g., 30 days)
  timeLimited,

  /// Transaction-limited trial (e.g., 100 invoices)
  transactionLimited,

  /// Feature-limited trial (some screens locked)
  featureLimited,

  /// Combined restrictions (time + transactions + features)
  combined,
}

/// Configurable trial policy
class TrialPolicy {
  /// Trial mode
  final TrialMode mode;

  /// Maximum trial duration in days (null = unlimited)
  final int? trialDays;

  /// Maximum number of sales invoices (null = unlimited)
  final int? maxInvoices;

  /// Maximum number of products (null = unlimited)
  final int? maxProducts;

  /// Maximum number of customers (null = unlimited)
  final int? maxCustomers;

  /// Maximum number of suppliers (null = unlimited)
  final int? maxSuppliers;

  /// Maximum number of users (null = unlimited)
  final int? maxUsers;

  /// Whether to show watermark on printed receipts
  final bool watermark;

  /// Locked screen indices (screens the trial user cannot access)
  final List<int> lockedScreens;

  const TrialPolicy({
    this.mode = TrialMode.combined,
    this.trialDays = 30,
    this.maxInvoices = 200,
    this.maxProducts = 50,
    this.maxCustomers = 50,
    this.maxSuppliers = 50,
    this.maxUsers = 2,
    this.watermark = true,
    this.lockedScreens = const [],
  });

  /// Full version — no restrictions
  static const TrialPolicy fullVersion = TrialPolicy(
    mode: TrialMode.full,
    trialDays: null,
    maxInvoices: null,
    maxProducts: null,
    maxCustomers: null,
    maxSuppliers: null,
    maxUsers: null,
    watermark: false,
    lockedScreens: [],
  );

  /// Default trial policy
  static const TrialPolicy defaultTrial = TrialPolicy(
    mode: TrialMode.combined,
    trialDays: 30,
    maxInvoices: 200,
    maxProducts: 50,
    maxCustomers: 50,
    maxSuppliers: 50,
    maxUsers: 2,
    watermark: true,
    lockedScreens: [],
  );

  /// Demo for exhibitions/presentations — unlimited but watermarked
  static const TrialPolicy demoPolicy = TrialPolicy(
    mode: TrialMode.featureLimited,
    trialDays: null,
    maxInvoices: null,
    maxProducts: null,
    maxCustomers: null,
    maxSuppliers: null,
    maxUsers: null,
    watermark: true,
    lockedScreens: [],
  );

  /// Whether this policy imposes any limits
  bool get hasLimits => mode != TrialMode.full;

  /// Whether a specific screen index is locked
  bool isScreenLocked(int screenIndex) => lockedScreens.contains(screenIndex);

  /// Encode policy to a compact string for embedding in license keys
  /// Format: MODE|DAYS|INV|PROD|CUST|SUPP|USR|WM|SCREENS
  String encode() {
    final parts = [
      mode.index.toString(),
      (trialDays ?? -1).toString(),
      (maxInvoices ?? -1).toString(),
      (maxProducts ?? -1).toString(),
      (maxCustomers ?? -1).toString(),
      (maxSuppliers ?? -1).toString(),
      (maxUsers ?? -1).toString(),
      watermark ? '1' : '0',
      lockedScreens.join(','),
    ];
    return parts.join('|');
  }

  /// Decode policy from compact string
  static TrialPolicy decode(String encoded) {
    try {
      final parts = encoded.split('|');
      if (parts.length < 8) return defaultTrial;

      return TrialPolicy(
        mode: TrialMode.values[int.parse(parts[0])],
        trialDays: int.parse(parts[1]) == -1 ? null : int.parse(parts[1]),
        maxInvoices: int.parse(parts[2]) == -1 ? null : int.parse(parts[2]),
        maxProducts: int.parse(parts[3]) == -1 ? null : int.parse(parts[3]),
        maxCustomers: int.parse(parts[4]) == -1 ? null : int.parse(parts[4]),
        maxSuppliers: int.parse(parts[5]) == -1 ? null : int.parse(parts[5]),
        maxUsers: int.parse(parts[6]) == -1 ? null : int.parse(parts[6]),
        watermark: parts[7] == '1',
        lockedScreens: parts.length > 8 && parts[8].isNotEmpty
            ? parts[8].split(',').map(int.parse).toList()
            : [],
      );
    } catch (_) {
      return defaultTrial;
    }
  }
}
