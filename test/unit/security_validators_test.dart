import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/security_service.dart';
import 'package:ural_erp/core/validators/input_validators.dart';

/// Unit tests for Security Service and Input Validators
void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // SECURITY SERVICE TESTS
  // ═══════════════════════════════════════════════════════════════════════════
  
  group('SecurityService', () {
    test('generateSalt creates unique salts', () {
      final salt1 = SecurityService.generateSalt();
      final salt2 = SecurityService.generateSalt();
      
      expect(salt1, isNotEmpty);
      expect(salt2, isNotEmpty);
      expect(salt1, isNot(equals(salt2)));
    });
    
    test('hashPassword creates consistent hash with same salt', () {
      final salt = SecurityService.generateSalt();
      final hash1 = SecurityService.hashPassword('password123', salt);
      final hash2 = SecurityService.hashPassword('password123', salt);
      
      expect(hash1, equals(hash2));
    });
    
    test('hashPassword creates different hash with different salt', () {
      final salt1 = SecurityService.generateSalt();
      final salt2 = SecurityService.generateSalt();
      final hash1 = SecurityService.hashPassword('password123', salt1);
      final hash2 = SecurityService.hashPassword('password123', salt2);
      
      expect(hash1, isNot(equals(hash2)));
    });
    
    test('hashPassword creates different hash for different passwords', () {
      final salt = SecurityService.generateSalt();
      final hash1 = SecurityService.hashPassword('password123', salt);
      final hash2 = SecurityService.hashPassword('password456', salt);
      
      expect(hash1, isNot(equals(hash2)));
    });
    
    test('verifyPassword returns true for correct password', () {
      final salt = SecurityService.generateSalt();
      final hash = SecurityService.hashPassword('testpassword', salt);
      
      expect(SecurityService.verifyPassword('testpassword', salt, hash), isTrue);
    });
    
    test('verifyPassword returns false for wrong password', () {
      final salt = SecurityService.generateSalt();
      final hash = SecurityService.hashPassword('testpassword', salt);
      
      expect(SecurityService.verifyPassword('wrongpassword', salt, hash), isFalse);
    });
    
    test('isLegacyHash detects legacy format', () {
      expect(SecurityService.isLegacyHash('0a3b2c1d'), isTrue);
      expect(SecurityService.isLegacyHash('thisIsNotLegacy=='), isFalse);
    });
    
    test('generateSessionToken creates unique tokens', () {
      final token1 = SecurityService.generateSessionToken();
      final token2 = SecurityService.generateSessionToken();
      
      expect(token1, isNotEmpty);
      expect(token2, isNotEmpty);
      expect(token1, isNot(equals(token2)));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // INPUT VALIDATORS TESTS
  // ═══════════════════════════════════════════════════════════════════════════
  
  group('InputValidators - Required', () {
    test('validateRequired returns error for empty string', () {
      expect(InputValidators.validateRequired('', 'الاسم'), isNotNull);
      expect(InputValidators.validateRequired(null, 'الاسم'), isNotNull);
      expect(InputValidators.validateRequired('   ', 'الاسم'), isNotNull);
    });
    
    test('validateRequired returns null for valid input', () {
      expect(InputValidators.validateRequired('أحمد', 'الاسم'), isNull);
      expect(InputValidators.validateRequired('Test Name', 'الاسم'), isNull);
    });
    
    // Spec 137 BUG-U15: a single character is a legitimate name/code.
    test('validateRequired accepts a single character', () {
      expect(InputValidators.validateRequired('أ', 'الاسم'), isNull);
    });

    test('validateRequired rejects input over the length cap', () {
      expect(InputValidators.validateRequired('x' * 201, 'الاسم'), isNotNull);
    });
  });
  
  group('InputValidators - Price', () {
    test('validatePrice returns error for empty required', () {
      expect(InputValidators.validatePrice(''), isNotNull);
      expect(InputValidators.validatePrice(null), isNotNull);
    });
    
    test('validatePrice returns null for empty optional', () {
      expect(InputValidators.validatePrice('', required: false), isNull);
    });
    
    test('validatePrice returns error for negative', () {
      expect(InputValidators.validatePrice('-10'), isNotNull);
    });
    
    test('validatePrice returns error for non-number', () {
      expect(InputValidators.validatePrice('abc'), isNotNull);
    });
    
    test('validatePrice returns null for valid price', () {
      expect(InputValidators.validatePrice('100'), isNull);
      expect(InputValidators.validatePrice('99.99'), isNull);
      expect(InputValidators.validatePrice('0'), isNull);
    });
    
    test('validatePrice returns error for too large', () {
      expect(InputValidators.validatePrice('9999999999999'), isNotNull);
    });
  });
  
  group('InputValidators - Quantity', () {
    test('validateQuantity returns error for zero when not allowed', () {
      expect(InputValidators.validateQuantity('0'), isNotNull);
    });
    
    test('validateQuantity returns null for zero when allowed', () {
      expect(InputValidators.validateQuantity('0', allowZero: true), isNull);
    });
    
    test('validateQuantity returns null for valid quantity', () {
      expect(InputValidators.validateQuantity('10'), isNull);
      expect(InputValidators.validateQuantity('1.5'), isNull);
    });
  });
  
  group('InputValidators - Barcode', () {
    test('validateBarcode returns null for empty (optional)', () {
      expect(InputValidators.validateBarcode(''), isNull);
      expect(InputValidators.validateBarcode(null), isNull);
    });
    
    test('validateBarcode returns null for valid barcode', () {
      expect(InputValidators.validateBarcode('1234567890123'), isNull);
      expect(InputValidators.validateBarcode('ABC-123'), isNull);
    });
    
    test('validateBarcode returns error for invalid characters', () {
      expect(InputValidators.validateBarcode('abc@123'), isNotNull);
      expect(InputValidators.validateBarcode('test#barcode'), isNotNull);
    });
    
    test('validateBarcode returns error for too short', () {
      expect(InputValidators.validateBarcode('12'), isNotNull);
    });
  });
  
  group('InputValidators - Phone', () {
    test('validatePhone returns null for empty (optional)', () {
      expect(InputValidators.validatePhone(''), isNull);
    });
    
    test('validatePhone returns null for valid phone', () {
      expect(InputValidators.validatePhone('+20123456789'), isNull);
      expect(InputValidators.validatePhone('01234567890'), isNull);
    });
    
    test('validatePhone returns error for invalid format', () {
      expect(InputValidators.validatePhone('abc123'), isNotNull);
    });
  });
  
  group('InputValidators - Username', () {
    test('validateUsername returns error for empty', () {
      expect(InputValidators.validateUsername(''), isNotNull);
    });
    
    test('validateUsername returns null for valid', () {
      expect(InputValidators.validateUsername('admin'), isNull);
      expect(InputValidators.validateUsername('user_123'), isNull);
    });
    
    test('validateUsername returns error for Arabic', () {
      expect(InputValidators.validateUsername('مستخدم'), isNotNull);
    });
  });
  
  group('InputValidators - Password', () {
    test('validatePassword returns error for too short', () {
      expect(InputValidators.validatePassword('123'), isNotNull);
    });
    
    test('validatePassword returns null for valid', () {
      expect(InputValidators.validatePassword('1234'), isNull);
      expect(InputValidators.validatePassword('strongpassword'), isNull);
    });
  });
  
  group('InputValidators - Password Confirmation', () {
    test('validatePasswordConfirmation returns error for mismatch', () {
      expect(InputValidators.validatePasswordConfirmation('pass1', 'pass2'), isNotNull);
    });
    
    test('validatePasswordConfirmation returns null for match', () {
      expect(InputValidators.validatePasswordConfirmation('password', 'password'), isNull);
    });
  });
  
  group('InputValidators - Percentage', () {
    test('validatePercentage returns error for out of range', () {
      expect(InputValidators.validatePercentage('-5'), isNotNull);
      expect(InputValidators.validatePercentage('101'), isNotNull);
    });
    
    test('validatePercentage returns null for valid', () {
      expect(InputValidators.validatePercentage('0'), isNull);
      expect(InputValidators.validatePercentage('50'), isNull);
      expect(InputValidators.validatePercentage('100'), isNull);
    });
  });
  
  group('InputValidators - Sanitization', () {
    test('sanitizeInput removes dangerous characters', () {
      final sanitized = InputValidators.sanitizeInput("test'; DROP TABLE--");
      expect(sanitized, isNot(contains("';")));
      expect(sanitized, isNot(contains("--")));
    });
    
    test('sanitizeInput escapes HTML tags', () {
      final sanitized = InputValidators.sanitizeInput('<script>');
      expect(sanitized, isNot(contains('<')));
      expect(sanitized, isNot(contains('>')));
    });
    
    test('cleanNumericString removes non-numeric', () {
      expect(InputValidators.cleanNumericString(r'$100.50'), equals('100.50'));
      expect(InputValidators.cleanNumericString('abc123'), equals('123'));
    });
  });
}
