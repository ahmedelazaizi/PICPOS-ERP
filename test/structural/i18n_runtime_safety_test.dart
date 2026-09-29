import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

const _nonUiMethods = {
  'codeUnitAt',
  'contains',
  'endsWith',
  'indexOf',
  'replaceAll',
  'replaceAllMapped',
  'replaceFirst',
  'split',
  'startsWith',
};

class _SafetyVisitor extends RecursiveAstVisitor<void> {
  _SafetyVisitor(this.path);

  final String path;
  final violations = <String>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'tr' && _hasNonUiContext(node)) {
      violations.add('$path:${node.offset}: tr() is used as non-UI data');
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final list = node.parent;
    if (list is VariableDeclarationList && list.isFinal) {
      final declaration = list.parent;
      final isStatic = declaration is FieldDeclaration && declaration.isStatic;
      final isTopLevel = declaration is TopLevelVariableDeclaration;
      if ((isStatic || isTopLevel) &&
          node.initializer?.toSource().contains('tr(') == true) {
        violations.add('$path:${node.offset}: final initializer captures tr()');
      }
    }
    super.visitVariableDeclaration(node);
  }

  bool _hasNonUiContext(MethodInvocation node) {
    if (path.startsWith('lib/core/utils/') ||
        path.startsWith('lib/presentation/widgets/touch_keyboard/')) {
      return true;
    }
    AstNode? current = node.parent;
    while (current != null) {
      if (current is MethodInvocation &&
          _nonUiMethods.contains(current.methodName.name)) {
        return true;
      }
      if (current is InstanceCreationExpression &&
          current.constructorName.type.toSource() == 'RegExp') {
        return true;
      }
      if (current is BinaryExpression &&
          (current.operator.lexeme == '==' || current.operator.lexeme == '!=')) {
        return true;
      }
      if (current is SwitchCase ||
          current is SwitchDefault ||
          current is ConstantPattern ||
          current is EnumConstantDeclaration) {
        return true;
      }
      if (current is MapLiteralEntry && identical(current.key, node)) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }
}

void main() {
  test('non-UI strings and locale-sensitive finals remain runtime-safe', () {
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      final relative = path.startsWith('./') ? path.substring(2) : path;
      final source = entity.readAsStringSync();
      if (RegExp(r'RegExp\s*\(\s*tr\s*\(').hasMatch(source)) {
        violations.add('$relative: RegExp(...) must not wrap a tr() call');
      }
      if (relative == 'lib/presentation/dialogs/daily_cash_closing_dialog.dart' &&
          RegExp(r'description\s*:\s*tr\s*\(').hasMatch(source)) {
        violations.add(
          '$relative: persisted daily-closing descriptions must not use tr()',
        );
      }
      final parse = parseString(content: source, path: relative);
      final visitor = _SafetyVisitor(relative);
      parse.unit.accept(visitor);
      violations.addAll(visitor.violations);
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
