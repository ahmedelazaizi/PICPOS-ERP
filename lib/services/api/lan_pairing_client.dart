import 'dart:convert';
import 'dart:io';

import '../device_identity_service.dart';
import '../server_proxy.dart';
import '../secure_storage_service.dart';
import '../tls_trust.dart';
import '../../core/config/brand.dart';
import '../../core/utils/uuid_v7.dart';
import 'lan_pairing_input.dart';

/// Client-side pairing handshake and device-header source of truth.
class LanPairingClient {
  /// Label only: nothing in the code base reads or writes this key (the device
  /// name comes from `Platform.localHostname`), so there is no stored value to
  /// migrate. Renamed to the PicPos name.
  static const deviceNameKey = 'picpos_lan_device_name';

  static Map<String, String> deviceHeaders() {
    final id = DeviceIdentityService.instance.tryGetDeviceId();
    return {
      if (id != null && id.isNotEmpty) 'X-Device-Id': id,
      'X-Device-Name': _deviceName(),
    };
  }

  static String _deviceName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'جهاز LAN';
    }
  }

  /// Pairs this device with a LAN host (SEC-007).
  ///
  /// [code] is either the 8-character one-time code or the full pairing
  /// payload (JSON) copied from the host. A payload carries the host
  /// certificate fingerprint: it is pinned BEFORE the first byte is sent and
  /// the connection is HTTPS-only (no downgrade). A bare code has no
  /// out-of-band fingerprint, so HTTPS is tried first with trust-on-first-use
  /// (the certificate actually presented is pinned after a successful pairing);
  /// plain HTTP is only used when the host does not speak TLS at all (the
  /// explicit legacy transport option on the host).
  static Future<Map<String, dynamic>> pair({
    required String address,
    required int port,
    required String code,
    String? deviceName,
    String? deviceKind,
  }) async {
    final input = LanPairingInput.parse(code);
    final id = await _deviceId();
    final name = deviceName?.trim().isNotEmpty == true
        ? deviceName!.trim()
        : _deviceName();
    final typed = address.trim();
    final explicit = typed.startsWith('http://') || typed.startsWith('https://');
    final host = typed.isEmpty && input.host != null ? input.host! : typed;
    final effectivePort = (typed.isEmpty ? input.port : null) ?? port;
    final List<String> bases;
    if (explicit) {
      bases = [_trimSlash(typed)];
    } else if (input.hasFingerprint) {
      bases = ['https://$host:$effectivePort'];
    } else {
      bases = ['https://$host:$effectivePort', 'http://$host:$effectivePort'];
    }

    Object? lastError;
    for (final base in bases) {
      final uri = Uri.parse('$base/api/pair');
      if (input.hasFingerprint && uri.scheme == 'https') {
        await TlsTrust.pin(uri.host, uri.port, input.fingerprint!);
      }
      String? firstUseFingerprint;
      final client = TlsTrust.ioClientTofu(
        connectionTimeout: const Duration(seconds: 15),
        onFirstUse: (_, _, fp) => firstUseFingerprint = fp,
      );
      try {
        final result =
            await _post(client, uri, input.code, id, name, deviceKind);
        final observed = firstUseFingerprint;
        if (result['success'] == true && observed != null) {
          await TlsTrust.pin(uri.host, uri.port, observed);
        }
        return result;
      } on HandshakeException catch (error) {
        // A certificate decision (pin mismatch) is final: never fall back to
        // HTTP after it. Any other handshake failure means the host is not
        // speaking TLS (legacy transport) and falls through to the next base.
        final text = error.toString();
        final certRejected = text.contains('CERTIFICATE_VERIFY_FAILED') ||
            text.contains('BAD_CERTIFICATE');
        if (!certRejected && bases.length > 1) {
          lastError = error;
          continue;
        }
        return {
          'success': false,
          'error': 'تعذّر تأمين الاتصال بالخادم (TLS): $error',
        };
      } catch (error) {
        lastError = error;
      } finally {
        client.close(force: true);
      }
    }
    return {'success': false, 'error': 'تعذّر الاتصال بالخادم: $lastError'};
  }

  static Future<Map<String, dynamic>> _post(
    HttpClient client,
    Uri uri,
    String code,
    String id,
    String name,
    String? deviceKind,
  ) async {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.headers.set('User-Agent', '${Brand.name}-Client');
    request.headers.set('X-Device-Id', id);
    request.headers.set('X-Device-Name', name);
    request.write(jsonEncode({
      'pairingCode': code.trim().toUpperCase(),
      'deviceId': id,
      'deviceName': name,
      'deviceKind': ?deviceKind,
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final data = body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return {
        'success': false,
        'error': data['error'] ?? 'فشل إقران الجهاز (${response.statusCode})',
      };
    }
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) {
      return {'success': false, 'error': 'لم يُرجع الخادم توكن الجهاز'};
    }
    DeviceIdentityService.instance.adoptForPairing(id);
    ServerProxy.instance.setApiToken(token);
    return {
      'success': true,
      'deviceId': id,
      'secure': uri.scheme == 'https',
      // M1: what the server bound this device to (from the code).
      'deviceKind': data['deviceKind'],
      'branchId': data['branchId'],
    };
  }

  static Future<String> _deviceId() async {
    final existing = DeviceIdentityService.instance.tryGetDeviceId();
    if (existing != null && existing.isNotEmpty) return existing;
    final storage = SecureStorageService();
    const key = 'device_id';
    final stored = await storage.read(key);
    if (stored != null && stored.isNotEmpty) return stored;
    final generated = UuidV7.generate();
    try {
      await storage.write(key, generated);
    } catch (_) {}
    return generated;
  }

  static String _trimSlash(String s) {
    final trimmed = s.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
