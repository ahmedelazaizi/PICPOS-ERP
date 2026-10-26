// Leftover #1b: "how long does THIS signed-in user still have offline?" - the
// data behind the branch-device warning banner. Driven by the existing
// credential stamps + grace logic of [OfflineLoginPolicy]; the clock is the
// policy's (injectable in tests).
library;

import 'offline_login_policy.dart';

/// What the banner shows.
enum OfflineStandingKind {
  /// Nothing to say (plenty of time left, or the user was never delivered -
  /// that case is the shadow/enforce summary's business, not a countdown).
  hidden,

  /// Within [OfflineStanding.warnWithin] of the end of the grace.
  expiring,

  /// The grace is over (or the device clock was rolled back): offline login is
  /// refused until the device reaches the main.
  expired,
}

class OfflineStanding {
  const OfflineStanding(this.kind, {this.daysLeft = 0, this.graceDays = 7});

  static const hiddenStanding = OfflineStanding(OfflineStandingKind.hidden);
  static const warnWithin = Duration(days: 2);

  final OfflineStandingKind kind;

  /// Whole days left, rounded UP (1 = "today is the last day"). 0 when expired.
  final int daysLeft;
  final int graceDays;

  bool get visible => kind != OfflineStandingKind.hidden;
}

/// Pure mapping of a verdict + the moment it was taken.
OfflineStanding standingOf(OfflineLoginVerdict v, DateTime now) {
  switch (v.decision) {
    case OfflineLoginDecision.expired:
    case OfflineLoginDecision.clockRolledBack:
      return OfflineStanding(OfflineStandingKind.expired,
          graceDays: v.graceDays);
    case OfflineLoginDecision.allowed:
      final verified = v.lastVerified;
      if (verified == null) return OfflineStanding.hiddenStanding;
      final left = verified.add(Duration(days: v.graceDays)).difference(now);
      if (left > OfflineStanding.warnWithin) return OfflineStanding.hiddenStanding;
      if (left <= Duration.zero) {
        return OfflineStanding(OfflineStandingKind.expired,
            graceDays: v.graceDays);
      }
      final days = (left.inMinutes / Duration.minutesPerDay).ceil();
      return OfflineStanding(OfflineStandingKind.expiring,
          daysLeft: days < 1 ? 1 : days, graceDays: v.graceDays);
    case OfflineLoginDecision.notProvisioned:
    case OfflineLoginDecision.credentialChanged:
    case OfflineLoginDecision.rejectedByMain:
      return OfflineStanding.hiddenStanding;
  }
}

extension OfflineLoginStandingX on OfflineLoginPolicy {
  /// The banner state for [userId] now.
  Future<OfflineStanding> standing(int userId, {required String passwordHash}) async {
    final v = await check(userId, passwordHash: passwordHash);
    return standingOf(v, now());
  }
}
