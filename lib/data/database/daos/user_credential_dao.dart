import 'package:drift/drift.dart';

import '../../../services/auth/credential_stamp_store.dart' show credentialFingerprint;
import '../database.dart';

/// الاعتمادُ الذي يصل من الرئيسي (خطة 2026-10-24، P2 / B.7.2). امتدادٌ مستقلٌّ
/// كي لا ينمو `user_dao.dart` (في سقف الحجم).
extension UserCredentialDao on AppDatabase {
  /// يكتب بصمةً سلّمها الرئيسي لصاحبها (ردّ `POST /api/auth/change-password`):
  /// Argon2id بملحٍ فارغ، ويمسح علمَ التغيير الإلزامي. لا يلمس غير هذه الأعمدة.
  /// يعيد `false` إن لم يوجد الصفّ محليًّا.
  Future<bool> applyServerCredential(int userId, String passwordHash) async {
    final n = await (update(users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        passwordHash: Value(passwordHash),
        passwordSalt: const Value(''),
        forcePasswordChange: const Value(false),
      ),
    );
    return n > 0;
  }

  /// الرئيسي قبل الدخول فعلًا (لا 403 «تغيير مطلوب») ⇒ علمٌ محليٌّ قديم يُمسح.
  Future<void> clearForcePasswordChangeFlag(int userId) =>
      (update(users)..where((u) => u.id.equals(userId))).write(
        const UsersCompanion(forcePasswordChange: Value(false)),
      );

  /// بصمةُ (fp) الاعتماد المحلّي لمستخدمٍ، أو `null`.
  Future<String?> getCredentialFingerprint(int userId) async {
    final u = await (select(users)..where((r) => r.id.equals(userId)))
        .getSingleOrNull();
    return (u == null || u.passwordHash.isEmpty)
        ? null
        : credentialFingerprint(u.passwordHash);
  }
}
