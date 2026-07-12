// اختبار مطابقة: التحقق أن خوارزمية hash في PowerShell (reset_pg_admin_password.ps1)
// تُنتج نفس القيمة التي ينتجها SecurityService.hashPassword في Dart.
//
// استخدم قيم ثابتة لا تعتمد على عشوائية وتحقق من أن الـ verify يمر.

import 'package:ural_erp/services/security_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hashPassword is deterministic and verifyPassword round-trips', () {
    const salt = 'Yv6Q/H4BC7gPZgnhAmaXMHsKCkPW2YmluSVw5VhGwUs=';
    final hash = SecurityService.hashPassword('admin', salt);
    final ok = SecurityService.verifyPassword('admin', salt, hash);
    expect(ok, isTrue);

    // Any 32-byte base64 salt + 'admin' should produce a 44-char base64 hash.
    expect(hash.length, 44);
    expect(hash.endsWith('='), isTrue);
  });

  test('PowerShell-generated hash verifies correctly', () {
    // القيمتان هاتان من تشغيل scripts/reset_pg_admin_password.ps1
    // إن تطابق verify → خوارزمية PS مطابقة لخوارزمية Dart.
    const salt = 'Yv6Q/H4BC7gPZgnhAmaXMHsKCkPW2YmluSVw5VhGwUs=';
    const psHash = 'Dp9sM+pL4CCUAXqFQY8unnERxP72idyR/ky5wELc5DE=';
    final dartHash = SecurityService.hashPassword('admin', salt);
    expect(dartHash, psHash,
        reason: 'PowerShell hash must match Dart hash exactly');
    expect(
      SecurityService.verifyPassword('admin', salt, psHash),
      isTrue,
      reason: 'PS-generated hash must verify against password "admin"',
    );
  });
}
