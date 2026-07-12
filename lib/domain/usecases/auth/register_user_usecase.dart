import '../../repositories/auth_repository.dart';

/// Use case: Register a new user.
///
/// Validates username uniqueness and password requirements,
/// then creates the user via the auth repository.
class RegisterUserUseCase {
  final IAuthRepository _repo;

  const RegisterUserUseCase(this._repo);

  /// Creates a new user with the given credentials.
  Future<int> execute({
    required String username,
    required String password,
    required String displayName,
    int? roleId,
    double? maxDiscountPercent,
    bool discountLimitIsPercent = true,
    String? cardCode,
  }) async {
    // Validation
    if (username.trim().isEmpty) {
      throw ArgumentError('اسم المستخدم مطلوب');
    }
    if (password.length < 4) {
      throw ArgumentError('كلمة المرور يجب أن تكون 4 أحرف على الأقل');
    }
    if (displayName.trim().isEmpty) {
      throw ArgumentError('الاسم المعروض مطلوب');
    }

    return _repo.createUser(
      username: username.trim(),
      password: password,
      displayName: displayName.trim(),
      roleId: roleId,
      maxDiscountPercent: maxDiscountPercent,
      discountLimitIsPercent: discountLimitIsPercent,
      cardCode: cardCode,
    );
  }
}
