import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/auth/admin_password_heal.dart';

void main() {
  test('preserves structurally valid Argon2 password', () {
    expect(
      adminPasswordNeedsHeal(
        salt: '',
        hash: r'$argon2id$v=19$m=65536,t=3,p=1$c2FsdA$aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      isFalse,
    );
  });

  test('preserves valid legacy password', () {
    expect(
      adminPasswordNeedsHeal(
        salt: 'salt',
        hash: List.filled(32, 'h').join(),
      ),
      isFalse,
    );
  });

  test('heals empty or malformed credentials', () {
    expect(
      adminPasswordNeedsHeal(
        salt: '',
        hash: List.filled(32, 'h').join(),
      ),
      isTrue,
    );
    expect(adminPasswordNeedsHeal(salt: 'salt', hash: ''), isTrue);
    expect(adminPasswordNeedsHeal(salt: '', hash: r'$argon2id$bad'), isTrue);
  });
}
