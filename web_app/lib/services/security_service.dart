import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Security service for password hashing
class SecurityService {
  /// Hash password using SHA256
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify password against hash
  static bool verifyPassword(String password, String storedHash) {
    final hash = hashPassword(password);
    return hash == storedHash;
  }
}
