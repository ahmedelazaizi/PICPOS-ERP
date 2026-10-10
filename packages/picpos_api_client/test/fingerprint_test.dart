import 'dart:convert';

import 'package:picpos_api_client/picpos_api_client.dart';
import 'package:test/test.dart';

void main() {
  test('signingKeyFingerprint: SHA-256 of the key, first 16 bytes, 8 groups of 4 hex digits', () async {
    // SHA-256 of 32 zero bytes = 66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5f2925
    final fp = await signingKeyFingerprint(base64.encode(List<int>.filled(32, 0)));
    expect(fp, '6668 7AAD F862 BD77 6C8F C18B 8E9F 8E20');
  });

  test('rejects keys that are not 32 bytes', () async {
    await expectLater(signingKeyFingerprint(base64.encode([1, 2, 3])), throwsFormatException);
  });
}
