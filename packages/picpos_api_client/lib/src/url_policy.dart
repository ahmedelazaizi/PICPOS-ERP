/// Which server URLs the app may talk to.
///
/// Dart's own `HttpClient` (used by `package:http`) does **not** consult
/// Android's network-security-config, so `usesCleartextTraffic=false` in the
/// manifest alone does not stop plain HTTP from Dart code. This policy is the
/// enforcement point: release builds accept `https` only; development builds
/// may also use `http` to the emulator host, loopback and the 192.168.0.0/16
/// shop LAN (ARCHITECTURE-M §2.4: M-A/M-B require TLS on the LAN in
/// production).
library;

class UrlPolicyException implements Exception {
  UrlPolicyException(this.uri, this.reason);
  final Uri uri;
  final String reason;
  @override
  String toString() => 'UrlPolicyException($reason: $uri)';
}

class UrlPolicy {
  const UrlPolicy({required this.allowDevCleartext});

  /// Release: HTTPS only.
  static const release = UrlPolicy(allowDevCleartext: false);

  /// Debug/profile builds: plain HTTP allowed to [isDevCleartextHost] hosts.
  static const development = UrlPolicy(allowDevCleartext: true);

  final bool allowDevCleartext;

  /// `10.0.2.2` (Android emulator → host PC), `localhost`, `127.0.0.0/8`,
  /// and `192.168.0.0/16` (typical shop LAN).
  static bool isDevCleartextHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h == '10.0.2.2') return true;
    final parts = h.split('.');
    if (parts.length != 4) return false;
    final octets = [for (final p in parts) int.tryParse(p)];
    if (octets.any((o) => o == null || o < 0 || o > 255)) return false;
    return octets[0] == 127 || (octets[0] == 192 && octets[1] == 168);
  }

  /// Throws [UrlPolicyException] when [uri] is not allowed.
  void check(Uri uri) {
    if (uri.host.isEmpty) throw UrlPolicyException(uri, 'no_host');
    if (uri.scheme == 'https') return;
    if (uri.scheme != 'http') throw UrlPolicyException(uri, 'unsupported_scheme');
    if (!allowDevCleartext) throw UrlPolicyException(uri, 'cleartext_not_allowed');
    if (!isDevCleartextHost(uri.host)) throw UrlPolicyException(uri, 'cleartext_host_not_allowed');
  }

  bool allows(Uri uri) {
    try {
      check(uri);
      return true;
    } on UrlPolicyException {
      return false;
    }
  }
}
