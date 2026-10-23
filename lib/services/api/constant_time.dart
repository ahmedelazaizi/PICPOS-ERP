/// Constant-time string comparison (no early exit on the first differing char).
class ConstantTime {
  ConstantTime._();

  static bool equals(String a, String b) {
    var diff = a.length ^ b.length;
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
