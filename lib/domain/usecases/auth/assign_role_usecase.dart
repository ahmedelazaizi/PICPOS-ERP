import '../../repositories/auth_repository.dart';

/// Use case: Assign a role to a user.
///
/// Validates that both user and role exist, then assigns the role.
class AssignRoleUseCase {
  final IAuthRepository _repo;

  const AssignRoleUseCase(this._repo);

  /// Assigns [roleId] to [userId].
  Future<void> execute({
    required int userId,
    required int? roleId,
  }) async {
    if (userId <= 0) throw ArgumentError('معرف المستخدم غير صالح');

    await _repo.assignRoleToUser(userId, roleId);
  }
}
