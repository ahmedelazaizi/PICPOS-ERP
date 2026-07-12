/// Utility for Arabic text normalization to improve search results
class ArabicUtils {
  /// Normalizes Arabic text by standardizing characters like Alef, Yeh, and Teh Marbuta.
  static String normalize(String text) {
    if (text.isEmpty) return text;

    String normalized = text;

    // Remove Harakat (diacritics)
    normalized = normalized.replaceAll(RegExp(r'[\u064B-\u0652]'), '');

    // Normalize Alef (أ, إ, آ -> ا)
    normalized = normalized.replaceAll(RegExp(r'[أإآ]'), 'ا');

    // Normalize Teh Marbuta (ة -> ه)
    normalized = normalized.replaceAll('ة', 'ه');

    // Normalize Yeh (ى -> ي)
    normalized = normalized.replaceAll('ى', 'ي');

    return normalized.trim();
  }
}
