/// Utility for stripping characters that the bundled Noto Naskh Arabic /
/// Cairo fonts cannot render in a PDF context.
///
/// Thermal printers receive a rasterised PDF stream: an unsupported glyph
/// causes `package:pdf` to log «Courier has no Unicode support» and silently
/// fall back to the Courier built-in font — which cannot encode Arabic and
/// produces garbled output or an exception.
///
/// ## Strategy
/// Strip, don't replace.  A blank space where an emoji was is less confusing
/// on a printed receipt than «□» replacement boxes.  Only code points that
/// Noto Naskh Arabic / Cairo are known to support are kept; everything else
/// (emoji, pictographs, dingbats, CJK, etc.) is silently removed.
///
/// ## Supported ranges
/// | Range | Block |
/// |---|---|
/// | U+0020–U+024F | Basic Latin + Latin Extended-A/B |
/// | U+0250–U+02FF | IPA Extensions (phone numbers, etc.) |
/// | U+0600–U+077F | Arabic + Arabic Supplement |
/// | U+08A0–U+08FF | Arabic Extended-A |
/// | U+200B–U+206F | General Punctuation (ZWJ, ZWNJ, soft-hyphen…) |
/// | U+20A0–U+20CF | Currency Symbols (incl. ﷼ and €) |
/// | U+FB50–U+FDFF | Arabic Presentation Forms-A |
/// | U+FE70–U+FEFF | Arabic Presentation Forms-B |
library;

/// Remove every code point that the bundled Arabic PDF fonts cannot render.
///
/// The result is safe to pass to any `pw.Text` widget without triggering the
/// «Courier has no Unicode support» or «Unable to find a font to draw» logs.
String sanitizeForPdf(String text) {
  final buf = StringBuffer();
  for (final cp in text.runes) {
    if (_supported(cp)) buf.writeCharCode(cp);
  }
  return buf.toString();
}

bool _supported(int cp) {
  if (cp < 0x0020) return false; // C0 controls
  if (cp <= 0x024F) return true;  // Basic Latin + Latin Extended
  if (cp <= 0x02FF) return true;  // IPA extensions
  if (cp >= 0x0600 && cp <= 0x077F) return true; // Arabic + supplement
  if (cp >= 0x08A0 && cp <= 0x08FF) return true; // Arabic Extended-A
  if (cp >= 0x200B && cp <= 0x206F) return true; // General Punctuation
  if (cp >= 0x20A0 && cp <= 0x20CF) return true; // Currency symbols
  if (cp >= 0xFB50 && cp <= 0xFDFF) return true; // Arabic Pres Forms-A
  if (cp >= 0xFE70 && cp <= 0xFEFF) return true; // Arabic Pres Forms-B
  return false; // emoji, CJK, symbols, pictographs → strip
}
