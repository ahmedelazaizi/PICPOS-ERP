// The four-eyes proof a device holds between "the manager approved" and "the
// operation reached the main" (plan 2026-10-24, P5).
//
// It is IN MEMORY ONLY and short lived. While held it
//   * rides every ServerProxy call as `X-Approval-Proof`, so the main can verify
//     it where the permission is checked;
//   * is stamped into the payload of a write as `approvalProof`, so an outbox row
//     that is replayed later still carries it (ServerProxy turns the payload key
//     back into the header and never sends it as business data).
import 'package:flutter/foundation.dart';

class ApprovalProofCarrier {
  ApprovalProofCarrier._();
  static final ApprovalProofCarrier instance = ApprovalProofCarrier._();

  /// How long a granted proof is attached to outgoing calls. The main accepts a
  /// proof for its first use for 5 minutes; this is deliberately shorter.
  static const Duration window = Duration(seconds: 90);

  /// The payload key that carries the proof through the outbox.
  static const String payloadKey = 'approvalProof';

  String? _proof;
  String? _permission;
  DateTime? _until;
  DateTime Function() _now = DateTime.now;

  /// The proof to attach now, or null (none held / window over).
  String? get proof {
    final until = _until;
    if (_proof == null || until == null || !_now().isBefore(until)) {
      return null;
    }
    return _proof;
  }

  String? get permission => proof == null ? null : _permission;

  void hold(String proof, {required String permission}) {
    _proof = proof;
    _permission = permission;
    _until = _now().add(window);
  }

  void clear() {
    _proof = null;
    _permission = null;
    _until = null;
  }

  /// Puts the held proof into a write [payload] (no-op without one).
  void stamp(Map<String, dynamic> payload) {
    final p = proof;
    if (p != null) payload[payloadKey] = p;
  }

  @visibleForTesting
  void debugUseClock(DateTime Function() now) => _now = now;

  @visibleForTesting
  void debugReset() {
    clear();
    _now = DateTime.now;
  }
}
