import 'package:ural_erp/core/i18n/tr.dart';
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
      return tr('{fieldName} مطلوب', {'fieldName': fieldName});
    }
    // BUG-U15: a single character is a legitimate name/code — only emptiness
    // is rejected here.
    if (value.length > 200) {
      return tr('{fieldName} طويل جداً (الحد الأقصى 200 حرف)', {'fieldName': fieldName});
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
      return tr('{fieldName} قصير جداً ({minLength} أحرف على الأقل)', {'fieldName': fieldName, 'minLength': minLength});
    }
    if (value.length > maxLength) {
      return tr('{fieldName} طويل جداً (الحد الأقصى {maxLength} حرف)', {'fieldName': fieldName, 'maxLength': maxLength});
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // NUMBER VALIDATORS
  // ═══════════════════════════════════════════════════════════════════════

  /// Validate positive number
  static String? validatePositiveNumber(String? value, String fieldName) {
    if (value == null || value.isEmpty) {
      return tr('{fieldName} مطلوب', {'fieldName': fieldName});
    }
    final number = double.tryParse(value);
    if (number == null) {
      return tr('{fieldName} يجب أن يكون رقماً', {'fieldName': fieldName});
    }
    if (number < 0) {
      return tr('{fieldName} يجب أن يكون موجباً', {'fieldName': fieldName});
    }
    return null;
  }

  /// Validate price (positive, within reasonable range)
  static String? validatePrice(String? value, {bool required = true}) {
    if (value == null || value.isEmpty) {
      return required ? tr('السعر مطلوب') : null;
    }
    final price = double.tryParse(value);
    if (price == null) {
      return tr('السعر يجب أن يكون رقماً');
    }
    if (price < 0) {
      return tr('السعر يجب أن يكون موجباً');
    }
    if (price > 999999999) {
      return tr('السعر كبير جداً');
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
      return required ? tr('الكمية مطلوبة') : null;
    }
    final qty = double.tryParse(value);
    if (qty == null) {
      return tr('الكمية يجب أن تكون رقماً');
    }
    if (!allowZero && qty <= 0) {
      return tr('الكمية يجب أن تكون أكبر من صفر');
    }
    if (allowZero && qty < 0) {
      return tr('الكمية يجب أن تكون موجبة');
    }
    if (qty > 999999) {
      return tr('الكمية كبيرة جداً');
    }
    return null;
  }

  /// Validate percentage (0-100)
  static String? validatePercentage(String? value, {bool required = false}) {
    if (value == null || value.isEmpty) {
      return required ? tr('النسبة مطلوبة') : null;
    }
    final percentage = double.tryParse(value);
    if (percentage == null) {
      return tr('النسبة يجب أن تكون رقماً');
    }
    if (percentage < 0 || percentage > 100) {
      return tr('النسبة يجب أن تكون بين 0 و 100');
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
      return tr('الباركود يحتوي على حروف غير صالحة');
    }
    if (value.length > 50) {
      return tr('الباركود طويل جداً (الحد الأقصى 50 حرف)');
    }
    if (value.length < 3) {
      return tr('الباركود قصير جداً (3 أحرف على الأقل)');
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
      return tr('رقم هاتف غير صالح');
    }
    return null;
  }

  /// Validate email
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Optional
    }
    if (!RegExp(r'^[\w\.\-]+@[\w\-]+(\.[a-zA-Z]{2,})+$').hasMatch(value)) {
      return tr('بريد إلكتروني غير صالح');
    }
    return null;
  }

  /// Validate username
  static String? validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return tr('اسم المستخدم مطلوب');
    }
    if (value.length < 3) {
      return tr('اسم المستخدم قصير جداً (3 أحرف على الأقل)');
    }
    if (value.length > 50) {
      return tr('اسم المستخدم طويل جداً');
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
      return tr('اسم المستخدم يجب أن يحتوي على أحرف إنجليزية وأرقام فقط');
    }
    return null;
  }

  /// Validate password
  static String? validatePassword(String? value, {int minLength = 4}) {
    if (value == null || value.isEmpty) {
      return tr('كلمة المرور مطلوبة');
    }
    if (value.length < minLength) {
      return tr('كلمة المرور يجب أن تكون {minLength} أحرف على الأقل', {'minLength': minLength});
    }
    if (value.length > 100) {
      return tr('كلمة المرور طويلة جداً');
    }
    return null;
  }

  /// Validate password confirmation
  static String? validatePasswordConfirmation(String? value, String? password) {
    if (value == null || value.isEmpty) {
      return tr('تأكيد كلمة المرور مطلوب');
    }
    if (value != password) {
      return tr('كلمات المرور غير متطابقة');
    }
    return null;
  }

  /// Validate tax ID
  static String? validateTaxId(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Optional
    }
    if (!RegExp(r'^[0-9\-]+$').hasMatch(value)) {
      return tr('الرقم الضريبي غير صالح');
    }
    if (value.length < 5 || value.length > 30) {
      return tr('طول الرقم الضريبي غير صحيح');
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
