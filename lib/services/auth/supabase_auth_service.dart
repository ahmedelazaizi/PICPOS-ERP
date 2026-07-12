import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around Supabase Auth for the web platform.
///
/// Responsibilities:
/// - Email/password sign-in and sign-out.
/// - Expose current user + tenant_id (loaded from `user_profiles`).
/// - Expose current role + permissions for UI gating.
///
/// Desktop/Server mode keeps using the local `AuthRepository` (which hits
/// SQLite/Postgres directly). This service is only invoked on the web.
class SupabaseAuthService {
  SupabaseAuthService._();
  static final instance = SupabaseAuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Currently-signed-in auth user (null if signed out).
  User? get currentUser => _client.auth.currentUser;

  /// Cached profile loaded on sign-in.
  UserProfile? _profile;
  UserProfile? get profile => _profile;

  /// Stream of auth state changes (sign-in / sign-out / token refresh).
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  /// Sign in with email + password.
  /// Returns the [UserProfile] on success; throws [AuthException] otherwise.
  Future<UserProfile> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final res = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (res.user == null) {
      throw const AuthException('Login failed: no user returned');
    }
    _profile = await _loadProfile(res.user!.id);
    return _profile!;
  }

  /// Sign out and clear cached profile.
  Future<void> signOut() async {
    await _client.auth.signOut();
    _profile = null;
  }

  /// Refresh the cached profile (call after role/permission changes).
  Future<UserProfile?> refreshProfile() async {
    final uid = currentUser?.id;
    if (uid == null) {
      _profile = null;
      return null;
    }
    _profile = await _loadProfile(uid);
    return _profile;
  }

  Future<UserProfile> _loadProfile(String userId) async {
    final row = await _client
        .from('user_profiles')
        .select()
        .eq('id', userId)
        .single();
    return UserProfile.fromJson(row);
  }

  /// Check if the current user has a given permission code.
  /// Admin role is implicitly granted all permissions.
  bool hasPermission(String code) {
    final p = _profile;
    if (p == null) return false;
    if (p.role == 'admin') return true;
    return p.permissions.contains(code);
  }

  /// Throws [StateError] if the user is not signed in on the web.
  /// Safe to call from UI that must never render signed-out state.
  void assertSignedIn() {
    if (!kIsWeb) return;
    if (currentUser == null || _profile == null) {
      throw StateError('SupabaseAuthService: not signed in.');
    }
  }
}

/// Typed view of `public.user_profiles`.
class UserProfile {
  final String id;
  final String tenantId;
  final String fullName;
  final String email;
  final String? phone;
  final String role;
  final String? defaultBranchId;
  final List<String> allowedBranchIds;
  final List<String> permissions;
  final bool isActive;

  const UserProfile({
    required this.id,
    required this.tenantId,
    required this.fullName,
    required this.email,
    required this.role,
    required this.allowedBranchIds,
    required this.permissions,
    required this.isActive,
    this.phone,
    this.defaultBranchId,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String?,
      role: json['role'] as String,
      defaultBranchId: json['default_branch_id'] as String?,
      allowedBranchIds:
          ((json['allowed_branch_ids'] as List?) ?? const []).cast<String>(),
      permissions:
          ((json['permissions'] as List?) ?? const []).cast<String>(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
