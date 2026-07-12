/// Input validators for form validation and data sanitization
/// Provides consistent validation across all screens
class InputValidators {
  InputValidators._();

  // ═══════════════════════════════════════════════════════════════════════
  // REQUIRED FIELD VALIDATORS
  // ═══════════════════════════════════════════════════════════════════════

  /// Validate required text field
  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName مطلوب';
    }
    // BUG-U15: a single character is a legitimate name/code — only emptiness
    // is rejected here.
    if (value.length > 200) {
      return '$fieldName طويل جداً (الحد الأقصى 200 حرف)';
    }
    return null;
  }

  /// Validate optional text field (if provided, must meet criteria)
  static String? validateOptional(
    String? value,
    String fieldName, {
    int minLength = 2,
    int maxLength = 200,
  }) {
    if (value == null || value.trim().isEmpty) {
      return null; // Optional, so empty is valid
    }
    if (value.trim().length < minLength) {
      return '$fieldName قصير جداً ($minLength أحرف على الأقل)';
    }
    if (value.length > maxLength) {
      return '$fieldName طويل جداً (الحد الأقصى $maxLength حرف)';
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // NUMBER VALIDATORS
  // ═══════════════════════════════════════════════════════════════════════

  /// Validate positive number
  static String? validatePositiveNumber(String? value, String fieldName) {
    if (value == null || value.isEmpty) {
      return '$fieldName مطلوب';
    }
    final number = double.tryParse(value);
    if (number == null) {
      return '$fieldName يجب أن يكون رقماً';
    }
    if (number < 0) {
      return '$fieldName يجب أن يكون موجباً';
    }
    return null;
  }

  /// Validate price (positive, within reasonable range)
  static String? validatePrice(String? value, {bool required = true}) {
    if (value == null || value.isEmpty) {
      return required ? 'السعر مطلوب' : null;
    }
    final price = double.tryParse(value);
    if (price == null) {
      return 'السعر يجب أن يكون رقماً';
    }
    if (price < 0) {
      return 'السعر يجب أن يكون موجباً';
    }
    if (price > 999999999) {
      return 'السعر كبير جداً';
    }
    return null;
  }

  /// Validate quantity
  static String? validateQuantity(
    String? value, {
    bool required = true,
    bool allowZero = false,
  }) {
    if (value == null || value.isEmpty) {
      return required ? 'الكمية مطلوبة' : null;
    }
    final qty = double.tryParse(value);
    if (qty == null) {
      return 'الكمية يجب أن تكون رقماً';
    }
    if (!allowZero && qty <= 0) {
      return 'الكمية يجب أن تكون أكبر من صفر';
    }
    if (allowZero && qty < 0) {
      return 'الكمية يجب أن تكون موجبة';
    }
    if (qty > 999999) {
      return 'الكمية كبيرة جداً';
    }
    return null;
  }

  /// Validate percentage (0-100)
  static String? validatePercentage(String? value, {bool required = false}) {
    if (value == null || value.isEmpty) {
      return required ? 'النسبة مطلوبة' : null;
    }
    final percentage = double.tryParse(value);
    if (percentage == null) {
      return 'النسبة يجب أن تكون رقماً';
    }
    if (percentage < 0 || percentage > 100) {
      return 'النسبة يجب أن تكون بين 0 و 100';
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SPECIFIC FIELD VALIDATORS
  // ═══════════════════════════════════════════════════════════════════════

  /// Validate barcode
  static String? validateBarcode(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Optional
    }
    if (!RegExp(r'^[0-9A-Za-z\-]+$').hasMatch(value)) {
      return 'الباركود يحتوي على حروف غير صالحة';
    }
    if (value.length > 50) {
      return 'الباركود طويل جداً (الحد الأقصى 50 حرف)';
    }
    if (value.length < 3) {
      return 'الباركود قصير جداً (3 أحرف على الأقل)';
    }
    return null;
  }

  /// Validate phone number
  static String? validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Optional
    }
    // Remove spaces for validation
    final cleaned = value.replaceAll(' ', '');
    if (!RegExp(r'^[\+]?[0-9\-]{7,20}$').hasMatch(cleaned)) {
      return 'رقم هاتف غير صالح';
    }
    return null;
  }

  /// Validate email
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Optional
    }
    if (!RegExp(r'^[\w\.\-]+@[\w\-]+(\.[a-zA-Z]{2,})+$').hasMatch(value)) {
      return 'بريد إلكتروني غير صالح';
    }
    return null;
  }

  /// Validate username
  static String? validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'اسم المستخدم مطلوب';
    }
    if (value.length < 3) {
      return 'اسم المستخدم قصير جداً (3 أحرف على الأقل)';
    }
    if (value.length > 50) {
      return 'اسم المستخدم طويل جداً';
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
      return 'اسم المستخدم يجب أن يحتوي على أحرف إنجليزية وأرقام فقط';
    }
    return null;
  }

  /// Validate password
  static String? validatePassword(String? value, {int minLength = 4}) {
    if (value == null || value.isEmpty) {
      return 'كلمة المرور مطلوبة';
    }
    if (value.length < minLength) {
      return 'كلمة المرور يجب أن تكون $minLength أحرف على الأقل';
    }
    if (value.length > 100) {
      return 'كلمة المرور طويلة جداً';
    }
    return null;
  }

  /// Validate password confirmation
  static String? validatePasswordConfirmation(String? value, String? password) {
    if (value == null || value.isEmpty) {
      return 'تأكيد كلمة المرور مطلوب';
    }
    if (value != password) {
      return 'كلمات المرور غير متطابقة';
    }
    return null;
  }

  /// Validate tax ID
  static String? validateTaxId(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Optional
    }
    if (!RegExp(r'^[0-9\-]+$').hasMatch(value)) {
      return 'الرقم الضريبي غير صالح';
    }
    if (value.length < 5 || value.length > 30) {
      return 'طول الرقم الضريبي غير صحيح';
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SANITIZATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Sanitize input to prevent SQL injection and XSS
  static String sanitizeInput(String input) {
    return input
        .replaceAll("'", "''")
        .replaceAll('"', '\\"')
        .replaceAll(';', '')
        .replaceAll('--', '')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('&', '&amp;')
        .trim();
  }

  /// Sanitize for database (less aggressive)
  static String sanitizeForDb(String input) {
    return input.replaceAll("'", "''").trim();
  }

  /// Clean numeric string (remove non-numeric except decimal)
  static String cleanNumericString(String input) {
    return input.replaceAll(RegExp(r'[^\d\.\-]'), '');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPER METHODS
  // ═══════════════════════════════════════════════════════════════════════

  /// Check if string contains only Arabic characters
  static bool isArabicOnly(String text) {
    return RegExp(r'^[\u0600-\u06FF\s]+$').hasMatch(text);
  }

  /// Check if string contains only English characters
  static bool isEnglishOnly(String text) {
    return RegExp(r'^[a-zA-Z\s]+$').hasMatch(text);
  }

  /// Parse double safely
  static double? parseDouble(String? value) {
    if (value == null || value.isEmpty) return null;
    return double.tryParse(cleanNumericString(value));
  }

  /// Parse int safely
  static int? parseInt(String? value) {
    if (value == null || value.isEmpty) return null;
    return int.tryParse(value.replaceAll(RegExp(r'[^\d\-]'), ''));
  }
}
