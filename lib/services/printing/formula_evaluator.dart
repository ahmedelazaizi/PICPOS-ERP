// ═══════════════════════════════════════════════════════════════════════════
// FORMULA EVALUATOR — Mathematical expressions for invoice template elements
// ═══════════════════════════════════════════════════════════════════════════

/// Evaluates mathematical formulas like "[subtotal] - [discount] + [tax]"
/// by resolving variable references from invoice data.
class FormulaEvaluator {
  /// Evaluate a formula string, substituting variables from [data].
  ///
  /// Supports: +, -, *, /, parentheses ().
  /// Variables are enclosed in brackets: [field_name].
  ///
  /// Returns the computed double, or null if the formula is invalid.
  static double? evaluate(String formula, Map<String, dynamic> data) {
    try {
      // 1. Substitute [variable] references with actual values
      String resolved = formula.replaceAllMapped(
        RegExp(r'\[([^\]]+)\]'),
        (match) {
          final key = match.group(1)!.trim();
          final value = data[key];
          if (value == null) return '0';
          if (value is num) return value.toString();
          final parsed = double.tryParse(value.toString());
          return (parsed ?? 0).toString();
        },
      );

      // 2. Remove any non-math characters (safety)
      resolved = resolved.replaceAll(RegExp(r'[^0-9+\-*/().%\s]'), '');
      if (resolved.trim().isEmpty) return null;

      // 3. Parse and evaluate the expression
      return _evaluateExpression(resolved.trim());
    } catch (e) {
      return null;
    }
  }

  /// Available variables for the formula builder help dialog.
  static const List<Map<String, String>> availableVariables = [
    {'key': 'subtotal', 'label': 'المجموع الفرعي'},
    {'key': 'discount', 'label': 'الخصم'},
    {'key': 'tax', 'label': 'الضريبة'},
    {'key': 'total', 'label': 'الإجمالي'},
    {'key': 'paid', 'label': 'المدفوع'},
    {'key': 'remaining', 'label': 'المتبقي'},
    {'key': 'delivery_fee', 'label': 'رسوم التوصيل'},
    {'key': 'quantity', 'label': 'الكمية'},
    {'key': 'unit_price', 'label': 'سعر الوحدة'},
    {'key': 'item_discount', 'label': 'خصم الصنف'},
    {'key': 'item_total', 'label': 'إجمالي الصنف'},
    {'key': 'item_tax', 'label': 'ضريبة الصنف'},
  ];

  // ═══ Simple recursive descent parser ═══

  static double? _evaluateExpression(String expr) {
    final parser = _Parser(expr);
    final result = parser.parseExpression();
    return result;
  }
}

/// Minimal recursive-descent parser for arithmetic expressions.
class _Parser {
  final String _input;
  int _pos = 0;

  _Parser(this._input);

  double? parseExpression() {
    final result = _addSub();
    return result;
  }

  double? _addSub() {
    var left = _mulDiv();
    if (left == null) return null;
    while (_pos < _input.length) {
      _skipSpaces();
      if (_pos >= _input.length) break;
      final op = _input[_pos];
      if (op != '+' && op != '-') break;
      _pos++;
      final right = _mulDiv();
      if (right == null) return null;
      left = op == '+' ? left! + right : left! - right;
    }
    return left;
  }

  double? _mulDiv() {
    var left = _unary();
    if (left == null) return null;
    while (_pos < _input.length) {
      _skipSpaces();
      if (_pos >= _input.length) break;
      final op = _input[_pos];
      if (op != '*' && op != '/' && op != '%') break;
      _pos++;
      final right = _unary();
      if (right == null) return null;
      if (op == '*') {
        left = left! * right;
      } else if (op == '/') {
        left = right != 0 ? left! / right : 0;
      } else {
        left = right != 0 ? left! % right : 0;
      }
    }
    return left;
  }

  double? _unary() {
    _skipSpaces();
    if (_pos < _input.length && _input[_pos] == '-') {
      _pos++;
      final val = _primary();
      return val == null ? null : -val;
    }
    return _primary();
  }

  double? _primary() {
    _skipSpaces();
    if (_pos >= _input.length) return null;

    // Parenthesized expression
    if (_input[_pos] == '(') {
      _pos++; // skip '('
      final val = _addSub();
      _skipSpaces();
      if (_pos < _input.length && _input[_pos] == ')') _pos++;
      return val;
    }

    // Number
    final start = _pos;
    while (_pos < _input.length &&
        (RegExp(r'[0-9.]').hasMatch(_input[_pos]))) {
      _pos++;
    }
    if (_pos == start) return null;
    return double.tryParse(_input.substring(start, _pos));
  }

  void _skipSpaces() {
    while (_pos < _input.length && _input[_pos] == ' ') {
      _pos++;
    }
  }
}
