import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as argon_lib;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'db_key_names.dart';
import 'legacy_device_seed.dart';

/// Password validation result containing validity, errors, and strength score
class PasswordValidationResult {
  final bool isValid;
  final List<String> errors;
  final int strength; // 0-100

  const PasswordValidationResult({
    required this.isValid,
    required this.errors,
    required this.strength,
  });
}

/// قاعدةٌ واحدةٌ من سياسة كلمة المرور، وحالُها على كلمةٍ بعينها.
///
/// ⚠️ **لماذا عنوانان لا واحد.** [message] هي رسالةُ الخطأ الكاملةُ التي
/// تدخل `errors` ولا يجوز أن تتبدّل. و[label] عنوانٌ قصيرٌ لشبكة القواعد في
/// لوحة التصميم — «٨ أحرف على الأقل» في خانةٍ من عمودَين لا تسع جملة.
/// وبديلُ ذلك أن ترسم الواجهةُ قواعدَها بنفسها بنفس التعابير النمطيّة، فتصير
/// السياسةُ في مكانين ينحرفان صامتَين.
class PasswordRule {
  const PasswordRule({
    required this.label,
    required this.message,
    required this.ok,
  });

  /// عنوانٌ قصيرٌ للعرض في شبكة القواعد.
  final String label;

  /// الرسالةُ الكاملة — تدخل `errors` حين لا تتحقّق القاعدة.
  final String message;

  final bool ok;
}

/// Secure password hashing service using PBKDF2-like approach
/// with SHA-256 and multiple iterations for enhanced security.
class DatabaseKeyUnavailableException implements Exception {
  const DatabaseKeyUnavailableException();

  @override
  String toString() =>
      'تعذّر قراءة مفتاح تشفير قاعدة البيانات من التخزين الآمن؛ '
      'لن تُفتح القاعدة تجنباً لفقدان البيانات.';
}

class SecurityService {
  SecurityService._();

  /// هل أُثبت أنّ محرّكَ القاعدة SQLCipher فعلاً؟
  ///
  /// تُرفَع **مرّةً واحدةً** في `openConnection()` بعد أن تُرجع
  /// `PRAGMA cipher_version` نسخةً غيرَ فارغة. وشاشةُ التدقيق تقرؤها بدل
  /// قيمةٍ ثابتةٍ كانت تعرض «مشفَّرة» خضراءَ على قاعدةٍ نصٍّ صريح.
  ///
  /// ⚠️ ولا تُستعمَل حارساً: الحارسُ هو رفضُ الفتح في `connection_io.dart`.
  /// هذه للعرض وحدَه — فبقاؤها `false` على PostgreSQL أو في الاختبارات
  /// سلوكٌ صحيحٌ لا عطب.
  static bool databaseEncryptionVerified = false;

  static const int _saltLength = 32;
  static const int _iterations = 10000;

  // ═══════════════════════════════════════════════════════════════════════
  // PASSWORD HASHING
  // ═══════════════════════════════════════════════════════════════════════

  /// Generate a cryptographically secure random salt
  static String generateSalt() {
    final random = Random.secure();
    final salt = List<int>.generate(_saltLength, (_) => random.nextInt(256));
    return base64Encode(salt);
  }

  /// Hash password using PBKDF2-like approach with SHA-256
  /// Returns a base64-encoded hash string
  static String hashPassword(String password, String salt) {
    List<int> key = utf8.encode('$salt$password');

    // Multiple iterations for security
    for (int i = 0; i < _iterations; i++) {
      final digest = sha256.convert(key);
      key = digest.bytes;
    }

    return base64Encode(key);
  }

  /// Verify password against stored hash
  static bool verifyPassword(String password, String salt, String storedHash) {
    final computedHash = hashPassword(password, salt);
    return _secureCompare(computedHash, storedHash);
  }

  /// Time-constant string comparison to prevent timing attacks
  static bool _secureCompare(String a, String b) {
    if (a.length != b.length) return false;

    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ARGON2ID — Week-8 upgrade
  // ═══════════════════════════════════════════════════════════════════════
  //
  // Parameters chosen for the pure-Dart `cryptography` package.
  //
  // The `cryptography` package uses a pure-Dart Argon2id implementation on
  // Windows / Linux / macOS Desktop (no native FFI backend exists yet for
  // desktop). Pure-Dart is significantly slower than native, so we use
  // parameters that provide a good security-vs-speed trade-off:
  //
  //   memory    = 4 MB (4 096 KB)  — enough to defeat GPU parallelism
  //   iterations = 3               — adds time cost on top of memory cost
  //   parallelism = 1              — pure-Dart is single-threaded anyway
  //   hashLength  = 32 bytes
  //
  // This is already massively better than our previous PBKDF2-SHA256 with
  // 10 000 iterations (which has zero memory-hardness).  If a native backend
  // is added later (via cryptography_flutter or dart_argon2_ffi), the
  // parameters can be raised to the OWASP "high" tier (m=65536,t=3,p=4)
  // without changing the stored hash format.
  //
  // Hash storage format (PHC string):
  //   $argon2id$v=19$m=4096,t=3,p=1$<base64salt>$<base64hash>

  static const String _argon2Prefix = '\$argon2id\$';
  static const int    _argon2Memory      = 4096;  // KB = 4 MB (pure-Dart safe)
  static const int    _argon2Iterations  = 3;
  static const int    _argon2Parallelism = 1;
  static const int    _argon2HashLength  = 32;    // bytes

  static argon_lib.Argon2id get _argon2 => argon_lib.Argon2id(
    parallelism: _argon2Parallelism,
    memory:      _argon2Memory,
    iterations:  _argon2Iterations,
    hashLength:  _argon2HashLength,
  );

  /// True when [hash] was produced by Argon2id (new format).
  static bool isArgon2Hash(String hash) => hash.startsWith(_argon2Prefix);

  /// Generate a 16-byte random salt for Argon2 (returns raw bytes).
  static List<int> generateArgon2Salt() {
    final rng = Random.secure();
    return List<int>.generate(16, (_) => rng.nextInt(256));
  }

  /// Hash [password] with Argon2id.
  /// Returns a self-describing PHC string:
  ///   `$argon2id$v=19$m=65536,t=3,p=4$<base64salt>$<base64hash>`
  static Future<String> hashPasswordArgon2(String password) async {
    final saltBytes = generateArgon2Salt();
    final secretKey = await _argon2.deriveKey(
      secretKey: argon_lib.SecretKey(utf8.encode(password)),
      nonce: saltBytes,
    );
    final hashBytes = await secretKey.extractBytes();
    final saltB64 = base64.encode(saltBytes);
    final hashB64 = base64.encode(hashBytes);
    return '\$argon2id\$v=19'
        '\$m=$_argon2Memory,t=$_argon2Iterations,p=$_argon2Parallelism'
        '\$$saltB64\$$hashB64';
  }

  /// Verify [password] against an Argon2id PHC string.
  static Future<bool> verifyArgon2(String password, String phcHash) async {
    try {
      // Parse: $argon2id$v=19$m=65536,t=3,p=4$<saltB64>$<hashB64>
      final parts = phcHash.split('\$');
      // parts[0]="" parts[1]="argon2id" parts[2]="v=19"
      // parts[3]="m=65536,t=3,p=4" parts[4]=saltB64 parts[5]=hashB64
      if (parts.length < 6) return false;
      final saltBytes = base64.decode(parts[4]);
      final storedHash = base64.decode(parts[5]);

      final secretKey = await _argon2.deriveKey(
        secretKey: argon_lib.SecretKey(utf8.encode(password)),
        nonce: saltBytes,
      );
      final computedHash = await secretKey.extractBytes();

      return _secureCompareBytes(computedHash, storedHash);
    } catch (_) {
      return false;
    }
  }

  /// Unified verify — dispatches to Argon2id for new hashes,
  /// falls back to legacy PBKDF2-SHA256 for old hashes.
  ///
  /// Returns `(verified: bool, needsRehash: bool)`.
  /// When `needsRehash` is true the caller should transparently
  /// upgrade the stored hash to Argon2id.
  static Future<({bool verified, bool needsRehash})> verifyPasswordFull(
    String password,
    String salt,     // legacy salt (ignored for Argon2id hashes)
    String storedHash,
  ) async {
    if (isArgon2Hash(storedHash)) {
      final ok = await verifyArgon2(password, storedHash);
      return (verified: ok, needsRehash: false);
    }
    // Legacy PBKDF2-SHA256
    final ok = verifyPassword(password, salt, storedHash);
    return (verified: ok, needsRehash: ok); // verified → schedule rehash
  }

  /// Constant-time comparison for byte lists.
  static bool _secureCompareBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LEGACY HASH MIGRATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Check if hash is in legacy format (old simple 8-char hex hash)
  static bool isLegacyHash(String hash) {
    return hash.length == 8 && RegExp(r'^[0-9a-f]+$').hasMatch(hash);
  }

  /// Migrate legacy hash to new format (synchronous PBKDF2-SHA256 path).
  /// Returns tuple of (newHash, salt).
  static (String hash, String salt) migrateLegacyPassword(String password) {
    final salt = generateSalt();
    final hash = hashPassword(password, salt);
    return (hash, salt);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SESSION TOKEN
  // ═══════════════════════════════════════════════════════════════════════

  /// Generate a secure session token
  static String generateSessionToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Hash an API key using SHA-256 for storage (one-way)
  static String hashApiKey(String apiKey) {
    final bytes = utf8.encode(apiKey);
    return sha256.convert(bytes).toString();
  }

  /// Generate a unique ID
  static String generateUniqueId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random.secure().nextInt(999999);
    return '$timestamp$random';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PASSWORD POLICY VALIDATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Minimum password length
  static const int minPasswordLength = 8;

  /// قواعدُ السياسة وحالُ كلٍّ منها على [password] — بترتيبها.
  ///
  /// هي **مصدرُ** `errors` في [validatePassword]، لا نسخةٌ ثانيةٌ منها:
  /// الرسائلُ ونصُّها وترتيبُها تخرج من هنا وحدَه.
  static List<PasswordRule> passwordRules(String password) => [
        PasswordRule(
          label: '$minPasswordLength أحرف على الأقل',
          message: 'كلمة المرور يجب أن تكون $minPasswordLength أحرف على الأقل',
          ok: password.length >= minPasswordLength,
        ),
        PasswordRule(
          label: 'حرف كبير (A-Z)',
          message: 'يجب أن تحتوي على حرف كبير واحد على الأقل (A-Z)',
          ok: RegExp(r'[A-Z]').hasMatch(password),
        ),
        PasswordRule(
          label: 'حرف صغير (a-z)',
          message: 'يجب أن تحتوي على حرف صغير واحد على الأقل (a-z)',
          ok: RegExp(r'[a-z]').hasMatch(password),
        ),
        PasswordRule(
          label: 'رقم واحد على الأقل',
          message: 'يجب أن تحتوي على رقم واحد على الأقل (0-9)',
          ok: RegExp(r'[0-9]').hasMatch(password),
        ),
        PasswordRule(
          label: 'رمز خاص',
          message: 'يجب أن تحتوي على رمز خاص واحد على الأقل (!@#\$%^&*)',
          ok: RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password),
        ),
        PasswordRule(
          label: 'بلا مسافات',
          message: 'كلمة المرور لا يجب أن تحتوي على مسافات',
          ok: !password.contains(' '),
        ),
      ];

  /// Password validation result
  static PasswordValidationResult validatePassword(String password) {
    final errors = [
      for (final r in passwordRules(password))
        if (!r.ok) r.message,
    ];

    return PasswordValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      strength: _calculatePasswordStrength(password),
    );
  }

  /// Calculate password strength (0-100)
  static int _calculatePasswordStrength(String password) {
    int strength = 0;

    // Length bonus (up to 30 points)
    strength += (password.length * 3).clamp(0, 30);

    // Character variety (up to 40 points)
    if (RegExp(r'[A-Z]').hasMatch(password)) strength += 10;
    if (RegExp(r'[a-z]').hasMatch(password)) strength += 10;
    if (RegExp(r'[0-9]').hasMatch(password)) strength += 10;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength += 10;

    // Bonus for length > 12 (up to 20 points)
    if (password.length > 12) strength += 10;
    if (password.length > 16) strength += 10;

    // Penalty for common patterns
    if (RegExp(
      r'12345|password|admin|qwerty',
      caseSensitive: false,
    ).hasMatch(password)) {
      strength -= 30;
    }

    return strength.clamp(0, 100);
  }

  /// Get password strength label
  static String getPasswordStrengthLabel(int strength) {
    if (strength < 30) return 'ضعيفة';
    if (strength < 50) return 'متوسطة';
    if (strength < 70) return 'جيدة';
    if (strength < 90) return 'قوية';
    return 'ممتازة';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // INPUT SANITIZATION (SQL Injection Prevention)
  // ═══════════════════════════════════════════════════════════════════════

  /// Sanitize string input to prevent SQL injection
  /// Note: Drift already uses parameterized queries, but this adds extra layer
  static String sanitizeInput(String input) {
    // Remove or escape dangerous characters
    return input
        .replaceAll(RegExp(r'''[;'"\\]'''), '') // Remove SQL special chars
        .replaceAll(RegExp(r'--'), '') // Remove SQL comments
        .replaceAll(RegExp(r'/\*|\*/'), '') // Remove block comments
        .trim();
  }

  /// Sanitize numeric input - only allow digits and decimal point
  static String sanitizeNumericInput(String input) {
    return input.replaceAll(RegExp(r'[^0-9.]'), '');
  }

  /// Validate and sanitize barcode input
  static String? sanitizeBarcode(String input) {
    final sanitized = input.replaceAll(RegExp(r'[^0-9A-Za-z-]'), '').trim();
    if (sanitized.isEmpty) return null;
    return sanitized;
  }

  /// Check if input contains potential SQL injection patterns
  static bool hasSqlInjectionRisk(String input) {
    final patterns = [
      r"'\s*OR\s*'", // ' OR '
      r';\s*(DROP|DELETE|UPDATE|INSERT|ALTER)', // dangerous SQL commands
      r'--', // SQL comment
      r'/\*', // Block comment start
      r'UNION\s+SELECT', // UNION injection
      r'1\s*=\s*1', // Always true condition
    ];

    for (final pattern in patterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(input)) {
        return true;
      }
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PIN SECURITY (Phase 2)
  // ═══════════════════════════════════════════════════════════════════════

  /// Check if a stored PIN is in legacy plain-text format (4-6 digits)
  static bool isLegacyPin(String? pin) {
    if (pin == null) return false;
    return pin.length >= 4 && pin.length <= 6 && RegExp(r'^\d+$').hasMatch(pin);
  }

  /// مفتاحُ SQLCipher **القديم** (المشتقّ من الجهاز) — لا يُغيَّر ناتجُه حرفيًّا
  /// لأنّ قواعد العملاء الحاليّة مشفّرةٌ به.
  ///
  /// الاشتقاقُ نفسُه في [LegacyDeviceSeed.derive] (لا نسخةَ مكرّرة هنا).
  /// عند غياب معرّف الجهاز يُقرأ المفتاحُ الاحتياطيّ من التخزين الآمن.
  ///
  /// ⚠️ [databaseExists]: «أوّلُ تشغيل» = غيابُ ملف القاعدة لا غيابُ المفتاح.
  /// التخزينُ الآمن على ويندوز يُرجع `null` عند أيّ عطل، فتوليدُ مفتاحٍ جديد
  /// عند `null` لقاعدةٍ موجودة كان يُتلف الوصولَ إليها. الافتراضُ `true`
  /// (آمن): لا يُولَّد مفتاحٌ أبدًا إلا إذا أثبت المستدعي أنّ الملفَّ غير موجود.
  static Future<String> getDatabaseEncryptionKey({
    bool databaseExists = true,
  }) async {
    final derived = await LegacyDeviceSeed.derive();
    if (derived != null) return derived;

    // Device ID unavailable (or device_info failed) — secure-storage fallback.
    return _getOrCreateSecureFallbackKey(allowCreate: !databaseExists);
  }

  /// المفتاحُ الاحتياطيّ القديم في flutter_secure_storage.
  static const _fallbackKeyStorageKey = DbKeyNames.legacyFallback;

  static Future<String> _getOrCreateSecureFallbackKey({
    required bool allowCreate,
  }) async {
    try {
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock,
        ),
      );

      final existing = await storage.read(key: _fallbackKeyStorageKey);
      if (existing != null && existing.length >= 32) {
        return existing;
      }

      // `null`/قصيرٌ مع قاعدةٍ موجودة = المفتاحُ ضاع لا «أوّل تشغيل».
      if (!allowCreate) {
        throw const DatabaseKeyUnavailableException();
      }

      // Generate a cryptographically secure 64-char hex key
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      final newKey = sha256.convert(bytes).toString();

      await storage.write(key: _fallbackKeyStorageKey, value: newKey);
      return newKey;
    } catch (_) {
      throw const DatabaseKeyUnavailableException();
    }
  }
}

