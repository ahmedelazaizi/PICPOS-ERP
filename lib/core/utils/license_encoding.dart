import 'dart:convert';

/// Encodes license binary fields in the unpadded base64url form used by PP2.
String encodeUnpaddedBase64Url(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
