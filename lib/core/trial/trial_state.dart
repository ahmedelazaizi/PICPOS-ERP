import 'trial_policy.dart';

/// Static global state for Trial and Licensing.
/// Moved out of LicenseService to break circular dependency with database layer.
class TrialState {
  /// Whether the app has been verified as activated
  static bool isActivatedCached = false;

  /// Current trial policy in effect
  static TrialPolicy activePolicy = TrialPolicy.defaultTrial;

  /// Whether the app is currently in trial mode (not full version)
  static bool get isTrial => activePolicy.hasLimits && !isActivatedCached;

  /// Whether to show a watermark on receipts
  static bool get showWatermark => isTrial && activePolicy.watermark;
}
